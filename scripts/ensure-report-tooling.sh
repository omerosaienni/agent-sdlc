#!/usr/bin/env bash
# Ensure this repo has the tooling the judge report needs: the coverage provider
# (@vitest/coverage-v8). Idempotent. Run from the project root.
#
# Usage:
#   ensure-report-tooling.sh            install if missing (default)
#   ensure-report-tooling.sh --check    report only, never install (exit 2 if missing)
#
# Exit: 0 present or installed, 1 coverage run failed, 2 --check found it missing
set -euo pipefail

# ============================================================================
# Helpers
# ============================================================================

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# consent: true if the script may install. Installing is the default, since invoking
# the script is the consent; --check is the read-only check that refuses.
consent() { [ "$mode" = check ] && return 1; return 0; }

# ============================================================================
# Parse arguments
# ============================================================================

mode="act"
for arg in "$@"; do
    case "$arg" in
        --check)   mode="check" ;;
        -h|--help) usage ;;
        *)
            echo "unknown argument: $arg" >&2
            echo "use --check or no argument" >&2
            exit 64 ;;
    esac
done

# ============================================================================
# Resolve inputs: what is missing
# ============================================================================

need=()
node -e "require.resolve('@vitest/coverage-v8')" 2>/dev/null || need+=("@vitest/coverage-v8")

# ============================================================================
# Install the gap (only with consent)
# ============================================================================

if [ ${#need[@]} -eq 0 ]; then
    echo "report tooling already present"
else
    echo "missing report tooling: ${need[*]}"
    if consent; then
        echo "installing (npm dev dependencies: network + package.json change): ${need[*]}"
        npm install -D "${need[@]}"
    else
        echo "--check: not installing; re-run without --check to install" >&2
        exit 2
    fi
fi

# ============================================================================
# Verify coverage actually runs
# ============================================================================

if npx vitest run --coverage --reporter=dot >/dev/null 2>&1; then
    echo "coverage runs"
else
    echo "coverage configured but a run failed; check the vitest tier config(s) (vitest.unit.config.ts, and vitest.integration.config.ts if present)" >&2
    exit 1
fi
