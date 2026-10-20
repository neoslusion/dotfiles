#!/bin/bash
# Distro smoke test: run the full installer inside Debian/Fedora/Arch
# containers to validate system_install's package-manager dispatch and the
# map_package name table. Manual (not CI) — requires docker and network.
#
# Usage: tests/distro_smoke.sh [image...]   (default: all three)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found; skipping distro smoke test" >&2
    exit 0
fi

IMAGES=("$@")
[ ${#IMAGES[@]} -eq 0 ] && IMAGES=(ubuntu:22.04 fedora:latest archlinux:latest)

# Bootstrap: each minimal image needs sudo + basic tools the installer
# assumes, plus a passwordless-sudo non-root user (installer calls sudo).
bootstrap_for() {
    case "$1" in
        ubuntu*|debian*)
            echo "apt-get update && apt-get install -y sudo git curl ca-certificates tar unzip findutils fontconfig" ;;
        fedora*)
            echo "dnf install -y sudo git curl tar unzip findutils fontconfig awk" ;;
        archlinux*)
            echo "pacman -Syu --noconfirm && pacman -S --needed --noconfirm sudo git curl tar unzip findutils fontconfig awk" ;;
        *)
            echo "false" ;;
    esac
}

failures=0
for image in "${IMAGES[@]}"; do
    echo "=== $image ==="
    if docker run --rm \
        -v "$ROOT":/dotfiles-src:ro \
        "$image" bash -c "
            set -euo pipefail
            $(bootstrap_for "$image")
            useradd -m tester
            echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
            cp -r /dotfiles-src /home/tester/dotfiles
            chown -R tester /home/tester/dotfiles
            su tester -c '
                cd /home/tester/dotfiles
                export DOTFILES_VERBOSE=1
                export DEBIAN_FRONTEND=noninteractive
                ./install.sh < /dev/null
            '
        "; then
        echo "=== $image: PASS ==="
    else
        echo "=== $image: FAIL ===" >&2
        failures=$((failures + 1))
    fi
done

exit "$failures"
