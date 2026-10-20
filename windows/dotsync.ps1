<#
.SYNOPSIS
  dotsync — fast redeploy of a single config module (native Windows).

.DESCRIPTION
  The dotfiles deploy by COPY, not symlink. Edits in the repo don't go live
  until re-deployed. This is the one-command fix for the Windows side, mirroring
  scripts/dotsync on Linux/WSL: copy config\<module> to its deployed location
  without running the full windows\install.ps1.

  On Windows, Neovim reads %LOCALAPPDATA%\nvim and Lazygit reads
  %LOCALAPPDATA%\lazygit — NOT ~/.config. The mapping below reflects that.
  Only the modules actually deployed on Windows are syncable here.

  Templated/multi-target configs (claude, codex, antigravity) are
  intentionally NOT handled; use the installer:
      pwsh -File windows\install.ps1

.EXAMPLE
  .\dotsync.ps1 nvim
.EXAMPLE
  .\dotsync.ps1 nvim lazygit
.EXAMPLE
  .\dotsync.ps1 all
.EXAMPLE
  .\dotsync.ps1 -List
.EXAMPLE
  .\dotsync.ps1 -DryRun nvim
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Modules,
    [switch] $List,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# Repo root = parent of this script's folder (windows\ -> repo)
$RepoRoot  = Split-Path -Parent $PSScriptRoot
$ConfigSrc = Join-Path $RepoRoot 'config'
if (-not (Test-Path $ConfigSrc)) {
    Write-Error "dotsync: could not locate the dotfiles repo (config\ not found at $ConfigSrc)."
    exit 1
}

$Local = $env:LOCALAPPDATA

# Windows deploy map: module -> destination directory.
# Only modules that windows\install.ps1 actually deploys belong here.
$Dest = @{
    'nvim'    = (Join-Path $Local 'nvim')
    'lazygit' = (Join-Path $Local 'lazygit')
}

function Show-List {
    Write-Host "Syncable modules (Windows):"
    $Dest.Keys | Sort-Object | ForEach-Object { Write-Host "  $_  ->  $($Dest[$_])" }
}

if ($List) { Show-List; exit 0 }

if (-not $Modules -or $Modules.Count -eq 0) {
    Write-Host "Usage: .\dotsync.ps1 <module> [<module> ...] | all | -List | -DryRun <module>"
    Show-List
    exit 0
}

# Expand 'all'
$targets = @()
foreach ($m in $Modules) {
    if ($m -eq 'all') { $targets += $Dest.Keys } else { $targets += $m }
}
$targets = $targets | Select-Object -Unique

# Relative path + hash of every file under $path (same check as
# Test-SameContent in install.ps1).
function Get-TreeDigest($path) {
    $root = (Get-Item -LiteralPath $path -Force).FullName
    (Get-ChildItem -LiteralPath $root -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($root.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash } |
        Sort-Object) -join "`n"
}

function Sync-One($name) {
    $src = Join-Path $ConfigSrc $name
    if (-not $Dest.ContainsKey($name)) {
        Write-Warning "skip $name - not deployed on Windows (or templated; use windows\install.ps1)"
        return $false
    }
    if (-not (Test-Path $src)) {
        Write-Warning "skip $name - no such module in config\"
        return $false
    }
    $target = $Dest[$name]

    # Unchanged: leave it alone, so its last real backup survives.
    if ((Test-Path -LiteralPath $target) -and ((Get-TreeDigest $src) -ceq (Get-TreeDigest $target))) {
        Write-Host "  unchanged $name" -ForegroundColor Green
        return $true
    }

    if ($DryRun) {
        Write-Host "  would sync $name -> $target" -ForegroundColor Cyan
        return $true
    }

    if (Test-Path $target) {
        $bak = "$target.bak"
        if (Test-Path $bak) { Remove-Item -Recurse -Force $bak }
        Move-Item $target $bak
    }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Recurse -Force (Join-Path $src '*') $target
    Write-Host "  synced $name -> $target" -ForegroundColor Green
    return $true
}

Write-Host "dotsync: $ConfigSrc -> (LOCALAPPDATA)"
$rc = 0
foreach ($m in $targets) { if (-not (Sync-One $m)) { $rc = 1 } }
if (-not $DryRun) { Write-Host "Done. Replaced configs were backed up to <dest>.bak." }
Write-Host "Reminder: in Neovim run :Lazy restore after syncing to match lazy-lock.json."
exit $rc
