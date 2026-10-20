#!/bin/bash
# scripts/utils/test-env.sh

# Import env logic (will fail initially as file doesn't exist)
source "$(dirname "$0")/env.sh"

echo "Testing Environment Detection..."

current_env=$(get_env)
echo "Detected Env: $current_env"

if [[ "$current_env" == "macos" ]]; then
    echo "Verification: SUCCESS (Running on macOS)"
else
    echo "Verification: FAILED (Expected macos, got $current_env)"
    exit 1
fi
