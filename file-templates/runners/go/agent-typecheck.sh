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
# ORDER MATTERS HERE, and both orders have been wrong at some point.
#
# A network marker is checked FIRST. Go attributes a module-fetch failure to the
# line of the import that triggered it, so an unreachable proxy still prints a
# "file.go:L:C:" diagnostic. Checking for a diagnostic first therefore classified
# every genuine network failure as a type error, and handed the builder "fix your
# types" for a dead proxy.
#
# A compiler diagnostic is checked SECOND, and only then does it override. That is
# what stops "go: downloading ...", printed on any cold-cache build including one
# that goes on to report real type errors, from swallowing the errors the builder
# actually needs to fix.
#
# Only a genuine inability to REACH the proxy is an environment block. A stale
# go.mod or go.sum is the builder's to fix with go mod tidy, so it stays a
# rejection: classifying it as environment consumes no attempt and leaves the loop
# with no way to route the one thing that would fix it.
env_failure() {
    if printf '%s' "$1" | grep -qE 'module lookup disabled|dial tcp|connection refused|i/o timeout|proxyconnect|TLS handshake timeout|GOPROXY=off'; then
        return 0
    fi
    return 1
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
