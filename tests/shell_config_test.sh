#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
HOME_DIR="$TMP_DIR/home"
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$HOME_DIR" "$FAKE_BIN"

printf '%s\n' '#!/bin/sh' "printf 'typeset -g DOTFILES_ATUIN_TEST=ok\\n'" > "$FAKE_BIN/atuin"
chmod +x "$FAKE_BIN/atuin"

HOME="$HOME_DIR" \
XDG_CACHE_HOME="$TMP_DIR/cache" \
PATH="$FAKE_BIN:/usr/bin:/bin" \
ROOT="$ROOT" \
    zsh -f -c '
        setopt null_glob
        function zvm_init { :; }
        source "$ROOT/config/terminal/core.zsh"

        if (( ${#zvm_after_init_commands} != 1 )); then
            print -u2 "Expected picker initialization to be deferred"
            exit 1
        fi

        $zvm_after_init_commands[1]

        [[ "$DOTFILES_ATUIN_TEST" == ok ]]
        [[ -f "$XDG_CACHE_HOME/dotfiles/atuin.zsh" ]]

    '

printf 'shell config tests passed\n'
