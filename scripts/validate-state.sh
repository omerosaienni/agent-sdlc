#!/usr/bin/env bash
# Validate a build-loop state file against the rules of contracts/state.schema.md,
# the loop's per-feature recovery record. Run on the POST-SYNC state.json: after the
# loop has additively synced the sheet into it, before it acts. Read-only.
#
# Always checks its inputs: the state-vs-sheet rules (4, 5) need the sheet, so this
# first RE-VALIDATES the sheet with validate-sheet.sh rather than trusting it. A bad
# sheet is reported as the sheet's own failure (the loop should never reach here with
# one, but a standalone caller might).
#
# The nine rules of state.schema.md, all mechanical:
#   1 sheet+conventions non-empty   2 mode valid if present   3 profile valid if present
#   4 increment keys == sheet ids   5 depends_on == sheet's    6 status in the enum
#   7 review/judge counts 0..3      8 branch null or unique    9 completion well-formed
#
# Defect vs rejection: state<->sheet DISAGREEMENT (rules 4, 5) is a STRUCTURAL DEFECT
# (exit 4): the producer desynced state from the sheet, an out-of-band reconciliation,
# not a spot-fix. Every other failure is a fixable REJECTION (exit 1).
#
# Usage:
#   validate-state.sh <state.json> <sheet.md>   validate, one line per rule, verdict last
#   validate-state.sh --help
#
# Read-only: never writes. Exit: 0 valid, 1 rejection, 3 node absent, 4 structural
# defect, 5 the sheet itself failed validation, 64 bad usage.
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

state="" ; sheet="" ; use_color=auto
for arg in "$@"; do
    case "$arg" in
        --no-color) use_color=never ;;
        -h|--help)  usage ;;
        -*)
            echo "unknown option: $arg" >&2
            echo "use: validate-state.sh <state.json> <sheet.md>" >&2
            exit 64 ;;
        *)
            if   [ -z "$state" ]; then state="$arg"
            elif [ -z "$sheet" ]; then sheet="$arg"
            else echo "too many arguments (got a third: $arg)" >&2; exit 64; fi ;;
    esac
done

setup_color

# ============================================================================
# Resolve and validate inputs (before any work)
# ============================================================================

if [ -z "$state" ] || [ -z "$sheet" ]; then
    echo "need both a state file and its sheet" >&2
    echo "use: validate-state.sh <state.json> <sheet.md>" >&2
    exit 64
fi
for f in "$state" "$sheet"; do
    if [ ! -f "$f" ]; then echo "not found: $f" >&2; exit 64; fi
done
if ! command -v node >/dev/null 2>&1; then
    echo "node not found; validate-state.sh needs node (part of the TypeScript pipeline)" >&2
    exit 3
fi

# Always check inputs: re-validate the sheet before trusting its ids/deps. The sheet
# validator lives beside this one. Its --no-color is honoured so output stays plain
# when ours is. A sheet failure is exit 5 here (distinct from this file's own rejections).
sheet_validator="$(dirname "$0")/validate-sheet.sh"
nc=""; [ "$use_color" = never ] && nc="--no-color"
if ! "$sheet_validator" $nc "$sheet" >/dev/null 2>&1; then
    echo "the sheet failed validation; fix it first (run: validate-sheet.sh $sheet)" >&2
    exit 5
fi

# ============================================================================
# Validate: parse state.json and the sheet, check the nine rules (in node)
# ============================================================================

C_OK="$C_OK" C_ERR="$C_ERR" C_RESET="$C_RESET" node - "$state" "$sheet" <<'NODE'
const fs = require('fs');
const [, , statePath, sheetPath] = process.argv;
const OK = process.env.C_OK || '', ERR = process.env.C_ERR || '', R = process.env.C_RESET || '';

// --- Parse the state JSON -----------------------------------------------------
let state;
try { state = JSON.parse(fs.readFileSync(statePath, 'utf8')); }
catch (e) {
  // A non-parseable state file is a structural defect: it is not a state record at all.
  console.log(`${ERR}DEFECT${R} parse: state.json is not valid JSON -- ${e.message}`);
  console.log(`${ERR}DEFECT${R} ${statePath}: not a parseable state file (regenerate)`);
  process.exit(4);
}

// --- Parse the sheet's ids and depends_on (same fixed tokens as validate-sheet) ---
// The sheet already passed validation, so this parse is for agreement only.
const sheetSrc = fs.readFileSync(sheetPath, 'utf8').split(/\r?\n/);
const sheetDeps = new Map();   // id -> [depId, ...]
{
  let cur = null;
  for (let i = 0; i < sheetSrc.length; i++) {
    const line = sheetSrc[i];
    if (line.startsWith('### ')) {
      const h = line.slice(4); const c = h.indexOf(':');
      cur = (c === -1 ? h : h.slice(0, c)).trim();
      sheetDeps.set(cur, []);
      continue;
    }
    if (!cur) continue;
    const m = line.match(/^- depends_on:(.*)$/);
    if (m) {
      const inner = m[1].trim().replace(/^\[/, '').replace(/\]$/, '').trim();
      sheetDeps.set(cur, inner === '' ? [] : inner.split(',').map((s) => s.trim()).filter(Boolean));
    }
  }
}
const sheetIds = new Set(sheetDeps.keys());

// --- Checks -------------------------------------------------------------------
// A rejection is a fixable flaw (exit 1); a defect is a state<->sheet disagreement
// (rules 4, 5: exit 4), the producer having desynced state from the sheet.
const results = [];
const pass = (rule) => results.push({ ok: true, rule });
const fail = (rule, detail) => results.push({ ok: false, rule, detail });
const defect = (rule, detail) => results.push({ ok: false, rule, detail, defect: true });

const MODES = ['sequential-attended', 'parallel-attended'];
const PROFILES = ['full', 'lite'];
const STATUSES = ['pending', 'building', 'in-review', 'in-judgement', 'documented', 'pr-open', 'merged', 'escalated', 'blocked'];
const INTEG = ['pending', 'passed', 'failed'];
const DOCS = ['pending', 'pr-open', 'merged'];
const isStr = (v) => typeof v === 'string' && v.length > 0;

// Rule 1: sheet and conventions present, non-empty strings.
{
  const bad = [];
  if (!isStr(state.sheet)) bad.push('sheet missing or empty');
  if (!isStr(state.conventions)) bad.push('conventions missing or empty');
  bad.length ? fail(1, bad.join('; ')) : pass(1);
}

// Rule 2: mode, if present, is allowed.
('mode' in state) && state.mode !== undefined
  ? (MODES.includes(state.mode) ? pass(2) : fail(2, `mode \`${state.mode}\` not one of ${MODES.join(', ')}`))
  : pass(2);

// Rule 3: profile, if present, is allowed.
('profile' in state) && state.profile !== undefined
  ? (PROFILES.includes(state.profile) ? pass(3) : fail(3, `profile \`${state.profile}\` not one of ${PROFILES.join(', ')}`))
  : pass(3);

const increments = (state.increments && typeof state.increments === 'object') ? state.increments : null;
if (!increments) {
  // No increments object at all is a defect: it cannot agree with any sheet.
  defect(4, '`increments` missing or not an object');
} else {
  const stateIds = new Set(Object.keys(increments));

  // Rule 4: every state key is a sheet id, and every sheet id has a key. DISAGREEMENT = defect.
  {
    const extra = [...stateIds].filter((id) => !sheetIds.has(id));
    const missing = [...sheetIds].filter((id) => !stateIds.has(id));
    const bad = [];
    if (extra.length) bad.push(`state has ids not in the sheet: ${extra.join(', ')}`);
    if (missing.length) bad.push(`sheet ids missing from state: ${missing.join(', ')}`);
    bad.length ? defect(4, bad.join('; ')) : pass(4);
  }

  // Rule 5: depends_on equals the sheet's depends_on for that id. DISAGREEMENT = defect.
  {
    const bad = [];
    for (const [id, inc] of Object.entries(increments)) {
      if (!sheetIds.has(id)) continue;               // rule 4 already flagged it
      const want = [...(sheetDeps.get(id) || [])].sort();
      const got = [...(Array.isArray(inc.depends_on) ? inc.depends_on : [])].sort();
      if (want.join(',') !== got.join(',')) {
        bad.push(`\`${id}\`: state [${got.join(', ')}] != sheet [${want.join(', ')}]`);
      }
    }
    bad.length ? defect(5, bad.join('; ')) : pass(5);
  }

  // Rule 6: status in the enum.
  {
    const bad = [];
    for (const [id, inc] of Object.entries(increments)) {
      if (!STATUSES.includes(inc.status)) bad.push(`\`${id}\`: status \`${inc.status}\``);
    }
    bad.length ? fail(6, `not a canonical status: ${bad.join('; ')}`) : pass(6);
  }

  // Rule 7: review_count and judge_count are integers in 0..3.
  {
    const bad = [];
    const okInt = (n) => Number.isInteger(n) && n >= 0 && n <= 3;
    for (const [id, inc] of Object.entries(increments)) {
      if (!okInt(inc.review_count)) bad.push(`\`${id}\`: review_count ${inc.review_count}`);
      if (!okInt(inc.judge_count)) bad.push(`\`${id}\`: judge_count ${inc.judge_count}`);
    }
    bad.length ? fail(7, `count out of 0..3: ${bad.join('; ')}`) : pass(7);
  }

  // Rule 8: branch null or a non-empty string, unique within this file.
  // (Cross-queue uniqueness needs the sibling files, out of scope for one-file validation.)
  {
    const bad = [];
    const seen = new Map();
    for (const [id, inc] of Object.entries(increments)) {
      const b = inc.branch;
      if (b === null || b === undefined) continue;
      if (!isStr(b)) { bad.push(`\`${id}\`: branch is neither null nor a non-empty string`); continue; }
      if (seen.has(b)) bad.push(`branch \`${b}\` reused by \`${seen.get(b)}\` and \`${id}\``);
      seen.set(b, id);
    }
    bad.length ? fail(8, bad.join('; ')) : pass(8);
  }
}

// Rule 9: completion, if present, only when profile is lite, with valid fields.
if ('completion' in state && state.completion !== undefined) {
  const bad = [];
  if (state.profile !== 'lite') bad.push('completion present but profile is not lite');
  const c = state.completion || {};
  if (!INTEG.includes(c.integration)) bad.push(`integration \`${c.integration}\` not one of ${INTEG.join('/')}`);
  if (!DOCS.includes(c.docs)) bad.push(`docs \`${c.docs}\` not one of ${DOCS.join('/')}`);
  bad.length ? fail(9, bad.join('; ')) : pass(9);
} else {
  pass(9);
}

// --- Report -------------------------------------------------------------------
const label = {
  1: 'sheet+conventions present', 2: 'mode valid', 3: 'profile valid',
  4: 'increment keys agree with sheet', 5: 'depends_on agrees with sheet',
  6: 'status in enum', 7: 'counts in 0..3', 8: 'branch null or unique', 9: 'completion well-formed',
  parse: 'state.json parses',
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
  console.log(`${ERR}DEFECT${R} ${statePath}: ${defects} state<->sheet disagreement(s) (reconcile), ${rejections} rejection(s)`);
  process.exit(4);
}
if (rejections) {
  console.log(`${ERR}INVALID${R} ${statePath}: ${rejections} rejection(s) to fix`);
  process.exit(1);
}
console.log(`${OK}VALID${R} ${statePath} agrees with ${sheetPath}`);
process.exit(0);
NODE
exit $?
