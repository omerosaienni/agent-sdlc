# Increment sheet schema

Typed interface between design and build. Design emits a sheet; build refuses to start unless it validates. Single source of truth. Referenced by design-partner and build-judge-loop.

## Vocabulary (canonical, used across every contract)
- Epic: whole program or product. Human-held, not modelled by design or build. Design partner may discuss it but writes no file.
- Feature: a shippable whole (a sprint's worth, e.g. Products). One feature = one sheet = one build queue = one folder `.building/features/<feature-name>/`. Done when all its increments are merged to main with no missing parts.
- Increment: an item making up a feature (e.g. Products API, then Products UI). The mergeable unit: one branch, one commit, one PR into main, own depends_on. A feature is delivered as an ordered set of increments.
- depends_on: ordering edge between increments WITHIN one sheet. Cross-feature order (Orders needs Customers merged first) is the human's to sequence, recorded in prose in the feature goal, not as a machine edge.

This sheet describes ONE feature: a `## Goal` paragraph plus the ordered list of increments delivering it.

## Document
- goal: one paragraph. Context only, not built against. If this feature assumes another is already merged to main, state that here in prose.
- increments: ordered list, each conforming below.

## Increment fields (all required, non-empty)
Each field has ONE job and states it ONCE. The reader is an AI builder that reads every field, so cross-field repetition is pure cost: state a fact in the field that owns it, never echo it in another. The sheet is the verdict of the design, not a re-explanation; terse and scannable, not defensive prose.

- id: `<feature>_<NN>-<increment>`, e.g. `claude-metrics_03-metrics-persist`. The feature stem (the kebab feature name) and `_` scope it; `NN` is a two-digit display-order number for scanning and sorting only, NOT a build-order source (depends_on alone orders the build, validation 5); `<increment>` is a short kebab name. The whole string is carried verbatim by state.json keys, depends_on, the doc file (document-agent.md) and the branch (build-judge-loop.md); nothing rewrites it. Carried in the heading (see Serialisation).
- title: one line. Carried in the heading (see Serialisation).
- depends_on: list of ids that must be merged before this starts. Empty if none. Drives order and dependent-freeze.
- description: the instruction, what to build. Enough for a builder with no other context, no more. Does not restate the done bar or the criteria.
- done_definition: one line, the done bar. The criteria are checked against this, not the reverse. Names what "done" means, not how it is tested (that is the criteria) nor what to build (that is the description).
- acceptance_criteria: list, the runnable checks. Each verifiable by running something, never opinion. The only field carrying the runnable proof; the others do not duplicate it.
- test_notes: list, the failure behaviours a correct test catches (what a wrong implementation breaks). One note per behaviour, never crammed with "or" into one line. Not a restatement of the criteria, the negatives they imply. If an increment has many independent failure modes, that is a signal it may be too big.

## Serialisation
Markdown: a `## Goal` paragraph, then one `### <id>: <title>` heading per increment followed by exactly five bullet fields, in this fixed shape:

```
### <id>: <title>
- depends_on: [<id>, <id>]
- description: <the instruction, once; no echo of the done bar or criteria>
- done_definition: <the done bar, one line>
- acceptance_criteria:
  - <runnable criterion>
  - <runnable criterion>
- test_notes:
  - <failure behaviour, one per line>
  - <failure behaviour, one per line>
```

Worked example (dense, each field stating its one thing once):

```
### smoke-answer: Answer function with a unit test
- depends_on: []
- description: A pure exported function returning the integer 42, no arguments, in the conventional source location with a co-located unit test.
- done_definition: The function exists, is exported, and its unit test passes.
- acceptance_criteria:
  - test:unit selects at least one test and passes.
  - The function returns 42 when called with no arguments.
- test_notes:
  - A correct test fails if the function returns anything but 42.
  - A correct test fails if the function takes an argument.
```

- Heading carries id and title: id is the token before the first colon, title is the text after it. NO separate `id`/`title` bullet (a second copy can disagree with the heading).
- Field labels plain lowercase, exactly depends_on, description, done_definition, acceptance_criteria, test_notes. No bold, no reordering, no extra fields.
- depends_on: inline bracketed list, ids comma-separated, `[]` when empty.
- acceptance_criteria and test_notes: nested bullet lists, one item per line (the two multi-value fields). The label line carries no inline value; the items follow as indented bullets.
- ids unique within the sheet (validation 2) and in the `<feature>_<NN>-<increment>` grammar the id field defines. The feature stem makes every id self-identifying and, because branch names form one git namespace across feature queues, makes cross-queue branches distinct by construction (no collision fallback needed).

This is the exact shape build validates and state.json keys on. A variant (bare `### 1`, separate `**id**:` bullet, bold labels) is a drift to correct, not an alternative.

## Validation (all must hold)
1. Every increment has all seven fields, non-empty (id and title in the heading per Serialisation, the other five as bullets).
2. ids unique.
3. Every depends_on id exists.
4. No cycle.
5. List order consistent with depends_on (never appears before a dep).
6. Every acceptance criterion runnable, not opinion.
7. Each increment independently buildable and mergeable given its deps merged. The feature as a whole is the shippable unit; an individual increment may be a partial step toward it (a read API before its UI) and need not be complete user-facing on its own, only buildable, testable and mergeable to a green main.
8. Each increment in the canonical Serialisation: an `### <id>: <title>` heading (first colon separates a colon-free, whitespace-free id from the title, which may itself contain colons) and exactly the five bullet fields with plain lowercase labels. A bare `### <id>` heading, a separate `id`/`title` bullet, bold labels or extra fields fail validation. Build refuses a non-conforming sheet.

## Validation tooling
- Enforced mechanically by `scripts/validate-sheet.sh <sheet>`: rules 1-5, 8, plus goal present-and-non-empty.
- The script is the source of truth for those checks. On disagreement with this prose, the script is what runs: fix the prose. Rules here are the spec, the script is the gate (mirrors claude-rules/omero-git-authorship.md).
- Parse keys only on the two fixed tokens (`### <id>: <title>` heading, `depends_on: [...]` bullet), so densifying the prose fields needs no change here.
- NOT checked (judgement, the design partner's): rule 6 runnable-not-opinion, rule 7 independently-buildable, goal usefulness. A clean run is necessary, not sufficient. Design-level soundness across increments (contradictions, dead-code cuts, hidden multi-increments) is the design review's, not this script's: design-review.md.
- Exits: 0 valid, 1 rejection (fixable), 3 node absent, 4 structural defect, 64 usage. A defect outranks a rejection when both are present.
- Defect vs rejection: the DAG is the law. A cycle (rule 4) or no increments = non-DAG/non-sheet = structural DEFECT (exit 4, regenerate upstream, an upstream-producer bug). Every other failure = a locatable REJECTION (exit 1); a dangling depends_on (rule 3) is a typo in an edge, still a DAG, so a rejection.
- Fixtures: tests/fixtures/sheets/ (valid + one per failing rule), run by tests/run.sh and the tests workflow on every PR into main.

## Excludes
No severity, budgets, commit rules, parallelism, reports. Those are build-contract concerns; schema describes only the seam. Parallelism is derived from depends_on by the build phase; the author never thinks about it here. Epic-level grouping of features is the human's; this schema describes one feature.
