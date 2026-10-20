#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local actual=$1 expected=$2
    [ "$actual" = "$expected" ] || fail "expected '$expected', got '$actual'"
}

# The fixed-machine-path scan below is the whole point of this suite, and it
# runs through `rg`. Without ripgrep that scan exits 127, matches nothing, and
# the suite reports success having checked nothing — which is how a hardcoded
# /mnt/c or C:\sandboxes path would slip in unnoticed. Fail loudly instead.
command -v rg >/dev/null 2>&1 || fail 'Missing required tool: rg (needed for the machine-path scan)'

PATH_HELPER="$ROOT/scripts/utils/paths.sh"
[ -f "$PATH_HELPER" ] || fail "path helper missing: $PATH_HELPER"
# shellcheck source=scripts/utils/paths.sh
source "$PATH_HELPER"

export HOME="$TMP_DIR/home with space"
mkdir -p "$HOME"

repo="$TMP_DIR/設定 space/dotfiles"
mkdir -p "$repo/config" "$repo/sub/dir"
touch "$repo/install.sh"

DOTFILES_REPO="$repo"
assert_eq "$(dotfiles_resolve_repo "$TMP_DIR")" "$repo"

export DOTFILES_REPO="$TMP_DIR/not-a-checkout"
if dotfiles_resolve_repo "$TMP_DIR" >/dev/null 2>&1; then
    fail 'invalid DOTFILES_REPO was accepted'
else
    [ "$?" -eq 2 ] || fail 'invalid DOTFILES_REPO did not return status 2'
fi

unset DOTFILES_REPO
assert_eq "$(dotfiles_resolve_repo "$repo/sub/dir")" "$repo"

if rg -n '/mnt/[a-z]/|[A-Za-z]:\\+sandboxes' \
    "$ROOT/installation" "$ROOT/scripts" "$ROOT/config" "$ROOT/windows" \
    -g '*.sh' -g '*.zsh' -g '*.ps1' -g '*.lua'; then
    fail 'executable source contains a fixed machine path'
fi

printf 'path policy tests passed\n'
