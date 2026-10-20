#!/bin/bash
# bootstrap_test.sh - verify pinned bootstrap refs and existing-checkout no-op.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export PATH="/usr/bin:/bin:$PATH"

BIN_DIR="$TMP_DIR/bin"
DEST="$TMP_DIR/checkout"
GIT_LOG="$TMP_DIR/git.log"
mkdir -p "$BIN_DIR"
: > "$GIT_LOG"

cat > "$BIN_DIR/git" <<'EOF'
#!/bin/bash
set -e
printf '%s\n' "$*" >> "$GIT_LOG"
if [ "$1" = "init" ]; then
    mkdir -p "$3"
elif [ "$1" = "-C" ]; then
    dir=$2
    shift 2
    if [ "$1" = "checkout" ]; then
        printf '#!/bin/sh\nexit 0\n' > "$dir/install.sh"
        chmod +x "$dir/install.sh"
    fi
elif [ "$1" = "clone" ]; then
    for arg in "$@"; do
        dest=$arg
    done
    mkdir -p "$dest"
    printf '#!/bin/sh\nexit 0\n' > "$dest/install.sh"
    chmod +x "$dest/install.sh"
fi
EOF
chmod +x "$BIN_DIR/git"

run_bootstrap() {
    PATH="$BIN_DIR:/usr/bin:/bin" \
    DOTFILES_DEST="$DEST" \
    GIT_LOG="$GIT_LOG" \
        bash "$ROOT/scripts/bootstrap" "$@"
}

set +e
no_ref_output="$(run_bootstrap 2>&1)"
no_ref_status=$?
set -e
[ "$no_ref_status" -ne 0 ] || { printf 'bootstrap accepted a missing ref\n' >&2; exit 1; }
printf '%s' "$no_ref_output" | grep -Fq 'commit SHA is required' || {
    printf 'missing-ref error was not clear: %s\n' "$no_ref_output" >&2
    exit 1
}
[ ! -e "$DEST" ] || { printf 'bootstrap created a checkout without a ref\n' >&2; exit 1; }

set +e
moving_output="$(run_bootstrap main 2>&1)"
moving_status=$?
set -e
[ "$moving_status" -ne 0 ] || { printf 'bootstrap accepted a moving ref by default\n' >&2; exit 1; }
printf '%s' "$moving_output" | grep -Fq 'refusing moving ref' || {
    printf 'moving-ref error was not clear: %s\n' "$moving_output" >&2
    exit 1
}

run_bootstrap main >/dev/null 2>&1 || true
# The previous invocation must not have created a checkout without opt-in.
[ ! -e "$DEST" ] || { printf 'moving ref was cloned without opt-in\n' >&2; exit 1; }

DOTFILES_ALLOW_MOVING_BOOTSTRAP_REF=1 run_bootstrap main >/dev/null
[ -x "$DEST/install.sh" ] || { printf 'moving-ref opt-in did not install the fixture\n' >&2; exit 1; }
grep -Fq 'clone -q --depth 1 --branch main' "$GIT_LOG" || {
    printf 'moving-ref opt-in did not use git clone\n' >&2
    exit 1
}

rm -rf "$DEST"
sha=0123456789abcdef0123456789abcdef01234567
run_bootstrap "$sha" >/dev/null
[ -x "$DEST/install.sh" ] || { printf 'pinned bootstrap did not install the fixture\n' >&2; exit 1; }
grep -Fq "fetch -q --depth 1 origin $sha" "$GIT_LOG" || {
    printf 'pinned bootstrap did not fetch the requested SHA\n' >&2
    exit 1
}

rm -rf "$DEST"
mkdir -p "$DEST"
: > "$GIT_LOG"
run_bootstrap >/dev/null
[ ! -s "$GIT_LOG" ] || { printf 'existing checkout was not a no-op\n' >&2; exit 1; }

printf 'bootstrap tests passed\n'
