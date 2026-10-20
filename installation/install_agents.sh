#!/bin/bash
# install_agents.sh - Install AI agent CLIs
# Set DOTFILES_SKIP_AGENT_INSTALLERS=1 to skip the remote Claude and Codex
# vendor shell installers; any other value (including unset) installs them.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if [ "${DOTFILES_SKIP_AGENT_INSTALLERS:-0}" = "1" ]; then
    skip_step "Claude/Codex vendor installers" "DOTFILES_SKIP_AGENT_INSTALLERS=1"
else
    # Install Claude Code headlessly.
    curl -fsSL https://claude.ai/install.sh | bash

    # Install Codex CLI headlessly.
    export CODEX_NON_INTERACTIVE=1
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
fi
