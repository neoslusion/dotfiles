#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/installation/versions.env"

# Hard-fail on a missing toolchain instead of passing vacuously. Both floating
# guards below run ripgrep; without it `rg` exits 127, the `|| true` swallows
# that, the pattern matches nothing, and this test reports success while
# checking nothing at all. A security gate that cannot run must be loud.
for tool in rg awk sort ls; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Missing required tool: %s\n' "$tool" >&2
        exit 1
    }
done
required=(
    DOTFILES_JETBRAINS_MONO_SHA256
    DOTFILES_STARSHIP_LINUX_MUSL_X86_64_SHA256
    DOTFILES_STARSHIP_LINUX_MUSL_ARM64_SHA256
    DOTFILES_ATUIN_LINUX_MUSL_X86_64_SHA256
    DOTFILES_ATUIN_LINUX_MUSL_ARM64_SHA256
    DOTFILES_ZOXIDE_LINUX_MUSL_X86_64_SHA256
    DOTFILES_ZOXIDE_LINUX_MUSL_ARM64_SHA256
    DOTFILES_LAZYGIT_LINUX_X86_64_SHA256
    DOTFILES_LAZYGIT_LINUX_ARM64_SHA256
    DOTFILES_YAZI_LINUX_MUSL_X86_64_SHA256
    DOTFILES_YAZI_LINUX_MUSL_ARM64_SHA256
)
[[ "${DOTFILES_TPM_REF:-}" =~ ^[0-9a-fA-F]{40}$ ]] || {
    printf 'Missing or malformed TPM commit pin\n' >&2
    exit 1
}
for name in "${required[@]}"; do
    value="${!name:-}"
    [[ "$value" =~ ^[0-9a-fA-F]{64}$ ]] || { printf 'Missing pin: %s\n' "$name" >&2; exit 1; }
done
# Official agent installers (claude.ai, chatgpt.com) are vendor-owned scripts
# with no tarball releases to pin. Allowlist exactly those two URLs — anything
# else piped to a shell stays banned.
# Homebrew's own bootstrapper joins them for the same class of reason: it is the
# package-manager bootstrap for the entire macOS path, ships no release tarball,
# and pinning its installer to a commit turns "bootstrap a Mac" into a time bomb
# the next time upstream reorganises that repo. The alternative — a SHA here that
# nobody revalidates — is worse than a documented, greppable exception.
# Everything else must still download a verified artifact, including the repo's
# own scripts/bootstrap, which pins its checkout by commit SHA.
#
# Two shapes are banned: the pipe form (`curl ... | sh`) and the -c form
# (`bash -c "$(curl ...)"`). The second used to slip through this test while
# being the single most privileged remote script in the installer.
floating="$(
    rg -n 'curl[^|]*\|[[:space:]]*(sh|bash)|(sh|bash)[[:space:]]+-c[^;]*curl' \
        "$ROOT/installation" -g '*.sh' \
        | grep -vE 'claude\.ai/install\.sh|chatgpt\.com/codex/install\.sh|Homebrew/install' || true
)"
if [ -n "$floating" ]; then
    printf '%s\n' "$floating" >&2
    printf 'Floating network install found.\n' >&2
    exit 1
fi
if rg -n 'refs/heads/(master|main)|git clone https://' "$ROOT/installation" -g '*.sh'; then
    printf 'Floating ref or unversioned git clone found.\n' >&2
    exit 1
fi
# Action tags are mutable, so a retagged upstream would run unreviewed code with
# repo secrets in scope. Pin full commit SHAs (keep the tag as a trailing comment).
if rg -n 'uses:' "$ROOT/.github/workflows" \
    | rg -v 'uses:[[:space:]]*(\./|[^@[:space:]]+@[0-9a-f]{40}([[:space:]]|$))'; then
    printf 'GitHub Action not pinned to a commit SHA.\n' >&2
    exit 1
fi
# --- Config manifest coverage --------------------------------------------------
# Every top-level config/ directory must be declared in
# installation/config_manifest, and every non-internal entry must point at a
# real directory. Turns "added a config dir but forgot the installer" from a
# silent skip into a test failure (tier/mode validity is checked too).
manifest="$ROOT/installation/config_manifest"
[ -f "$manifest" ] || { printf 'Missing config manifest: %s\n' "$manifest" >&2; exit 1; }
declared="$(awk '!/^#/ && NF {print $1}' "$manifest" | sort)"
present="$(cd "$ROOT/config" && ls -1d */ | sed 's:/$::' | sort)"
if [ -z "$present" ]; then
    printf 'No config directories found under %s\n' "$ROOT/config" >&2
    exit 1
fi
if [ "$declared" != "$present" ]; then
    printf 'config manifest drift (installation/config_manifest vs config/):\n' >&2
    diff -L manifest -L 'config/' \
        <(printf '%s\n' "$declared") <(printf '%s\n' "$present") >&2 || true
    exit 1
fi
while read -r name tier mode _; do
    case "$name" in ''|'#'*) continue ;; esac
    case "$tier" in
        core|internal) ;;
        *) printf 'Invalid tier for %s: %s\n' "$name" "$tier" >&2; exit 1 ;;
    esac
    if [ "$tier" = "internal" ]; then continue; fi
    case "$mode" in
        copy|seed) ;;
        *) printf 'Invalid mode for %s: %s\n' "$name" "$mode" >&2; exit 1 ;;
    esac
    if [ ! -d "$ROOT/config/$name" ]; then
        printf 'Manifest entry has no config dir: %s\n' "$name" >&2
        exit 1
    fi
done < "$manifest"

# --- Windows installer parity --------------------------------------------------
# windows/install.ps1 deploys from the same config/ tree by hand, so a module
# added for Linux can silently never reach Windows. Each manifest entry must be
# referenced by install.ps1 or listed here with the reason Windows skips it.
windows_skip=(
    atuin             # gap: atuin is installed and hooked on Windows, config is not deployed
    bottom            # btm is not installed on Windows
    sketchybar        # macOS bar
    tmux              # herdr covers multiplexing on Windows
)
ps1="$ROOT/windows/install.ps1"
for name in $declared; do
    deployed=0
    rg -q "config[\\\\/]$name([\\\\/]|\")" "$ps1" && deployed=1
    case " ${windows_skip[*]} " in
        *" $name "*)
            [ "$deployed" = 0 ] || { printf 'Windows deploys %s; drop it from windows_skip\n' "$name" >&2; exit 1; } ;;
        *)
            [ "$deployed" = 1 ] || { printf 'Windows installer never deploys config/%s (deploy it or add to windows_skip)\n' "$name" >&2; exit 1; } ;;
    esac
done

# Statuslines run git on every redraw under a hard timeout. A killed
# `git status` leaves .git/index.lock behind and breaks the repo for every
# later git command, so each call must skip the optional index lock.
for statusline in "$ROOT"/config/*/statusline.py; do
    if grep -n '\["git",' "$statusline" | grep -v '"--no-optional-locks"' >&2; then
        printf '%s: git call without --no-optional-locks\n' "${statusline#"$ROOT"/}" >&2
        exit 1
    fi
done

printf 'install policy tests passed\n'
