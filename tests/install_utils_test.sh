#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="$TMP_DIR/home"
export DOTFILES_LOG_FILE="$TMP_DIR/install.log"
mkdir -p "$HOME"
source "$ROOT/installation/utils.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

state="$TMP_DIR/state"
lazy_log="$(
    unset DOTFILES_LOG_FILE
    export XDG_STATE_HOME="$state"
    source "$ROOT/installation/utils.sh"
    [ ! -e "$state" ] || fail 'sourcing utils.sh created the log directory'
    log 'first write'
    printf '%s' "$DOTFILES_LOG_FILE"
)"
grep -q 'first write' "$lazy_log" || fail 'log() did not create the log file'

asset="$TMP_DIR/asset"
printf 'verified content\n' > "$asset"
sha="$(sha256sum "$asset" | awk '{print $1}')"
verify_sha256 "$asset" "$sha" || fail 'valid SHA rejected'
if verify_sha256 "$asset" '' >/dev/null 2>&1; then fail 'empty SHA accepted'; fi
if verify_sha256 "$asset" deadbeef >/dev/null 2>&1; then fail 'short SHA accepted'; fi
if verify_sha256 "$asset" "${sha%?}0" >/dev/null 2>&1; then fail 'wrong SHA accepted'; fi
if download_verified_asset 'https://invalid.example/asset' "$TMP_DIR/out" '' >/dev/null 2>&1; then
    fail 'download started without a valid SHA'
fi

# Every release_assets row must resolve to a real pin on each arch it declares;
# a typo in a sha-var name would otherwise surface only mid-install.
ra_asset='' ra_sha='' # assigned by release_asset (by name)
while IFS='|' read -r tool _ _ _ _ _ arm _; do
    case "$tool" in ''|'#'*) continue ;; esac
    for arch in x86_64 aarch64; do
        [ "$arch" = aarch64 ] && [ -z "$arm" ] && continue
        uname() { echo "$arch"; }
        release_asset "$tool" ra_asset ra_sha >/dev/null || fail "$tool/$arch did not resolve"
        [[ -n "$ra_asset" && "$ra_sha" =~ ^[0-9a-f]{64}$ ]] || fail "$tool/$arch: bad asset '$ra_asset' or sha '$ra_sha'"
    done
done < "$ROOT/installation/release_assets"
uname() { echo riscv64; }
if release_asset nvim ra_asset ra_sha >/dev/null; then fail 'unsupported arch resolved'; fi
unset -f uname

fallback_bin="$TMP_DIR/fallback-bin"
mkdir -p "$fallback_bin"
cat > "$fallback_bin/shasum" <<'EOF'
#!/bin/bash
[ "$1" = '-a' ] && [ "$2" = '256' ] && [ "$3" = '-c' ] && [ "$4" = '-' ] || exit 2
exec "$REAL_SHA256SUM" -c -
EOF
chmod +x "$fallback_bin/shasum"
REAL_SHA256SUM="$(command -v sha256sum)" PATH="$fallback_bin" verify_sha256 "$asset" "$sha" || fail 'shasum fallback rejected valid SHA'

calls="$TMP_DIR/sudo-calls"
sudo() { printf '%s\n' "$*" >> "$calls"; return 0; }
# The apt and pacman paths only run on Linux, where the stale-source cleanup is
# live; pin that so the macOS job checks the same ordering.
is_macos() { return 1; }

: > "$calls"
DOTFILES_PKG_MGR=apt
unset DOTFILES_APT_INDEX_REFRESHED
prepare_system_packages
prepare_system_packages
[ "$(grep -c '^apt-get update$' "$calls" || true)" -eq 1 ] || fail 'apt refreshed more than once'
[ "$(head -n 1 "$calls")" != 'apt-get update' ] || fail 'apt refreshed before stale source cleanup'
export -p | grep -q 'DOTFILES_APT_INDEX_REFRESHED="1"' || fail 'apt state not exported'

: > "$calls"
DOTFILES_PKG_MGR=pacman
unset DOTFILES_PACMAN_SYNCED
prepare_system_packages
prepare_system_packages
[ "$(grep -c '^pacman -Syu --noconfirm$' "$calls" || true)" -eq 1 ] || fail 'pacman synced more than once'
export -p | grep -q 'DOTFILES_PACMAN_SYNCED="1"' || fail 'pacman state not exported'
unset -f sudo

printf 'install utility tests passed\n'
