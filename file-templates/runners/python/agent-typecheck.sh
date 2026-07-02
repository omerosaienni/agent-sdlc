#!/usr/bin/env bash
# Type-check the project with pyright, as a single bare command the judge runs as a
# gate before the test tiers. Terse on a clean pass; the full pyright output on
# type errors so the cause is visible without a second run.
#
# This is the AGENT type-check path, called by the build loop's judge. Humans keep
# the verbose path (uv run pyright), which drives the same pyright config, so the
# two paths cannot disagree on what is checked, only on how much they print. The
# judge reads only the EXIT CODE (contracts/agent-runner.md).
#
# Nothing else type-checks: the tiers run through the Python interpreter, which does
# not check types, so a type error passes the tests. pyright is the only thing that
# catches it, which is why it is a gate. It is configured strict in pyproject.toml.
#
# Usage:
#   agent-typecheck.sh             type-check the project (pyright config in pyproject.toml)
#   agent-typecheck.sh --verbose   full pyright output regardless of result
#
# Exit (the stack-neutral contract, contracts/agent-runner.md):
#   0 clean, no type errors
#   1 type errors (a rejection: the builder must fix them, like a failing test)
#   3 could not run (pyright not installed, no config): an environment problem,
#     never read as the builder's fault
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

# pyright is invoked through uv run so it uses the project's locked venv. If uv
# cannot run pyright at all (not installed in the venv), that is an environment
# problem, distinct from pyright running and finding type errors.
out="$(uv run pyright 2>&1)"; rc=$?

# pyright exit codes: 0 no errors, 1 errors reported. Anything else (or uv failing
# to launch pyright) means it could not run: an environment block, not a type error.
# A clean run prints a "0 errors" summary; its absence on a non-1 exit means pyright
# never produced a report, so the check could not run.
if [ "$rc" -eq 0 ]; then
    [ "$verbose" = 1 ] && printf '%s\n' "$out"
    echo "typecheck: clean"
    exit 0
fi

if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE '[0-9]+ error'; then
    echo "typecheck: TYPE ERRORS"
    printf '%s\n' "$out"
    exit 1
fi

# Any other exit, or an exit 1 with no error summary (pyright never ran a real
# check: missing tool, no config, a launch failure): could not run.
echo "typecheck: COULD NOT RUN (environment, not a type error)"
printf '%s\n' "$out"
exit 3
