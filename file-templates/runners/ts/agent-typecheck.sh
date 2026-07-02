#!/usr/bin/env bash
# Type-check the project with tsc --noEmit, as a single bare command the judge
# runs as a gate before the test tiers. Terse on a clean pass; the full tsc
# output on type errors so the cause is visible without a second run.
#
# This is the AGENT type-check path, called by the build loop's judge. Humans
# keep the verbose path (npm run typecheck, make typecheck), which drives the
# same tsconfig, so the two paths cannot disagree on what is checked, only on
# how much they print.
#
# Nothing here type-checks unless this runs: the test tiers go through esbuild
# and tsx, which strip types, so a strict-mode type error passes the tests. tsc
# --noEmit is the only thing that catches it, which is why it is a gate.
#
# Usage:
#   agent-typecheck.sh                 type-check the whole project (tsconfig.json)
#   agent-typecheck.sh -p <tsconfig>   type-check against a specific tsconfig
#
# In a monorepo, point -p at a tsconfig that covers every workspace (project
# references), or have the caller run this once per workspace; a single default
# tsconfig.json may leave sibling workspaces unchecked.
#   agent-typecheck.sh --verbose       full tsc output regardless of result
#
# Exit: 0 clean, no type errors
#       1 type errors (a rejection: the builder must fix them, like a failing test)
#       3 could not run (no tsconfig, tsc not installed, config error): an
#         environment problem, never read as the builder's fault
set -uo pipefail

project="tsconfig.json"
verbose=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p|--project) project="${2:-}"; shift 2 ;;
        -v|--verbose) verbose=1; shift ;;
        -h|--help) awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 64 ;;
        *) echo "unexpected argument: $1" >&2; exit 64 ;;
    esac
done

# A missing tsconfig means the check cannot run at all: environment, not a type
# error. Distinguishing this from real type errors is the whole point of exit 3.
[ -f "$project" ] || { echo "typecheck: COULD NOT RUN (no $project)"; exit 3; }

# tsc is invoked through npx directly, NOT via npm run typecheck, because this
# script IS the agent equivalent of that script; going back through npm would
# recurse on projects that point typecheck at a wrapper.
out="$(npx tsc --noEmit -p "$project" 2>&1)"; rc=$?

# tsc emits ANSI colour codes even when captured; strip them before any parsing
# or the error-code greps below silently fail.
out="$(printf '%s' "$out" | sed -E 's/\x1b\[[0-9;]*m//g')"

if [ "$rc" -eq 0 ]; then
    [ "$verbose" = 1 ] && printf '%s\n' "$out"
    echo "typecheck: clean"
    exit 0
fi

# Non-zero from tsc is one of two things the loop must treat differently:
#   - genuine type errors (the builder's problem, exit 1)
#   - tsc could not run at all, or a tsconfig/CLI problem (environment, exit 3)
# Config and CLI failures carry the TS5xxx/TS6xxx/TS18003 family; a tsc that
# never started (npx could not resolve it) prints no 'error TS' line at all.
if ! printf '%s' "$out" | grep -qE 'error TS[0-9]+'; then
    echo "typecheck: COULD NOT RUN (environment, not a type error)"
    printf '%s\n' "$out"
    exit 3
fi
if printf '%s' "$out" | grep -qE 'error TS(5023|5057|5058|6053|18003)'; then
    echo "typecheck: COULD NOT RUN (tsconfig problem)"
    printf '%s\n' "$out"
    exit 3
fi

echo "typecheck: TYPE ERRORS"
printf '%s\n' "$out"
exit 1
