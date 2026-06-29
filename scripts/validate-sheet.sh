#!/usr/bin/env bash
# Validate an increment sheet against the mechanical rules of
# contracts/increment-sheet.schema.md. Enforces the checkable rules; the two
# judgement rules stay the design partner's and are NOT checked here:
#   goal present and non-empty       1 fields present and non-empty   2 ids unique
#   3 every depends_on id exists      4 no dependency cycle            5 order matches deps
#   8 canonical serialisation
#   (NOT 6 acceptance criteria runnable-not-opinion, NOT 7 independently buildable, NOT
#    whether the goal is USEFUL: these need judgement, so an agent confirms them; a pass
#    here is necessary, not sufficient.)
#
# The DAG is the law: a sheet that cannot be a DAG (a cycle) or is not a sheet at all
# (no increments) is a STRUCTURAL DEFECT, an upstream-producer bug to regenerate, not a
# spot-fix. Every other failure is an ordinary rejection: a locatable, fixable flaw
# (a dangling depends_on is a typo in an edge, still a DAG, so a rejection not a defect).
#
# The parse keys ONLY on the two fixed tokens the format guarantees stable, the
# `### <id>: <title>` heading and the `depends_on: [...]` bullet, so a later
# densification of the prose fields does not require rewriting this script.
#
# Usage:
#   validate-sheet.sh <sheet.md>     validate the sheet, print one line per rule, verdict last
#   validate-sheet.sh --help         print this header
#
# Read-only: never writes the sheet or anything else. Exit: 0 valid, 1 an ordinary
# rejection (a fixable rule failure), 3 node is absent, 4 a structural defect
# (non-DAG/no increments: regenerate upstream), 64 bad usage.
set -uo pipefail   # no -e: checks run in node, the script decides the exit code from node's result

# ============================================================================
# Helpers
# ============================================================================

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# Colour only at a real terminal, TERM not dumb, not opted out (NO_COLOR / --no-color).
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

sheet=""
use_color=auto
for arg in "$@"; do
    case "$arg" in
        --no-color) use_color=never ;;
        -h|--help)  usage ;;
        -*)
            echo "unknown option: $arg" >&2
            echo "use: validate-sheet.sh <sheet.md>" >&2
            exit 64 ;;
        *)
            if [ -n "$sheet" ]; then
                echo "only one sheet path is accepted (got a second: $arg)" >&2
                exit 64
            fi
            sheet="$arg" ;;
    esac
done

setup_color

# ============================================================================
# Resolve and validate inputs (before any work)
# ============================================================================

if [ -z "$sheet" ]; then
    echo "no sheet path given" >&2
    echo "use: validate-sheet.sh <sheet.md>" >&2
    exit 64
fi
if [ ! -f "$sheet" ]; then
    echo "sheet not found: $sheet" >&2
    exit 64
fi
# node is a hard dependency of the TypeScript pipeline; declare it rather than fail
# obscurely inside the heredoc.
if ! command -v node >/dev/null 2>&1; then
    echo "node not found; validate-sheet.sh needs node (part of the TypeScript pipeline)" >&2
    exit 3
fi

# ============================================================================
# Validate: parse the sheet and check rules 1-5 and 8 (in node)
# ============================================================================

# node owns the parse and the checks: it emits one `OK <rule>` / `FAIL <rule>: <detail>`
# line per rule to stdout, prints the verdict, and exits 0 (valid) or 1 (a rule failed).
# C_OK/C_ERR are passed in so colour stays a single decision made above.
C_OK="$C_OK" C_ERR="$C_ERR" C_RESET="$C_RESET" node - "$sheet" <<'NODE'
const fs = require('fs');
const [, , sheetPath] = process.argv;
const OK = process.env.C_OK || '', ERR = process.env.C_ERR || '', R = process.env.C_RESET || '';

const src = fs.readFileSync(sheetPath, 'utf8');
const lines = src.split(/\r?\n/);

// --- Parse, keyed only on the two fixed tokens --------------------------------
// A heading is a line starting with '### '. The canonical form is `### <id>: <title>`
// where the id is the colon-free, whitespace-free token before the first colon.
const FIELDS = ['depends_on', 'description', 'done_definition', 'acceptance_criteria', 'test_notes'];
// Fields whose value is a nested bullet list (one item per line) rather than inline text.
const LIST_FIELDS = new Set(['acceptance_criteria', 'test_notes']);
const increments = [];
let cur = null;

// Goal: the prose under a `## Goal` heading, before the first increment. Collected so
// its presence and non-emptiness can be checked; whether it is USEFUL stays the agent's.
let inGoal = false;
const goalLines = [];

const startBullet = (line) => line.match(/^- ([a-z_]+):(.*)$/);

for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  if (!cur && /^##\s+Goal\s*$/i.test(line)) { inGoal = true; continue; }
  if (inGoal) {
    if (line.startsWith('### ') || /^##\s/.test(line)) inGoal = false;  // goal ends at the next heading
    else { goalLines.push(line); continue; }
  }
  if (line.startsWith('### ')) {
    const headingText = line.slice(4);
    const colon = headingText.indexOf(':');
    const inc = {
      lineNo: i + 1,
      headingRaw: headingText,
      hasColon: colon !== -1,
      id: colon === -1 ? headingText.trim() : headingText.slice(0, colon).trim(),
      title: colon === -1 ? '' : headingText.slice(colon + 1).trim(),
      bullets: {},        // label -> value (first occurrence)
      bulletOrder: [],    // labels in the order seen
      extraBullets: [],   // labels that are not one of the five canonical fields
    };
    increments.push(inc);
    cur = inc;
    continue;
  }
  if (!cur) continue;       // pre-heading content (the ## Goal block) is not validated here
  const m = startBullet(line);
  if (m) {
    const label = m[1], value = m[2].trim();
    cur.bulletOrder.push(label);
    if (!(label in cur.bullets)) cur.bullets[label] = value;
    if (!FIELDS.includes(label)) cur.extraBullets.push(label);
    // A list field carries its value on the nested lines that follow; collect them.
    if (LIST_FIELDS.has(label)) {
      const items = [];
      for (let j = i + 1; j < lines.length; j++) {
        if (/^  \S/.test(lines[j]) || /^  - /.test(lines[j])) { items.push(lines[j].trim()); continue; }
        if (lines[j].trim() === '') continue;
        break;
      }
      cur.listItems = cur.listItems || {};
      cur.listItems[label] = items;
    }
  }
}

// --- Checks -------------------------------------------------------------------
// A failure is either an ordinary rejection (fixable: exit 1) or a structural defect
// (the sheet cannot be a DAG / is not a sheet: exit 4, regenerate upstream).
const results = [];
const pass = (rule) => results.push({ ok: true, rule });
const fail = (rule, detail) => results.push({ ok: false, rule, detail });
const defect = (rule, detail) => results.push({ ok: false, rule, detail, defect: true });

// Goal: present and non-empty. Mechanical; the goal's usefulness is the agent's call.
goalLines.join('').trim() === ''
  ? fail('goal', 'no `## Goal` paragraph, or it is empty')
  : pass('goal');

if (increments.length === 0) {
  defect('structure', 'no `### <id>: <title>` increments: this is not a buildable sheet');
}

// Rule 8 (serialisation) is checked first: the other rules read the parsed id/fields,
// so a malformed heading or label set is the most basic failure.
{
  const bad = [];
  for (const inc of increments) {
    if (!inc.hasColon) bad.push(`line ${inc.lineNo}: bare heading \`### ${inc.headingRaw}\` has no \`: <title>\``);
    else if (!inc.id) bad.push(`line ${inc.lineNo}: heading has an empty id before the colon`);
    else if (/\s/.test(inc.id)) bad.push(`line ${inc.lineNo}: id \`${inc.id}\` contains whitespace`);
    if (inc.extraBullets.length) bad.push(`increment \`${inc.id}\`: non-canonical bullet(s): ${[...new Set(inc.extraBullets)].join(', ')}`);
  }
  bad.length ? fail(8, bad.join('; ')) : pass(8);
}

// Rule 1: all five fields present and non-empty.
{
  const bad = [];
  for (const inc of increments) {
    for (const f of FIELDS) {
      if (!(f in inc.bullets)) { bad.push(`\`${inc.id}\`: missing ${f}`); continue; }
      const empty = LIST_FIELDS.has(f)
        ? !(inc.listItems && inc.listItems[f] && inc.listItems[f].length)
        : inc.bullets[f] === '';
      if (empty) bad.push(`\`${inc.id}\`: empty ${f}`);
    }
  }
  bad.length ? fail(1, bad.join('; ')) : pass(1);
}

// Rule 2: ids unique.
{
  const seen = new Map(), dups = new Set();
  for (const inc of increments) {
    if (seen.has(inc.id)) dups.add(inc.id);
    seen.set(inc.id, true);
  }
  dups.size ? fail(2, `duplicate id(s): ${[...dups].join(', ')}`) : pass(2);
}

// depends_on parse: `[a, b]` -> ['a','b']; `[]` -> []. Used by rules 3, 4, 5.
const deps = (inc) => {
  const raw = inc.bullets.depends_on;
  if (raw === undefined) return [];
  const inner = raw.replace(/^\[/, '').replace(/\]$/, '').trim();
  return inner === '' ? [] : inner.split(',').map((s) => s.trim()).filter(Boolean);
};

const ids = new Set(increments.map((i) => i.id));

// Rule 3: every depends_on id exists.
{
  const bad = [];
  for (const inc of increments) for (const d of deps(inc)) {
    if (!ids.has(d)) bad.push(`\`${inc.id}\` depends on unknown id \`${d}\``);
  }
  bad.length ? fail(3, bad.join('; ')) : pass(3);
}

// Rule 4: no cycle (DFS over the depends_on edges, among known ids only).
{
  const WHITE = 0, GREY = 1, BLACK = 2;
  const colour = new Map([...ids].map((id) => [id, WHITE]));
  const adj = new Map(increments.map((i) => [i.id, deps(i).filter((d) => ids.has(d))]));
  let cycle = null;
  const stack = [];
  const visit = (u) => {
    colour.set(u, GREY); stack.push(u);
    for (const v of adj.get(u) || []) {
      if (colour.get(v) === GREY) { cycle = [...stack.slice(stack.indexOf(v)), v]; return true; }
      if (colour.get(v) === WHITE && visit(v)) return true;
    }
    colour.set(u, BLACK); stack.pop(); return false;
  };
  for (const id of ids) if (colour.get(id) === WHITE && visit(id)) break;
  // A cycle is a STRUCTURAL DEFECT: the sheet cannot be a DAG, so it is an upstream-producer
  // bug to regenerate, not a spot-fix. Reported as a defect (exit 4), not an ordinary rejection.
  cycle ? defect(4, `cycle: ${cycle.join(' -> ')}`) : pass(4);
}

// Rule 5: list order consistent with depends_on (a dep must appear earlier in the list).
// Reported honestly even under a cycle: a cycle also breaks order, and that is a true fact,
// not noise. The defect exit code (4, from rule 4) already tells the reader the cycle is the
// root cause; suppressing rule 5 would hide a real consequence.
{
  const pos = new Map(increments.map((inc, idx) => [inc.id, idx]));
  const bad = [];
  for (const inc of increments) for (const d of deps(inc)) {
    if (pos.has(d) && pos.get(d) > pos.get(inc.id)) {
      bad.push(`\`${inc.id}\` appears before its dep \`${d}\``);
    }
  }
  bad.length ? fail(5, bad.join('; ')) : pass(5);
}

// --- Report -------------------------------------------------------------------
const label = {
  goal: 'goal present and non-empty', structure: 'sheet has increments',
  1: 'fields present and non-empty', 2: 'ids unique', 3: 'depends_on ids exist',
  4: 'no dependency cycle', 5: 'order matches depends_on', 8: 'canonical serialisation',
};
// Order: goal first (orientation), then numbered rules, then structure.
const order = (rule) => rule === 'goal' ? -1 : rule === 'structure' ? 99 : Number(rule);
results.sort((a, b) => order(a.rule) - order(b.rule));

let rejections = 0, defects = 0;
for (const r of results) {
  const name = typeof r.rule === 'number' ? `rule ${r.rule}` : r.rule;
  if (r.ok) { console.log(`${OK}OK${R}   ${name}: ${label[r.rule]}`); continue; }
  if (r.defect) { defects++; console.log(`${ERR}DEFECT${R} ${name}: ${label[r.rule]} -- ${r.detail}`); }
  else { rejections++; console.log(`${ERR}FAIL${R} ${name}: ${label[r.rule]} -- ${r.detail}`); }
}

// A defect (non-DAG / not a sheet) outranks a rejection: it is the upstream-producer bug,
// so exit 4 wins over exit 1 when both are present.
if (defects) {
  console.log(`${ERR}DEFECT${R} ${sheetPath}: ${defects} structural defect(s) (regenerate upstream), ${rejections} rejection(s)`);
  process.exit(4);
}
if (rejections) {
  console.log(`${ERR}INVALID${R} ${sheetPath}: ${rejections} rejection(s) to fix`);
  process.exit(1);
}
console.log(`${OK}VALID${R} ${sheetPath} (mechanical rules only; rules 6-7 and goal usefulness are the agent's)`);
process.exit(0);
NODE
exit $?
