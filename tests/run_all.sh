#!/bin/bash
# run_all.sh - run every local test suite in one command.
# Skips the docker distro smoke unless --smoke is passed (needs docker + network).
#
# Usage: tests/run_all.sh [--smoke]
#
# Windows-side checks (windows_preflight.ps1, windows_profile_test.ps1) run
# when pwsh is on PATH (native Windows, or pwsh installed on Linux/macOS).
# windows_dryrun_test.ps1 runs the real installer, which needs Windows (its
# env vars, .ps1 command shims), so it only runs on native Windows; CI's
# windows job covers it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE=0
for arg in "$@"; do
    case "$arg" in
        --smoke) SMOKE=1 ;;
        *)
            echo "run_all.sh: unknown option '$arg' (usage: tests/run_all.sh [--smoke])" >&2
            exit 2
            ;;
    esac
done

SUITES=(
    install_policy_test.sh
    bootstrap_test.sh
    path_policy_test.sh
    doctor_test.sh
    install_agents_test.sh
    install_utils_test.sh
    install_configs_test.sh
    shell_config_test.sh
    config_preflight_test.sh
    bump_version_test.sh
)
if [ "$SMOKE" -eq 1 ]; then
    SUITES+=(distro_smoke.sh)
fi

failures=0
for suite in "${SUITES[@]}"; do
    printf -- "--- %s\n" "$suite"
    # $BASH, not PATH bash: CI pins the interpreter (macOS: stock /bin/bash 3.2).
    if "$BASH" "$ROOT/tests/$suite"; then
        printf "    ok\n"
    else
        printf "    FAILED\n" >&2
        failures=$((failures + 1))
    fi
done

if command -v pwsh &> /dev/null; then
    printf -- "--- windows_preflight.ps1\n"
    if pwsh -NoProfile -File "$ROOT/tests/windows_preflight.ps1"; then
        printf "    ok\n"
    else
        printf "    FAILED\n" >&2
        failures=$((failures + 1))
    fi
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            printf -- "--- windows_dryrun_test.ps1\n"
            if pwsh -NoProfile -File "$ROOT/tests/windows_dryrun_test.ps1"; then
                printf "    ok\n"
            else
                printf "    FAILED\n" >&2
                failures=$((failures + 1))
            fi
            ;;
        *) printf -- "--- windows_dryrun_test.ps1 (skipped: needs native Windows)\n" ;;
    esac
    printf -- "--- windows_profile_test.ps1\n"
    if pwsh -NoProfile -File "$ROOT/tests/windows_profile_test.ps1"; then
        printf "    ok\n"
    else
        printf "    FAILED\n" >&2
        failures=$((failures + 1))
    fi
else
    printf -- "--- windows checks (skipped: pwsh not on PATH)\n"
fi

if [ "$failures" -eq 0 ]; then
    echo "All test suites passed."
    exit 0
fi
echo "Test suites failed: $failures" >&2
exit 1
