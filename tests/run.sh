#!/usr/bin/env bash
# Run the repo's test suites. Discovers every tests/<name>/test.sh, runs each, and
# exits non-zero if any suite fails. Each suite tests one script under scripts/ and
# uses the assertions in tests/lib.sh. New suites are picked up by adding a folder;
# no change here and none in the GitHub workflow.
#
# Usage:
#   tests/run.sh             run every suite
#   tests/run.sh <name>      run only tests/<name>/test.sh
#   tests/run.sh --help
#
# Exit: 0 all suites passed, 1 a suite failed, 64 bad usage, 127 node absent (the
# suites need it, since the scripts under test do).
set -uo pipefail   # no -e: suites accumulate failures and the run decides the exit

# ============================================================================
# Helpers
# ============================================================================

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

setup_color() {
    if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ] || [ "${TERM:-dumb}" = dumb ]; then
        C_RESET= ; C_STEP= ; C_OK= ; C_ERR=
    else
        C_RESET=$'\033[0m'; C_STEP=$'\033[1;36m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'
    fi
}

# ============================================================================
# Parse arguments
# ============================================================================

only=""
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage ;;
        -*) echo "unknown option: $arg" >&2; exit 64 ;;
        *)  if [ -n "$only" ]; then echo "only one suite name is accepted" >&2; exit 64; fi
            only="$arg" ;;
    esac
done

# ============================================================================
# Resolve inputs
# ============================================================================

# REPO_ROOT is this script's parent's parent (tests/ is at the repo top). Suites read it.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export REPO_ROOT
setup_color
export C_RESET C_STEP C_OK C_ERR

if ! command -v node >/dev/null 2>&1; then
    echo "node not found; the suites exercise scripts that need node (the TypeScript pipeline)" >&2
    exit 127
fi

# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

# ============================================================================
# Discover and run suites
# ============================================================================

failed=0
ran=0
for suite in "$REPO_ROOT"/tests/*/test.sh; do
    [ -f "$suite" ] || continue
    name="$(basename "$(dirname "$suite")")"
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    ran=$((ran+1))
    # shellcheck source=/dev/null
    . "$suite" || failed=$((failed+1))
done

# ============================================================================
# Finish
# ============================================================================

if [ -n "$only" ] && [ "$ran" -eq 0 ]; then
    echo "no suite named '$only' (looked for tests/$only/test.sh)" >&2
    exit 64
fi

echo
if [ "$failed" -eq 0 ]; then
    printf '%s%d suite(s) passed%s\n' "$C_OK" "$ran" "$C_RESET"
    exit 0
fi
printf '%s%d of %d suite(s) failed%s\n' "$C_ERR" "$failed" "$ran" "$C_RESET"
exit 1
