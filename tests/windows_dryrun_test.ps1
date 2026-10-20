# windows_dryrun_test.ps1 - staged dry run of the Windows installer.
# Copies the repo into a temp sandbox, redirects USERPROFILE/LOCALAPPDATA/
# APPDATA there, and runs windows\install.ps1 in both ConfigOnly and full
# DryRun modes. Verifies package selection, deployed agent homes, configs,
# tokens, and seeds without touching the real user profile. Idempotency and
# unrelated content preservation use a second ConfigOnly run.
#
# Windows known-folder lookups ignore redirected environment variables.
# Patch the profile dir in the staged copy.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Failures = @()
$Sandbox = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-dryrun-" + [Guid]::NewGuid().ToString('N'))
$SandboxRepo = Join-Path $Sandbox 'repo'
$FakeHome = Join-Path $Sandbox 'home'
$Docs = Join-Path $Sandbox 'docs'
$LocalAppData = Join-Path $Sandbox 'localappdata'
$AppData = Join-Path $Sandbox 'appdata'
$PreviousEnvironment = @{}
foreach ($Name in @('USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'DOTFILES_DRYRUN_MYDOCS', 'PATH', 'CLAUDE_CONFIG_DIR')) {
    $PreviousEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
}

function Write-Fail($Message) {
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:Failures += $Message
}
function Assert-Exists($Path, $What) {
    if (-not (Test-Path $Path)) { Write-Fail "missing ${What}: ${Path}" }
}
function Assert-NotExists($Path, $What) {
    if (Test-Path $Path) { Write-Fail "${What} must not exist: ${Path}" }
}
function Assert-Contains($Path, $Needle, $What) {
    Assert-Exists $Path $What
    if (-not ((Get-Content $Path -Raw).Contains($Needle))) { Write-Fail "${What} does not contain '$Needle': ${Path}" }
}
function Assert-NotContains($Path, $Needle, $What) {
    Assert-Exists $Path $What
    if ((Get-Content $Path -Raw).Contains($Needle)) { Write-Fail "${What} must not contain '$Needle': ${Path}" }
}
function Assert-Match($Text, $Pattern, $What) {
    if ($Text -notmatch $Pattern) { Write-Fail "${What} does not match '$Pattern'" }
}
function Assert-JsonCommandContains($Path, $Needle, $What) {
    Assert-Exists $Path $What
    try {
        $Json = Get-Content $Path -Raw | ConvertFrom-Json
        if (-not ([string]$Json.statusLine.command).Contains($Needle)) {
            Write-Fail "${What} does not contain '$Needle': ${Path}"
        }
    }
    catch {
        Write-Fail "${What} is not valid JSON: ${Path}"
    }
}
function Assert-Identical($PathA, $PathB, $What) {
    if (-not (Test-Path $PathA) -or -not (Test-Path $PathB)) {
        Write-Fail "${What} identity check failed: ${PathA} or ${PathB} missing"
        return
    }
    if ((Get-FileHash $PathA).Hash -ne (Get-FileHash $PathB).Hash) {
        Write-Fail "${What} differs between install and repo: ${PathB}"
    }
}

try {
    # 1. Stage the repo (working tree, minus .git).
    foreach ($Item in Get-ChildItem $Root -Recurse -File -Force) {
        if ($Item.FullName -like '*\.git\*' -or $Item.FullName -eq (Join-Path $Root '.git')) { continue }
        $Relative = $Item.FullName.Substring($Root.Length + 1)
        $Dest = Join-Path $SandboxRepo $Relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $Dest) -Force | Out-Null
        Copy-Item $Item.FullName $Dest -Force
    }
    New-Item -ItemType Directory -Path $SandboxRepo, $FakeHome, $Docs, $LocalAppData, $AppData -Force | Out-Null

    # User-managed instructions, commands, and skills must survive both installs.
    $AgentPaths = @('.claude', '.codex', '.gemini\antigravity-cli', '.config\opencode')
    $UnmanagedFiles = @('CUSTOM.md', 'commands\custom.md', 'skills\custom\SKILL.md')
    $UnmanagedSource = Join-Path $Sandbox 'unmanaged.md'
    Set-Content $UnmanagedSource 'user-managed content'
    foreach ($AgentPath in $AgentPaths) {
        foreach ($File in $UnmanagedFiles) {
            $Target = Join-Path (Join-Path $FakeHome $AgentPath) $File
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
            Copy-Item $UnmanagedSource $Target
        }
    }

    # Claude settings.json and CLAUDE.md are shared with other installers (e.g.
    # rtk): their entries must survive both installs, and the pre-merge
    # settings are kept as .bak.
    $ClaudeHome = Join-Path $FakeHome '.claude'
    New-Item -ItemType Directory -Path $ClaudeHome -Force | Out-Null
    Copy-Item (Join-Path $Root 'tests\fixtures\claude_settings_live.json') (Join-Path $ClaudeHome 'settings.json')
    Set-Content (Join-Path $ClaudeHome 'CLAUDE.md') '@RTK.md'
    New-Item -ItemType Directory -Path (Join-Path $FakeHome '.codex') -Force | Out-Null
    Set-Content (Join-Path $FakeHome '.codex\AGENTS.md') '@RTK.md'
    # Older installs injected the sidecar by its expanded path; that must count
    # as injected, or every shell dot-sources the profile twice.
    $ProfileFile = Join-Path $Docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfileFile) -Force | Out-Null
    Set-Content $ProfileFile ('."' + (Join-Path $FakeHome 'PowerShell\dotfiles.profile.ps1') + '"  # dotfiles local profile')

    # 2. Patch the profileDir line in the staged copy only
    $StagedInstaller = Join-Path $SandboxRepo 'windows\install.ps1'
    $Text = [IO.File]::ReadAllText($StagedInstaller)
    $Patched = $Text.Replace("[Environment]::GetFolderPath('MyDocuments')", '$env:DOTFILES_DRYRUN_MYDOCS')
    if ($Text -eq $Patched) { throw 'dry-run patch target not found in staged install.ps1' }
    [IO.File]::WriteAllText($StagedInstaller, $Patched, (New-Object Text.UTF8Encoding($true)))

    # 3. Run the installer with redirected user dirs
    $env:USERPROFILE = $FakeHome
    $env:LOCALAPPDATA = $LocalAppData
    $env:APPDATA = $AppData
    $env:DOTFILES_DRYRUN_MYDOCS = $Docs
    # Exercise registration without calling the user's installed Claude CLI.
    # The installer must not pin CLAUDE_CONFIG_DIR: the CLI would then look for
    # its global config at ~\.claude\.claude.json and create a stray one.
    $env:CLAUDE_CONFIG_DIR = $null
    $MockBin = Join-Path $Sandbox 'bin'
    New-Item -ItemType Directory -Path $MockBin -Force | Out-Null
    $MockClaude = @'
$ErrorActionPreference = 'Stop'
if ($env:CLAUDE_CONFIG_DIR) { throw 'Installer pinned CLAUDE_CONFIG_DIR' }
[IO.File]::AppendAllText((Join-Path $env:USERPROFILE '.claude\mod-registration.log'), ($args -join ' ') + [Environment]::NewLine)
$global:LASTEXITCODE = 0
'@
    [IO.File]::WriteAllText((Join-Path $MockBin 'claude.ps1'), $MockClaude.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.UTF8Encoding]::new($true))
    $env:PATH = $MockBin + [IO.Path]::PathSeparator + $env:PATH
    & pwsh -NoProfile -File $StagedInstaller -ConfigOnly *> $null
    if ($LASTEXITCODE -ne 0) { Write-Fail "installer exited $LASTEXITCODE" }

    # Full-install DryRun exercises package selection without invoking a
    # package manager, bootstrapping Scoop, or downloading any installer.
    $FullInstallLog = Join-Path $Sandbox 'full-install-dryrun.log'
    & pwsh -NoProfile -File $StagedInstaller -DryRun *>&1 | Tee-Object -FilePath $FullInstallLog | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Fail "full installer dry-run exited $LASTEXITCODE" }
    $FullInstallText = Get-Content $FullInstallLog -Raw
    Assert-Match $FullInstallText 'DRY-RUN scoop git \(Git\)' 'Git Scoop selection'
    Assert-Match $FullInstallText 'DRY-RUN scoop tree-sitter \(tree-sitter CLI\)' 'tree-sitter Scoop selection'
    Assert-Match $FullInstallText 'DRY-RUN installer preview \(Herdr\)' 'Herdr installer selection'
    Assert-Match $FullInstallText 'DRY-RUN PowerShellGet PSFzf \(PSFzf\)' 'PSFzf module selection'
    $WingetInstallLog = Join-Path $Sandbox 'winget-install-dryrun.log'
    & pwsh -NoProfile -File $StagedInstaller -DryRun -Winget *>&1 | Tee-Object -FilePath $WingetInstallLog | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Fail "winget installer dry-run exited $LASTEXITCODE" }
    $WingetInstallText = Get-Content $WingetInstallLog -Raw
    Assert-Match $WingetInstallText 'DRY-RUN winget Git.Git \(Git\)' 'Git winget selection'
    Assert-Match $WingetInstallText 'DRY-RUN winget equalsraf.win32yank \(win32yank\)' 'win32yank winget selection'
    Assert-Match $WingetInstallText 'DRY-RUN scoop tree-sitter \(tree-sitter CLI\)' 'tree-sitter remains Scoop-only'

    # 4. Deployed content assertions
    $AgentsDir = Join-Path $Root 'config\agents'
    $AgentHomes = @{
        'Claude'       = Join-Path $FakeHome '.claude'
        'Codex'        = Join-Path $FakeHome '.codex'
        'Antigravity'  = Join-Path $FakeHome '.gemini\antigravity-cli'
        'Opencode'     = Join-Path $FakeHome '.config\opencode'
    }
    foreach ($Label in $AgentHomes.Keys) {
        $Dir = $AgentHomes[$Label]
        Assert-Exists (Join-Path $Dir 'ENGINEERING.md') "$Label ENGINEERING.md"
        Assert-Identical (Join-Path $Dir 'ENGINEERING.md') (Join-Path $AgentsDir 'ENGINEERING.md') "$Label ENGINEERING.md"
    }

    Assert-Exists (Join-Path $FakeHome '.claude\settings.json.bak') 'settings.json .bak'
    $ClaudeStatuslinePath = (Join-Path $FakeHome '.claude\statusline.py') -replace '\\', '/'
    Assert-NotContains (Join-Path $FakeHome '.claude\settings.json') '__PYTHON__' 'Claude statusline interpreter token'
    Assert-JsonCommandContains (Join-Path $FakeHome '.claude\settings.json') $ClaudeStatuslinePath 'Claude statusline'
    Assert-Exists (Join-Path $FakeHome '.claude\CLAUDE.md') 'Claude CLAUDE.md'
    Assert-Identical (Join-Path $FakeHome '.claude\mods\.claude-plugin\marketplace.json') (Join-Path $Root 'config\claude\mods\.claude-plugin\marketplace.json') 'Claude mods marketplace'
    Assert-Identical (Join-Path $FakeHome '.claude\mods\pretty-tools\hooks\register.tsx') (Join-Path $Root 'config\claude\mods\pretty-tools\hooks\register.tsx') 'Claude pretty-tools mod'
    Assert-Exists (Join-Path $FakeHome '.codex\config.toml') 'Codex base config'
    Assert-Exists (Join-Path $FakeHome '.gemini\antigravity-cli\settings.json') 'Antigravity settings.json'
    $AntigravityStatuslinePath = (Join-Path $FakeHome '.gemini\antigravity-cli\statusline.py') -replace '\\', '/'
    Assert-JsonCommandContains (Join-Path $FakeHome '.gemini\antigravity-cli\settings.json') $AntigravityStatuslinePath 'Antigravity statusline rendering'
    Assert-Exists (Join-Path $FakeHome '.gemini\antigravity-cli\mcp.json') 'Antigravity mcp.json'
    Assert-Exists (Join-Path $FakeHome '.gemini\antigravity-cli\statusline.py') 'Antigravity statusline.py'
    Assert-Identical (Join-Path $FakeHome '.config\opencode\AGENTS.md') (Join-Path $Root 'config\opencode\AGENTS.md') 'Opencode AGENTS.md'
    Assert-Identical (Join-Path $FakeHome '.config\opencode\opencode.json') (Join-Path $Root 'config\opencode\opencode.json') 'opencode.json seed'

    # Alacritty only reads %APPDATA% on Windows. The negative assertion pins the
    # design decision: a manifest `copy` entry under config/ would deploy to
    # ~/.config/alacritty, which this platform never consults.
    Assert-Identical (Join-Path $AppData 'alacritty\alacritty.toml') (Join-Path $Root 'windows\alacritty\alacritty.toml') 'Alacritty config'
    Assert-NotExists (Join-Path $FakeHome '.config\alacritty\alacritty.toml') 'XDG Alacritty config (wrong location on Windows)'
    Assert-Exists (Join-Path $FakeHome '.wslconfig') 'wslconfig'
    Assert-Identical (Join-Path $FakeHome '.config\starship.toml') (Join-Path $Root 'config\terminal\starship.toml') 'Starship config'
    Assert-Identical (Join-Path $LocalAppData 'nvim\init.lua') (Join-Path $Root 'config\nvim\init.lua') 'Neovim config'
    Assert-Identical (Join-Path $LocalAppData 'lazygit\config.yml') (Join-Path $Root 'config\lazygit\config.yml') 'Lazygit config'
    Assert-Identical (Join-Path $AppData 'herdr\config.toml') (Join-Path $Root 'config\herdr\config.toml') 'Herdr config'
    Assert-Identical (Join-Path $FakeHome 'PowerShell\dotfiles.profile.ps1') (Join-Path $Root 'windows\profile.ps1') 'local profile sidecar'
    Assert-Contains (Join-Path $Docs 'PowerShell\Microsoft.PowerShell_profile.ps1') 'PowerShell\dotfiles.profile.ps1' 'local profile injection'
    Assert-Exists (Join-Path $FakeHome '.secrets\env.ps1') 'secrets env scaffold'


    # 5. Idempotency: runtime-managed files must survive a refresh
    Add-Content (Join-Path $FakeHome '.codex\config.toml') 'trusted_projects=1'
    Add-Content (Join-Path $FakeHome '.config\opencode\opencode.json') '//user-pref'
    Add-Content (Join-Path $AppData 'herdr\config.toml') '[ui] tab_bar_position = "bottom"'
    # Copy-managed configs are only backed up when their content changed.
    Add-Content (Join-Path $LocalAppData 'lazygit\config.yml') '# local edit'
    # Claude rewrites settings.json in its own JSON style; a refresh that
    # changes no content must leave the file as it is (no rewrite, no .bak).
    $SettingsPath = Join-Path $ClaudeHome 'settings.json'
    $Restyled = [IO.File]::ReadAllText($SettingsPath) | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress
    [IO.File]::WriteAllText($SettingsPath, $Restyled)
    & pwsh -NoProfile -File $StagedInstaller -ConfigOnly *> $null
    if ($LASTEXITCODE -ne 0) { Write-Fail "second installer run exited $LASTEXITCODE" }
    Assert-Contains (Join-Path $LocalAppData 'lazygit\config.yml.bak') '# local edit' 'backup of the changed Lazygit config'
    Assert-Identical (Join-Path $LocalAppData 'lazygit\config.yml') (Join-Path $Root 'config\lazygit\config.yml') 'restored Lazygit config'
    foreach ($Unchanged in @((Join-Path $LocalAppData 'nvim'), (Join-Path $ClaudeHome 'mods'), (Join-Path $ClaudeHome 'ENGINEERING.md'), (Join-Path $FakeHome '.config\starship.toml'))) {
        Assert-NotExists "$Unchanged.bak" 'backup of an unchanged config'
    }
    if ([IO.File]::ReadAllText($SettingsPath) -cne $Restyled) {
        Write-Fail 'an unchanged Claude settings.json was rewritten'
    }
    if (@(Get-Content $ProfileFile | Where-Object { $_ -like '*dotfiles.profile.ps1*' }).Count -ne 1) {
        Write-Fail '$PROFILE must dot-source the sidecar exactly once'
    }
    $Registration = @(Get-Content (Join-Path $ClaudeHome 'mod-registration.log'))
    $ExpectedCommands = @("plugin marketplace add $(Join-Path $ClaudeHome 'mods')")
    $Marketplace = Get-Content (Join-Path $Root 'config\claude\mods\.claude-plugin\marketplace.json') -Raw | ConvertFrom-Json
    foreach ($Mod in $Marketplace.plugins) { $ExpectedCommands += "plugin install $($Mod.name)@my-mods --scope user" }
    foreach ($Command in $ExpectedCommands) {
        if (@($Registration | Where-Object { $_ -ceq $Command }).Count -ne 2) {
            Write-Fail "Claude registration must run on both installs: $Command"
        }
    }
    $Settings = Get-Content (Join-Path $ClaudeHome 'settings.json') -Raw | ConvertFrom-Json
    $SettingsChecks = [ordered]@{
        'foreign key kept'          = $Settings.cleanupPeriodDays -eq 3650
        'rtk hook kept'             = $Settings.hooks.PreToolUse[0].hooks[0].command -eq 'rtk hook claude'
        'foreign hook kept'         = $Settings.hooks.SessionStart[0].matcher -eq 'startup'
        'user plugin kept'          = $Settings.enabledPlugins.'caveman@caveman' -eq $true
        'nested user key kept'      = $Settings.env.USER_VAR -eq 'kept'
        'nested repo key merged'    = $Settings.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC -eq '1'
        'repo key wins'             = $Settings.theme -eq 'dark'
    }
    foreach ($Check in $SettingsChecks.Keys) {
        if (-not $SettingsChecks[$Check]) { Write-Fail "Claude settings.json merge: $Check" }
    }
    $ImportFiles = [ordered]@{
        '.claude\CLAUDE.md' = '@ENGINEERING.md'
        '.codex\AGENTS.md'  = '@~/.codex/ENGINEERING.md'
    }
    foreach ($File in $ImportFiles.Keys) {
        $Lines = @(Get-Content (Join-Path $FakeHome $File))
        if ($Lines -cnotcontains '@RTK.md') { Write-Fail "$File lost the @RTK.md import" }
        if (@($Lines | Where-Object { $_ -ceq $ImportFiles[$File] }).Count -ne 1) {
            Write-Fail "$File must import $($ImportFiles[$File]) exactly once"
        }
    }
    Assert-Contains (Join-Path $FakeHome '.codex\config.toml') 'trusted_projects=1' 'codex config.toml preservation'
    Assert-Contains (Join-Path $FakeHome '.config\opencode\opencode.json') '//user-pref' 'opencode.json preservation'
    Assert-Contains (Join-Path $AppData 'herdr\config.toml') 'tab_bar_position' 'herdr config.toml preservation'
    foreach ($AgentPath in $AgentPaths) {
        foreach ($File in $UnmanagedFiles) {
            $Target = Join-Path (Join-Path $FakeHome $AgentPath) $File
            Assert-Identical $Target $UnmanagedSource "$AgentPath $File preservation"
        }
    }
}
finally {
    foreach ($Name in $PreviousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $PreviousEnvironment[$Name], 'Process')
    }
    $Resolved = [IO.Path]::GetFullPath($Sandbox)
    $TempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    if (-not $Resolved.StartsWith($TempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($Resolved) -notlike 'dotfiles-dryrun-*') { throw 'Invalid test cleanup path' }
    if (Test-Path -LiteralPath $Resolved) { Remove-Item -LiteralPath $Resolved -Recurse -Force }
}

if ($Failures.Count) {
    Write-Fail "$($Failures.Count) assertion(s) failed"
    exit 1
}
Write-Output 'Windows installer dry-run passed'
