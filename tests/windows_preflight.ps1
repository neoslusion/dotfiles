$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Failures = @()
$StrictUtf8 = New-Object Text.UTF8Encoding($true, $true)
$PowerShellFiles = @(@(& git -C $Root ls-files '*.ps1' '*.psm1' '*.psd1') + 'tests/windows_preflight.ps1' | Select-Object -Unique)

foreach ($Relative in $PowerShellFiles) {
    $Path = Join-Path $Root $Relative
    $Bytes = [IO.File]::ReadAllBytes($Path)
    $HasBom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
    if (-not $HasBom) { $Failures += "${Relative}: missing UTF-8 BOM"; continue }
    try { $Text = $StrictUtf8.GetString($Bytes, 3, $Bytes.Length - 3) }
    catch { $Failures += "${Relative}: invalid UTF-8"; continue }
    if ($Text.Contains("`n") -and $Text.Replace("`r`n", '').Contains("`n")) {
        $Failures += "${Relative}: non-CRLF line ending"
    }

    $Tokens = $null
    $ParseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors) | Out-Null
    foreach ($Error in $ParseErrors) { $Failures += "${Relative}: $($Error.Message)" }
    foreach ($Token in $Tokens) {
        if ($Token.Kind -in 'StringLiteral','StringExpandable','HereStringLiteral','HereStringExpandable' -and $Token.Text -match '[^\x00-\x7F]') {
            $Failures += "${Relative}:$($Token.Extent.StartLineNumber): non-ASCII string literal"
        }
    }
}

Get-ChildItem (Join-Path $Root 'windows') -Recurse -File | Where-Object Extension -in '.ps1','.lua' | ForEach-Object {
    $Matches = Select-String -Path $_.FullName -Pattern '[A-Za-z]:\\sandboxes'
    foreach ($Match in $Matches) { $Failures += "$($_.FullName):$($Match.LineNumber): fixed workspace path" }
}

# Cross-installer source-existence: every repo path windows\install.ps1
# references as a deploy source must exist. Guards against the class of bug
# where a Linux-side refactor (e.g. moving shared docs into config/agents)
# leaves install.ps1 pointing at deleted files.
$InstallScriptText = [IO.File]::ReadAllText((Join-Path $Root 'windows\install.ps1'))
$Referenced = @()
$Referenced += [regex]::Matches($InstallScriptText, 'Join-Path \$RepoRoot\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
$Referenced += [regex]::Matches($InstallScriptText, 'Join-Path \$PSScriptRoot\s+(["''])([^"'']+)\1') | ForEach-Object { Join-Path 'windows' $_.Groups[2].Value }
$Referenced += [regex]::Matches($InstallScriptText, 'Join-Path \$agentsDir\s+"([^"]+)"') | ForEach-Object { Join-Path 'config\agents' $_.Groups[1].Value }
foreach ($Relative in ($Referenced | Select-Object -Unique)) {
    if ($Relative -match '[*?]') {
        $Parent = Join-Path $Root (Split-Path $Relative -Parent)
        $Filter = Split-Path $Relative -Leaf
        if (-not (Test-Path $Parent) -or -not (Get-ChildItem $Parent -Filter $Filter -ErrorAction SilentlyContinue)) {
            $Failures += "windows\install.ps1: referenced glob has no match: $Relative"
        }
    }
    elseif (-not (Test-Path (Join-Path $Root $Relative))) {
        $Failures += "windows\install.ps1: referenced source missing: $Relative"
    }
}

# The staged Windows test must exercise both supported configuration-only
# coverage and the full-install package-plan seam.
if ($InstallScriptText -notmatch '\[switch\]\$DryRun' -or
    $InstallScriptText -notmatch 'Write-DryRunPackage') {
    $Failures += 'windows\install.ps1: -DryRun package-plan seam is missing'
}

if ($Failures.Count) {
    $Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Output 'Windows preflight passed'
