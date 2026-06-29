#!/usr/bin/env bash
# Suite for scripts/validate-sheet.sh: every fixture sheet exits with its expected
# code AND, for failures, names the rule it should. Sourced and run by tests/run.sh,
# which sets REPO_ROOT, the colour vars, and sources tests/lib.sh first.

suite_begin "validate-sheet.sh"

V="$REPO_ROOT/scripts/validate-sheet.sh"
F="$REPO_ROOT/tests/fixtures/sheets"

# Valid sheets exit 0. The smoke-test sheet is a real example, not a fixture, so it
# lives under examples/ and is checked here too: a valid sheet the loop actually uses.
expect_exit 0 "smoke-test sheet (real example)" "$V" --no-color "$REPO_ROOT/examples/smoke-test-sheet.md"
expect_exit 0 "valid fixture"                   "$V" --no-color "$F/valid.md"

# Rejections (exit 1): a fixable flaw, the right rule named.
expect_match 1 'rule 2'   "duplicate id -> rule 2"        "$V" --no-color "$F/dup-id.md"
expect_match 1 'rule 1'   "missing field -> rule 1"       "$V" --no-color "$F/missing-field.md"
expect_match 1 'rule 8'   "bad heading -> rule 8"         "$V" --no-color "$F/bad-heading.md"
expect_match 1 'rule 3'   "dangling depends_on -> rule 3" "$V" --no-color "$F/missing-dep.md"
expect_match 1 'rule 5'   "forward reference -> rule 5"   "$V" --no-color "$F/forward-reference.md"
expect_match 1 'goal'     "missing goal -> goal"          "$V" --no-color "$F/missing-goal.md"
expect_match 1 'rule 1'   "empty test_notes list -> rule 1" "$V" --no-color "$F/empty-test-notes.md"

# Structural defects (exit 4): not a DAG / not a sheet, regenerate upstream.
expect_match 4 'DEFECT.*rule 4'   "cycle -> defect rule 4"         "$V" --no-color "$F/cycle.md"
expect_match 4 'DEFECT.*structure' "no increments -> defect"       "$V" --no-color "$F/no-increments.md"

# Usage guards.
expect_exit 64 "no argument -> usage error"  "$V"
expect_exit 64 "unknown flag -> usage error" "$V" --bogus
expect_exit 64 "missing file -> usage error" "$V" "$F/does-not-exist.md"

suite_summary
