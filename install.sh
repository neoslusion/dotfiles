#!/bin/bash
# =============================================================================
# Dotfiles Installer - Single entry point for fresh machine setup
# Usage: ./install.sh             (full install: dependencies + configs)
#        ./install.sh --config    (config only: deploy/update config files)
#        ./install.sh --verbose   (stream raw command output)
#        ./install.sh --doctor    (non-mutating health check)
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --config|--config-only)
            CONFIG_ONLY=1
            ;;
        --verbose|-v)
            export DOTFILES_VERBOSE=1
            ;;
        --doctor)
            "$SCRIPT_DIR/installation/doctor.sh"
            exit $?
            ;;
        --help|-h)
            echo "Usage: ./install.sh [--config] [--verbose] [--doctor]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: ./install.sh [--config] [--verbose] [--doctor]"
            exit 1
            ;;
    esac
done

source "$SCRIPT_DIR/installation/utils.sh"

banner "Dotfiles Installer"

# ─────────────────────────────────────────────────────────
# Step 1: Install Dependencies (skip with --config flag)
# ─────────────────────────────────────────────────────────
if [ "$CONFIG_ONLY" -eq 0 ]; then
    section "[1/4] Dependencies"
    "$SCRIPT_DIR/installation/common_install.sh"

    # Set Zsh as the default shell if not already. Non-fatal: chsh needs a
    # password/PAM in some environments (containers, remote boxes) — the
    # install must not die at the finish line over it.
    if [ "$SHELL" != "$(which zsh)" ]; then
        run_step "Default shell: zsh" chsh -s "$(which zsh)" \
            || warning "Could not change default shell; run manually: chsh -s \$(which zsh)"
    else
        skip_step "Default shell: zsh" "already default"
    fi
else
    section "[1/2] Config Preflight"
    run_step "Config preflight" "$SCRIPT_DIR/installation/preflight_config.sh"

    section "[2/2] Configuration"
    "$SCRIPT_DIR/installation/install_configs.sh"

    echo ""
    success "Configuration refresh complete."
    echo ""
    echo "  To reapply configs later, run: ./install.sh --config"
    echo "  Full log: $DOTFILES_LOG_FILE"
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────
# Step 2: Validate Configuration Files
# ─────────────────────────────────────────────────────────
section "[2/4] Config Preflight"
run_step "Config preflight" "$SCRIPT_DIR/installation/preflight_config.sh"

# ─────────────────────────────────────────────────────────
# Step 3: Deploy Configuration Files
# ─────────────────────────────────────────────────────────
section "[3/4] Configuration"
"$SCRIPT_DIR/installation/install_configs.sh"

# ─────────────────────────────────────────────────────────
# Step 4: Post-Install (Tmux plugins)
# ─────────────────────────────────────────────────────────
section "[4/4] Tmux Plugins"

TPM_DIR="$HOME/.tmux/plugins/tpm"
install_tpm() {
    mkdir -p "$(dirname "$TPM_DIR")"
    if [ ! -d "$TPM_DIR/.git" ]; then
        git init -q "$TPM_DIR"
    fi
    if git -C "$TPM_DIR" remote get-url origin >/dev/null 2>&1; then
        git -C "$TPM_DIR" remote set-url origin https://github.com/tmux-plugins/tpm.git
    else
        git -C "$TPM_DIR" remote add origin https://github.com/tmux-plugins/tpm.git
    fi
    git -C "$TPM_DIR" fetch -q --depth 1 origin "$DOTFILES_TPM_REF"
    git -C "$TPM_DIR" checkout -q --detach FETCH_HEAD
}

if [ ! -d "$TPM_DIR/.git" ] || \
   [ "$(git -C "$TPM_DIR" rev-parse HEAD 2>/dev/null || true)" != "$DOTFILES_TPM_REF" ]; then
    run_step "TPM plugin manager" install_tpm
else
    skip_step "TPM plugin manager" "installed (pinned)"
fi

# Automatically install Tmux plugins via TPM (no manual Ctrl+b I needed)
run_step "Tmux plugins" "$HOME/.tmux/plugins/tpm/bin/install_plugins" || \
    warning "Tmux plugin install skipped; run Ctrl+b I inside tmux if needed."

echo ""
success "Installation complete."
echo ""
echo "  Next steps:"
echo "  1. Close this terminal and open a new one"
echo "     - Default is a plain Zsh prompt. tmux auto-attach is opt-in:"
echo "       export DOTFILES_TMUX=1 (see README: First Session)"
echo ""
echo "  2. (Optional) Open Neovim and run :Copilot auth"
echo ""
echo "  To reapply configs later, run: ./install.sh --config"
echo "  Full log: $DOTFILES_LOG_FILE"
echo ""
exit 0
