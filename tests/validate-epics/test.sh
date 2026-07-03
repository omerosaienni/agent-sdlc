#!/usr/bin/env bash
# Suite for scripts/validate-epics.sh: every fixture epic.json exits with its expected
# code AND, for failures, names the rule. Sourced and run by tests/run.sh.

suite_begin "validate-epics.sh" unit

V="$REPO_ROOT/scripts/validate-epics.sh"
E="$REPO_ROOT/tests/fixtures/epics"

# Valid manifests -> exit 0.
expect_exit 0 "valid multi-feature manifest" "$V" --no-color "$E/valid.json"
expect_exit 0 "single-feature epic"          "$V" --no-color "$E/single-feature.json"

# Rejections (exit 1): a fixable flaw, the right rule named.
expect_match 1 'rule 1' "empty epic -> rule 1"            "$V" --no-color "$E/missing-epic.json"
expect_match 1 'rule 2' "feature missing sheet -> rule 2" "$V" --no-color "$E/bad-feature.json"
expect_match 1 'rule 3' "duplicate name -> rule 3"        "$V" --no-color "$E/dup-name.json"
expect_match 1 'rule 4' "dangling depends_on -> rule 4"   "$V" --no-color "$E/missing-dep.json"
expect_match 1 'rule 6' "forward reference -> rule 6"     "$V" --no-color "$E/forward-reference.json"
expect_match 1 'rule 7' "sheet path mismatch -> rule 7"   "$V" --no-color "$E/bad-sheet-path.json"

# Structural defects (exit 4): a non-DAG or non-manifest, regenerate upstream.
expect_match 4 'DEFECT.*rule 5' "cycle -> defect rule 5"       "$V" --no-color "$E/cycle.json"
expect_match 4 'DEFECT.*rule 2' "no features -> defect rule 2" "$V" --no-color "$E/no-features.json"
expect_match 4 'DEFECT.*parse'  "bad JSON -> defect parse"     "$V" --no-color "$E/bad-json.json"

# Usage guards.
expect_exit 64 "no arguments -> usage error"     "$V"
expect_exit 64 "two manifests -> usage error"    "$V" "$E/valid.json" "$E/single-feature.json"
expect_exit 64 "missing file -> usage error"     "$V" "$E/nope.json"
expect_exit 64 "unknown option -> usage error"   "$V" --bogus "$E/valid.json"

suite_summary
