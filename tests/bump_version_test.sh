#!/bin/bash
# bump_version_test.sh - offline tests for scripts/bump-version.
# Uses bump-version's env-gated test seams (DOTFILES_BUMP_TEST_API_DIR /
# _ASSETS / _FAIL_ASSET) and a synthetic versions.env via DOTFILES_VERSIONS_ENV,
# so nothing here touches the network or the real pins file. The harness also
# avoids process forks in hot loops: spawning even grep costs >1s under
# MSYS2/Windows, which turns naive suites into minutes-long crawls.
#
# Covered: inventory parity between versions.env and the release_assets table,
# pin-style conformance (the nvim/herdr v-prefix rule), --check drift reporting,
# and single-tool bumps in both pin styles with failure isolation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUMP="$ROOT/scripts/bump-version"
REAL_ENV="$ROOT/installation/versions.env"
FAILURES=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    FAILURES=$((FAILURES + 1))
}

assert_contains() { # assert_contains <haystack> <needle> <label>
    case "$1" in
        *"$2"*) ;;
        *) fail "$3: expected output containing '$2'";;
    esac
}

# Pure-bash "does file contain this fixed substring" (no grep spawn).
file_has() { # file_has <file> <substring>
    local l
    while IFS= read -r l || [ -n "$l" ]; do
        [[ "$l" == *"$2"* ]] && return 0
    done < "$1"
    return 1
}

assert_line_contains() { # assert_line_contains <file> <fixed-substring> <label>
    file_has "$1" "$2" || fail "$3: expected $1 to contain '$2'"
}

# Pure-bash equality of two files (no cmp/diff spawn).
files_equal() {
    local a="" b="" l
    while IFS= read -r l || [ -n "$l" ]; do a+="$l"$'\n'; done < "$1"
    while IFS= read -r l || [ -n "$l" ]; do b+="$l"$'\n'; done < "$2"
    [[ "$a" == "$b" ]]
}

expect_sha() { # expect_sha <url> -> sha256 of the seam body (= url itself)
    printf '%s' "$1" | sha256sum | awk '{print $1}'
}

# Extract a pin value the same way bump-version does (glob, not ERE).
env_pin() { # env_pin <file> <var> -> sets PIN_VAL
    local head="$2=\"\${$2:-" l rest
    PIN_VAL=""
    while IFS= read -r l || [ -n "$l" ]; do
        [[ "$l" == "$head"*\"* ]] || continue
        rest="${l#"$head"}"
        PIN_VAL="${rest%%\"*}"
        PIN_VAL="${PIN_VAL%\}}"
    done < "$1"
}

# ─────────────────────────────────────────────────────────
# Tool metadata, parsed ONCE into parallel arrays (one fork total).
# ─────────────────────────────────────────────────────────
T_TOOLS=(); T_REPO=(); T_PREFIX=(); T_VAR=(); T_STYLE=()

load_meta() {
    local t r p v _a1 _s1 _a2 _s2 st
    while IFS='|' read -r t r p v _a1 _s1 _a2 _s2 st; do
        T_TOOLS+=("$t"); T_REPO+=("$r"); T_PREFIX+=("$p")
        T_VAR+=("$v"); T_STYLE+=("$st")
    done < <(bash "$BUMP" --dump-meta)
}

# ─────────────────────────────────────────────────────────
# Sandbox plumbing. Create returns a dir; Activate mutates the CURRENT shell
# (command substitution would swallow exports — keep them in parent scope).
# ─────────────────────────────────────────────────────────

sandbox_create() {
    mktemp -d
}

sandbox_activate() {
    DOTFILES_BUMP_TEST_API_DIR="$1/api"
    export DOTFILES_BUMP_TEST_API_DIR
    mkdir -p "$1/api"
    DOTFILES_BUMP_TEST_ASSETS=1
    export DOTFILES_BUMP_TEST_ASSETS
}

fake_latest() { # fake_latest <repo-with-slash> <tag>
    printf '{"tag_name": "%s"}\n' "$2" > "${DOTFILES_BUMP_TEST_API_DIR}/${1//\//__}.json"
}

run_bump() { # run_bump <sandbox> <args...>; sets OUT and RC
    local sb=$1
    shift
    if DOTFILES_VERSIONS_ENV="$sb/env" bash "$BUMP" "$@" > "$sb/out.txt" 2>&1; then
        RC=0
    else
        RC=$?
    fi
    OUT="$(cat "$sb/out.txt")"
    # BUMP_DEBUG=1 streams each child's output + pins copy for triage.
    [ -z "${BUMP_DEBUG:-}" ] || { printf '=== DEBUG %s rc=%s ===\n%s\n' "$*" "$RC" "$OUT" >&2; cp -r "$sb/env" "/tmp/bumpdbg-env-$RANDOM" 2>/dev/null || :; }
}

# ─────────────────────────────────────────────────────────
# 1) Inventory parity: every *_VERSION pin in the real file is either mapped
#    in tool_info; every mapping exists in file.
# ─────────────────────────────────────────────────────────
test_inventory_parity() {
    local declared
    declared=" $(grep -oE '^DOTFILES_[A-Z0-9_]+_VERSION=' "$REAL_ENV" | tr -d '=' | tr '\n' ' ')"
    [ -n "$(printf '%s' "$declared" | tr -d ' ')" ] \
        || { fail "parity: could not read version pins from $REAL_ENV"; return; }

    local mapped=" " i var d
    for i in "${!T_TOOLS[@]}"; do
        var="${T_VAR[i]}"
        mapped="$mapped$var "
        case "$declared" in *" $var "*) : ;; *) fail "parity: tool_info var '$var' absent from versions.env" ;; esac
    done
    for d in $declared; do
        case "$mapped" in *" $d "*) : ;; *) fail "parity: pin '$d' has no tool_info entry" ;; esac
    done
    printf 'inventory parity ok\n'
}

# ─────────────────────────────────────────────────────────
# 2) Pin-style conformance on the REAL pins file: tag-style tools store the
#    prefix, bare-style tools do not. This is the regression net for the
#    nvim/herdr v-prefix bug class.
# ─────────────────────────────────────────────────────────
test_pin_styles() {
    local i t pin
    for i in "${!T_TOOLS[@]}"; do
        t="${T_TOOLS[i]}"
        [ -n "${T_PREFIX[i]}" ] || continue
        env_pin "$REAL_ENV" "${T_VAR[i]}"
        pin="$PIN_VAL"
        [ -n "$pin" ] || { fail "style: no pin value for ${T_VAR[i]}"; continue; }
        if [ "${T_STYLE[i]}" = "tag" ]; then
            case "$pin" in "${T_PREFIX[i]}"*) : ;; *) fail "style: $t (${T_VAR[i]}='$pin') must start with '${T_PREFIX[i]}'" ;; esac
        else
            case "$pin" in "${T_PREFIX[i]}"*) fail "style: $t (${T_VAR[i]}='$pin') must not embed prefix '${T_PREFIX[i]}'" ;; *) : ;; esac
        fi
    done
    printf 'pin-style conformance ok\n'
}

A64=$(printf 'a%.0s' $(seq 1 64))

# Every tool pinned at 9.0.0 (tag-style tools keep their prefix); then nvim is
# set back to v1.0.0 so it is the one drifted tool.
write_fixture_env() { # write_fixture_env <dest-env>
    local i pin_val
    : > "$1"
    for i in "${!T_TOOLS[@]}"; do
        [ "${T_TOOLS[i]}" = nvim ] && continue
        if [ "${T_STYLE[i]}" = "tag" ]; then pin_val="${T_PREFIX[i]}9.0.0"; else pin_val="9.0.0"; fi
        printf '%s="${%s:-%s}"\n' "${T_VAR[i]}" "${T_VAR[i]}" "$pin_val" >> "$1"
    done
    cat >> "$1" <<EOF
DOTFILES_NEOVIM_VERSION="\${DOTFILES_NEOVIM_VERSION:-v1.0.0}"
DOTFILES_NEOVIM_LINUX_X86_64_SHA256="\${DOTFILES_NEOVIM_LINUX_X86_64_SHA256:-$A64}"
DOTFILES_NEOVIM_LINUX_ARM64_SHA256="\${DOTFILES_NEOVIM_LINUX_ARM64_SHA256:-$A64}"
EOF
}

fake_all_latest() { # every repo's latest is 9.0.0, except nvim at v2.0.0
    local i tag
    for i in "${!T_TOOLS[@]}"; do
        tag="${T_PREFIX[i]}9.0.0"
        [ "${T_TOOLS[i]}" = nvim ] && tag="v2.0.0"
        fake_latest "${T_REPO[i]}" "$tag"
    done
}

# ─────────────────────────────────────────────────────────
# 3) --check: reports drift, never edits, fails when a release can't resolve.
# ─────────────────────────────────────────────────────────
test_check() {
    local sb
    sb="$(sandbox_create)"
    sandbox_activate "$sb"
    write_fixture_env "$sb/env"
    fake_all_latest
    cp "$sb/env" "$sb/env.bak"
    run_bump "$sb" --check
    [ "$RC" = "0" ] || fail "--check exited $RC; output: $OUT"
    assert_contains "$OUT" "nvim v1.0.0 -> v2.0.0" "check drift"
    case "$OUT" in *"eza "*) fail "check reported a current tool: $OUT" ;; esac
    files_equal "$sb/env" "$sb/env.bak" || fail "--check mutated the pins file"

    fake_latest "neovim/neovim" "v1.0.0"
    run_bump "$sb" --check
    assert_contains "$OUT" "nothing to bump" "check clean"

    rm -f "$DOTFILES_BUMP_TEST_API_DIR/eza-community__eza.json"
    run_bump "$sb" --check
    [ "$RC" != "0" ] || fail "--check should fail when a release cannot be resolved"
    rm -rf "$sb"
    printf '%s\n' '--check ok'
}

# ─────────────────────────────────────────────────────────
# 4) Single-tool bumps in both pin styles, dry run, and failure isolation.
# ─────────────────────────────────────────────────────────
test_single_tool() {
    local sb h
    sb="$(sandbox_create)"
    sandbox_activate "$sb"
    cat > "$sb/env" <<EOF
DOTFILES_TREE_SITTER_VERSION="\${DOTFILES_TREE_SITTER_VERSION:-0.26.11}"
DOTFILES_TREE_SITTER_LINUX_X64_SHA256="\${DOTFILES_TREE_SITTER_LINUX_X64_SHA256:-$A64}"
DOTFILES_TREE_SITTER_LINUX_ARM64_SHA256="\${DOTFILES_TREE_SITTER_LINUX_ARM64_SHA256:-$A64}"
DOTFILES_NEOVIM_VERSION="\${DOTFILES_NEOVIM_VERSION:-v1.0.0}"
DOTFILES_NEOVIM_LINUX_X86_64_SHA256="\${DOTFILES_NEOVIM_LINUX_X86_64_SHA256:-$A64}"
DOTFILES_NEOVIM_LINUX_ARM64_SHA256="\${DOTFILES_NEOVIM_LINUX_ARM64_SHA256:-$A64}"
EOF
    # No API files needed: explicit VERSION must not require resolution.

    run_bump "$sb" tree-sitter 9.9.9
    [ "$RC" = "0" ] || fail "single tree-sitter bump exited $RC; output: $OUT"
    assert_line_contains "$sb/env" 'DOTFILES_TREE_SITTER_VERSION="${DOTFILES_TREE_SITTER_VERSION:-9.9.9}"' "bare-style pin"
    h="$(expect_sha "https://github.com/tree-sitter/tree-sitter/releases/download/v9.9.9/tree-sitter-linux-x64.gz")"
    assert_line_contains "$sb/env" "DOTFILES_TREE_SITTER_LINUX_X64_SHA256=\"\${DOTFILES_TREE_SITTER_LINUX_X64_SHA256:-$h}\"" "tree-sitter x64 hash"

    # THE regression test: nvim consumes its pin raw in the release URL, so an
    # explicit bare version must be stored WITH the v-prefix.
    run_bump "$sb" nvim 9.9.9
    [ "$RC" = "0" ] || fail "single nvim bump exited $RC; output: $OUT"
    assert_line_contains "$sb/env" 'DOTFILES_NEOVIM_VERSION="${DOTFILES_NEOVIM_VERSION:-v9.9.9}"' "tag-style pin keeps prefix"
    h="$(expect_sha "https://github.com/neovim/neovim/releases/download/v9.9.9/nvim-linux-arm64.tar.gz")"
    assert_line_contains "$sb/env" "DOTFILES_NEOVIM_LINUX_ARM64_SHA256=\"\${DOTFILES_NEOVIM_LINUX_ARM64_SHA256:-$h}\"" "nvim arm64 hash"

    # Dry run and a failed second download must both leave every pin untouched.
    cp "$sb/env" "$sb/env.bak"
    run_bump "$sb" nvim 10.0.0 --dry-run
    [ "$RC" = "0" ] || fail "dry-run bump exited $RC; output: $OUT"
    assert_contains "$OUT" "nvim: v9.9.9 -> v10.0.0 (dry run)" "dry-run report"
    DOTFILES_BUMP_TEST_FAIL_ASSET="nvim-linux-arm64" run_bump "$sb" nvim 10.0.0
    [ "$RC" != "0" ] || fail "failed download should exit non-zero"
    files_equal "$sb/env" "$sb/env.bak" || fail "dry run or failed download changed pins"
    rm -rf "$sb"
    printf 'single-tool bumps ok\n'
}

test_arg_handling() {
    local sb
    sb="$(sandbox_create)"
    sandbox_activate "$sb"
    write_fixture_env "$sb/env"
    run_bump "$sb" nosuchtool
    [ "$RC" != "0" ] || fail "unknown tool should exit non-zero"
    run_bump "$sb" nvim 1.0 2.0
    [ "$RC" != "0" ] || fail "two VERSIONs should exit non-zero"
    rm -rf "$sb"
    printf 'arg handling ok\n'
}

load_meta
test_inventory_parity
test_pin_styles
test_check
test_single_tool
test_arg_handling

if [ "$FAILURES" != "0" ]; then
    printf 'bump_version_test: %d failure(s)\n' "$FAILURES" >&2
    exit 1
fi
printf 'bump_version_test passed\n'
