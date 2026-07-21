#!/usr/bin/env bash
# Type-check the project with go vet plus go build, as a single bare command the
# judge runs as a gate before the test tiers. Terse on a clean pass; the full tool
# output on errors so the cause is visible without a second run.
#
# This is the AGENT type-check path, called by the build loop's judge. Humans keep
# the verbose path (go vet ./... && go build ./...), which drives the same two
# commands, so the two paths cannot disagree on what is checked, only on how much
# they print. The judge reads only the EXIT CODE (contracts/agent-runner.md).
#
# Go has no separate type-checker: the compiler IS the type system, so `go build`
# is the type gate and `go vet` adds the correctness checks a compile does not make
# (printf arguments, unreachable code, struct tags, lost cancel functions). The gate
# is kept even though `go test` also compiles, because it fails fast, it covers
# packages that have no test files at all, and the judge's discipline is
# type-check-first.
#
# Order matters: build first, then vet. A package that does not compile makes vet's
# output noise about the same root cause, so the compiler's diagnostic is the one
# worth showing.
#
# Usage:
#   agent-typecheck.sh             type-check the module (go build ./... + go vet ./...)
#   agent-typecheck.sh --verbose   full output regardless of result
#
# Exit (the stack-neutral contract, contracts/agent-runner.md):
#   0 clean, no build or vet errors
#   1 build or vet errors (a rejection: the builder must fix them, like a failing test)
#   3 could not run (the go toolchain absent, no go.mod, a module resolution
#     failure): an environment problem, never read as the builder's fault
set -uo pipefail

verbose=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        -v|--verbose) verbose=1; shift ;;
        -h|--help) awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 64 ;;
        *) echo "unexpected argument: $1" >&2; exit 64 ;;
    esac
done

# Environment first: no toolchain or no module means the check could not run (3),
# which is distinct from it running and finding errors (1).
command -v go >/dev/null 2>&1 || {
    echo "typecheck: COULD NOT RUN (go toolchain not on PATH)"; exit 3; }
[ -f go.mod ] || {
    echo "typecheck: COULD NOT RUN (no go.mod; run from the module root)"; exit 3; }

# report <exit> <message> <output>: print terse, or the full output on anything but
# a clean pass (and always under --verbose).
report() {
    local code="$1" msg="$2" out="$3"
    echo "typecheck: $msg"
    { [ "$code" -ne 0 ] || [ "$verbose" = 1 ]; } && [ -n "$out" ] && printf '%s\n' "$out"
    exit "$code"
}

# A module whose dependencies cannot be resolved (no network on a cold module cache,
# a bad require) fails to build for an ENVIRONMENT reason, not a type reason. go
# names that class in its output, so it is separated out rather than reported as a
# type error the builder is asked to fix.
#
# A COMPILER DIAGNOSTIC OVERRIDES ALL OF IT. "go: downloading ..." is printed on any
# cold-cache build, including one that then reports real type errors, so treating it
# as an environment signal made the first judge run after a scaffold report an
# environment block instead of the errors the builder needs to fix. If go got far
# enough to name a file, a line and a column, it ran.
env_failure() {
    if printf '%s' "$1" | grep -qE '^[^[:space:]]+\.go:[0-9]+:[0-9]+:'; then
        return 1
    fi
    printf '%s' "$1" | grep -qE 'no required module provides|missing go\.sum entry|module lookup disabled|dial tcp|connection refused|i/o timeout|go: updates to go\.mod needed'
}

# -o sends any linked executable to a throwaway directory. Without it, `go build`
# drops a binary named after the module into the working tree whenever the module
# has a main package at its root, so running the gate would leave a file behind.
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
build_out="$(go build -o "$build_dir/" ./... 2>&1)"; build_rc=$?
if [ "$build_rc" -ne 0 ]; then
    env_failure "$build_out" \
        && report 3 "COULD NOT RUN (module resolution failed, not a type error)" "$build_out"
    report 1 "BUILD ERRORS" "$build_out"
fi

vet_out="$(go vet ./... 2>&1)"; vet_rc=$?
if [ "$vet_rc" -ne 0 ]; then
    env_failure "$vet_out" \
        && report 3 "COULD NOT RUN (module resolution failed, not a vet error)" "$vet_out"
    report 1 "VET ERRORS" "$vet_out"
fi

report 0 "clean" "$(printf '%s\n%s' "$build_out" "$vet_out")"
