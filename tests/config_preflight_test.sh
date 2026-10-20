#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf "Expected output to contain: %s\n\nOutput was:\n%s\n" "$needle" "$haystack" >&2
        return 1
    fi
}

copy_preflight_fixture() {
    local dest="$1"

    mkdir -p "$dest/config"
    cp -R "$ROOT/config/tmux" "$dest/config/tmux"
}

bash "$ROOT/installation/preflight_config.sh" "$ROOT" >/dev/null

DUP_ROOT="$TMP_DIR/duplicate-root"
copy_preflight_fixture "$DUP_ROOT"
mkdir -p "$DUP_ROOT/config/nvim/lua/config" "$DUP_ROOT/config/nvim/lua/plugins"
cat > "$DUP_ROOT/config/nvim/lua/config/duplicate.lua" <<'EOF'
vim.keymap.set("n", "<leader>zz", function() end)
vim.keymap.set("n", "<leader>zz", function() end)
EOF

set +e
duplicate_output="$(bash "$ROOT/installation/preflight_config.sh" "$DUP_ROOT" 2>&1)"
duplicate_status=$?
set -e

if [[ "$duplicate_status" -eq 0 ]]; then
    printf "Expected preflight to fail on duplicate Neovim keymaps.\n\nOutput was:\n%s\n" "$duplicate_output" >&2
    exit 1
fi

assert_contains "$duplicate_output" "Duplicate Neovim keymaps"
assert_contains "$duplicate_output" "<leader>zz"

EMPTY_ROOT="$TMP_DIR/empty-root"
mkdir -p "$EMPTY_ROOT/config/nvim/lua/config" "$EMPTY_ROOT/config/nvim/lua/plugins"

set +e
empty_output="$(bash "$ROOT/scripts/audit-nvim-keymaps" "$EMPTY_ROOT" 2>&1)"
empty_status=$?
set -e

if [[ "$empty_status" -eq 0 ]]; then
    printf "Expected audit-nvim-keymaps to fail when no Lua files are found.\n\nOutput was:\n%s\n" "$empty_output" >&2
    exit 1
fi

assert_contains "$empty_output" "No Neovim Lua files found"

printf "config preflight tests passed\n"
