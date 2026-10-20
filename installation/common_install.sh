#!/bin/bash
# common_install.sh - Main entry point for dotfiles installation
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if ! is_macos; then
    run_step "System package preparation" prepare_system_packages
fi

# 1. Install Core Packages and Fonts
section "Core"
"$SCRIPT_DIR/install_core.sh"

# 2. Install Shell and Enhancement Tools
section "Shell"
"$SCRIPT_DIR/install_shell.sh"

# 3. Install the required cli tools
section "Agents"
"$SCRIPT_DIR/install_agents.sh"
 
# 4. Install Modern CLI Tools
section "CLI Tools"
"$SCRIPT_DIR/install_cli_tools.sh"

# 5. macOS-only desktop bar (no-op elsewhere)
"$SCRIPT_DIR/install_bars.sh"

success "Dependencies ready."
