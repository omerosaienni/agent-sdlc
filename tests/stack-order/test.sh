#!/usr/bin/env bash
# Suite for scripts/stack-order.sh: the linearised build order must be a valid topological
# order of the sheet's depends_on with sibling ties broken by lowest id, and reproducible.
# Reuses the diamond fixture (root -> mid-a/mid-b/tail, sink -> mid-a/mid-b), whose only
# valid lowest-id-first linearisation is root, mid-a, mid-b, sink, tail: it pins the
# tie-break (three siblings on root, ordered by id) and the join (sink after both parents).
# Sourced and run by tests/run.sh.

suite_begin "stack-order.sh" unit

V="$REPO_ROOT/scripts/stack-order.sh"
B="$REPO_ROOT/tests/fixtures/boards"

# valid pair: a two-node chain linearises to itself.
expect_json "valid: [prod-api, prod-ui]" \
  "assert.deepStrictEqual(b,['prod-api','prod-ui']);" \
  "$V" "$REPO_ROOT/tests/fixtures/states/valid.json" "$REPO_ROOT/tests/fixtures/sheets/valid.md"

# diamond: the exact lowest-id-first linearisation.
expect_json "diamond: [root, mid-a, mid-b, sink, tail]" \
  "assert.deepStrictEqual(b,['root','mid-a','mid-b','sink','tail']);" \
  "$V" "$B/diamond-mixed.json" "$B/diamond.md"

# Tie-break DISCRIMINATOR: this fixture declares its two siblings out of id order (zeta
# before alpha). A lowest-id tie-break emits alpha before zeta; a sheet-order tie-break
# would emit zeta before alpha. The diamond above cannot catch this (its siblings are
# already in id order), so this case is what actually pins the lowest-id rule: it fails
# if the tie-break ever degrades to sheet order.
S="$REPO_ROOT/tests/fixtures/stacks"
expect_json "unordered siblings: lowest-id wins (alpha before zeta)" \
  "assert.deepStrictEqual(b,['root','alpha','zeta','omega']); assert.ok(b.indexOf('alpha')<b.indexOf('zeta'));" \
  "$V" "$S/unordered-siblings.json" "$S/unordered-siblings.md"

# Invariant: every dependency precedes its dependent (a real topological order), and every
# sheet id appears exactly once. Checked independent of the exact tie-break above.
expect_json "diamond: deps precede dependents, complete, no dupes" \
  "const p=id=>b.indexOf(id); assert.ok(p('root')<p('mid-a')); assert.ok(p('root')<p('mid-b')); assert.ok(p('root')<p('tail')); assert.ok(p('mid-a')<p('sink')); assert.ok(p('mid-b')<p('sink')); assert.strictEqual(b.length,5); assert.strictEqual(new Set(b).size,5);" \
  "$V" "$B/diamond-mixed.json" "$B/diamond.md"

# Determinism: two runs on the same inputs emit byte-identical output (the stack must be
# reproducible across conversations).
o1="$("$V" "$B/diamond-mixed.json" "$B/diamond.md" 2>/dev/null)"
o2="$("$V" "$B/diamond-mixed.json" "$B/diamond.md" 2>/dev/null)"
if [ "$o1" = "$o2" ]; then _t_ok "determinism: identical across runs"
else _t_bad "determinism: output differed across runs"; fi

# Input checking: a state that disagrees with the sheet is rejected before computing (exit 2).
expect_exit 2 "disagreeing inputs -> exit 2 (not computed)" \
  "$V" "$REPO_ROOT/tests/fixtures/states/deps-mismatch.json" "$REPO_ROOT/tests/fixtures/sheets/valid.md"

# Usage guards.
expect_exit 64 "no arguments -> usage error"      "$V"
expect_exit 64 "only one argument -> usage error" "$V" "$B/diamond-mixed.json"

suite_summary
