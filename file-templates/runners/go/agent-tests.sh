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
            # The ROOT package, not the whole module. Expanding it to ./... would
            # silently unscope the hollow check's negative run for a root-level test
            # file, so an unrelated failing package elsewhere would be read as the
            # planted fault being caught: a false ASSERTS on the one gate whose job
            # is catching hollow tests.
            .)      printf '.\n' ;;
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
    classify "$label" "$out" "$rc"
}

# classify <label> <output> <rc>: map go test's conflated result onto the four
# contract codes. Precedence matters and is deliberate:
#   1. a reported test failure wins, even alongside a build error elsewhere, because
#      "could not run" means NO suite executed (contracts/agent-runner.md)
#   2. then a build or setup failure, which is an environment problem and must never
#      reach the builder as a behaviour failure
#   3. then, on a clean exit, whether any package actually ran a test
#
# The build-failure probe matches ONLY go's own "[build failed]"/"[setup failed]"
# markers. It deliberately does NOT match a leading "# ", which go prints as the
# banner above compiler diagnostics: the code under test can print that too (any
# program emitting a shell, SQL or markdown comment does), and matching it turned
# genuine failures into environment blocks.
classify() {
    local label="$1" out="$2" rc="$3"

    if printf '%s' "$out" | grep -qE '^[[:space:]]*--- FAIL:'; then
        echo "$label: FAILED"
        printf '%s\n' "$out"
        return 1
    fi

    if printf '%s' "$out" | grep -qE '\[(build|setup) failed\]'; then
        echo "$label: COULD NOT RUN (build error in a test package, not a test failure)"
        printf '%s\n' "$out"
        return 3
    fi

    if [ "$rc" -eq 0 ]; then
        # Counted PER PACKAGE. A module-wide grep would let one benchmark-only
        # package ("ok pkg [no tests to run]") mark a fully green tier hollow.
        local ran
        ran="$(printf '%s' "$out" | grep -E '^ok  ' | grep -vc 'no tests to run')"
        if [ "$ran" -gt 0 ]; then
            echo "$label: $ran package(s) passed"
            # --verbose adds detail; it never changes the verdict, so the contract
            # code is the same whether or not it was asked for.
            [ "$verbose" = 1 ] && printf '%s\n' "$out"
            return 0
        fi
        echo "$label: 0 tests selected (hollow suite)"
        return 2
    fi

    # Non-zero with neither a build failure nor a reported test failure: go itself
    # could not run (a bad pattern, a module error, a toolchain problem).
    echo "$label: COULD NOT RUN (environment, not a test failure)"
    printf '%s\n' "$out"
    return 3
}

# integration_packages: the packages holding at least one integration-tagged test
# file. The tag ADDS files rather than selecting only them, so `go test -tags=...`
# over the whole module is a superset of the unit tier: it can never report a zero
# selection, and it re-runs every unit test. Scoping to the tagged packages is what
# makes code 2 reachable on this tier, as contracts/agent-runner.md requires.
integration_packages() {
    grep -rl --include='*_test.go' --exclude-dir=.building --exclude-dir=vendor \
        --exclude-dir=node_modules '//go:build integration' . 2>/dev/null \
        | xargs -r -n1 dirname | sort -u
}

# run_integration: the tagged tier, scoped to the packages that actually carry
# tagged files unless the caller scoped it themselves.
run_integration() {
    local dirs=()
    if [ "${#scope[@]}" -eq 0 ]; then
        mapfile -t dirs < <(integration_packages)
        if [ "${#dirs[@]}" -eq 0 ]; then
            echo "integration: 0 tests selected (hollow suite)"
            return 2
        fi
        scope=("${dirs[@]}")
    fi
    run_one integration -tags=integration
}

case "$tier" in
    unit)        run_one unit ;;
    integration) run_integration ;;
    both)
        run_one unit || exit $?
        run_integration ;;
esac
