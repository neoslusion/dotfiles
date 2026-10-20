#!/bin/bash
# doctor.sh - non-mutating health check for the dotfiles setup.
# Verifies installed tool versions against versions.env pins, config
# deployment parity (repo vs home), agent homes, and the secrets scaffold.
# Exit code 0 = healthy, 1 = failures found (warnings never fail).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=installation/versions.env
source "$ROOT/installation/versions.env"

# utils.sh defines is_macos too, but sourcing it here would create a log file
# and doctor must stay non-mutating — this check is all the fonts section needs.
is_macos() {
    [[ "${OSTYPE:-}" == "darwin"* ]]
}

if [ -t 1 ]; then
    C_PASS=$'\033[32m'; C_WARN=$'\033[33m'; C_FAIL=$'\033[31m'; C_MUT=$'\033[2m'; C_NC=$'\033[0m'
else
    C_PASS=''; C_WARN=''; C_FAIL=''; C_MUT=''; C_NC=''
fi

pass() { printf "%spass%s %s\n" "$C_PASS" "$C_NC" "$1"; }
warn() { printf "%swarn%s %s\n" "$C_WARN" "$C_NC" "$1"; }
fail() { printf "%sfail%s %s\n" "$C_FAIL" "$C_NC" "$1"; }
muted() { printf "%s%s%s\n" "$C_MUT" "$1" "$C_NC"; }

FAILURES=0
WARNINGS=0

# --- Tool versions ------------------------------------------------------------
tool_output() {
    local cmd=$1 out=""
    for flag in --version -V version; do
        if out="$("$cmd" "$flag" 2>/dev/null)"; then
            printf '%s\n' "$out"
            return 0
        fi
    done
    return 1
}

check_pinned() {
    # check_pinned <label> <cmd> <version-env-var> [core|extra]
    local label=$1 cmd=$2 pin=${!3:-} kind=${4:-core}
    local out

    if ! command -v "$cmd" &> /dev/null; then
        if [ "$kind" = "core" ]; then
            fail "$label: not installed"
            FAILURES=$((FAILURES + 1))
        fi
        return 0
    fi
    if [ -z "$pin" ]; then
        warn "$label: no version pin for this tool"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi
    pin="${pin#v}"
    if out="$(tool_output "$cmd")" && [[ "$out" == *"$pin"* ]]; then
        pass "$label $pin"
    else
        if [ "$kind" = "core" ]; then
            warn "$label: expected $pin, got: $(printf '%s' "$out" | head -n 1)"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
}

check_present() {
    local label=$1 cmd=$2
    if command -v "$cmd" &> /dev/null; then
        pass "$label"
    else
        fail "$label: not installed"
        FAILURES=$((FAILURES + 1))
    fi
}

muted "--- tools (pinned)"
check_pinned "nvim"        nvim        DOTFILES_NEOVIM_VERSION
check_pinned "tree-sitter" tree-sitter DOTFILES_TREE_SITTER_VERSION
check_pinned "lazygit"     lazygit     DOTFILES_LAZYGIT_VERSION
check_pinned "bottom"      btm         DOTFILES_BOTTOM_VERSION
check_pinned "starship"    starship    DOTFILES_STARSHIP_VERSION
check_pinned "atuin"       atuin       DOTFILES_ATUIN_VERSION
check_pinned "eza"         eza         DOTFILES_EZA_VERSION
check_pinned "delta"       delta       DOTFILES_DELTA_VERSION
check_pinned "zoxide"      zoxide      DOTFILES_ZOXIDE_VERSION
check_pinned "herdr"       herdr       DOTFILES_HERDR_VERSION
check_pinned "yazi"        yazi        DOTFILES_YAZI_VERSION

muted "--- fonts"
# The font has no --version CLI, so verify presence via fc-list instead of the
# pinned-version comparison used for tools. Windows side checks it in
# doctor.ps1 via Test-Font.
# macOS has no fc-list and no headless font query, so this degrades to a note.
# It uses doctor's own muted vocabulary rather than utils.sh's skip_step:
# doctor deliberately does not source utils.sh (see above), so the installer's
# step vocabulary is undefined here and calling it aborted the run on macOS.
if is_macos; then
    muted "font: JetBrainsMono NF - verify via System Settings / Font Book"
elif fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    pass "font: JetBrainsMono NF"
else
    warn "font: JetBrainsMono Nerd Font not found via fc-list (pinned $DOTFILES_JETBRAINS_MONO_VERSION)"
fi

muted "--- tools (repo packages, presence)"
for pair in "zsh:zsh" "tmux:tmux" "git:git" "ripgrep:rg" "fd:fd" "fzf:fzf" "python3:python3"; do
    label="${pair%%:*}"; cmd="${pair##*:}"
    check_present "$label" "$cmd"
done
check_present "bat" bat || check_present "bat" batcat

# --- Config deployment parity -------------------------------------------------
muted "--- configs"
check_file() { # check_file <label> <path> [required]
    local label=$1 path=$2 required=${3:-1}
    if [ -e "$path" ]; then
        pass "$label"
    elif [ "$required" -eq 1 ]; then
        fail "$label: missing $path"
        FAILURES=$((FAILURES + 1))
    fi
}

check_dir() { # check_dir <label> <path> [required]
    local label=$1 path=$2 required=${3:-1}
    if [ -d "$path" ]; then
        pass "$label"
    elif [ "$required" -eq 1 ]; then
        fail "$label: missing $path"
        FAILURES=$((FAILURES + 1))
    fi
}

check_copied_config() { # check_copied_config <name>
    local name=$1
    local source_dir="$ROOT/config/$name"
    local deployed_dir="$HOME/.config/$name"
    local path relative deployed_path

    if [ ! -d "$deployed_dir" ]; then
        check_dir "config: $name" "$deployed_dir"
        return
    fi

    # Compare only paths provided by the repository. This detects missing or
    # modified copy-managed files (including nested files) without treating
    # user-created destination entries as drift.
    while IFS= read -r -d '' path; do
        [ "$path" = "$source_dir" ] && continue
        relative=${path#"$source_dir"/}
        deployed_path="$deployed_dir/$relative"
        if [ ! -d "$deployed_path" ]; then
            fail "config: $name: content drift (missing $relative; run installer to refresh)"
            FAILURES=$((FAILURES + 1))
            return
        fi
    done < <(find "$source_dir" -type d -print0)

    while IFS= read -r -d '' path; do
        relative=${path#"$source_dir"/}
        deployed_path="$deployed_dir/$relative"
        if [ ! -e "$deployed_path" ] && [ ! -L "$deployed_path" ]; then
            fail "config: $name: content drift (missing $relative; run installer to refresh)"
            FAILURES=$((FAILURES + 1))
            return
        fi
        if [ -d "$deployed_path" ] || ! diff -q "$path" "$deployed_path" >/dev/null 2>&1; then
            fail "config: $name: content drift ($relative differs; run installer to refresh)"
            FAILURES=$((FAILURES + 1))
            return
        fi
    done < <(find "$source_dir" ! -type d -print0)

    pass "config: $name"
}

# Config modules — derived from the deploy manifest (installation/config_manifest)
# so doctor, the installer, and the manifest coverage test share one list.
DOTFILES_MANIFEST="$ROOT/installation/config_manifest"
if [ ! -f "$DOTFILES_MANIFEST" ]; then
    fail "config manifest missing: $DOTFILES_MANIFEST"
    FAILURES=$((FAILURES + 1))
fi
while read -r name tier mode sentinel; do
    case "$name" in ''|'#'*) continue ;; esac
    [ "$tier" = "core" ] || continue
    if [ "$mode" = "seed" ]; then
        check_file "config: $name" "$HOME/.config/$name/${sentinel:-}"
    else
        check_copied_config "$name"
    fi
done < "$DOTFILES_MANIFEST"
check_file "config: zsh core" "$HOME/.config/zsh/core.zsh"
check_file "config: starship" "$HOME/.config/starship.toml"
check_file "shell: .zshrc" "$HOME/.zshrc"
check_file "shell: .zshenv" "$HOME/.zshenv"
check_file "tmux: .tmux.conf" "$HOME/.tmux.conf"
check_file "tmux: core" "$HOME/.config/tmux/tmux.core.conf"
check_file "tmux: theme" "$HOME/.config/tmux/theme.conf"
check_dir "tmux: tpm" "$HOME/.tmux/plugins/tpm"
for s in audit-nvim-keymaps dotsync sys-info; do
    check_file "script: $s" "$HOME/.local/bin/$s"
done

muted "--- agents"
check_file "claude: settings.json" "$HOME/.claude/settings.json"
check_file "claude: CLAUDE.md" "$HOME/.claude/CLAUDE.md"
check_file "claude: shared docs" "$HOME/.claude/ENGINEERING.md"
check_file "codex: AGENTS.md" "$HOME/.codex/AGENTS.md"
check_file "codex: base config" "$HOME/.codex/config.toml"
check_file "antigravity: AGENTS.md" "$HOME/.gemini/antigravity-cli/AGENTS.md"
check_file "antigravity: mcp.json" "$HOME/.gemini/antigravity-cli/mcp.json"
check_file "opencode: AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
check_file "opencode: opencode.json" "$HOME/.config/opencode/opencode.json"

muted "--- secrets scaffold"
check_file "secrets: env.sh" "$HOME/.secrets/env.sh"

echo ""
if [ "$FAILURES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    pass "health check complete"
    exit 0
fi
if [ "$FAILURES" -eq 0 ]; then
    warn "health check complete: $WARNINGS warning(s)"
    exit 0
fi
printf "%sfail%s health check complete: %d failure(s), %d warning(s)\n" "$C_FAIL" "$C_NC" "$FAILURES" "$WARNINGS"
exit 1
