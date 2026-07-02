#!/usr/bin/env bash
# Run a test tier (or both) through pytest and print one terse line per tier, so a
# passing run costs a few tokens of context instead of the full pytest dump. On
# failure, print the full output so the cause is visible without a second run.
#
# This is the AGENT test path, called by the build loop's judge. Humans keep the
# verbose path (uv run pytest tests/unit / tests/integration). Both drive the same
# tier directories, so they cannot disagree on what they test, only on how much
# they print. The judge reads only the EXIT CODE (contracts/agent-runner.md); the
# terse line is advisory.
#
# Usage:
#   agent-tests.sh unit                  run the unit tier, terse on pass
#   agent-tests.sh integration           run the integration tier, terse on pass
#   agent-tests.sh both                  unit then integration, stops if unit fails
#   agent-tests.sh <tier> <path>...      scope to specific test files (the scoped
#                                        negative run the hollow check uses)
#   agent-tests.sh <tier> [path]... --verbose   full pytest output regardless
#
# Exit (the stack-neutral contract, contracts/agent-runner.md):
#   0 all selected tiers passed
#   1 a tier ran and a test failed
#   2 a tier selected zero tests (hollow suite)
#   3 a tier could not run (environment: import/collection error, pytest absent)
set -uo pipefail

# Each tier maps to its test directory. pytest is invoked through uv run so it uses
# the project's locked venv (pytest, the package under test), the same environment
# the human path uses.
unit_dir="tests/unit"
integration_dir="tests/integration"

verbose=0
tier=""
scope=()
for a in "$@"; do
    case "$a" in
        unit|integration|both) tier="$a" ;;
        -v|--verbose)          verbose=1 ;;
        -h|--help) awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        -*) echo "unknown option: $a" >&2; exit 64 ;;
        *) scope+=("$a") ;;
    esac
done
[ -z "$tier" ] && { echo "usage: agent-tests.sh unit|integration|both [path]... [--verbose]" >&2; exit 64; }
[ "$tier" = both ] && [ "${#scope[@]}" -gt 0 ] && { echo "scope paths cannot be combined with 'both'; run one tier" >&2; exit 64; }

# run_one <label> <dir>: run one tier through pytest, classify, emit terse or full.
# When scope paths are given they REPLACE the tier dir (the scoped negative run
# targets one test file), matching how the TypeScript runner intersects scope.
run_one() {
    local label="$1" dir="$2" out rc target
    if [ "${#scope[@]}" -gt 0 ]; then target=("${scope[@]}"); else target=("$dir"); fi
    # PYTHONDONTWRITEBYTECODE: do not write .pyc during a run. The hollow check
    # restores a source file by an mtime-preserving copy; a .pyc cached from the
    # faulted source could then be re-imported as stale bytecode after restore, so
    # the restore-verify would wrongly stay red (HALT). Writing no bytecode removes
    # that whole class of stale-cache reads. This sets the env for the pytest child
    # we spawn; it is not caller-chosen behaviour read from the environment.
    out="$(PYTHONDONTWRITEBYTECODE=1 uv run pytest "${target[@]}" 2>&1)"; rc=$?

    if [ "$verbose" = 1 ]; then
        printf '%s\n' "$out"
        return "$rc"
    fi

    # Map pytest's exit codes onto the stack-neutral contract:
    #   pytest 0 -> 0  all passed
    #   pytest 1 -> 1  tests ran and failed, UNLESS the run never collected (a
    #                  collection/import error also surfaces as 1 in some configs):
    #                  detect "error" in the summary and treat as could-not-run (3)
    #   pytest 5 -> 2  no tests collected (the hollow-suite signal)
    #   pytest 2/3/4 -> 3  interrupted / internal / usage: could not run
    case "$rc" in
        0)
            # Pull pytest's summary line (e.g. "5 passed in 0.1s") for the terse line.
            local summary
            summary="$(printf '%s' "$out" | grep -E '[0-9]+ (passed|skipped)' | tail -1 | sed -E 's/^=+ *//; s/ *=+$//')"
            echo "$label: ${summary:-passed}"
            return 0
            ;;
        5)
            echo "$label: 0 tests selected (hollow suite)"
            return 2
            ;;
        1)
            # A collection/import error can also exit 1 with no test actually run.
            # pytest reports it as "errors" in the summary and an ERROR section; a
            # genuine test failure reports "failed". Distinguish so an environment
            # problem is not bounced to the builder as a behaviour failure.
            if printf '%s' "$out" | grep -qE '[0-9]+ error' && ! printf '%s' "$out" | grep -qE '[0-9]+ failed'; then
                echo "$label: COULD NOT RUN (collection/import error, not a test failure)"
                printf '%s\n' "$out"
                return 3
            fi
            echo "$label: FAILED"
            printf '%s\n' "$out"
            return 1
            ;;
        *)
            # 2 interrupted, 3 internal error, 4 usage, or pytest absent: the tier
            # could not run. An environment problem, never the builder's fault.
            echo "$label: COULD NOT RUN (environment, not a test failure)"
            printf '%s\n' "$out"
            return 3
            ;;
    esac
}

case "$tier" in
    unit)        run_one unit "$unit_dir" ;;
    integration) run_one integration "$integration_dir" ;;
    both)
        run_one unit "$unit_dir" || exit $?
        run_one integration "$integration_dir" ;;
esac
