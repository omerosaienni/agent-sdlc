#!/usr/bin/env bash
# Suite for scripts/board-state.sh: the computed board must match values worked out by
# hand on known graphs. The diamond fixture (root -> mid-a/mid-b -> sink, plus an
# off-path tail depending only on root) pins the hard cases: the longest-chain star with
# a tie, the off-path exclusion, the four-section partition, and the per-mode cut rule.
# Sourced and run by tests/run.sh.

suite_begin "board-state.sh" unit

V="$REPO_ROOT/scripts/board-state.sh"
B="$REPO_ROOT/tests/fixtures/boards"
ids='const ids=a=>a.map(x=>x.id);'

# valid pair (prod-api merged, prod-ui ready) -> simple partition + 2-node critical path.
expect_json "valid: prod-ui ready, both starred" \
  "$ids assert.deepStrictEqual(ids(b.sections.ready),['prod-ui']); assert.deepStrictEqual(b.starred,['prod-api','prod-ui']); assert.strictEqual(b.critical_path_length,2);" \
  "$V" "$REPO_ROOT/tests/fixtures/states/valid.json" "$REPO_ROOT/tests/fixtures/sheets/valid.md"

# diamond, sequential, mixed states: every section populated, star ties, off-path excluded.
DM_STATE="$B/diamond-mixed.json"; DM_SHEET="$B/diamond.md"
expect_json "diamond: ready = [mid-b]" \
  "$ids assert.deepStrictEqual(ids(b.sections.ready),['mid-b']);" "$V" "$DM_STATE" "$DM_SHEET"
expect_json "diamond: awaiting = [mid-a] unblocking sink" \
  "$ids assert.deepStrictEqual(ids(b.sections.awaiting_merge),['mid-a']); assert.deepStrictEqual(b.sections.awaiting_merge[0].unblocks,['sink']);" \
  "$V" "$DM_STATE" "$DM_SHEET"
expect_json "diamond: blocked = [sink] waiting on mid-a,mid-b" \
  "$ids assert.deepStrictEqual(ids(b.sections.blocked),['sink']); assert.deepStrictEqual(b.sections.blocked[0].waiting_on.map(w=>w.id),['mid-a','mid-b']);" \
  "$V" "$DM_STATE" "$DM_SHEET"
expect_json "diamond: stalled = [tail] (building)" \
  "$ids assert.deepStrictEqual(ids(b.sections.possibly_stalled),['tail']); assert.strictEqual(b.sections.possibly_stalled[0].state,'building');" \
  "$V" "$DM_STATE" "$DM_SHEET"
expect_json "diamond: star = root,mid-a,mid-b,sink (tail excluded), L=3" \
  "assert.deepStrictEqual(b.starred,['mid-a','mid-b','root','sink']); assert.strictEqual(b.critical_path_length,3); assert.ok(!b.starred.includes('tail'));" \
  "$V" "$DM_STATE" "$DM_SHEET"
expect_json "diamond: total 5 / merged 1" \
  "assert.strictEqual(b.total,5); assert.strictEqual(b.merged,1);" "$V" "$DM_STATE" "$DM_SHEET"

# Cut rule: sequential suppresses a cut while non-pending work is in flight; parallel does not.
expect_json "sequential: cut_allowed false (work in flight)" \
  "assert.strictEqual(b.mode,'sequential-attended'); assert.strictEqual(b.cut_allowed,false);" "$V" "$DM_STATE" "$DM_SHEET"
expect_json "parallel: cut_allowed true (ready non-empty)" \
  "assert.strictEqual(b.mode,'parallel-attended'); assert.strictEqual(b.cut_allowed,true);" \
  "$V" "$B/diamond-parallel.json" "$DM_SHEET"

# Mermaid: roots vs dependents classed, representative edges present. Node ids are
# prefixed n_ so a sheet id never collides with a Mermaid keyword; labels keep the raw id.
expect_json "mermaid: root classed root, sink classed dependent, edges present" \
  "assert.ok(/class n_root[, ]/.test(b.mermaid)||/class n_root;/.test(b.mermaid)); assert.ok(b.mermaid.includes('n_root --> n_mid-a')); assert.ok(b.mermaid.includes('n_mid-a --> n_sink'));" \
  "$V" "$DM_STATE" "$DM_SHEET"

# Mermaid: a sheet id that is a Mermaid keyword (graph) must not be emitted as a bare node
# id (a parse error); it is prefixed, and the raw id survives in the label.
expect_json "mermaid: keyword id 'graph' is prefixed, not emitted bare" \
  "assert.ok(!/(^|\n)\s*graph\[/.test(b.mermaid)); assert.ok(b.mermaid.includes('n_graph[\"graph: Bare graph increment\"]')); assert.ok(b.mermaid.includes('n_graph --> n_run'));" \
  "$V" "$B/keyword-id.json" "$B/keyword-id.md"

# Input checking: a state that disagrees with the sheet is rejected before computing (exit 2).
expect_exit 2 "disagreeing inputs -> exit 2 (not computed)" \
  "$V" "$REPO_ROOT/tests/fixtures/states/deps-mismatch.json" "$REPO_ROOT/tests/fixtures/sheets/valid.md"

# Usage guards.
expect_exit 64 "no arguments -> usage error"      "$V"
expect_exit 64 "only one argument -> usage error" "$V" "$DM_STATE"

suite_summary
