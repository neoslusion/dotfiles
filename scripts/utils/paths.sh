#!/bin/bash

dotfiles_repo_is_valid() {
    [ -n "${1:-}" ] && [ -d "$1/config" ] && [ -f "$1/install.sh" ]
}

dotfiles_resolve_repo() {
    local start=${1:-$PWD}
    local script_candidate=${2:-}
    local current

    if [ -n "${DOTFILES_REPO:-}" ]; then
        if ! dotfiles_repo_is_valid "$DOTFILES_REPO"; then
            printf 'DOTFILES_REPO is not a checkout: %s\n' "$DOTFILES_REPO" >&2
            return 2
        fi
        (cd "$DOTFILES_REPO" && pwd)
        return 0
    fi

    current="$(cd "$start" 2>/dev/null && pwd)" || current=""
    while [ -n "$current" ]; do
        if dotfiles_repo_is_valid "$current"; then
            printf '%s\n' "$current"
            return 0
        fi
        [ "$current" = / ] && break
        current="$(dirname "$current")"
    done

    for current in "$script_candidate" "$HOME/sandboxes/dotfiles" "$HOME/dotfiles"; do
        if dotfiles_repo_is_valid "$current"; then
            (cd "$current" && pwd)
            return 0
        fi
    done

    return 1
}
