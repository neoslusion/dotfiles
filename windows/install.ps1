# Dotfiles Windows installer - native-Windows counterpart of install.sh.
# Entry point: install.ps1 at the repo root (forwards here).
# Usage:  .\install.ps1               (tools + configs, Scoop-first)
#         .\install.ps1 -ConfigOnly   (deploy/refresh configs only)
#         .\install.ps1 -DryRun       (print package plan; no package installs)
#         .\install.ps1 -NoAdmin      (force Scoop user-scope installs)
#         .\install.ps1 -Winget       (winget-first, Scoop fallback)
#
# Idempotent: scoop/winget skip already-installed packages; configs are only
# rewritten when their content changed, and the previous copy is then kept as
# <name>.bak (mirrors copy_config).
#
# Package manager priority: Scoop by default - user-scope, no UAC, shims on
# PATH immediately - with winget as the automatic fallback. Pass -Winget to
# invert. -NoAdmin guarantees Scoop-only, ever (locked-down boxes).
param(
    [switch]$ConfigOnly,
    [switch]$DryRun,
    [switch]$NoAdmin,
    [switch]$Winget
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

# --- Elevation awareness -------------------------------------------------------
# Elevated is fine for winget (no UAC prompts), but: (a) Scoop refuses elevated
# shells, so Scoop-first degrades to winget; (b) if elevated as a DIFFERENT
# account, all user-scoped work (configs, profile, PSFzf) lands in that
# account's profile.
$IsElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsElevated) {
    Write-Warning "Elevated shell: configs/profile will deploy to THIS account's profile ($HOME)."
    if ($NoAdmin) {
        Write-Error "-NoAdmin requires a non-elevated shell (Scoop refuses to install as admin). Re-run without elevation."
    }
}

# --- Output helpers (mirror run_step / skip_step) ---------------------------
function Write-Ok($label) { Write-Host ("  {0,-34}" -f $label) -NoNewline; Write-Host "ok" -ForegroundColor Green }
function Write-Skip($label, $reason) { Write-Host ("  {0,-34}" -f $label) -NoNewline; Write-Host "skip $reason" -ForegroundColor Yellow }
function Write-Fail($label) { Write-Host ("  {0,-34}" -f $label) -NoNewline; Write-Host "fail" -ForegroundColor Red }
function Write-DryRunPackage($label, $manager, $package) {
    Write-Host "  DRY-RUN $manager $package ($label)" -ForegroundColor Cyan
}

# --- Scoop (default path) ------------------------------------------------------
# Scoop-first unless -Winget; -NoAdmin forces Scoop even alongside -Winget.
$script:ScoopFirst = (-not $Winget -or $NoAdmin)
$script:ScoopBuckets = $null

function Ensure-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return $true }
    if ($IsElevated) {
        Write-Warning "Scoop is unavailable in an elevated shell; using winget for this run."
        return $false
    }
    Write-Host "  Bootstrapping Scoop into ~\scoop (no admin required)" -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "https://get.scoop.sh" | Invoke-Expression *> $null
    }
    catch {
        Write-Warning "Scoop bootstrap failed: $_"
        return $false
    }
    # Shims dir for the current session; the installer persists it in user PATH
    $shims = Join-Path $HOME "scoop\shims"
    if ($env:Path -notlike "*$shims*") { $env:Path = "$shims;$env:Path" }
    return [bool](Get-Command scoop -ErrorAction SilentlyContinue)
}

function Ensure-ScoopBucket($bucket) {
    # Bucket management needs git; main-bucket apps do not
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { scoop install git *> $null }
    if ($null -eq $script:ScoopBuckets) {
        $script:ScoopBuckets = @(scoop bucket list 6> $null | ForEach-Object { $_.Name })
    }
    if ($script:ScoopBuckets -notcontains $bucket) {
        scoop bucket add $bucket *> $null
        $script:ScoopBuckets += $bucket
    }
}

# "Already on PATH" guard, so a tool installed by winget or a vendor installer
# is not duplicated by Scoop. The command defaults to the app name; listed here
# only where it differs. $null skips the guard: the WindowsApps `python` alias
# would pass it, so Python is guarded by Find-Python at its call site instead.
$ScoopCommandByName = @{
    'ripgrep' = 'rg'
    'neovim'  = 'nvim'
    'python'  = $null
}

function Install-ScoopApp($label, $spec) {
    if ($DryRun) {
        Write-DryRunPackage $label 'scoop' $spec
        return $true
    }
    if (-not (Ensure-Scoop)) { return $false }
    $name = $spec
    if ($spec -match '^([^/]+)/(.+)$') {
        Ensure-ScoopBucket $Matches[1]
        $name = $Matches[2]
    }
    if (Test-Path (Join-Path $HOME "scoop\apps\$name")) {
        Write-Skip $label "installed (scoop)"
        return $true
    }
    $cmd = if ($ScoopCommandByName.ContainsKey($name)) { $ScoopCommandByName[$name] } else { $name }
    if ($cmd -and (Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Skip $label "installed ($cmd on PATH)"
        return $true
    }
    scoop install $spec *> $null
    # scoop's exit code is unreliable through the shim; verify by app dir
    if (Test-Path (Join-Path $HOME "scoop\apps\$name")) {
        Write-Ok "$label (scoop)"
        return $true
    }
    Write-Fail $label
    Write-Warning "scoop install $spec did not produce ~\scoop\apps\$name"
    return $false
}

# --- winget with Scoop fallback ------------------------------------------------
$WingetAlreadyInstalled = -1978335189  # 0x8A15002B

# Pinned winget versions - Windows parity with installation/versions.env.
# Bump intentionally (query current: winget show --id <id> -e | findstr Version).
# Apps without a pin install latest; a failed pinned install retries unpinned.
$WingetPins = @{
    'Git.Git'                      = '2.55.0.3'
    'Microsoft.PowerShell'         = '7.6.4.0'
    'Alacritty.Alacritty'           = '0.17.0'
    'DEVCOM.JetBrainsMonoNerdFont' = '3.3.0'
    'Starship.Starship'            = '1.26.0'
    'ajeetdsouza.zoxide'           = '0.10.0'
    'Atuinsh.Atuin'                = '18.16.1'
    'junegunn.fzf'                 = '0.74.2'
    'Python.Python.3.14'           = '3.14.7'
    'jqlang.jq'                    = '1.8.2'
    'sharkdp.bat'                  = '0.26.1'
    'sharkdp.fd'                   = '10.4.2'
    'eza-community.eza'            = '0.23.5'
    'dandavison.delta'             = '0.19.2'
    'BurntSushi.ripgrep.MSVC'      = '15.2.0'
    'Neovim.Neovim'                = '0.12.4'
    'zig.zig'                      = '0.16.0'
    'Kitware.CMake'                = '4.4.2'
    'equalsraf.win32yank'          = '0.1.1'
    'JesseDuffield.lazygit'        = '0.64.0'
}

function Install-App($label, $id, $scoopSpec) {
    if ($DryRun) {
        if ($script:ScoopFirst -and $scoopSpec) {
            Write-DryRunPackage $label 'scoop' $scoopSpec
        }
        else {
            Write-DryRunPackage $label 'winget' $id
        }
        return
    }
    if ($script:ScoopFirst -and $scoopSpec) {
        if (Install-ScoopApp $label $scoopSpec) { return }
        Write-Warning "scoop install of $label failed; retrying via winget"
    }
    winget list --id $id -e --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Skip $label "installed"
        return
    }
    $pin = $WingetPins[$id]
    if ($pin) {
        winget install --id $id -e --version $pin --accept-source-agreements --accept-package-agreements *> $null
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $WingetAlreadyInstalled) {
            Write-Warning "winget install $id pinned to $pin exited with $LASTEXITCODE; retrying unpinned"
            winget install --id $id -e --accept-source-agreements --accept-package-agreements *> $null
        }
    }
    else {
        winget install --id $id -e --accept-source-agreements --accept-package-agreements *> $null
    }
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $WingetAlreadyInstalled) {
        Write-Ok $label
        return
    }
    if ($scoopSpec) {
        Write-Warning "winget install $id exited with $LASTEXITCODE; retrying via Scoop"
        [void](Install-ScoopApp $label $scoopSpec)
    }
    else {
        Write-Fail $label
        Write-Warning "winget install $id exited with $LASTEXITCODE"
    }
}

# --- Config deployment (mirror copy_config's .bak convention) ----------------
# True when $dest already holds exactly $source's files. Unchanged configs are
# left alone, so a re-run neither rewrites them nor replaces the last real .bak
# with a copy of identical content.
function Test-SameContent($source, $dest) {
    if (-not (Test-Path -LiteralPath $dest)) { return $false }
    $digest = {
        param($path)
        $item = Get-Item -LiteralPath $path -Force
        if (-not $item.PSIsContainer) { return (Get-FileHash -LiteralPath $item.FullName).Hash }
        Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force |
            ForEach-Object { $_.FullName.Substring($item.FullName.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash } |
            Sort-Object
    }
    return ((& $digest $source) -join "`n") -ceq ((& $digest $dest) -join "`n")
}

function Deploy-Config($label, $source, $dest) {
    if (Test-SameContent $source $dest) { Write-Ok $label; return }
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    if (Test-Path $dest) {
        Remove-Item "$dest.bak" -Force -ErrorAction SilentlyContinue
        Move-Item $dest "$dest.bak" -Force
    }
    Copy-Item $source $dest -Force
    Write-Ok $label
}

function Deploy-ConfigDir($label, $source, $dest) {
    # Directory analogue of copy_config: back up the whole tree, then copy
    if (Test-SameContent $source $dest) { Write-Ok $label; return }
    if (Test-Path $dest) {
        Remove-Item "$dest.bak" -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item $dest "$dest.bak" -Force
    }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item $source $dest -Recurse -Force
    Write-Ok $label
}

# A real interpreter for the agent statuslines, or $null. The WindowsApps
# `python` alias is the Python install manager: it adds ~100 ms per render and
# can print its own setup output into the bar, so it never counts. Resolved
# from disk, never by running the alias, which could start a runtime download.
function Find-Python {
    $onPath = Get-Command python -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } | Select-Object -First 1
    if ($onPath) { return $onPath.Source -replace '\\', '/' }
    # Off this session's PATH: installed earlier in this run, or by an installer
    # that leaves PATH alone (python.org/winget, the install manager's runtimes).
    $patterns = @(
        (Join-Path $HOME 'scoop\apps\python\current\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Python\pythoncore-*\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\python.exe'),
        (Join-Path $env:ProgramFiles 'Python3*\python.exe')
    )
    foreach ($pattern in $patterns) {
        $hit = Get-ChildItem $pattern -ErrorAction SilentlyContinue |
            Sort-Object { $_.VersionInfo.ProductVersion -as [version] } -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName -replace '\\', '/' }
    }
    return $null
}

Write-Host "`nDotfiles Windows Installer" -ForegroundColor Cyan

# --- Step 1: Tools (skipped with -ConfigOnly) --------------------------------
if (-not $ConfigOnly) {
    Write-Host "`nCore tools" -ForegroundColor Magenta
    if ($script:ScoopFirst) {
        if (-not $DryRun -and -not (Get-Command scoop -ErrorAction SilentlyContinue) -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Warning "Neither Scoop nor winget is available; tool installs will fail."
        }
    }
    elseif (-not $DryRun -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget not found - falling back to Scoop (user-scope) for all tools."
        $script:ScoopFirst = $true
    }

    Install-App "Git"                "Git.Git"                       "git"
    Install-App "PowerShell 7"       "Microsoft.PowerShell"          "pwsh"
    Install-App "Alacritty"          "Alacritty.Alacritty"            "extras/alacritty"
    # A font has no command for the PATH guard; check the two font dirs that
    # winget (machine) and Scoop (per-user) install into.
    $nerdFont = Get-ChildItem "$env:WINDIR\Fonts", "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" `
        -Filter 'JetBrainsMonoNerdFont*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nerdFont) {
        Write-Skip "JetBrainsMono NF" "installed"
    }
    else {
        Install-App "JetBrainsMono NF" "DEVCOM.JetBrainsMonoNerdFont"  "nerd-fonts/JetBrainsMono-NF"
    }
    Install-App "Starship"           "Starship.Starship"             "starship"
    Install-App "Zoxide"             "ajeetdsouza.zoxide"            "zoxide"
    Install-App "Atuin"              "Atuinsh.Atuin"                 "atuin"
    Install-App "fzf"                "junegunn.fzf"                  "fzf"
    Install-App "Bat"                "sharkdp.bat"                   "bat"
    Install-App "fd"                 "sharkdp.fd"                    "fd"
    Install-App "Eza"                "eza-community.eza"             "eza"
    Install-App "Delta"              "dandavison.delta"              "delta"
    # Wire delta into git once installed (lazygit already pages through it
    # via config/lazygit/config.yml; this covers the plain git CLI).
    if (-not $DryRun -and (Get-Command delta -ErrorAction SilentlyContinue)) {
        git config --global core.pager "delta"
        git config --global interactive.diffFilter "delta --color-only"
        Write-Ok "Delta wired as git pager"
    }
    # Both agent statuslines run on Python. An existing real interpreter is
    # kept rather than adding a second one. The main/ prefix is deliberate: a
    # bare `python` makes Scoop resolve a .\Python directory in the cwd instead.
    if (Find-Python) {
        Write-Skip "Python" "installed"
    }
    else {
        Install-App "Python"         "Python.Python.3.14"            "main/python"
    }
    Install-App "jq"                 "jqlang.jq"                     "jq"
    Install-App "ripgrep"            "BurntSushi.ripgrep.MSVC"       "ripgrep"
    Install-App "Neovim"             "Neovim.Neovim"                 "neovim"
    # Neovim treesitter (main branch) build deps: parser compile needs a C
    # compiler + the tree-sitter CLI on PATH (zig serves as the compiler);
    # some parsers' build scripts also invoke cmake.
    Install-App "Zig (treesitter cc)" "zig.zig"                      "zig"
    Install-App "CMake"               "Kitware.CMake"                "cmake"
    # tree-sitter has no winget package (id 'tree-sitter.tree-sitter' does not
    # exist) - Scoop-only, so it always goes through the user-scope fallback.
    [void](Install-ScoopApp "tree-sitter CLI" "tree-sitter")
    Install-App "win32yank"          "equalsraf.win32yank"           "win32yank"
    Install-App "Lazygit"            "JesseDuffield.lazygit"         "extras/lazygit"

    # Herdr: agent multiplexer. Native Windows support is preview-beta only -
    # no winget/scoop package, so use the official installer (downloads the
    # preview channel's herdr.exe + app-local ConPTY runtime; herdr update
    # keeps it current). Linux/macOS parity lives in installation/install_shell.sh.
    if ($DryRun) {
        Write-DryRunPackage 'Herdr' 'installer' 'preview'
    }
    elseif (-not (Get-Command herdr -ErrorAction SilentlyContinue)) {
        try {
            Invoke-RestMethod -Uri "https://herdr.dev/install.ps1" | Invoke-Expression *> $null
            if (Get-Command herdr -ErrorAction SilentlyContinue) {
                Write-Ok "Herdr (preview beta)"
            }
            else {
                Write-Fail "Herdr"
                Write-Warning "herdr installer ran but herdr.exe was not found on PATH"
            }
        }
        catch {
            Write-Fail "Herdr"
            Write-Warning "herdr preview install failed: $_"
        }
    }
    else {
        Write-Skip "Herdr" "installed"
    }

    Write-Host "`nPowerShell modules" -ForegroundColor Magenta
    if ($DryRun) {
        Write-DryRunPackage 'PSFzf' 'PowerShellGet' 'PSFzf'
    }
    else {
        # Install through pwsh 7 explicitly: run from Windows PowerShell 5.1,
        # Install-Module would land in a module path pwsh 7 does not read.
        $pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwshExe) {
            # Just installed; current session PATH may not see it yet
            $candidates = @(
                (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"),
                (Join-Path $HOME "scoop\shims\pwsh.exe")
            )
            $pwshExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        }
        if ($pwshExe) {
            # Save-Module to ~\.psmodules, NOT -Scope CurrentUser: Known Folder
            # Move redirects the CurrentUser module dir (Documents\PowerShell)
            # into OneDrive and every import pays the sync filter driver.
            # profile.ps1 prepends this dir to PSModulePath per-session.
            # Identical behavior elevated or not; no admin needed either way.
            $modDir = Join-Path $HOME ".psmodules"
            & $pwshExe -NoProfile -Command "if (Test-Path '$modDir\PSFzf') { exit 10 } ; New-Item -ItemType Directory -Path '$modDir' -Force | Out-Null ; Save-Module PSFzf -Path '$modDir' -Force"
            if ($LASTEXITCODE -eq 10) { Write-Skip "PSFzf" "installed (local)" }
            elseif ($LASTEXITCODE -eq 0) { Write-Ok "PSFzf (-> ~\.psmodules)" }
            else { Write-Fail "PSFzf" }
        }
        else {
            Write-Skip "PSFzf" "pwsh 7 not found; re-run install.ps1"
        }
    }
}

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry-run complete. No configuration was changed." -ForegroundColor Green
    exit 0
}

# --- Step 2: Configuration ----------------------------------------------------
Write-Host "`nConfiguration" -ForegroundColor Magenta

# Alacritty reads ONLY %APPDATA%\alacritty\alacritty.toml on Windows; the XDG
# paths it consults on Linux and macOS are never checked. Deploy straight from
# source: it has no machine paths to render.
# $env:APPDATA rather than [Environment]::GetFolderPath('ApplicationData'):
# Alacritty resolves its own config dir through the Known Folder API (verified -
# `alacritty migrate` ignores a redirected APPDATA), so the two could diverge if
# the roaming profile is ever moved. They agree on a normal machine, and the
# env var is what keeps the dry-run test sandboxed; the herdr deploy below has
# the same latent assumption.
$AlacrittySource = Join-Path $PSScriptRoot 'alacritty\alacritty.toml'
if (-not (Test-Path $AlacrittySource)) { throw "Alacritty config source missing: $AlacrittySource" }
if (-not $env:APPDATA) { throw 'APPDATA is not set; cannot locate the Alacritty config directory' }
Deploy-Config 'Alacritty config' $AlacrittySource (Join-Path $env:APPDATA 'alacritty\alacritty.toml')

# WSL memory/disk guardrails: seed-if-missing ONLY (a tuned ~/.wslconfig is
# machine state the user may have customized). Applies after `wsl --shutdown`.
$wslConfig = Join-Path $HOME ".wslconfig"
if (-not (Test-Path $wslConfig)) {
    Copy-Item (Join-Path $PSScriptRoot "wslconfig") $wslConfig
    Write-Ok "WSL config (~/.wslconfig)"
}
else {
    Write-Skip "WSL config" "exists (user-managed)"
}

# Reuse the Linux starship.toml so the prompt matches both sides exactly
Deploy-Config "Starship config" `
    (Join-Path $RepoRoot "config\terminal\starship.toml") `
    (Join-Path $HOME ".config\starship.toml")

# Same Neovim config as the Linux side. Windows Neovim reads
# %LOCALAPPDATA%\nvim, NOT ~/.config/nvim. lazy.nvim bootstraps plugins on
# first launch (lazy-lock.json pins versions).
Deploy-ConfigDir "Neovim config" `
    (Join-Path $RepoRoot "config\nvim") `
    (Join-Path $env:LOCALAPPDATA "nvim")

# Lazygit reads %LOCALAPPDATA%\lazygit on Windows (`lazygit --print-config-dir`).
# File-level copy: lazygit keeps runtime state next to config.yml on Windows.
Deploy-Config "Lazygit config" `
    (Join-Path $RepoRoot "config\lazygit\config.yml") `
    (Join-Path $env:LOCALAPPDATA "lazygit\config.yml")

# Herdr reads %APPDATA%\herdr\config.toml on Windows (Roaming, NOT LOCALAPPDATA).
# Seed-if-missing ONLY: the herdr Settings TUI writes back into config.toml at
# runtime (same contract as Codex config.toml above).
# The shared seed leaves default_shell empty so Herdr discovers PowerShell
# on Windows while Unix/WSL uses $SHELL; do not hardcode pwsh in the seed.
$herdrToml = Join-Path $env:APPDATA "herdr\config.toml"
if (-not (Test-Path $herdrToml)) {
    Deploy-Config "Herdr config.toml" (Join-Path $RepoRoot "config\herdr\config.toml") $herdrToml
}
else {
    Write-Skip "Herdr config.toml" "exists (runtime-managed)"
}

# Profile: keep the generated sidecar on the local disk. Known Folder Move
# redirects Documents into OneDrive on many machines; the tiny wrapper below
# remains in $PROFILE, but the latency-sensitive profile never leaves $HOME.
$profileDir = Join-Path $HOME 'PowerShell'
$profilePath = Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell') 'Microsoft.PowerShell_profile.ps1'
$sidecar = Join-Path $profileDir 'dotfiles.profile.ps1'

Deploy-Config 'Profile (local sidecar)' (Join-Path $PSScriptRoot 'profile.ps1') $sidecar

# --- Agent configs (Claude Code / Codex / Antigravity / Opencode) --------------
# File-level only - never replace ~\.claude or ~\.codex wholesale (live
# sessions/credentials). Secrets are NOT in the repo: API profiles load their
# machine-local credential files only on demand.
# Shared engineering guidance (config\agents): ENGINEERING.md copied verbatim
# to every agent home (mirrors install_configs.sh's deploy_shared_agent_docs).
$agentsDir = Join-Path $RepoRoot "config\agents"
function Deploy-AgentDocs($label, $destDir) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Deploy-Config "$label ENGINEERING.md" (Join-Path $agentsDir "ENGINEERING.md") (Join-Path $destDir "ENGINEERING.md")
}

$claudeDir = Join-Path $HOME ".claude"
$utf8NoBom = New-Object Text.UTF8Encoding($false)
Deploy-Config "Claude statusline.py" (Join-Path $RepoRoot "config\claude\statusline.py") (Join-Path $claudeDir "statusline.py")
# Statusline commands get absolute, forward-slash paths (no JSON escaping).
$pythonPath = Find-Python
if (-not $pythonPath) { $pythonPath = 'python' }
$statuslinePath = (Join-Path $claudeDir "statusline.py") -replace '\\', '/'

# settings.json and CLAUDE.md are shared with other installers (e.g. rtk) and
# with /plugin and /effort, so merge into them instead of replacing them:
# everyone else's entries survive a refresh. Same rules as
# installation/merge_settings.py - repo keys win, nested objects merge, keys the
# repo does not set are kept, an unparseable file is replaced. PSCustomObject,
# not -AsHashtable: a fresh machine runs this under Windows PowerShell 5.1.
function Merge-JsonObject($Target, $Source) {
    foreach ($prop in $Source.PSObject.Properties) {
        $current = $Target.PSObject.Properties[$prop.Name]
        if ($current -and $current.Value -is [Management.Automation.PSCustomObject] -and
            $prop.Value -is [Management.Automation.PSCustomObject]) {
            Merge-JsonObject $current.Value $prop.Value
        }
        elseif (-not $current -or
            (ConvertTo-Json -InputObject $current.Value -Depth 100 -Compress) -cne
            (ConvertTo-Json -InputObject $prop.Value -Depth 100 -Compress)) {
            # Equal values are left alone: -Force re-adds the member at the end,
            # and that reorder alone would count as a change on every run.
            $Target | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }
}
$claudeSettings = Join-Path $claudeDir "settings.json"
$repoSettings = [IO.File]::ReadAllText((Join-Path $RepoRoot "config\claude\settings.json"))
$repoSettings = $repoSettings.Replace('__PYTHON__', $pythonPath).Replace('__CLAUDE_STATUSLINE__', $statuslinePath)
$liveSettings = $null
$liveText = $null
if (Test-Path $claudeSettings) {
    $liveText = [IO.File]::ReadAllText($claudeSettings)
    try { $liveSettings = $liveText | ConvertFrom-Json } catch { $liveSettings = $null }
}
if ($liveSettings -is [Management.Automation.PSCustomObject]) {
    $beforeMerge = $liveSettings | ConvertTo-Json -Depth 100
    Merge-JsonObject $liveSettings ($repoSettings | ConvertFrom-Json)
    $afterMerge = $liveSettings | ConvertTo-Json -Depth 100
    # Compare content, not text: Claude rewrites the file in its own JSON style,
    # so a text compare would rewrite it (and leave a .bak) on every run.
    $mergedText = if ($afterMerge -ceq $beforeMerge) { $liveText } else { $afterMerge + "`n" }
}
else {
    $mergedText = $repoSettings
}
if ($mergedText -cne $liveText) {
    if ($null -ne $liveText) { Copy-Item $claudeSettings "$claudeSettings.bak" -Force }
    [IO.File]::WriteAllText($claudeSettings, $mergedText, $utf8NoBom)
    Write-Ok "Claude settings.json (merged, statusline: $pythonPath)"
}
else {
    Write-Skip "Claude settings.json" "up to date"
}
# First-party mods (config\claude\mods) are a folder marketplace. settings.json
# alone does not install them, so every run registers them through the CLI (both
# commands are idempotent). Do not set CLAUDE_CONFIG_DIR here, even to ~\.claude:
# the CLI then looks for its global config at ~\.claude\.claude.json instead of
# ~\.claude.json, warns, and creates a stray one (same rule as the bash side).
$modsDir = Join-Path $claudeDir "mods"
Deploy-ConfigDir "Claude mods" (Join-Path $RepoRoot "config\claude\mods") $modsDir
if (Get-Command claude -ErrorAction SilentlyContinue) {
    try {
        & claude plugin marketplace add $modsDir | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "marketplace add exited $LASTEXITCODE" }
        foreach ($mod in Get-ChildItem $modsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.claude-plugin\plugin.json') }) {
            & claude plugin install "$($mod.Name)@my-mods" --scope user | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "install of $($mod.Name) exited $LASTEXITCODE" }
        }
        Write-Ok "Claude mods registered"
    }
    catch { Write-Skip "Claude mods registration" "$_" }
}
else {
    Write-Skip "Claude mods registration" "claude not on PATH"
}
# Instruction files that other tools (rtk) also add imports to: ensure our
# import line instead of replacing the file. Same format as install_configs.sh's
# inject_sourcing; the leading newline keeps the import off a last line that has
# no trailing newline.
function Add-ImportLine($label, $path, $line) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, "$line`n", $utf8NoBom)
        Write-Ok $label
    }
    elseif (-not ([IO.File]::ReadAllText($path)).Contains($line)) {
        [IO.File]::AppendAllText($path, "`n# Added by dotfiles`n$line`n", $utf8NoBom)
        Write-Ok "$label (import added)"
    }
    else {
        Write-Skip $label "already imports it"
    }
}
Add-ImportLine "Claude CLAUDE.md" (Join-Path $claudeDir "CLAUDE.md") '@ENGINEERING.md'
Deploy-AgentDocs "Claude" $claudeDir

$codexDir = Join-Path $HOME ".codex"
Add-ImportLine "Codex AGENTS.md" (Join-Path $codexDir "AGENTS.md") '@~/.codex/ENGINEERING.md'
Deploy-AgentDocs "Codex" $codexDir
# config.toml is seed-if-missing ONLY (Codex appends trust entries at runtime)
$codexToml = Join-Path $codexDir "config.toml"
if (-not (Test-Path $codexToml)) {
    Deploy-Config "Codex config.toml" (Join-Path $RepoRoot "config\codex\config.toml") $codexToml
}
else {
    Write-Skip "Codex config.toml" "exists (runtime-managed)"
}

$agyDir = Join-Path $HOME ".gemini\antigravity-cli"
Deploy-Config "Antigravity AGENTS.md" (Join-Path $RepoRoot "config\antigravity\AGENTS.md") (Join-Path $agyDir "AGENTS.md")
Deploy-AgentDocs "Antigravity" $agyDir
Deploy-Config "Antigravity statusline.py"  (Join-Path $RepoRoot "config\antigravity\statusline.py")  (Join-Path $agyDir "statusline.py")

$agySettings = Join-Path $agyDir "settings.json"
$statuslinePath = (Join-Path $agyDir "statusline.py") -replace '\\', '/'
$agyCommand = '"{0}" "{1}"' -f $pythonPath, $statuslinePath
if (-not (Test-Path $agySettings)) {
    Deploy-Config "Antigravity settings.json" (Join-Path $RepoRoot "config\antigravity\settings.json") $agySettings
    $rendered = [IO.File]::ReadAllText($agySettings) | ConvertFrom-Json
    $rendered.statusLine.command = $agyCommand
    [IO.File]::WriteAllText($agySettings, ($rendered | ConvertTo-Json -Depth 10), $utf8NoBom)
}
else {
    try {
        $raw = [IO.File]::ReadAllText($agySettings)
        if ($raw -and $raw -notmatch '"statusLine"') {
            $j = $raw | ConvertFrom-Json
            $j | Add-Member -NotePropertyName "statusLine" -NotePropertyValue ([PSCustomObject]@{
                type = "command"
                command = $agyCommand
                enabled = $true
            }) -Force
            [IO.File]::WriteAllText($agySettings, ($j | ConvertTo-Json -Depth 10), $utf8NoBom)
            Write-Ok "Antigravity settings.json (wired statusLine)"
        } else {
            Write-Skip "Antigravity settings.json" "exists (runtime-managed)"
        }
    } catch {
        Write-Skip "Antigravity settings.json" "exists (runtime-managed)"
    }
}

$agyMcp = Join-Path $agyDir "mcp.json"
if (-not (Test-Path $agyMcp)) {
    Deploy-Config "Antigravity mcp.json" (Join-Path $RepoRoot "config\antigravity\mcp.json") $agyMcp
}
else {
    Write-Skip "Antigravity mcp.json" "exists (runtime-managed)"
}

# Opencode: global config dir is ~\.config\opencode (same path on Windows:
# %USERPROFILE%\.config\opencode). Opencode does not parse @file imports in
# AGENTS.md; opencode.json lists the shared docs via its instructions array
# (paths relative to the config file). opencode.json is seed-if-missing
# ONLY - opencode writes user prefs (model, theme) into it at runtime.
$ocDir = Join-Path $HOME ".config\opencode"
Deploy-Config "Opencode AGENTS.md" (Join-Path $RepoRoot "config\opencode\AGENTS.md") (Join-Path $ocDir "AGENTS.md")
Deploy-AgentDocs "Opencode" $ocDir
$ocJson = Join-Path $ocDir "opencode.json"
if (-not (Test-Path $ocJson)) {
    Deploy-Config "Opencode opencode.json" (Join-Path $RepoRoot "config\opencode\opencode.json") $ocJson
}
else {
    Write-Skip "Opencode opencode.json" "exists (runtime-managed)"
}

# --- Secrets scaffold (machine-local, never committed) -------------------------
$secretsDir = Join-Path $HOME ".secrets"
$secretsEnv = Join-Path $secretsDir "env.ps1"
if (-not (Test-Path $secretsEnv)) {
    New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    @(
        '# Machine-local secrets - auto-sourced by the dotfiles profile. NEVER commit.'
        '# Do NOT set $env:ANTHROPIC_API_KEY here: a global key forces API billing even'
        '# with a subscription login.'
        '# $env:OPENAI_API_KEY = "..."   # only if not using codex login'
    ) | Set-Content -Path $secretsEnv
    Write-Ok "Secrets scaffold"
}
else {
    Write-Skip "Secrets scaffold" "exists"
}
# chmod-700 analogue (same pattern OpenSSH uses for key files): drop inherited
# ACEs, grant only the current user. Idempotent; applied even if seeded earlier.
icacls $secretsDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" *> $null
if ($LASTEXITCODE -ne 0) { Write-Warning "Could not tighten ACLs on $secretsDir" }

$sourceLine = '. "$HOME\PowerShell\dotfiles.profile.ps1"  # dotfiles local profile'
if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }
# Either spelling of the sidecar path counts as injected: older installs wrote
# the expanded path, and matching only $HOME appended a second dot-source,
# loading the whole profile twice per shell.
if (-not (Select-String -Path $profilePath -Pattern @('$HOME\PowerShell\dotfiles.profile.ps1', $sidecar) -SimpleMatch -Quiet)) {
    Add-Content -Path $profilePath -Value $sourceLine
    Write-Ok 'Profile injection'
}
else {
    Write-Skip 'Profile injection' 'already injected'
}

Write-Host ""
Write-Host "Done. Open Alacritty to get started." -ForegroundColor Green
Write-Host "  - Native pwsh 7 with the dotfiles profile; run herdr for panes and tabs"
Write-Host "  - Health check: pwsh -File windows\doctor.ps1"
Write-Host ""
