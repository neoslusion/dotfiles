#!/bin/bash
# install_agents_test.sh - verify the Claude/Codex vendor-installer opt-out.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export PATH="/usr/bin:/bin:$PATH"

BIN_DIR="$TMP_DIR/bin"
CALL_LOG="$TMP_DIR/calls.log"
mkdir -p "$BIN_DIR"
: > "$CALL_LOG"

printf '%s\n' \
    '#!/bin/bash' \
    'printf "%s %s\\n" "$(basename "$0")" "$*" >> "$CALL_LOG"' \
    'printf ":\\n"' \
    > "$BIN_DIR/curl"
chmod +x "$BIN_DIR/curl"

output="$(
    PATH="$BIN_DIR:$PATH" \
    CALL_LOG="$CALL_LOG" \
    DOTFILES_LOG_FILE="$TMP_DIR/install.log" \
    DOTFILES_SKIP_AGENT_INSTALLERS=1 \
        bash "$ROOT/installation/install_agents.sh"
)"

if grep -q '^curl ' "$CALL_LOG"; then
    printf 'Vendor curl was called in opt-out mode.\n' >&2
    exit 1
fi

printf '%s' "$output" | grep -Fq 'Claude/Codex vendor installers' || {
    printf 'Vendor-installer skip was not visible.\n' >&2
    exit 1
}
printf 'install agents tests passed\n'
