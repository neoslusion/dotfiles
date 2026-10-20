# Dotfiles PowerShell profile — thin parity layer with config/terminal/core.zsh.
# Dot-sourced from $PROFILE by windows/install.ps1 (injected, never overwrites).
# Boring by default: prompt, history, navigation, and the same modern-CLI
# aliases as the zsh side. No auto-mux — herdr covers multiplexing.

# --- Machine-local secrets (parity with core.zsh sourcing ~/.secrets/env.sh) ---
$dotfilesSecretsEnv = "$HOME\.secrets\env.ps1"
if ([IO.File]::Exists($dotfilesSecretsEnv)) { . $dotfilesSecretsEnv }

# --- Local module path (OneDrive escape) ---
# Known Folder Move points Documents into OneDrive. Do not put the
# OneDrive module directory on PSModulePath: module discovery then pays
# the sync/filter-driver cost on every interactive startup.
$dotfilesModules = "$HOME\.psmodules"
$dotfilesOneDriveModules = [IO.Path]::Combine([Environment]::GetFolderPath('MyDocuments'), 'PowerShell\Modules')
if ([IO.Directory]::Exists($dotfilesModules) -and ($env:PSModulePath -notlike "*$dotfilesModules*")) {
    $env:PSModulePath = $dotfilesModules + [IO.Path]::PathSeparator + $env:PSModulePath
}
if ($env:PSModulePath) {
    $env:PSModulePath = (@(foreach ($modulePath in $env:PSModulePath -split ';') {
        if ($modulePath -and $modulePath -ne $dotfilesOneDriveModules) { $modulePath }
    })) -join ';'
}

# --- Local bin dir ---
# Claude Code's native installer puts claude.exe here (the claude launcher
# below resolves it from PATH). Prepended per-session so it wins over anything
# machine-wide; mirrors ~\.local\bin on the Linux side.
$dotfilesLocalBin = "$HOME\.local\bin"
if ([IO.Directory]::Exists($dotfilesLocalBin) -and ($env:Path -notlike "*$dotfilesLocalBin*")) {
    $env:Path = "$dotfilesLocalBin;" + $env:Path
}

# Scoop's shim adds measurable process-start overhead for the Atuin hook.
# Put the pinned app directory first when it exists; Scoop updates preserve it.
$dotfilesAtuinBin = "$HOME\scoop\apps\atuin\current"
if ([IO.File]::Exists("$dotfilesAtuinBin\atuin.exe") -and
    ($env:Path -notlike "*$dotfilesAtuinBin*")) {
    $env:Path = "$dotfilesAtuinBin;" + $env:Path
}

# Cache command lookups: the profile probes the same tools repeatedly, and
# PATH resolution on this Windows host is not free. One batched probe keeps
# startup work proportional to the profile, not to the number of call sites.
$dotfilesCommandCache = @{}
$dotfilesToolNames = @('atuin', 'bat', 'eza', 'git', 'lazygit', 'nvim', 'starship', 'zoxide')
foreach ($toolName in $dotfilesToolNames) { $dotfilesCommandCache[$toolName] = $null }
# Restrict to applications: missing optional tools must not trigger module
# auto-discovery. ApplicationInfo.Name includes .exe, unlike our lookup keys.
foreach ($found in @(Get-Command -Name $dotfilesToolNames -CommandType Application -ErrorAction SilentlyContinue)) {
    $toolName = [IO.Path]::GetFileNameWithoutExtension($found.Name)
    if (-not $dotfilesCommandCache[$toolName]) {
        $dotfilesCommandCache[$toolName] = $found
    }
}
function Get-DotfilesCommand {
    param([string]$Name)

    return $dotfilesCommandCache[$Name]
}

function Set-DotfilesGitPrefix {
    param($Command)

    if ($env:EXEPATH -or -not $Command) { return }
    $root = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($Command.Source))
    if ($Command.Source -eq "$HOME\scoop\shims\git.exe") { $root = "$HOME\scoop\apps\git\current" }
    $architectures = @('mingw64', 'mingw32', 'clangarm64')
    if ([IO.Path]::GetFileName($root) -in $architectures) { $root = [IO.Path]::GetDirectoryName($root) }
    foreach ($architecture in $architectures) {
        if ([IO.Directory]::Exists([IO.Path]::Combine($root, $architecture, 'libexec', 'git-core'))) {
            # gitoxide otherwise spawns git to discover its installation prefix
            # on EACH Starship render. EXEPATH is the Git Bash hint for this same
            # native layout; configuration and repository discovery stay intact.
            $env:EXEPATH = $root
            return
        }
    }
}
Set-DotfilesGitPrefix (Get-DotfilesCommand 'git')

$dotfilesAtuinCommand = Get-DotfilesCommand 'atuin'
$dotfilesZoxideCommand = Get-DotfilesCommand 'zoxide'
if ($dotfilesZoxideCommand) {
    $dotfilesZoxideBin = [IO.Path]::GetDirectoryName($dotfilesZoxideCommand.Source)
    if ([IO.Directory]::Exists($dotfilesZoxideBin) -and
        ($env:Path -notlike "*$dotfilesZoxideBin*")) {
        $env:Path = "$dotfilesZoxideBin;" + $env:Path
    }
}

# --- PSReadLine (zsh-vi-mode + zsh-autosuggestions analogue) ---
# History prediction searches the entire history while typing. Atuin owns
# Ctrl+R, so prediction is unnecessary and adds latency on every keystroke.
$dotfilesInteractive = -not [Console]::IsOutputRedirected
if ($dotfilesInteractive) {
    try {
        Set-PSReadLineOption -EditMode Vi -PredictionSource None -PredictionViewStyle InlineView -BellStyle None
    } catch { }
}

# --- fzf keybindings (Ctrl+T files, Alt+C fuzzy-cd) ---
# Importing PSFzf costs ~300 ms (module files live on OneDrive) — defer to the
# first chord press. Ctrl+R remains Atuin's history search.
if ($dotfilesInteractive) {
    try {
        $dotfilesPsFzfChords = @{
            'Ctrl+t' = 'Invoke-FzfPsReadlineHandlerProvider'
            'Alt+c'  = 'Invoke-FzfPsReadlineHandlerSetLocation'
        }
        foreach ($entry in $dotfilesPsFzfChords.GetEnumerator()) {
            $handlerName = $entry.Value
            Set-PSReadLineKeyHandler -Key $entry.Key -BriefDescription 'PSFzf (lazy)' -ScriptBlock {
                Import-Module PSFzf -ErrorAction SilentlyContinue
                if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
                    Set-PsFzfOption @{
                        PSReadlineChordProvider    = 'Ctrl+t'
                        PSReadlineChordSetLocation = 'Alt+c'
                    }
                    if (Get-Command $handlerName -ErrorAction SilentlyContinue) { & $handlerName }
                }
            }.GetNewClosure()
        }
    } catch { }
}

# --- Modern replacements (parity with core.zsh) ---
if (Get-DotfilesCommand 'bat') {
    function cat { bat -p --paging=never @args }
}

if (Get-DotfilesCommand 'eza') {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons @args }
    function ll { eza -l --icons --git @args }
    function la { eza -la --icons --git @args }
    function lt { eza --tree --icons @args }
}

if (Get-DotfilesCommand 'lazygit') {
    function lg { lazygit @args }
}

if (Get-DotfilesCommand 'nvim') {
    $env:EDITOR = 'nvim'
    $env:VISUAL = 'nvim'
}

# --- Quick navigation ---
function .. { Set-Location .. }
function ... { Set-Location ../.. }
function .... { Set-Location ../../.. }

# --- Native-call module isolation (shared by the Claude and Codex launchers) ---
# Every native CLI launched below can spawn Windows PowerShell 5.1 as a child
# (Codex runs its updater that way). A WinPS child that inherits PS7's PSModulePath resolves
# modules against PS7-only directories, so even built-in cmdlets (Get-FileHash,
# ConvertFrom-Json, Get-Content) fail to load and the child dies. Clearing the
# variable lets each child rebuild its own defaults from its own install paths;
# the caller's value is restored afterwards so the session is unaffected.
#
# This guard spans the WHOLE native invocation, not just the child-spawn step:
# for `claude exec` or `codex exec` that is an entire agent session. That is
# deliberate and still correct, because anything spawned underneath rebuilds its
# own module path -- but do not read it as an updater-only workaround.
#
# Callers MUST assign their argument list to a named variable and reference THAT
# inside the scriptblock. `@args` inside a scriptblock refers to the scriptblock's
# own (empty) argument list, which silently drops every argument passed.
function _Invoke-WithIsolatedModulePath {
    param([scriptblock]$Action)
    $previousModulePath = $env:PSModulePath
    try {
        $env:PSModulePath = $null
        & $Action
    }
    finally { $env:PSModulePath = $previousModulePath }
}

function _Invoke-IsolatedNative {
    param([string]$Name, [object[]]$Arguments)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        Write-Error "$Name command not found"
        return
    }
    _Invoke-WithIsolatedModulePath { & $command.Source @Arguments }
}

function claude { _Invoke-IsolatedNative claude $args }
function codex { _Invoke-IsolatedNative codex $args }

function Set-DotfilesCache {
    param([string]$Path, [string]$Content)

    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    # Several tabs can start together. Publish a complete file so another shell
    # never dot-sources a partially written init script.
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $Content, [Text.UTF8Encoding]::new($true))
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Get-DotfilesInitScript {
    param([string]$Name, $Command, [string[]]$Arguments)

    $cache = [IO.Path]::Combine($dotfilesCacheDir, "$Name.ps1")
    $binary = [IO.FileInfo]::new($Command.Source)
    # File metadata invalidates the cache after upgrades without spawning --version.
    # Include the executable path and init options: both affect generated code.
    $identity = "# dotfiles-init: $($binary.FullName)|$($binary.Length)|$($binary.LastWriteTimeUtc.Ticks)|$($Arguments -join ' ')"
    if (-not [IO.File]::Exists($cache) -or
        -not [IO.File]::ReadAllText($cache).StartsWith("$identity`r`n")) {
        $init = (& $Command.Source @Arguments) -join "`r`n"
        if ($LASTEXITCODE -ne 0) { throw "$Name init failed (exit $LASTEXITCODE)" }
        Set-DotfilesCache $cache "$identity`r`n$init`r`n"
    }
    return $cache
}

function Get-DotfilesStarshipConfig {
    param([string]$Source, [string]$Cache)

    $config = [IO.FileInfo]::new($Source)
    if (-not $config.Exists) { return $null }
    $identity = "# dotfiles-source: $($config.FullName)|$($config.Length)|$($config.LastWriteTimeUtc.Ticks)"
    if (-not [IO.File]::Exists($Cache) -or
        -not [IO.File]::ReadAllText($Cache).StartsWith("$identity`r`n")) {
        # A false `when` still spawns sh. Omit the already-hidden Windows dirty
        # module from the format so Starship never evaluates it. The shared
        # source stays untouched, including the Linux dirty indicator.
        $text = [IO.File]::ReadAllText($Source).Replace('${custom.git_dirty}', '')
        Set-DotfilesCache $Cache "$identity`r`n$text"
    }
    return $Cache
}

# --- Prompt + smart cd (must come last: hooks the prompt function) ---
# ~/.cache/dotfiles is delete-safe: it rebuilds on the next shell start.
# Dot-source at script scope: loading inside a helper would scope away definitions.
$dotfilesCacheDir = "$HOME\.cache\dotfiles"

if ($dotfilesInteractive -and (Get-DotfilesCommand 'starship')) {
    $windowsConfig = "$dotfilesCacheDir\starship-windows.toml"
    # Honor an explicit user config; inherited dotfiles cache paths still refresh
    # from the managed source when starting a nested PowerShell session.
    if (-not $env:STARSHIP_CONFIG -or $env:STARSHIP_CONFIG -eq $windowsConfig) {
        $renderedConfig = Get-DotfilesStarshipConfig "$HOME\.config\starship.toml" $windowsConfig
        if ($renderedConfig) { $env:STARSHIP_CONFIG = $renderedConfig }
    }
    $env:STARSHIP_GIT_DIRTY_SKIP = "1"
    # Report cwd to the terminal (OSC 7)
    function Invoke-Starship-PreCommand {
        $loc = $executionContext.SessionState.Path.CurrentLocation
        if ($loc.Provider.Name -eq 'FileSystem') {
            $esc = [char]27
            $path = $loc.ProviderPath -replace '\\', '/'
            $Host.UI.Write("$esc]7;file://$env:COMPUTERNAME/$path$esc\")
        }
    }
    $cache = Get-DotfilesInitScript 'starship' (Get-DotfilesCommand 'starship') @('init', 'powershell', '--print-full-init')
    . $cache
}

if ($dotfilesZoxideCommand) {
    # z/zi still work; --hook none avoids wrapping every prompt in a no-op hook.
    # Directory scoring was already disabled by the previous empty hook override.
    $cache = Get-DotfilesInitScript 'zoxide' $dotfilesZoxideCommand @('init', 'powershell', '--hook', 'none')
    . $cache
}

# --- Atuin shell history (parity with core.zsh) ---
# Keep Ctrl+R interactive search, but do not intercept UpArrow: native
# PSReadLine history navigation is faster and predictable for normal use.
if ($dotfilesInteractive -and $dotfilesAtuinCommand) {
    $cache = Get-DotfilesInitScript 'atuin' $dotfilesAtuinCommand @('init', 'powershell', '--disable-up-arrow')
    . $cache
}
