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

# classify_failure <output> -> 1 (the builder's, a rejection) or 3 (the environment's,
# a block). This mirrors agent-tests.sh's rule, and for the same reason.
#
# THE RULE: go prints a "# <import/path>" banner above every compiler and vet
# diagnostic, and prints no banner at all when go ITSELF could not get as far as
# compiling. So a banner means the tool ran and judged the code (1), and no banner
# means the tool never ran (3).
#
# This replaced a whitelist of environment error strings, which was patched three
# times and was wrong in principle each time. Error text nobody controls cannot be
# enumerated, and the failures it missed defaulted to 1, handing the builder "fix
# your types" for a dead proxy or an unusable toolchain. Worse, a phrase on the list
# matched a compiler diagnostic that merely QUOTED it, so
# `var x int = "connection refused"` was reported as an environment block. The banner
# is a structural property of go's own output rather than a guess at its wording.
#
# Unlike agent-tests.sh, a "# " line here cannot be forged by the code under test:
# go build and go vet never execute it, they only compile it.
#
# The one class that needs naming is module hygiene: go reports it without a banner,
# but the builder has a command that fixes it (go mod tidy / go get), so it must stay
# a rejection. Classifying it as environment consumes no attempt and leaves the loop
# with no way to route the one thing that would fix it.
#
# Note which way each rule fails. Both the banner and the list below push towards 1,
# and 3 is what is left when neither fires. A wrong match on the list therefore
# reports a diagnostic as a diagnostic, which is where it was going anyway. That is
# the whole point of the inversion: nothing has to be on a list to be recognised as
# an environment block.
builder_fixable() {
    printf '%s' "$1" | grep -qE 'no required module provides package|missing go\.sum entry|updates to go\.mod needed|errors parsing go\.mod|malformed module path|inconsistent vendoring'
}

classify_failure() {
    builder_fixable "$1" && return 1
    printf '%s' "$1" | grep -qE '^# ' && return 1
    return 3
}

# `go build ./...` drops a binary named after the module into the working tree
# whenever the module has a main package, and the gate must leave nothing behind.
# -o sends it to a throwaway directory instead, but ONLY when there is something to
# link: with no main package `go build -o <dir>/` fails outright with "no main
# packages to build", which would report a perfectly clean library as a build error.
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
if go list -f '{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./... 2>/dev/null | grep -q .; then
    build_out="$(go build -o "$build_dir/" ./... 2>&1)"; build_rc=$?
else
    build_out="$(go build ./... 2>&1)"; build_rc=$?
fi
if [ "$build_rc" -ne 0 ]; then
    classify_failure "$build_out"; fail_code=$?
    [ "$fail_code" -eq 1 ] && report 1 "BUILD ERRORS" "$build_out"
    report 3 "COULD NOT RUN (go could not compile the module, not a type error)" "$build_out"
fi

vet_out="$(go vet ./... 2>&1)"; vet_rc=$?
if [ "$vet_rc" -ne 0 ]; then
    classify_failure "$vet_out"; fail_code=$?
    [ "$fail_code" -eq 1 ] && report 1 "VET ERRORS" "$vet_out"
    report 3 "COULD NOT RUN (go could not run vet, not a vet error)" "$vet_out"
fi

report 0 "clean" "$(printf '%s\n%s' "$build_out" "$vet_out")"
