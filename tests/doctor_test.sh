#!/bin/bash
# doctor_test.sh - verify copy-managed config drift detection.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=installation/versions.env
source "$ROOT/installation/versions.env"
TMP_DIR="$(mktemp -d "$ROOT/.doctor-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"
export PATH="$FAKE_BIN:/usr/bin:/bin"

# Presence-only tools: doctor asserts these exist, never compares versions.
for tool in zsh tmux git rg fd fzf python3 bat batcat; do
    printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN/$tool"
    chmod +x "$FAKE_BIN/$tool"
done
printf '#!/bin/sh\nprintf "%%s\\n" "JetBrainsMono Nerd Font"\n' > "$FAKE_BIN/fc-list"
chmod +x "$FAKE_BIN/fc-list"

# Pinned tools: each fake reports exactly the version its own declared pin
# holds. The previous fixture copied one script that printed a blob containing
# every version at once, so any permuted or typo'd pin still substring-matched
# and the suite could not fail. Deriving the list from doctor.sh keeps the
# fixture in sync and turns a bad pin variable into a visible mismatch.
pinned_count=0
while read -r _fn _label cmd var _kind; do
    # A real call site is `check_pinned "<label>" <cmd> <VAR> [kind]`. Requiring
    # the quoted label in the second field rejects both the function definition
    # (`check_pinned() {`) and any malformed row.
    [[ "${_label:-}" == \"* ]] || continue
    [[ "${var:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "${!var}" > "$FAKE_BIN/$cmd"
    chmod +x "$FAKE_BIN/$cmd"
    pinned_count=$((pinned_count + 1))
done < <(awk '/^[[:space:]]*check_pinned[[:space:]]+"/ {print}' "$ROOT/installation/doctor.sh")
if [ "$pinned_count" -lt 10 ]; then
    printf 'Fixture looks wrong: parsed %s check_pinned entries, expected many more\n' \
        "$pinned_count" >&2
    exit 1
fi

HOME_DIR="$TMP_DIR/home"
CONFIG_HOME="$HOME_DIR/.config"
mkdir -p "$CONFIG_HOME"

# Seed the deployed copy-managed modules from the repository fixture.
for name in atuin bottom lazygit nvim; do
    mkdir -p "$CONFIG_HOME/$name"
    cp -R "$ROOT/config/$name/." "$CONFIG_HOME/$name/"
done
# Herdr is seed/runtime-managed and must not be content-compared.
mkdir -p "$CONFIG_HOME/herdr"
printf '[ui]\ntab_bar_position = "bottom"\n' > "$CONFIG_HOME/herdr/config.toml"

run_doctor() {
    local ostype=${1:-}
    HOME="$HOME_DIR" \
    DOTFILES_LOG_FILE="$TMP_DIR/doctor.log" \
    OSTYPE="$ostype" \
    bash "$ROOT/installation/doctor.sh" 2>&1 || true
}

# A command the health check calls but cannot resolve aborts that section of the
# run and leaves the rest of the report looking short. doctor.sh deliberately
# does not source utils.sh (it must stay non-mutating), so installer's step
# vocabulary such as skip_step is undefined there — this guards every branch
# against reintroducing a call into that void.
assert_no_crash() {
    local label=$1 output=$2
    if grep -q 'command not found' <<< "$output"; then
        printf 'Doctor called an undefined command (%s):\n%s\n' "$label" "$output" >&2
        exit 1
    fi
}

clean_output="$(run_doctor)"
assert_no_crash "linux" "$clean_output"
if grep -q 'content drift' <<< "$clean_output"; then
    printf 'Doctor falsely reported drift for a matching deployment:\n%s\n' "$clean_output" >&2
    exit 1
fi
# Every fake reports its own declared pin, so a pin variable that does not
# resolve shows up here as a mismatch rather than passing silently.
if grep -q 'no version pin\|expected .*, got' <<< "$clean_output"; then
    printf 'Doctor could not match a declared pin against the fixture:\n%s\n' \
        "$clean_output" >&2
    exit 1
fi

# macOS branch: no fc-list, so the font check degrades to a manual note. This
# branch was unreachable from the suite, which is how a skip_step call in it
# survived — the health check crashed on the platform with the least tooling.
macos_output="$(run_doctor darwin23)"
assert_no_crash "macos" "$macos_output"
if ! grep -q 'JetBrainsMono' <<< "$macos_output"; then
    printf 'macOS doctor run never reached the font section:\n%s\n' "$macos_output" >&2
    exit 1
fi

printf '\n# user edit\n' >> "$CONFIG_HOME/atuin/config.toml"
drift_output="$(run_doctor)"
if ! grep -q 'config: atuin: content drift' <<< "$drift_output"; then
    printf 'Doctor did not report modified copy-managed config:\n%s\n' "$drift_output" >&2
    exit 1
fi

printf 'doctor tests passed\n'
