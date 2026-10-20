$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Tokens = $null
$ParseErrors = $null
$Ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'windows/profile.ps1'), [ref]$Tokens, [ref]$ParseErrors)
if ($ParseErrors.Count) { throw 'Profile parse failed' }
foreach ($Name in @('claude', 'codex', '_Invoke-IsolatedNative', '_Invoke-WithIsolatedModulePath')) {
    $Function = $Ast.Find({ param($Node)
        $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name
    }, $true)
    . ([scriptblock]::Create($Function.Extent.Text))
}
# Argument forwarding across the isolation scriptblock. Get-Command is stubbed to
# resolve a local function standing in for the native binary, so this stays
# cross-platform. If the helper wrote `@args` inside the scriptblock instead of
# the captured variable, the argument list would arrive empty (the scriptblock
# has its own $args) and fail here rather than silently eating user arguments.
function Invoke-NativeStub { [pscustomobject]@{ Arguments = $args } }
function Get-Command { [pscustomobject]@{ Source = 'Invoke-NativeStub' } }
foreach ($Launcher in @('claude', 'codex')) {
    foreach ($InputArgs in @(@(), @('--version'), @('exec', '--model', 'test-model', 'prompt with spaces'))) {
        $Result = & $Launcher @InputArgs
        if ((ConvertTo-Json @($Result.Arguments) -Compress) -ne (ConvertTo-Json @($InputArgs) -Compress)) {
            throw "$Launcher did not preserve its argument list"
        }
    }
}
Remove-Item -LiteralPath 'Function:\Get-Command', 'Function:\Invoke-NativeStub'

# Cache hits must not spawn init again; upgrades/options/paths must invalidate it.
# Load just the cache helpers so this test never sources the user's real profile.
& {
    foreach ($Name in @('Set-DotfilesCache', 'Get-DotfilesInitScript', 'Get-DotfilesStarshipConfig', 'Set-DotfilesGitPrefix')) {
        $Function = $Ast.Find({ param($Node)
            $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name
        }, $true)
        . ([scriptblock]::Create($Function.Extent.Text))
    }
    $FixtureDir = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-profile-cache-' + [guid]::NewGuid())
    $dotfilesCacheDir = Join-Path $FixtureDir 'cache'
    $PreviousGitPrefix = $env:EXEPATH
    try {
        [IO.Directory]::CreateDirectory($FixtureDir) | Out-Null
        $GitRoot = Join-Path $FixtureDir 'git'
        [IO.Directory]::CreateDirectory((Join-Path $GitRoot 'mingw64\libexec\git-core')) | Out-Null
        foreach ($GitExecutable in @('cmd\git.exe', 'mingw64\bin\git.exe')) {
            $env:EXEPATH = $null
            Set-DotfilesGitPrefix ([pscustomobject]@{ Source = Join-Path $GitRoot $GitExecutable })
            if ($env:EXEPATH -ne $GitRoot) { throw 'Git prefix did not match the selected installation' }
        }
        $env:EXEPATH = 'user-selected-prefix'
        Set-DotfilesGitPrefix ([pscustomobject]@{ Source = Join-Path $GitRoot 'cmd\git.exe' })
        if ($env:EXEPATH -ne 'user-selected-prefix') { throw 'Git prefix overwrote the user environment' }
        $env:EXEPATH = $null
        Set-DotfilesGitPrefix ([pscustomobject]@{ Source = Join-Path $FixtureDir 'unrelated\git.exe' })
        if ($env:EXEPATH) { throw 'Git prefix guessed an unsupported installation layout' }
        $Binary = Join-Path $FixtureDir 'tool.ps1'
        $Counter = Join-Path $FixtureDir 'calls.txt'
        $Body = @'
$ErrorActionPreference = 'Stop'
[IO.File]::AppendAllText((Join-Path $PSScriptRoot 'calls.txt'), "call`n")
$global:LASTEXITCODE = 0
'function global:Invoke-CacheFixture { "cached" }'
'# arguments: ' + ($args -join ' ')
'@
        [IO.File]::WriteAllText($Binary, $Body)
        $Command = [pscustomobject]@{ Source = $Binary }
        $Cache = Get-DotfilesInitScript 'fixture' $Command @('init', 'powershell')
        . $Cache
        if ((Invoke-CacheFixture) -ne 'cached') { throw 'Cached init did not define its function' }
        $null = Get-DotfilesInitScript 'fixture' $Command @('init', 'powershell')
        if ([IO.File]::ReadAllLines($Counter).Count -ne 1) { throw 'Cache hit reran init' }
        [IO.File]::AppendAllText($Binary, "`n# upgrade")
        $null = Get-DotfilesInitScript 'fixture' $Command @('init', 'powershell')
        $null = Get-DotfilesInitScript 'fixture' $Command @('init', 'powershell', '--hook', 'none')
        $OtherBinary = Join-Path $FixtureDir 'other-tool.ps1'
        [IO.File]::Copy($Binary, $OtherBinary)
        $null = Get-DotfilesInitScript 'fixture' ([pscustomobject]@{ Source = $OtherBinary }) @('init', 'powershell', '--hook', 'none')
        if ([IO.File]::ReadAllLines($Counter).Count -ne 4) { throw 'Cache did not follow executable/options changes' }
        if (Get-ChildItem $dotfilesCacheDir -Filter '*.tmp') { throw 'Cache left temporary files behind' }

        $Source = Join-Path $FixtureDir 'starship.toml'
        $Rendered = Join-Path $dotfilesCacheDir 'starship-windows.toml'
        $Toml = 'format = "$character$directory$git_branch${custom.git_dirty}$git_state$cmd_duration$jobs"'
        [IO.File]::WriteAllText($Source, $Toml)
        $null = Get-DotfilesStarshipConfig $Source $Rendered
        $Result = [IO.File]::ReadAllText($Rendered)
        if ($Result.Contains('${custom.git_dirty}')) { throw 'Windows prompt still evaluates the hidden dirty module' }
        if (-not $Result.Contains('$git_branch') -or -not $Result.Contains('$git_state$cmd_duration$jobs')) {
            throw 'Windows prompt lost its visible modules'
        }
        if ([IO.File]::ReadAllText($Source) -cne $Toml) { throw 'Rendering changed the shared Starship source' }
        $Timestamp = [IO.File]::GetLastWriteTimeUtc($Rendered)
        $null = Get-DotfilesStarshipConfig $Source $Rendered
        if ([IO.File]::GetLastWriteTimeUtc($Rendered) -ne $Timestamp) { throw 'Config cache hit rewrote the file' }
        [IO.File]::AppendAllText($Source, "`n# changed config")
        $null = Get-DotfilesStarshipConfig $Source $Rendered
        if (-not [IO.File]::ReadAllText($Rendered).Contains('# changed config')) { throw 'Config cache did not follow source changes' }
    }
    finally {
        $env:EXEPATH = $PreviousGitPrefix
        Remove-Item -LiteralPath 'Function:\Invoke-CacheFixture' -ErrorAction SilentlyContinue
        if (-not [IO.Path]::GetFullPath($FixtureDir).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Fixture cleanup escaped the temporary directory'
        }
        Remove-Item -LiteralPath $FixtureDir -Recurse -Force
    }
}
if ($env:OS -eq 'Windows_NT') {
    # A native intermediary reproduces the updater's inheritance of PS7 paths.
    $FixtureDir = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-codex-' + [guid]::NewGuid())
    $SavedPath = $env:PATH
    $SavedModulePath = $env:PSModulePath
    $SavedHashFixture = $env:DOTFILES_CODEX_HASH_FIXTURE
    try {
        New-Item -ItemType Directory -Path $FixtureDir | Out-Null
        $env:DOTFILES_CODEX_HASH_FIXTURE = Join-Path $FixtureDir 'empty.txt'
        [IO.File]::WriteAllText($env:DOTFILES_CODEX_HASH_FIXTURE, '')
        # One fixture body, installed under both native names the launchers
        # resolve. It reproduces a native CLI spawning Windows PowerShell: if
        # PSModulePath is inherited the child cannot resolve even Get-FileHash,
        # so the module isolation is what makes exit 23 reachable.
        $NativeFixture = @'
@echo off
if defined PSModulePath exit /b 91
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; (Get-FileHash -LiteralPath $env:DOTFILES_CODEX_HASH_FIXTURE).Hash"
if errorlevel 1 exit /b 92
exit /b 23
'@
        [IO.File]::WriteAllText((Join-Path $FixtureDir 'codex.cmd'), $NativeFixture)
        [IO.File]::WriteAllText((Join-Path $FixtureDir 'claude.cmd'), $NativeFixture)
        $env:PATH = "$FixtureDir;$env:WINDIR\System32\WindowsPowerShell\v1.0;$env:WINDIR\System32"
        foreach ($ModulePath in @($SavedModulePath, $null)) {
            foreach ($Launcher in @('codex', 'claude')) {
                $env:PSModulePath = $ModulePath
                $Result = & $Launcher --version
                if ($LASTEXITCODE -ne 23) { throw "$Launcher failed the native module inheritance check (exit $LASTEXITCODE)" }
                if ($Result -ne 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') {
                    throw "$Launcher updater subprocess could not hash a file"
                }
                if ($env:PSModulePath -cne $ModulePath) { throw "$Launcher changed the caller module path" }
            }
        }
    }
    finally {
        $env:PATH = $SavedPath
        $env:PSModulePath = $SavedModulePath
        $env:DOTFILES_CODEX_HASH_FIXTURE = $SavedHashFixture
        if (-not [IO.Path]::GetFullPath($FixtureDir).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Fixture cleanup escaped the temporary directory'
        }
        Remove-Item -LiteralPath $FixtureDir -Recurse -Force
    }
}
Write-Output 'Windows profile launcher, module inheritance, Git prefix, and cache tests passed.'
