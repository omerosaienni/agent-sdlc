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

usage() { awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0; }

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

# Suites stream their output in discovery order; the per-kind grouping is the
# summary at the end (reordering or buffering live output would cost more than it
# is worth). Each suite records its kind in _t_kind via suite_begin; we read it
# right after sourcing and accumulate a "name:kind:result" line per suite, plus a
# bad-kind counter so a suite that fails to declare a valid kind fails the run.
failed=0
ran=0
badkind=0
results=""
for suite in "$REPO_ROOT"/tests/*/test.sh; do
    [ -f "$suite" ] || continue
    name="$(basename "$(dirname "$suite")")"
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    ran=$((ran+1))
    _t_kind=""
    # Each suite gets its own TMPDIR, removed when it finishes.
    #
    # Suites are SOURCED into this one shell, so a suite's `trap ... EXIT` replaces
    # the previous suite's and only the last one ever fires: every earlier suite
    # leaked its scratch directory, which for the ones that npm-install or scaffold
    # Go projects is hundreds of megabytes per run. Isolating TMPDIR fixes it for
    # every suite at once, including ones that clean up correctly, and needs no
    # cooperation from the suite. TMPDIR is the standard way to say where temporary
    # files go, which is why it is an environment variable and not a flag.
    suite_tmp="$(mktemp -d)"
    # shellcheck source=/dev/null
    if TMPDIR="$suite_tmp" . "$suite"; then res=pass; else res=fail; failed=$((failed+1)); fi
    rm -rf "$suite_tmp"
    case " $_T_KINDS " in
        *" $_t_kind "*) : ;;
        *) badkind=$((badkind+1)); _t_kind="UNDECLARED" ;;
    esac
    results="${results}${name}:${_t_kind}:${res}"$'\n'
done

# ============================================================================
# Finish
# ============================================================================

if [ -n "$only" ] && [ "$ran" -eq 0 ]; then
    echo "no suite named '$only' (looked for tests/$only/test.sh)" >&2
    exit 64
fi

# Per-kind grouping and tally. Iterate the known kinds (plus UNDECLARED for any
# suite that did not categorise itself), printing each kind's suites and a tally.
echo
printf '%s== suites by kind ==%s\n' "${C_STEP:-}" "${C_RESET:-}"
for kind in $_T_KINDS UNDECLARED; do
    block="$(printf '%s' "$results" | awk -F: -v k="$kind" '$2==k')"
    [ -z "$block" ] && continue
    kpass=$(printf '%s\n' "$block" | grep -c ':pass$')
    kfail=$(printf '%s\n' "$block" | grep -c ':fail$')
    printf '%s [%d passed%s]\n' "$kind" "$kpass" "$([ "$kfail" -gt 0 ] && printf ', %d failed' "$kfail")"
    printf '%s\n' "$block" | awk -F: '{printf "  - %s (%s)\n", $1, $3}'
done

echo
if [ "$failed" -eq 0 ] && [ "$badkind" -eq 0 ]; then
    printf '%s%d suite(s) passed%s\n' "$C_OK" "$ran" "$C_RESET"
    exit 0
fi
[ "$badkind" -gt 0 ] && printf '%s%d suite(s) did not declare a valid kind%s\n' "$C_ERR" "$badkind" "$C_RESET"
[ "$failed" -gt 0 ] && printf '%s%d of %d suite(s) failed%s\n' "$C_ERR" "$failed" "$ran" "$C_RESET"
exit 1
