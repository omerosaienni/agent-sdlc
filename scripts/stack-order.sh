#!/usr/bin/env bash
# Linearise a feature's depends_on DAG into the single build order the stacked build
# loop appends in. Read-only. Emits one JSON array of increment ids, lowest-id-first
# topological order: an increment never precedes one it depends on, and sibling ties
# (increments sharing a dependency) are broken by lowest id. Consumed by the stacked
# build loop (contracts/build-stacked.md, Linearisation): it appends each increment as
# a git-town child of the one before it, forming one linear stack.
#
# Why a script: a git-town stack is linear but the sheet is a DAG, so the loop must pick
# a linear extension. An LLM hand-picking a topological order with tie-breaks drifts, yet
# the stack must be reproducible across conversations. Determinism is the point (mirrors
# board-state.sh). The orchestrator stays the SOLE WRITER of state.json; this only reads.
#
# Always checks its inputs: runs validate-state.sh first (which itself re-validates the
# sheet), so the order is never computed from a state that disagrees with its sheet. A
# non-DAG never reaches here: the sheet validator rejects a cycle upstream, and this
# script fails loudly (exit 4) rather than emit a partial order if one is ever seen.
#
# Usage:
#   stack-order.sh <state.json> <sheet.md>   emit the build-order JSON array
#   stack-order.sh --help
#
# Read-only. Exit: 0 emitted, 2 inputs failed validation (the validator's message is
# shown; the order is not computed), 3 node absent, 4 a cycle was seen (structural
# defect, should have been caught upstream), 64 bad usage.
set -uo pipefail

# ============================================================================
# Helpers
# ============================================================================

usage() { awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0; }

# ============================================================================
# Parse arguments
# ============================================================================

state="" ; sheet=""
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage ;;
        -*) echo "unknown option: $arg" >&2
            echo "use: stack-order.sh <state.json> <sheet.md>" >&2; exit 64 ;;
        *)  if   [ -z "$state" ]; then state="$arg"
            elif [ -z "$sheet" ]; then sheet="$arg"
            else echo "too many arguments (got a third: $arg)" >&2; exit 64; fi ;;
    esac
done

# ============================================================================
# Resolve and validate inputs (before any work)
# ============================================================================

if [ -z "$state" ] || [ -z "$sheet" ]; then
    echo "need both a state file and its sheet" >&2
    echo "use: stack-order.sh <state.json> <sheet.md>" >&2
    exit 64
fi
for f in "$state" "$sheet"; do
    [ -f "$f" ] || { echo "not found: $f" >&2; exit 64; }
done
if ! command -v node >/dev/null 2>&1; then
    echo "node not found; stack-order.sh needs node (as board-state.sh does)" >&2
    exit 3
fi

# Always check inputs: the order is meaningless if state and sheet disagree, so validate
# the pair first. validate-state.sh re-validates the sheet itself, so this one call covers
# both inputs and their agreement. Its output goes to stderr on failure; we do not compute.
validator="$(dirname "$0")/validate-state.sh"
if ! "$validator" --no-color "$state" "$sheet" >/dev/null 2>&1; then
    echo "inputs failed validation; not computing the order (run: validate-state.sh $state $sheet)" >&2
    exit 2
fi

# ============================================================================
# Compute the linear build order (in node) and emit one JSON array
# ============================================================================

node - "$sheet" <<'NODE'
const fs = require('fs');
const [, , sheetPath] = process.argv;

// --- Parse the sheet for ids and depends_on (fixed tokens only, as board-state.sh) ---
const sheetSrc = fs.readFileSync(sheetPath, 'utf8').split(/\r?\n/);
const order = [];                 // ids in sheet order
const deps = new Map();           // id -> [depId, ...]
{
  let cur = null;
  for (const line of sheetSrc) {
    if (line.startsWith('### ')) {
      const h = line.slice(4); const c = h.indexOf(':');
      cur = (c === -1 ? h : h.slice(0, c)).trim();
      order.push(cur); deps.set(cur, []);
      continue;
    }
    if (!cur) continue;
    const m = line.match(/^- depends_on:(.*)$/);
    if (m) {
      const inner = m[1].trim().replace(/^\[/, '').replace(/\]$/, '').trim();
      deps.set(cur, inner === '' ? [] : inner.split(',').map((s) => s.trim()).filter(Boolean));
    }
  }
}
const ids = new Set(order);

// --- Kahn's algorithm, ties broken by lowest id -------------------------------
// A deterministic linear extension of the DAG: repeatedly emit the lowest-id node whose
// every dependency has already been emitted. Lowest-id tie-break makes siblings reproducible.
const remaining = new Set(order);
const emitted = new Set();
const result = [];
const depsMet = (id) => deps.get(id).every((d) => !ids.has(d) || emitted.has(d));

while (remaining.size > 0) {
  // lowest id among remaining nodes whose deps are all met
  let pick = null;
  for (const id of [...remaining].sort()) {
    if (depsMet(id)) { pick = id; break; }
  }
  if (pick === null) {
    // No node is buildable => a cycle remains. The sheet validator should have caught it
    // upstream; fail loudly rather than emit a partial order.
    process.stderr.write('cycle detected in depends_on; the sheet is not a DAG\n');
    process.exit(4);
  }
  result.push(pick);
  emitted.add(pick);
  remaining.delete(pick);
}

console.log(JSON.stringify(result, null, 2));
NODE
exit $?
