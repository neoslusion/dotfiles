#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_ROOT="${1:-$TOOL_ROOT}"

require_command() {
    local name="$1"

    if ! command -v "$name" >/dev/null 2>&1; then
        printf "Config preflight requires %s.\n" "$name" >&2
        return 1
    fi
}

is_bash_script() {
    local path="$1"
    local first_line

    if [[ "$path" == *.sh ]]; then
        return 0
    fi

    IFS= read -r first_line < "$path" || first_line=""
    [[ "$first_line" == "#!"*bash* ]]
}

check_bash_syntax() {
    local path

    while IFS= read -r -d '' path; do
        if is_bash_script "$path"; then
            bash -n "$path"
        fi
    done < <(find "$TARGET_ROOT" \
        -path "$TARGET_ROOT/.git" -prune -o \
        -path "$TARGET_ROOT/.worktrees" -prune -o \
        -type f -print0)
}

check_nvim_keymaps() {
    "$TOOL_ROOT/scripts/audit-nvim-keymaps" "$TARGET_ROOT"
}

check_tmux_config() {
    local tmp_home status

    require_command tmux

    tmp_home="$(mktemp -d)"

    mkdir -p "$tmp_home/.config"
    cp -R "$TARGET_ROOT/config/tmux" "$tmp_home/.config/tmux"
    cp -f "$TARGET_ROOT/config/tmux/.tmux.conf" "$tmp_home/.tmux.conf"
    cp -f "$tmp_home/.config/tmux/themes/dotbar.conf" "$tmp_home/.config/tmux/theme.conf"

    set +e
    tmux_parse_file "$tmp_home" "$tmp_home/.tmux.conf"
    status=$?
    if [ "$status" -eq 0 ]; then
        tmux_parse_file "$tmp_home" "$tmp_home/.config/tmux/tmux.core.conf"
        status=$?
    fi
    if [ "$status" -eq 0 ]; then
        tmux_parse_file "$tmp_home" "$tmp_home/.config/tmux/theme.conf"
        status=$?
    fi
    if [ "$status" -eq 77 ]; then
        tmux_static_fallback "$tmp_home"
        status=$?
    fi
    rm -rf "$tmp_home"
    set -e

    return "$status"
}

tmux_parse_file() {
    local tmp_home="$1"
    local file="$2"
    local output status

    output="$(HOME="$tmp_home" tmux -f /dev/null source-file -n "$file" 2>&1 >/dev/null)"
    status=$?

    if [ "$status" -ne 0 ]; then
        # Containers: no TTY ("Operation not permitted") or no startable
        # server ("error connecting to") — fall back to static validation
        if [[ "$output" == *"Operation not permitted"* || "$output" == *"error connecting to"* ]]; then
            return 77
        fi

        printf "%s\n" "$output" >&2
        return "$status"
    fi
}

tmux_static_fallback() {
    local tmp_home="$1"

    [ -s "$tmp_home/.tmux.conf" ] || return 1
    [ -s "$tmp_home/.config/tmux/tmux.core.conf" ] || return 1
    [ -s "$tmp_home/.config/tmux/theme.conf" ] || return 1
    grep -qF 'source-file "$HOME/.config/tmux/tmux.core.conf"' "$tmp_home/.tmux.conf"
    grep -qF 'source-file -q "$HOME/.config/tmux/theme.conf"' "$tmp_home/.tmux.conf"
}

check_bash_syntax
check_nvim_keymaps
check_tmux_config

printf "Config preflight passed.\n"
