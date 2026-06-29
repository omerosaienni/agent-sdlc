#!/usr/bin/env bash
# Suite for scripts/validate-state.sh: every fixture state.json exits with its expected
# code AND, for failures, names the rule. The states are validated against the valid
# sheet fixture (matching ids prod-api, prod-ui). Sourced and run by tests/run.sh.

suite_begin "validate-state.sh"

V="$REPO_ROOT/scripts/validate-state.sh"
S="$REPO_ROOT/tests/fixtures/states"
SHEET="$REPO_ROOT/tests/fixtures/sheets/valid.md"

# Valid state agrees with the sheet -> exit 0.
expect_exit 0 "valid state agrees with sheet" "$V" --no-color "$S/valid.json" "$SHEET"

# Rejections (exit 1): a fixable flaw, the right rule named.
expect_match 1 'rule 1' "missing sheet field -> rule 1" "$V" --no-color "$S/missing-sheet.json" "$SHEET"
expect_match 1 'rule 2' "bad mode -> rule 2"            "$V" --no-color "$S/bad-mode.json"     "$SHEET"
expect_match 1 'rule 3' "bad profile -> rule 3"         "$V" --no-color "$S/bad-profile.json"  "$SHEET"
expect_match 1 'rule 6' "bad status -> rule 6"          "$V" --no-color "$S/bad-status.json"   "$SHEET"
expect_match 1 'rule 7' "count out of range -> rule 7"  "$V" --no-color "$S/bad-count.json"    "$SHEET"
expect_match 1 'rule 8' "duplicate branch -> rule 8"    "$V" --no-color "$S/dup-branch.json"   "$SHEET"
expect_match 1 'rule 9' "completion in full -> rule 9"  "$V" --no-color "$S/bad-completion.json" "$SHEET"

# Structural defects (exit 4): state disagrees with the sheet, or is not a state file.
expect_match 4 'DEFECT.*rule 4' "id mismatch -> defect rule 4"   "$V" --no-color "$S/id-mismatch.json"  "$SHEET"
expect_match 4 'DEFECT.*rule 5' "deps mismatch -> defect rule 5" "$V" --no-color "$S/deps-mismatch.json" "$SHEET"
expect_match 4 'DEFECT.*parse'  "bad JSON -> defect parse"       "$V" --no-color "$S/bad-json.json"      "$SHEET"

# The sheet itself failing validation is exit 5 (distinct from this file's rejections).
expect_exit 5 "invalid sheet -> exit 5" "$V" --no-color "$S/valid.json" "$REPO_ROOT/tests/fixtures/sheets/cycle.md"

# Usage guards.
expect_exit 64 "no arguments -> usage error"      "$V"
expect_exit 64 "only one argument -> usage error" "$V" "$S/valid.json"
expect_exit 64 "missing file -> usage error"      "$V" "$S/nope.json" "$SHEET"

suite_summary
