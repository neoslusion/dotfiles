#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

install_font() {
    local status=0
    if is_macos; then
        FONT_DIR="$HOME/Library/Fonts"
    else
        FONT_DIR="$HOME/.local/share/fonts"
    fi
    TEMP_DIR=$(mktemp -d)
    mkdir -p "$FONT_DIR"
    (
        cd "$TEMP_DIR" \
            && download_verified_asset \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v${DOTFILES_JETBRAINS_MONO_VERSION}/JetBrainsMono.zip" \
                JetBrainsMono.zip "$DOTFILES_JETBRAINS_MONO_SHA256" \
            && unzip -o JetBrainsMono.zip -d "$FONT_DIR" \
            && { is_macos || fc-cache -f -v; }
    ) || status=$?
    rm -rf "$TEMP_DIR"
    return "$status"
}

if is_macos; then
    # Install Homebrew if missing
    if ! command -v brew &> /dev/null; then
        run_step "Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add brew to path for the current session if it was just installed
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    else
        skip_step "Homebrew" "installed"
    fi

    run_step "Core packages (brew)" brew install \
        wget tmux ripgrep fd
else
    # Package-manager preparation is shared and runs once per installer process.
    run_step "Core packages" system_install \
        zsh git curl wget unzip tar build-essential tmux ripgrep fd-find libfuse2 \
        python3-pip python3-venv
fi

# Install JetBrains Mono Nerd Font
if is_macos; then
    # Simple check for MacOS font
    if ! find "$HOME/Library/Fonts" -maxdepth 1 -name "JetBrainsMono*" 2>/dev/null | grep -q .; then
        run_step "JetBrainsMono Nerd Font" install_font
    else
        skip_step "JetBrainsMono Nerd Font" "installed"
    fi
else
    if ! fc-list | grep -q "JetBrainsMono Nerd Font"; then
        run_step "JetBrainsMono Nerd Font" install_font
    else
        skip_step "JetBrainsMono Nerd Font" "installed"
    fi
fi
