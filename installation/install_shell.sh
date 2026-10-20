#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

install_starship() {
    local asset sha256 status=0 temp_dir version
    version="$DOTFILES_STARSHIP_VERSION"
    release_asset starship asset sha256 || return 1
    temp_dir=$(mktemp -d)
    (
        cd "$temp_dir" \
            && download_verified_asset "https://github.com/starship/starship/releases/download/v${version}/${asset}" "$asset" "$sha256" \
            && tar -xzf "$asset" \
            && sudo install starship /usr/local/bin/starship
    ) || status=$?
    rm -rf "$temp_dir"
    return "$status"
}

install_atuin() {
    local asset binary sha256 status=0 temp_dir version
    version="$DOTFILES_ATUIN_VERSION"
    release_asset atuin asset sha256 || return 1
    temp_dir=$(mktemp -d)
    (
        cd "$temp_dir" \
            && download_verified_asset "https://github.com/atuinsh/atuin/releases/download/v${version}/${asset}" "$asset" "$sha256" \
            && tar -xzf "$asset" \
            && binary="$(find . -type f -name atuin | head -n 1)" \
            && [ -n "$binary" ] \
            && mkdir -p "$HOME/.atuin/bin" \
            && install "$binary" "$HOME/.atuin/bin/atuin"
    ) || status=$?
    rm -rf "$temp_dir"
    return "$status"
}

# Release tarball, not zoxide's install.sh: that script downloads
# releases/latest unverified, so pinning the script never pinned the binary.
install_zoxide() {
    local asset sha256
    release_asset zoxide asset sha256 || return 1
    install_release_binary \
        "https://github.com/ajeetdsouza/zoxide/releases/download/v${DOTFILES_ZOXIDE_VERSION}/${asset}" \
        zoxide zoxide "$sha256"
}

install_herdr() {
    # herdr ships bare binaries (herdr-linux-<arch>, no tarball), so this
    # skips the tar step install_release_binary assumes. macOS uses brew.
    local asset sha256 status=0 temp_dir version
    version="$DOTFILES_HERDR_VERSION"
    release_asset herdr asset sha256 || return 1
    temp_dir=$(mktemp -d)
    (
        cd "$temp_dir" \
            && download_verified_asset "https://github.com/herdrdev/herdr/releases/download/${version}/${asset}" "$asset" "$sha256" \
            && chmod +x "$asset" \
            && sudo install "$asset" /usr/local/bin/herdr
    ) || status=$?
    rm -rf "$temp_dir"
    return "$status"
}

# Install Oh My Zsh
check_dir_and_run "$HOME/.oh-my-zsh" "Oh My Zsh" \
    git_clone_ref "https://github.com/ohmyzsh/ohmyzsh.git" "$HOME/.oh-my-zsh" "$DOTFILES_OH_MY_ZSH_REF"

# Install Zsh plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

check_dir_and_run "$ZSH_CUSTOM/plugins/zsh-autosuggestions" "zsh-autosuggestions" \
    git_clone_ref "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM/plugins/zsh-autosuggestions" "$DOTFILES_ZSH_AUTOSUGGESTIONS_REF"

check_dir_and_run "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting" \
    git_clone_ref "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" "$DOTFILES_ZSH_SYNTAX_HIGHLIGHTING_REF"

check_dir_and_run "$ZSH_CUSTOM/plugins/zsh-vi-mode" "zsh-vi-mode" \
    git_clone_ref "https://github.com/jeffreytse/zsh-vi-mode.git" "$ZSH_CUSTOM/plugins/zsh-vi-mode" "$DOTFILES_ZSH_VI_MODE_REF"

# Shell Enhancement Tools
if is_macos; then
    check_and_install "starship" "Starship" brew install starship
    check_and_install "atuin" "Atuin" brew install atuin
    check_and_install "zoxide" "Zoxide" brew install zoxide
    check_and_install "herdr" "Herdr" brew install herdr
else
    check_and_install "starship" "Starship" install_starship
    check_and_install "atuin" "Atuin" install_atuin
    check_and_install "zoxide" "Zoxide" install_zoxide
    check_and_install "herdr" "Herdr" install_herdr
fi

if [ ! -d "$HOME/.fzf" ]; then
    install_fzf() {
        git_clone_ref "https://github.com/junegunn/fzf.git" "$HOME/.fzf" "$DOTFILES_FZF_REF"
        "$HOME/.fzf/install" --all
    }
    run_step "FZF" install_fzf
else
    skip_step "FZF" "installed"
fi
