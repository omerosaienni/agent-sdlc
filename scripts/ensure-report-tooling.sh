#!/usr/bin/env bash
# Ensure this repo has the tooling the judge report needs: the coverage provider
# (@vitest/coverage-v8), matching the installed vitest major. Idempotent. Run from
# the project root.
#
# Usage:
#   ensure-report-tooling.sh            install or realign if missing/mismatched (default)
#   ensure-report-tooling.sh --check    report only, never install (exit 2 if missing/mismatched)
#
# Exit: 0 ok, 1 vitest absent or coverage run failed, 2 --check found it missing or mismatched
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
# Resolve inputs: vitest major, and whether coverage-v8 matches it
# ============================================================================

# The coverage provider major must match the installed vitest major; a present but
# mismatched provider fails the run, so match it, do not just check presence. This
# mirrors the setup gate's step 1, of which this is the standalone version.
node_major(){ node -e "try{console.log(require('$1/package.json').version.split('.')[0])}catch(e){process.exit(1)}" 2>/dev/null; }

vmaj=$(node_major vitest || true)
if [ -z "$vmaj" ]; then
    echo "vitest not installed; install it before ensuring report tooling" >&2
    exit 1
fi
cmaj=$(node_major '@vitest/coverage-v8' || true)

# ============================================================================
# Install or realign the coverage provider (only with consent)
# ============================================================================

if [ -n "$cmaj" ] && [ "$cmaj" = "$vmaj" ]; then
    echo "report tooling present (coverage-v8 matches vitest $vmaj)"
else
    [ -n "$cmaj" ] && echo "coverage-v8 major $cmaj does not match vitest $vmaj" || echo "coverage-v8 missing (need ^$vmaj)"
    if consent; then
        echo "installing @vitest/coverage-v8@^$vmaj (npm dev dependency: network + package.json change)"
        npm install -D "@vitest/coverage-v8@^${vmaj}"
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
