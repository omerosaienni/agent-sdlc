#!/usr/bin/env bash
# Validate an epic manifest against the rules of contracts/epic-manifest.schema.md,
# the epic's build-order manifest written by the design partner. Read-only.
#
# The manifest lists an epic's features in build order, each with the cross-feature
# depends_on edges that justify the order. Validated for internal shape only; the sheet
# files it names are not required to exist (`.building` is gitignored, a manifest is
# valid whether or not the sheets are present in a given checkout).
#
# The seven rules of epic-manifest.schema.md, all mechanical:
#   1 epic non-empty          2 features non-empty, each well-formed   3 names unique
#   4 depends_on names exist   5 no cycle   6 order matches deps   7 sheet path matches name
#
# Defect vs rejection: the DAG is the law (mirrors validate-sheet.sh). A cycle (rule 5),
# an empty/absent features list, or non-JSON is a non-DAG/non-manifest = STRUCTURAL DEFECT
# (exit 4, regenerate upstream). Every other failure is a fixable REJECTION (exit 1); a
# dangling depends_on (rule 4) is a typo in an edge, still a DAG, so a rejection.
#
# Usage:
#   validate-epics.sh <epic.json>   validate, one line per rule, verdict last
#   validate-epics.sh --help
#
# Read-only: never writes. Exit: 0 valid, 1 rejection, 3 node absent, 4 structural
# defect, 64 bad usage.
set -uo pipefail   # no -e: checks run in node, the script decides the exit from node's result

# ============================================================================
# Helpers
# ============================================================================

usage() { awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0; }

setup_color() {
    if [ "$use_color" = never ] || [ -n "${NO_COLOR:-}" ] \
       || [ ! -t 1 ] || [ "${TERM:-dumb}" = dumb ]; then
        C_RESET= ; C_OK= ; C_ERR=
    else
        C_RESET=$'\033[0m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'
    fi
}

# ============================================================================
# Parse arguments
# ============================================================================

manifest="" ; use_color=auto
for arg in "$@"; do
    case "$arg" in
        --no-color) use_color=never ;;
        -h|--help)  usage ;;
        -*)
            echo "unknown option: $arg" >&2
            echo "use: validate-epics.sh <epic.json>" >&2
            exit 64 ;;
        *)
            if [ -z "$manifest" ]; then manifest="$arg"
            else echo "too many arguments (got a second: $arg)" >&2; exit 64; fi ;;
    esac
done

setup_color

# ============================================================================
# Resolve and validate inputs (before any work)
# ============================================================================

if [ -z "$manifest" ]; then
    echo "need an epic manifest to validate" >&2
    echo "use: validate-epics.sh <epic.json>" >&2
    exit 64
fi
if [ ! -f "$manifest" ]; then echo "not found: $manifest" >&2; exit 64; fi
if ! command -v node >/dev/null 2>&1; then
    echo "node not found; validate-epics.sh needs node (part of the TypeScript pipeline)" >&2
    exit 3
fi

# ============================================================================
# Validate: parse epic.json, check the seven rules (in node)
# ============================================================================

C_OK="$C_OK" C_ERR="$C_ERR" C_RESET="$C_RESET" node - "$manifest" <<'NODE'
const fs = require('fs');
const [, , manifestPath] = process.argv;
const OK = process.env.C_OK || '', ERR = process.env.C_ERR || '', R = process.env.C_RESET || '';

// --- Parse the manifest JSON --------------------------------------------------
let m;
try { m = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); }
catch (e) {
  // A non-parseable manifest is a structural defect: it is not a manifest at all.
  console.log(`${ERR}DEFECT${R} parse: epic.json is not valid JSON -- ${e.message}`);
  console.log(`${ERR}DEFECT${R} ${manifestPath}: not a parseable epic manifest (regenerate)`);
  process.exit(4);
}

// --- Checks -------------------------------------------------------------------
// A rejection is a fixable flaw (exit 1); a defect is a non-DAG/non-manifest (exit 4):
// a cycle (rule 5) or an empty/absent features list, an upstream-producer bug.
const results = [];
const pass = (rule) => results.push({ ok: true, rule });
const fail = (rule, detail) => results.push({ ok: false, rule, detail });
const defect = (rule, detail) => results.push({ ok: false, rule, detail, defect: true });
const isStr = (v) => typeof v === 'string' && v.length > 0;

// Rule 1: epic present, non-empty string.
isStr(m.epic) ? pass(1) : fail(1, 'epic missing or empty');

// Rule 2: features a non-empty list; each element well-formed. An absent/empty list is a
// defect (not a manifest); a malformed element is a rejection.
const features = Array.isArray(m.features) ? m.features : null;
if (!features || features.length === 0) {
  defect(2, '`features` missing, not a list, or empty');
} else {
  const bad = [];
  features.forEach((f, i) => {
    if (!f || typeof f !== 'object') { bad.push(`feature ${i}: not an object`); return; }
    if (!isStr(f.name)) bad.push(`feature ${i}: name missing or empty`);
    if (!isStr(f.sheet)) bad.push(`feature ${i} (${f.name || '?'}): sheet missing or empty`);
    if (!Array.isArray(f.depends_on)) bad.push(`feature ${i} (${f.name || '?'}): depends_on not a list`);
  });
  bad.length ? fail(2, bad.join('; ')) : pass(2);
}

// The remaining rules need well-formed elements; run them on the valid subset so a lone
// malformed element (already flagged by rule 2) does not mask an otherwise-real cycle.
const wf = (features || []).filter(
  (f) => f && typeof f === 'object' && isStr(f.name) && Array.isArray(f.depends_on));
const names = new Set(wf.map((f) => f.name));

// Rule 3: names unique.
{
  const seen = new Set(), dup = new Set();
  for (const f of wf) { if (seen.has(f.name)) dup.add(f.name); seen.add(f.name); }
  dup.size ? fail(3, `duplicate name(s): ${[...dup].join(', ')}`) : pass(3);
}

// Rule 4: every depends_on entry names a feature in the manifest.
{
  const bad = [];
  for (const f of wf) {
    for (const d of f.depends_on) {
      if (!names.has(d)) bad.push(`\`${f.name}\` depends on \`${d}\`, not a feature here`);
    }
  }
  bad.length ? fail(4, bad.join('; ')) : pass(4);
}

// Rule 5: no cycle across depends_on. A cycle is a DEFECT (the manifest is not a DAG).
// Only edges to known features count (rule 4 owns the dangling ones).
{
  const adj = new Map(wf.map((f) => [f.name, f.depends_on.filter((d) => names.has(d))]));
  const WHITE = 0, GREY = 1, BLACK = 2;
  const colour = new Map([...names].map((n) => [n, WHITE]));
  let cyclic = false;
  const visit = (n) => {
    colour.set(n, GREY);
    for (const d of adj.get(n) || []) {
      if (colour.get(d) === GREY) { cyclic = true; return; }
      if (colour.get(d) === WHITE) { visit(d); if (cyclic) return; }
    }
    colour.set(n, BLACK);
  };
  for (const n of names) { if (colour.get(n) === WHITE) visit(n); if (cyclic) break; }
  cyclic ? defect(5, 'a cycle exists in the feature depends_on graph') : pass(5);
}

// Rule 6: list order consistent with depends_on (a feature never precedes a dep).
// Skipped if a cycle was found (order is meaningless then).
{
  const hasCycle = results.some((r) => r.rule === 5 && !r.ok);
  if (hasCycle) { pass(6); }
  else {
    const pos = new Map();
    wf.forEach((f, i) => pos.set(f.name, i));
    const bad = [];
    wf.forEach((f, i) => {
      for (const d of f.depends_on) {
        if (names.has(d) && pos.get(d) > i) {
          bad.push(`\`${f.name}\` (position ${i}) precedes its dep \`${d}\` (position ${pos.get(d)})`);
        }
      }
    });
    bad.length ? fail(6, bad.join('; ')) : pass(6);
  }
}

// Rule 7: sheet path is `.building/features/<name>/increments.md` (agrees with the name).
{
  const bad = [];
  for (const f of wf) {
    if (!isStr(f.sheet)) continue;   // rule 2 flagged it
    const want = `.building/features/${f.name}/increments.md`;
    if (f.sheet !== want) bad.push(`\`${f.name}\`: sheet is \`${f.sheet}\`, want \`${want}\``);
  }
  bad.length ? fail(7, bad.join('; ')) : pass(7);
}

// --- Report -------------------------------------------------------------------
const label = {
  1: 'epic present', 2: 'features present and well-formed', 3: 'names unique',
  4: 'depends_on names exist', 5: 'no cycle', 6: 'order matches deps',
  7: 'sheet path matches name', parse: 'epic.json parses',
};
results.sort((a, b) => String(a.rule).localeCompare(String(b.rule), undefined, { numeric: true }));

let rejections = 0, defects = 0;
for (const r of results) {
  const name = typeof r.rule === 'number' ? `rule ${r.rule}` : r.rule;
  if (r.ok) { console.log(`${OK}OK${R}   ${name}: ${label[r.rule]}`); continue; }
  if (r.defect) { defects++; console.log(`${ERR}DEFECT${R} ${name}: ${label[r.rule]} -- ${r.detail}`); }
  else { rejections++; console.log(`${ERR}FAIL${R} ${name}: ${label[r.rule]} -- ${r.detail}`); }
}

if (defects) {
  console.log(`${ERR}DEFECT${R} ${manifestPath}: ${defects} structural defect(s) (regenerate), ${rejections} rejection(s)`);
  process.exit(4);
}
if (rejections) {
  console.log(`${ERR}INVALID${R} ${manifestPath}: ${rejections} rejection(s) to fix`);
  process.exit(1);
}
console.log(`${OK}VALID${R} ${manifestPath}`);
process.exit(0);
NODE
exit $?
