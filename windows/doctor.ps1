# Dotfiles Windows health check - counterpart of exit-code-based verification
# on the Linux side. Exit 0 = healthy; non-zero = count of missing core tools.
# Usage: pwsh -File windows\doctor.ps1

$ErrorActionPreference = 'Stop'
$failures = 0

function Test-Tool($name, $cmd) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host ("  {0,-34}" -f $name) -NoNewline; Write-Host "ok" -ForegroundColor Green
    }
    else {
        Write-Host ("  {0,-34}" -f $name) -NoNewline; Write-Host "missing" -ForegroundColor Red
        $script:failures++
    }
}

function Test-File($name, $path) {
    if (Test-Path $path) {
        Write-Host ("  {0,-34}" -f $name) -NoNewline; Write-Host "ok" -ForegroundColor Green
    }
    else {
        Write-Host ("  {0,-34}" -f $name) -NoNewline; Write-Host "missing" -ForegroundColor Red
        $script:failures++
    }
}

function Test-Font($name, $pattern) {
    # Fonts register under HKLM (machine-wide MSI) or HKCU (per-user installs)
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    $found = $false
    foreach ($key in $keys) {
        if (Test-Path $key) {
            $props = (Get-ItemProperty $key).PSObject.Properties | Where-Object { $_.Name -like $pattern -or $_.Value -like $pattern }
            if ($props) { $found = $true; break }
        }
    }
    if ($found) {
        Write-Host ("  {0,-34}" -f $name) -NoNewline; Write-Host "ok" -ForegroundColor Green
    }
    else {
        Write-Host ("  {0,-34}" -f $name) -NoNewline; Write-Host "missing" -ForegroundColor Red
        $script:failures++
    }
}

Write-Host "`nCore tools" -ForegroundColor Magenta
Test-Tool "Git"        git
Test-Tool "Alacritty"  alacritty
Test-Tool "Starship"   starship
Test-Tool "Zoxide"     zoxide
Test-Tool "fzf"        fzf
Test-Tool "Bat"        bat
Test-Tool "fd"         fd
Test-Tool "Eza"        eza
Test-Tool "ripgrep"    rg
Test-Tool "Neovim"     nvim
Test-Tool "Lazygit"    lazygit
Test-Tool "jq"         jq
Test-Tool "CMake"      cmake
Test-Tool "Atuin"      atuin
Test-Tool "Python"     python
Test-Tool "Yazi"       yazi
Test-Tool "Herdr"      herdr

Write-Host "`nConfiguration" -ForegroundColor Magenta
Test-Font "JetBrainsMono Nerd Font" "JetBrainsMono*Nerd*Font*"
# Alacritty reads only %APPDATA% on Windows; never check ~/.config/alacritty
# here, because Alacritty would not read it.
Test-File "Alacritty config" (Join-Path $env:APPDATA "alacritty\alacritty.toml")
Test-File "Starship config"  (Join-Path $HOME ".config\starship.toml")
Test-File "Neovim config"    (Join-Path $env:LOCALAPPDATA "nvim\init.lua")
Test-File "Lazygit config"   (Join-Path $env:LOCALAPPDATA "lazygit\config.yml")
Test-File "Herdr config"     (Join-Path $env:APPDATA "herdr\config.toml")
Test-File "Claude settings"      (Join-Path $HOME ".claude\settings.json")
Test-File "Claude CLAUDE.md"     (Join-Path $HOME ".claude\CLAUDE.md")
Test-File "Codex AGENTS.md"      (Join-Path $HOME ".codex\AGENTS.md")
Test-File "Opencode AGENTS.md"   (Join-Path $HOME ".config\opencode\AGENTS.md")
Test-File "Opencode opencode.json" (Join-Path $HOME ".config\opencode\opencode.json")

$profileDir = Join-Path $HOME 'PowerShell'
Test-File 'Profile sidecar' (Join-Path $profileDir 'dotfiles.profile.ps1')

$profilePath = Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell') 'Microsoft.PowerShell_profile.ps1'
if ((Test-Path $profilePath) -and (Select-String -Path $profilePath -Pattern '\$HOME\\PowerShell\\dotfiles\.profile\.ps1' -Quiet)) {
    Write-Host ("  {0,-34}" -f 'Profile injection') -NoNewline; Write-Host 'ok' -ForegroundColor Green
}
else {
    Write-Host ("  {0,-34}" -f 'Profile injection') -NoNewline; Write-Host 'missing' -ForegroundColor Red
    $failures++
}

# --- Agent configs (parity with installation/doctor.sh) -----------------------
Write-Host "`nAgents" -ForegroundColor Magenta
$claudeDir = Join-Path $HOME ".claude"
$codexDir = Join-Path $HOME ".codex"
$agyDir = Join-Path $HOME ".gemini\antigravity-cli"
$ocDir = Join-Path $HOME ".config\opencode"
$secretsDir = Join-Path $HOME ".secrets"

Test-File "Claude settings.json" (Join-Path $claudeDir "settings.json")
Test-File "Claude CLAUDE.md"     (Join-Path $claudeDir "CLAUDE.md")
Test-File "Claude shared docs"   (Join-Path $claudeDir "ENGINEERING.md")
Test-File "Codex AGENTS.md"      (Join-Path $codexDir "AGENTS.md")
Test-File "Codex base config"    (Join-Path $codexDir "config.toml")
Test-File "Antigravity AGENTS.md" (Join-Path $agyDir "AGENTS.md")
Test-File "Antigravity mcp.json"  (Join-Path $agyDir "mcp.json")
Test-File "Opencode AGENTS.md"    (Join-Path $ocDir "AGENTS.md")
Test-File "Opencode opencode.json" (Join-Path $ocDir "opencode.json")
Test-File "Opencode shared docs"  (Join-Path $ocDir "ENGINEERING.md")
Test-File "Secrets env scaffold"  (Join-Path $secretsDir "env.ps1")

Write-Host ""
if ($failures -eq 0) {
    Write-Host "All checks passed." -ForegroundColor Green
}
else {
    Write-Host "$failures check(s) failed. Run .\install.ps1 to fix." -ForegroundColor Red
}
exit $failures
