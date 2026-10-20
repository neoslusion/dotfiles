#!/bin/bash
# Shared utilities for installation scripts
set -eo pipefail

UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$UTILS_DIR/versions.env" ]; then
    # shellcheck source=installation/versions.env
    source "$UTILS_DIR/versions.env"
fi

get_arch() {
    local arch
    arch=$(uname -m)
    if [ "$arch" = "x86_64" ]; then
        echo "amd64"
    elif [ "$arch" = "aarch64" ]; then
        echo "arm64"
    else
        echo "$arch"
    fi
}

is_macos() {
    [[ "$OSTYPE" == "darwin"* ]]
}

is_linux() {
    [[ "$OSTYPE" == "linux-gnu"* ]]
}

get_os() {
    if is_macos; then
        echo "macos"
    elif is_linux; then
        echo "linux"
    else
        echo "unknown"
    fi
}

if [ -t 1 ]; then
    RED=$'\033[38;2;247;118;142m'
    GREEN=$'\033[38;2;158;206;106m'
    BLUE=$'\033[38;2;122;162;247m'
    YELLOW=$'\033[38;2;224;175;104m'
    PURPLE=$'\033[38;2;187;154;247m'
    MUTED=$'\033[38;2;86;95;137m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED=''
    GREEN=''
    BLUE=''
    YELLOW=''
    PURPLE=''
    MUTED=''
    BOLD=''
    NC=''
fi

DOTFILES_VERBOSE="${DOTFILES_VERBOSE:-0}"

if [ -z "${DOTFILES_LOG_FILE:-}" ]; then
    DOTFILES_LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install-$(date +%Y%m%d-%H%M%S).log"
    export DOTFILES_LOG_FILE
fi

# The log is created on first write, not on source: helpers and tests source
# this file without logging and must not touch $HOME. run_step logs before its
# own `>>` / `tee -a` writes, so the directory exists by then.
log() {
    [ -f "$DOTFILES_LOG_FILE" ] || mkdir -p "$(dirname "$DOTFILES_LOG_FILE")"
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$DOTFILES_LOG_FILE"
}

banner() {
    printf "\n%s%s%s\n" "$BOLD" "$1" "$NC"
    printf "%s%s%s\n\n" "$MUTED" "Log: $DOTFILES_LOG_FILE" "$NC"
}

section() {
    printf "\n%s%s%s\n" "$PURPLE" "$1" "$NC"
}

info() {
    printf "%sinfo%s %s\n" "$BLUE" "$NC" "$1"
    log "INFO $1"
}

success() {
    printf "%sok%s   %s\n" "$GREEN" "$NC" "$1"
    log "OK $1"
}

warning() {
    printf "%swarn%s %s\n" "$YELLOW" "$NC" "$1"
    # Side channel for run_step: in quiet mode the step's own output is
    # captured to the log file, which would otherwise hide this warning
    # entirely (unset outside a step → /dev/null, the printf above is shown).
    printf '%s\n' "$1" >> "${DOTFILES_STEP_WARN_FILE:-/dev/null}"
    log "WARN $1"
}

error() {
    printf "%sfail%s %s\n" "$RED" "$NC" "$1"
    log "FAIL $1"
}

step_prefix() {
    printf "  %-34s" "$1"
}

run_step() {
    local label=$1
    shift

    log "START $label"

    # Warnings raised inside the step are buffered on a side channel and
    # replayed beneath the status line, so quiet mode (which sends the step's
    # output to the log file) still surfaces them. Save/restore around nested
    # run_step calls so the outer step doesn't lose its own warnings.
    local prev_warn_file="${DOTFILES_STEP_WARN_FILE:-}"
    DOTFILES_STEP_WARN_FILE="$(mktemp)"
    export DOTFILES_STEP_WARN_FILE

    local status=0
    if [ "$DOTFILES_VERBOSE" = "1" ]; then
        printf "%s▶%s %s\n" "$BLUE" "$NC" "$label"
        # `|| status=$?` keeps set -eo pipefail from aborting the whole
        # install before the failure branch can print anything.
        "$@" 2>&1 | tee -a "$DOTFILES_LOG_FILE" || status=$?
        if [ "$status" -eq 0 ]; then
            success "$label"
        else
            error "$label (see $DOTFILES_LOG_FILE)"
        fi
    else
        step_prefix "$label"
        if "$@" >> "$DOTFILES_LOG_FILE" 2>&1; then
            printf "%sok%s\n" "$GREEN" "$NC"
            log "OK $label"
        else
            status=$?
            printf "%sfail%s\n" "$RED" "$NC"
            error "$label failed. See $DOTFILES_LOG_FILE"
        fi
    fi

    _flush_step_warnings
    rm -f "$DOTFILES_STEP_WARN_FILE"
    if [ -n "$prev_warn_file" ]; then
        DOTFILES_STEP_WARN_FILE="$prev_warn_file"
    else
        unset DOTFILES_STEP_WARN_FILE
    fi
    return "$status"
}

# Replay the step's buffered warnings beneath its status line. Verbose mode
# already streamed them through tee, so only quiet mode prints. The raw
# messages are already in the log (warning() logs them itself) — display only.
_flush_step_warnings() {
    [ -s "$DOTFILES_STEP_WARN_FILE" ] || return 0
    local line
    while IFS= read -r line; do
        if [ "$DOTFILES_VERBOSE" != "1" ]; then
            printf '%36s%s%s %s%s\n' '' "$YELLOW" "warn" "$line" "$NC"
        fi
    done < "$DOTFILES_STEP_WARN_FILE"
    return 0
}

skip_step() {
    local label=$1
    local reason=${2:-already done}
    step_prefix "$label"
    printf "%sskip%s %s\n" "$YELLOW" "$NC" "$reason"
    log "SKIP $label ($reason)"
}

# Helper to check if a command exists and install it if missing
# Usage: check_and_install <cmd_name> <display_name> <install_command...>
check_and_install() {
    local cmd=$1
    local name=$2
    shift 2

    if ! command -v "$cmd" &> /dev/null; then
        run_step "$name" "$@"
    else
        skip_step "$name" "installed"
    fi
}

# Helper to check if a directory exists and clone/install if missing
# Usage: check_dir_and_run <dir_path> <display_name> <command...>
check_dir_and_run() {
    local dir=$1
    local name=$2
    shift 2

    if [ ! -d "$dir" ]; then
        run_step "$name" "$@"
    else
        skip_step "$name" "installed"
    fi
}

verify_sha256() {
    local file=$1 expected=${2:-}
    if [[ ! "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
        error "Missing or malformed SHA256 for $(basename "$file")"
        return 2
    fi
    if command -v sha256sum &> /dev/null; then
        printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
    elif command -v shasum &> /dev/null; then
        printf '%s  %s\n' "$expected" "$file" | shasum -a 256 -c -
    else
        error "No SHA256 verification tool found (need sha256sum or shasum)"
        return 2
    fi
}

download_verified_asset() {
    local url=$1 dest=$2 sha256=${3:-}
    if [[ ! "$sha256" =~ ^[0-9a-fA-F]{64}$ ]]; then
        error "Missing or malformed SHA256 for ${url##*/}"
        return 2
    fi
    curl -fL "$url" -o "$dest" && verify_sha256 "$dest" "$sha256"
}

# release_asset <tool> <asset-var> <sha-var>: set the caller's two variables to
# this machine's asset name and pinned SHA256 from installation/release_assets.
release_asset() {
    local ver_var="" x86="" x86_sha="" arm="" arm_sha="" name="" sha_var=""
    IFS='|' read -r _ _ _ ver_var x86 x86_sha arm arm_sha _ \
        < <(awk -F'|' -v t="$1" '$1 == t' "$UTILS_DIR/release_assets") || :
    case "$(uname -m)" in
        x86_64) name=$x86 sha_var=$x86_sha ;;
        aarch64|arm64) name=$arm sha_var=$arm_sha ;;
    esac
    if [ -z "$name" ]; then
        error "No $1 release asset for architecture: $(uname -m)"
        return 1
    fi
    printf -v "$2" '%s' "${name//\{V\}/${!ver_var:-}}"
    printf -v "$3" '%s' "${!sha_var:-}"
}

git_clone_ref() {
    local repo_url=$1
    local dest=$2
    local ref=${3:-}

    git clone "$repo_url" "$dest"
    if [ -n "$ref" ]; then
        git -C "$dest" checkout --detach "$ref"
    fi
}

# --- Package manager abstraction --------------------------------------------
# Callers ALWAYS pass Debian package names; map_package translates per-distro.

detect_pkg_mgr() {
    if [ -n "${DOTFILES_PKG_MGR:-}" ]; then
        return 0
    fi
    # Probe order covers derivatives: Mint/Pop -> apt, Nobara -> dnf,
    # Manjaro -> pacman.
    if command -v apt-get &> /dev/null; then
        DOTFILES_PKG_MGR="apt"
    elif command -v dnf &> /dev/null; then
        DOTFILES_PKG_MGR="dnf"
    elif command -v pacman &> /dev/null; then
        DOTFILES_PKG_MGR="pacman"
    else
        DOTFILES_PKG_MGR="unknown"
    fi
    export DOTFILES_PKG_MGR
}

prepare_system_packages() {
    detect_pkg_mgr
    case "$DOTFILES_PKG_MGR" in
        apt)
            if [ -z "${DOTFILES_APT_INDEX_REFRESHED:-}" ]; then
                remove_legacy_gdu_ppa
                sudo apt-get update || warning "apt-get update failed; using existing package index"
                export DOTFILES_APT_INDEX_REFRESHED=1
            fi
            ;;
        pacman)
            if [ -z "${DOTFILES_PACMAN_SYNCED:-}" ]; then
                sudo pacman -Syu --noconfirm || return $?
                export DOTFILES_PACMAN_SYNCED=1
            fi
            ;;
        dnf) ;;
        *) error "No supported package manager found"; return 1 ;;
    esac
}

# Translate one Debian-canonical name for the active package manager.
# Echoing nothing = intentionally dropped there; unlisted names pass through.
map_package() {
    local pkg=$1

    if [ "$DOTFILES_PKG_MGR" = "apt" ]; then
        echo "$pkg"
        return 0
    fi

    if [ "$DOTFILES_PKG_MGR" = "pacman" ]; then
        case "$pkg" in
            build-essential) echo "base-devel" ;;
            fd-find) echo "fd" ;;
            libfuse2) echo "fuse2" ;;
            python3) echo "python" ;;
            python3-pip) echo "python-pip" ;;
            python3-venv) ;; # venv ships with python
            *) echo "$pkg" ;;
        esac
        return 0
    fi

    # dnf
    case "$pkg" in
        build-essential) echo "gcc gcc-c++ make" ;;
        libfuse2) echo "fuse-libs" ;;
        python3-venv) ;; # venv ships with python3
        *) echo "$pkg" ;;
    esac
}

# Install system packages by Debian name on apt, dnf, or pacman systems.
system_install() {
    prepare_system_packages || return $?

    local pkg mapped=""
    for pkg in "$@"; do
        mapped="$mapped $(map_package "$pkg")"
    done
    # Intentional word splitting: one Debian name can map to several packages
    # shellcheck disable=SC2086
    set -- $mapped

    if [ "$#" -eq 0 ]; then
        warning "No $DOTFILES_PKG_MGR equivalent for requested package(s); skipping"
        return 0
    fi

    case "$DOTFILES_PKG_MGR" in
        apt)
            # Noninteractive is mandatory: run_step captures output with no
            # TTY, so a debconf prompt would hang forever. sudo strips env
            # vars, so the assignment must ride the sudo command line.
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
            ;;
        dnf)
            sudo dnf install -y "$@"
            ;;
        pacman)
            sudo pacman -S --needed --noconfirm "$@"
            ;;
    esac
}

# Download a pinned GitHub-release tarball, verify, and install one binary.
# Usage: install_release_binary <url> <find_pattern> <dest_name> [sha256]
# run_step invokes commands in an `if` context where set -e is suppressed,
# so every step is &&-chained with the status captured explicitly.
install_release_binary() {
    local url=$1
    local find_pattern=$2
    local dest_name=$3
    local sha256=${4:-}
    local temp_dir asset status=0

    temp_dir=$(mktemp -d)
    asset="${url##*/}"
    (
        cd "$temp_dir" \
            && download_verified_asset "$url" "$asset" "$sha256" \
            && tar -xzf "$asset" \
            && binary="$(find . -type f -name "$find_pattern" -perm -111 | head -n 1)" \
            && [ -n "$binary" ] \
            && sudo install "$binary" "/usr/local/bin/$dest_name"
    ) || status=$?
    rm -rf "$temp_dir"
    return "$status"
}

remove_legacy_gdu_ppa() {
    if is_macos; then
        return 0
    fi

    sudo rm -f \
        /etc/apt/sources.list.d/daniel-milde-ubuntu-gdu*.list \
        /etc/apt/sources.list.d/daniel-milde-ubuntu-gdu*.list.save \
        /etc/apt/sources.list.d/daniel-milde-ubuntu-gdu*.sources \
        /etc/apt/sources.list.d/daniel-milde-ubuntu-gdu*.sources.save
}
