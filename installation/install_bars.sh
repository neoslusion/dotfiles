#!/bin/bash
# install_bars.sh - macOS-only desktop bar (SketchyBar). No-op elsewhere.
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if ! is_macos; then
    skip_step "SketchyBar" "Linux/WSL detected"
    exit 0
fi

section "Installing SketchyBar"
run_step "Tapping FelixKratz/formulae" brew tap FelixKratz/formulae
check_and_install "sketchybar" "SketchyBar" brew install sketchybar

run_step "Config: SketchyBar" bash -c '
    mkdir -p "$HOME/.config/sketchybar"
    cp -f "$1/../config/sketchybar/sketchybarrc" "$HOME/.config/sketchybar/sketchybarrc"
    chmod +x "$HOME/.config/sketchybar/sketchybarrc"
' _ "$SCRIPT_DIR"

# Start the service
run_step "Start SketchyBar" brew services restart sketchybar
