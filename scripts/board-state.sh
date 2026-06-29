#!/usr/bin/env bash
# Compute the build loop's board state from state.json and the sheet: every
# depends_on computation the orchestrator and the document agent would otherwise do
# by hand. Read-only. Emits one JSON object; the orchestrator pastes the board into
# its verbatim template and the document agent embeds the Mermaid graph.
#
# Owns (all pure functions of the sheet's depends_on plus state.json):
#   - the four-section board partition: ready, awaiting_merge, blocked, possibly_stalled
#   - the critical-path star set (longest root-to-terminal chain over the full sheet DAG,
#     measured in NODES; on a tie, every node on any longest chain is starred)
#   - the ready set and the cut-rule boolean (per mode, read from state.json)
#   - the coloured Mermaid dependency graph (roots one colour, dependents another)
#
# Why a script: an LLM hand-computing longest-path-with-ties drifts, yet the board must
# render byte-identical across conversations. Determinism is the point. The orchestrator
# stays the SOLE WRITER of state.json; this script only reads and emits.
#
# Always checks its inputs: runs validate-state.sh first (which itself re-validates the
# sheet), so the board is never computed from a state that disagrees with its sheet.
#
# KNOWN GAP (lite profile only): does NOT yet emit the synthetic `completion-docs` row
# that AWAITING MERGE carries when a lite queue's `completion.docs` is pr-open
# (build-judge-loop.md, The board). Full and build-quick have no completion block, so
# they are fully covered; only lite's end-of-queue docs-PR row is missing. To be added
# when the completion/docs flow settles.
#
# Usage:
#   board-state.sh <state.json> <sheet.md>   emit the board-state JSON
#   board-state.sh --help
#
# Read-only. Exit: 0 emitted, 2 inputs failed validation (the validator's message is
# shown; the board is not computed), 3 node absent, 64 bad usage.
set -uo pipefail

# ============================================================================
# Helpers
# ============================================================================

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ============================================================================
# Parse arguments
# ============================================================================

state="" ; sheet=""
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage ;;
        -*) echo "unknown option: $arg" >&2
            echo "use: board-state.sh <state.json> <sheet.md>" >&2; exit 64 ;;
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
    echo "use: board-state.sh <state.json> <sheet.md>" >&2
    exit 64
fi
for f in "$state" "$sheet"; do
    [ -f "$f" ] || { echo "not found: $f" >&2; exit 64; }
done
if ! command -v node >/dev/null 2>&1; then
    echo "node not found; board-state.sh needs node (part of the TypeScript pipeline)" >&2
    exit 3
fi

# Always check inputs: the board is meaningless if state and sheet disagree, so validate
# the pair first. validate-state.sh re-validates the sheet itself, so this one call covers
# both inputs and their agreement. Its output goes to stderr on failure; we do not compute.
validator="$(dirname "$0")/validate-state.sh"
if ! "$validator" --no-color "$state" "$sheet" >/dev/null 2>&1; then
    echo "inputs failed validation; not computing the board (run: validate-state.sh $state $sheet)" >&2
    exit 2
fi

# ============================================================================
# Compute the board state (in node) and emit one JSON object
# ============================================================================

node - "$state" "$sheet" <<'NODE'
const fs = require('fs');
const [, , statePath, sheetPath] = process.argv;

const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));

// --- Parse the sheet for ids, titles and depends_on (fixed tokens only) -------
const sheetSrc = fs.readFileSync(sheetPath, 'utf8').split(/\r?\n/);
const order = [];                 // ids in sheet order
const title = new Map();          // id -> title
const deps = new Map();           // id -> [depId, ...]
{
  let cur = null;
  for (const line of sheetSrc) {
    if (line.startsWith('### ')) {
      const h = line.slice(4); const c = h.indexOf(':');
      cur = (c === -1 ? h : h.slice(0, c)).trim();
      title.set(cur, c === -1 ? '' : h.slice(c + 1).trim());
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
const incs = state.increments || {};
const statusOf = (id) => (incs[id] && incs[id].status) || 'pending';
const isMerged = (id) => statusOf(id) === 'merged';

// dependents: reverse of deps. A terminal is an id nothing depends on.
const dependents = new Map(order.map((id) => [id, []]));
for (const id of order) for (const d of deps.get(id)) if (dependents.has(d)) dependents.get(d).push(id);
const isTerminal = (id) => dependents.get(id).length === 0;

// --- Critical-path star: longest root-to-terminal chain in NODES --------------
// Static over the FULL sheet DAG (not the remaining-work subgraph), so it never drifts
// as increments merge. longest[id] = max nodes on a chain ENDING at id. L = the max over
// terminals. Star = every id that lies on at least one chain of node-length L: it must be
// reachable on a path whose nodes-before-it (longest[id]) plus nodes-after-it
// (longestFwd[id]) - 1 == L. Computed in topological order via memoised DFS.
const longestBack = new Map();   // max nodes on a chain ending at id (counting id)
const longestFwd = new Map();    // max nodes on a chain starting at id (counting id)
const back = (id) => {
  if (longestBack.has(id)) return longestBack.get(id);
  let best = 1;
  for (const d of deps.get(id)) if (ids.has(d)) best = Math.max(best, 1 + back(d));
  longestBack.set(id, best); return best;
};
const fwd = (id) => {
  if (longestFwd.has(id)) return longestFwd.get(id);
  let best = 1;
  for (const c of dependents.get(id)) best = Math.max(best, 1 + fwd(c));
  longestFwd.set(id, best); return best;
};
for (const id of order) { back(id); fwd(id); }
const L = order.reduce((m, id) => isTerminal(id) ? Math.max(m, longestBack.get(id)) : m, 0);
// An id is on a longest chain iff a longest chain through it has total length L.
const starred = new Set(order.filter((id) => longestBack.get(id) + longestFwd.get(id) - 1 === L));

// --- Board partition ----------------------------------------------------------
// Every non-merged increment falls in exactly one section; merged appear in none.
const ready = [], awaiting = [], blocked = [], stalled = [];

for (const id of order) {
  const st = statusOf(id);
  if (st === 'merged') continue;
  if (st === 'pr-open') {
    awaiting.push({ id, title: title.get(id), starred: starred.has(id),
      unblocks: dependents.get(id).slice().sort() });
    continue;
  }
  if (st === 'pending') {
    const unmet = deps.get(id).filter((d) => ids.has(d) && !isMerged(d));
    if (unmet.length === 0) ready.push({ id, title: title.get(id), starred: starred.has(id) });
    else blocked.push({ id, title: title.get(id), starred: starred.has(id),
      waiting_on: unmet.map((d) => ({ id: d, status: statusOf(d) })) });
    continue;
  }
  // building, in-review, in-judgement, documented, escalated, blocked(endpoint) => stalled
  stalled.push({ id, title: title.get(id), starred: starred.has(id), state: st });
}

const byId = (a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0;  // lowest id first within each section
[ready, awaiting, blocked, stalled].forEach((s) => s.sort(byId));

// --- Ready set and cut-rule (per mode, read from state.json) -------------------
const mode = state.mode || 'sequential-attended';
const readySet = ready.map((r) => r.id);
const nonMerged = order.filter((id) => !isMerged(id));
const everyNonMergedPending = nonMerged.every((id) => statusOf(id) === 'pending');
const cutAllowed = mode === 'parallel-attended'
  ? readySet.length > 0
  : readySet.length > 0 && everyNonMergedPending;  // sequential: nothing else in flight

// --- Mermaid dependency graph (roots vs dependents, repo palette) --------------
// A root has no depends_on; a dependent has at least one. Matches the document agent spec.
const isRoot = (id) => deps.get(id).length === 0;
const mermaid = (() => {
  const lines = [
    "%%{init: {'theme':'base','themeVariables':{'primaryColor':'#e4edf4','primaryTextColor':'#1d2733','primaryBorderColor':'#5b6b7a','lineColor':'#5b6b7a','fontSize':'14px'}}}%%",
    'flowchart TD',
  ];
  for (const id of order) {
    const t = title.get(id) ? `${id}: ${title.get(id)}` : id;
    lines.push(`    ${id}["${t.replace(/"/g, "'")}"]`);
  }
  for (const id of order) for (const d of deps.get(id)) if (ids.has(d)) lines.push(`    ${d} --> ${id}`);
  lines.push('    classDef root fill:#dbe7f0,stroke:#5b6b7a,color:#1d2733;');
  lines.push('    classDef dependent fill:#e4edf4,stroke:#5b6b7a,color:#1d2733;');
  const roots = order.filter(isRoot), depcls = order.filter((id) => !isRoot(id));
  if (roots.length) lines.push(`    class ${roots.join(',')} root;`);
  if (depcls.length) lines.push(`    class ${depcls.join(',')} dependent;`);
  return lines.join('\n');
})();

// --- Emit ---------------------------------------------------------------------
const total = order.length;
const merged = order.filter(isMerged).length;
const out = {
  total, merged,
  sections: { ready, awaiting_merge: awaiting, blocked, possibly_stalled: stalled },
  starred: [...starred].sort(),
  critical_path_length: L,
  ready_set: readySet,
  mode,
  cut_allowed: cutAllowed,
  mermaid,
};
console.log(JSON.stringify(out, null, 2));
NODE
exit $?
