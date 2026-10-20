# Dotfiles installer - Windows entry point (counterpart of ./install.sh).
# Thin forwarder; the real logic lives in windows/install.ps1.
# Usage:  .\install.ps1               (tools + configs, Scoop-first)
#         .\install.ps1 -ConfigOnly   (deploy/refresh configs only)
#         .\install.ps1 -DryRun       (print package plan; no changes)
#         .\install.ps1 -NoAdmin      (force Scoop user-scope installs)
#         .\install.ps1 -Winget       (winget-first, Scoop fallback)
param(
    [switch]$ConfigOnly,
    [switch]$DryRun,
    [switch]$NoAdmin,
    [switch]$Winget
)

& (Join-Path $PSScriptRoot "windows\install.ps1") -ConfigOnly:$ConfigOnly -DryRun:$DryRun -NoAdmin:$NoAdmin -Winget:$Winget
