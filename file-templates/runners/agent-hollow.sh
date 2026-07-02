#!/usr/bin/env bash
# Run the judge's hollow-test negative check for ONE increment, as a single
# committed command. The judge supplies the fault (an exact literal string in a
# source file to flip, and what to flip it to); the script owns everything else:
# backup, apply, scoped run, verdict, restore and a green re-verify. The restore
# runs from an EXIT trap, so the file is put back however the script exits. The
# backup is a plain filesystem copy under .building/ (gitignored), which works on
# the UNTRACKED files a new increment adds, where git checkout/restore/stash
# silently no-op. The index is never touched.
#
# Usage:
#   agent-hollow.sh <tier> <src-file> <test-file> <old-string> <new-string>
#
# The fault must be BEHAVIOURAL and still compile (flip a value or comparison).
# <old-string> must occur exactly once in <src-file>, and differ from <new-string>.
#
# The verdict reads ONLY the test runner's exit code, never its output text, so
# this one script serves every stack (contracts/agent-runner.md): codes are the
# contract, words are advisory.
#
# Verdict (what the negative run proves about <test-file>):
#   exit 0  ASSERTS   a test failed on the fault: the test is real, not hollow
#   exit 1  HOLLOW    the tier stayed green with the code broken: hollow test, FAIL
#   exit 2  BAD FAULT the fault was not behavioural (no tests selected, or it broke
#                     the build/import so the tier could not run): re-pick and retry
#   exit 3  HALT      restore did not return the tier to green: do not proceed
#   exit 64 usage / <old-string> not found exactly once / old == new
set -euo pipefail

backup_root=".building/hollow"

die(){ echo "$1" >&2; exit "${2:-1}"; }
usage(){ awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; }

[ "$#" -eq 5 ] || { usage >&2; exit 64; }
tier="$1"; src="$2"; testfile="$3"; old="$4"; new="$5"

[ -f "$src" ] || die "no such source file: $src" 64
[ -f "$testfile" ] || die "no such test file: $testfile" 64
[ "$old" != "$new" ] || die "old and new strings are identical; not a fault" 64
occ=$(grep -Fo -- "$old" "$src" | wc -l | tr -d ' ')
[ "$occ" = 1 ] || die "fault target must occur exactly once in $src (found $occ)" 64

bak="$backup_root/$src"
mkdir -p "$(dirname "$bak")"
cp "$src" "$bak"
# Restore from the backup no matter how we exit, then drop the backup.
restore(){ [ -f "$bak" ] && mv "$bak" "$src"; }
trap restore EXIT

# Apply the fault: literal first-occurrence replace (no regex), via bash expansion.
content="$(cat "$src")"
printf '%s\n' "${content/"$old"/"$new"}" > "$src"

# Scoped negative run through the project's runner (single source of truth for
# HOW tests run). The verdict reads only the runner's EXIT CODE, never its output
# text, so this one script serves every stack: the codes are the stack-neutral
# contract (contracts/agent-runner.md), the words are advisory. Capture output only
# to print on the unexpected path. Capture without letting a non-zero runner exit
# trip set -e (a failing test is the expected outcome here, not a script error).
if out="$(.building/scripts/agent-tests.sh "$tier" "$testfile" 2>&1)"; then rc=0; else rc=$?; fi

# Map agent-tests.sh's exit code straight to the verdict (agent-runner.md):
#   0 the tier stayed green with the code broken -> the test never asserted: HOLLOW
#   1 a test failed on the fault -> the test is real: ASSERTS
#   2 zero tests selected -> the fault was not behavioural: re-pick (BAD FAULT)
#   3 the tier could not run -> our fault broke the build/import, not behaviour, so
#     during THIS negative run that is a non-behavioural fault to re-pick, NOT a halt
#     (a halt is only a failed restore, below). Same on every stack.
case "$rc" in
    0) verdict="HOLLOW"; code=1 ;;
    1) verdict="ASSERTS"; code=0 ;;
    2) verdict="BAD FAULT (no tests selected; fault was not behavioural)"; code=2 ;;
    3) verdict="BAD FAULT (fault stopped the tier running; not behavioural)"; code=2 ;;
    *) verdict="BAD FAULT (unexpected runner exit $rc); $out"; code=2 ;;
esac

# Explicit restore now, then verify green before reporting (the trap is a backstop).
restore; trap - EXIT
if green="$(.building/scripts/agent-tests.sh "$tier" "$testfile" 2>&1)"; then grc=0; else grc=$?; fi
[ "$grc" -eq 0 ] || { echo "HALT: $src did not return to green after restore"; printf '%s\n' "$green"; exit 3; }

echo "hollow-check: $verdict"
exit "$code"
