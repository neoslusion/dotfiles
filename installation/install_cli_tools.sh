#!/bin/bash
set -eo pipefail
export PATH="$HOME/.cargo/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

nvim_is_usable() {
    command -v nvim &> /dev/null && nvim --version &> /dev/null
}

# nvim-treesitter (main branch) shells out to the tree-sitter CLI to compile
# parsers; the C compiler itself comes from build-essential (install_core.sh).
install_tree_sitter() {
    if is_macos; then
        brew install tree-sitter
    else
        local asset sha256 status=0 temp_dir
        release_asset tree-sitter asset sha256 || return 1
        temp_dir=$(mktemp -d)
        (
            cd "$temp_dir" \
                && download_verified_asset \
                    "https://github.com/tree-sitter/tree-sitter/releases/download/v${DOTFILES_TREE_SITTER_VERSION}/${asset}" \
                    "$asset" "$sha256" \
                && gunzip -c "$asset" > tree-sitter \
                && sudo install tree-sitter /usr/local/bin
        ) || status=$?
        rm -rf "$temp_dir"
        return "$status"
    fi
}

install_neovim() {
    if is_macos; then
        brew install neovim
    else
        local tarball extract_dir install_dir sha256 status=0 temp_dir
        release_asset nvim tarball sha256 || return 1
        extract_dir="${tarball%.tar.gz}"
        install_dir="/opt/nvim/${DOTFILES_NEOVIM_VERSION}-${extract_dir#nvim-linux-}"
        temp_dir=$(mktemp -d)
        (
            cd "$temp_dir" \
                && download_verified_asset \
                    "https://github.com/neovim/neovim/releases/download/${DOTFILES_NEOVIM_VERSION}/${tarball}" \
                    "$tarball" "$sha256" \
                && tar -xzf "$tarball" \
                && sudo mkdir -p /opt/nvim \
                && sudo rm -rf "$install_dir" \
                && sudo cp -R "$extract_dir" "$install_dir" \
                && sudo mkdir -p /usr/local/bin \
                && sudo ln -sfn "$install_dir/bin/nvim" /usr/local/bin/nvim
        ) || status=$?
        rm -rf "$temp_dir"
        return "$status"
    fi
}

install_lazygit() {
    if is_macos; then
        brew install jesseduffield/lazygit/lazygit
    else
        local asset sha256 status=0 temp_dir
        release_asset lazygit asset sha256 || return 1
        temp_dir=$(mktemp -d)
        (
            cd "$temp_dir" \
                && download_verified_asset \
                    "https://github.com/jesseduffield/lazygit/releases/download/v${DOTFILES_LAZYGIT_VERSION}/${asset}" \
                    "$asset" "$sha256" \
                && tar -xzf "$asset" lazygit \
                && sudo install lazygit /usr/local/bin
        ) || status=$?
        rm -rf "$temp_dir"
        return "$status"
    fi
}

install_bottom() {
    if is_macos; then
        brew install bottom
    else
        local asset sha256
        release_asset bottom asset sha256 || return 1
        # Pinned musl release binary: distro-agnostic (bottom's tag has no v
        # prefix and the binary inside is `btm`)
        install_release_binary \
            "https://github.com/ClementTsang/bottom/releases/download/${DOTFILES_BOTTOM_VERSION}/${asset}" \
            btm btm "$sha256"
    fi
}

install_bat() {
    if is_macos; then
        brew install bat
    else
        system_install bat
        # Debian/Ubuntu ship the binary as batcat; other distros use bat
        if [ "${DOTFILES_PKG_MGR:-}" = "apt" ]; then
            mkdir -p "$HOME/.local/bin"
            ln -s /usr/bin/batcat "$HOME/.local/bin/bat" || true
        fi
    fi
}

install_eza() {
    if is_macos; then
        brew install eza
    else
        local asset binary sha256 status=0 temp_dir version
        release_asset eza asset sha256 || return 1
        temp_dir=$(mktemp -d)
        (
            cd "$temp_dir" \
                && version="$DOTFILES_EZA_VERSION" \
                && download_verified_asset "https://github.com/eza-community/eza/releases/download/v${version}/${asset}" "$asset" "$sha256" \
                && tar -xzf "$asset" \
                && binary="$(find . -type f -name eza -perm -111 | head -n 1)" \
                && [ -n "$binary" ] \
                && sudo install "$binary" /usr/local/bin/eza
        ) || status=$?
        rm -rf "$temp_dir"
        return "$status"
    fi
}

install_delta() {
    if is_macos; then
        brew install git-delta
    else
        # Arch/Fedora package it; Debian/Ubuntu do not (no v prefix on tags)
        system_install delta || {
            local asset sha256
            release_asset delta asset sha256 || return 1
            install_release_binary \
                "https://github.com/dandavison/delta/releases/download/${DOTFILES_DELTA_VERSION}/${asset}" \
                delta delta "$sha256"
        }
    fi
}

install_python() {
    if is_macos; then
        brew install python
    else
        system_install python3 python3-pip python3-venv
    fi
}

install_yazi() {
    if is_macos; then
        brew install yazi
    else
        local asset extract_dir sha256 status=0 temp_dir
        release_asset yazi asset sha256 || return 1
        extract_dir="${asset%.zip}"
        temp_dir=$(mktemp -d)
        (
            cd "$temp_dir" \
                && download_verified_asset \
                    "https://github.com/sxyazi/yazi/releases/download/v${DOTFILES_YAZI_VERSION}/${asset}" \
                    "$asset" "$sha256" \
                && unzip "$asset" \
                && [ -f "$extract_dir/yazi" ] \
                && [ -f "$extract_dir/ya" ] \
                && sudo install "$extract_dir/yazi" "$extract_dir/ya" /usr/local/bin/
        ) || status=$?
        rm -rf "$temp_dir"
        return "$status"
    fi
}

# Neovim
if ! nvim_is_usable; then
    run_step "Neovim" install_neovim
else
    skip_step "Neovim" "installed"
fi

# tree-sitter CLI (nvim-treesitter parser builds)
check_and_install "tree-sitter" "tree-sitter CLI" install_tree_sitter

# Lazygit
check_and_install "lazygit" "Lazygit" install_lazygit

# Modern CLI Tools
check_and_install "btm" "Bottom" install_bottom
check_and_install "delta" "Delta" install_delta
# Wire delta into git once both exist (lazygit already pages through it via
# config/lazygit/config.yml; this covers the plain git CLI).
if command -v delta >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    run_step "Delta as git pager" git config --global core.pager "delta"
    run_step "Delta interactive diff" git config --global interactive.diffFilter "delta --color-only"
fi

# Bat (Modern cat)
if ! command -v bat &> /dev/null && ! command -v batcat &> /dev/null; then
    run_step "Bat" install_bat
else
    skip_step "Bat" "installed"
fi

# Eza (Modern ls)
check_and_install "eza" "Eza" install_eza

# Python 3
check_and_install "python3" "Python 3" install_python

# Yazi (file manager)
if command -v yazi &> /dev/null && command -v ya &> /dev/null; then
    skip_step "Yazi" "installed"
else
    run_step "Yazi" install_yazi
fi
