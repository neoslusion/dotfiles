#!/bin/bash
# scripts/utils/env.sh

is_macos() { [[ "$OSTYPE" == "darwin"* ]]; }
is_linux() { [[ "$OSTYPE" == "linux-gnu"* ]]; }
is_wsl() { [[ -n "$WSL_DISTRO_NAME" || -n "$WSL_INTEROP" ]]; }

get_env() {
    if is_macos; then echo "macos";
    elif is_wsl; then echo "wsl";
    elif is_linux; then echo "linux";
    else echo "unknown"; fi
}
