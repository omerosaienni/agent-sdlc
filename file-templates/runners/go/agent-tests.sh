#!/usr/bin/env bash
# Run a test tier (or both) through go test and print one terse line per tier, so a
# passing run costs a few tokens of context instead of the full go test dump. On
# failure, print the full output so the cause is visible without a second run.
#
# This is the AGENT test path, called by the build loop's judge. Humans keep the
# verbose path (go test ./... / go test -tags=integration ./...). Both drive the
# same tier split, so they cannot disagree on what they test, only on how much they
# print. The judge reads only the EXIT CODE (contracts/agent-runner.md); the terse
# line is advisory.
#
# Tiers split by BUILD TAG, not by directory: the unit tier is every untagged test
# in the module, the integration tier adds the files behind //go:build integration.
# Go's convention is co-located _test.go files, so a directory split would fight the
# language; the tag split is the idiomatic equivalent of the pytest tier directories.
#
# Usage:
#   agent-tests.sh unit                  run the unit tier, terse on pass
#   agent-tests.sh integration           run the integration tier, terse on pass
#   agent-tests.sh both                  unit then integration, stops if unit fails
#   agent-tests.sh <tier> <path>...      scope to specific packages (the scoped
#                                        negative run the hollow check uses)
#   agent-tests.sh <tier> [path]... --verbose   full go test output regardless
#
# Scope granularity is the PACKAGE DIRECTORY, because that is Go's unit of
# compilation: `go test ./some/file_test.go` compiles that one file without the rest
# of its package and fails to build. The shared agent-hollow.sh passes a test FILE
# (its usage contract requires one), so a file argument is mapped to its directory
# here. That is the reconciliation contracts/agent-runner.md's scoped negative run
# needs on this stack; the two agree on package-path granularity.
#
# Exit (the stack-neutral contract, contracts/agent-runner.md):
#   0 all selected tiers passed
#   1 a tier ran and a test failed
#   2 a tier selected zero tests (hollow suite)
#   3 a tier could not run (environment: go absent, no go.mod, a build error in a
#     test package)
set -uo pipefail

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

# Environment first: without the toolchain or a module there is no tier to run, and
# that is exit 3 (an environment block), never a test failure.
command -v go >/dev/null 2>&1 || { echo "go: COULD NOT RUN (go toolchain not on PATH)"; exit 3; }
[ -f go.mod ] || { echo "go: COULD NOT RUN (no go.mod; run from the module root)"; exit 3; }

# as_packages: map each scope argument onto a Go package pattern. A file becomes its
# directory (package granularity, see the header); a directory is used as is. Every
# result is ./-prefixed so go reads it as a filesystem path, not an import path.
as_packages() {
    local p d
    for p in "$@"; do
        if [ -f "$p" ]; then d="$(dirname "$p")"; else d="${p%/}"; fi
        case "$d" in
            ./*|/*) printf '%s\n' "$d" ;;
            .)      printf './...\n' ;;
            *)      printf './%s\n' "$d" ;;
        esac
    done
}

# run_one <label> <tag-args...>: run one tier through go test, classify, emit terse
# or full. When scope paths are given they REPLACE the whole-module pattern, matching
# how the other stacks' runners narrow the scoped negative run.
run_one() {
    local label="$1"; shift
    local tags=("$@") out rc targets=()
    if [ "${#scope[@]}" -gt 0 ]; then
        mapfile -t targets < <(as_packages "${scope[@]}")
    else
        targets=("./...")
    fi
    out="$(go test "${tags[@]}" "${targets[@]}" 2>&1)"; rc=$?

    if [ "$verbose" = 1 ]; then
        printf '%s\n' "$out"
        return "$rc"
    fi

    # go test conflates outcomes into two exit codes, so the classification is by
    # OUTPUT, not by code (this is the whole reason this runner is not a one-liner):
    #   exit 0 with only "[no test files]" lines  -> nothing ran   -> 2
    #   exit 0 with at least one "ok " line       -> tests passed  -> 0
    #   exit 1 with a build/setup failure         -> could not run -> 3
    #   exit 1 with "--- FAIL:"                   -> real failure  -> 1
    #   anything else non-zero                    -> could not run -> 3
    if [ "$rc" -eq 0 ]; then
        # "testing: warning: no tests to run" is go's other zero-selection signal
        # (every test filtered out); treat it the same as no test files.
        if printf '%s' "$out" | grep -qE '^ok  ' \
           && ! printf '%s' "$out" | grep -q 'no tests to run'; then
            local summary
            summary="$(printf '%s' "$out" | grep -cE '^ok  ')"
            echo "$label: $summary package(s) passed"
            return 0
        fi
        echo "$label: 0 tests selected (hollow suite)"
        return 2
    fi

    # A build error in a test package is an environment problem, not a behaviour
    # failure, and must never be bounced to the builder as one. go reports it as
    # "[build failed]" / "[setup failed]" on the FAIL line, and prints the compiler
    # diagnostics under a "# package" banner. Checked BEFORE the failure case: if
    # anything failed to compile, the tier did not fully run.
    if printf '%s' "$out" | grep -qE '\[(build|setup) failed\]|^# '; then
        echo "$label: COULD NOT RUN (build error in a test package, not a test failure)"
        printf '%s\n' "$out"
        return 3
    fi

    if printf '%s' "$out" | grep -qE '^\s*--- FAIL:|^FAIL'; then
        echo "$label: FAILED"
        printf '%s\n' "$out"
        return 1
    fi

    # Non-zero with neither a build failure nor a reported test failure: go itself
    # could not run (a bad pattern, a module error, a toolchain problem).
    echo "$label: COULD NOT RUN (environment, not a test failure)"
    printf '%s\n' "$out"
    return 3
}

case "$tier" in
    unit)        run_one unit ;;
    integration) run_one integration -tags=integration ;;
    both)
        run_one unit || exit $?
        run_one integration -tags=integration ;;
esac
