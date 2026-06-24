# Increment sheet schema

Typed interface between design and build. Design emits a sheet conforming to this. Build refuses to start unless it validates. Single source of truth. Referenced by design-partner and build-judge-loop.

## Vocabulary (canonical, used across every contract)
- Epic: the whole program or product. Held by the human, not modelled by the design or build phases. The design partner may discuss it but writes no file for it.
- Feature: a shippable whole (a sprint's worth of work, e.g. Products). One feature = one sheet = one build queue = one folder under `.building/features/<feature-name>/`. A feature is "done" when all its increments are merged to main with no missing parts.
- Increment: an item that makes up a feature (e.g. Products API, then Products UI). The mergeable unit: one branch, one commit, one PR into main, with its own depends_on. A feature is delivered as an ordered set of increments.
- depends_on: an ordering edge between increments WITHIN one feature sheet. Cross-feature order (Orders needs Customers merged first) is the human's to sequence and is recorded in prose in the feature's goal, not as a machine edge.

This sheet describes ONE feature: a `## Goal` paragraph plus the ordered list of increments that deliver it.

## Document
- goal: one paragraph. Context only, not built against. If this feature assumes another feature is already merged to main, state that here in prose.
- increments: ordered list, each conforming below.

## Increment fields (all required, non-empty)
- id: unique short id. Used by state.json and depends_on. Carried in the heading, see Serialisation.
- title: one line. Carried in the heading, see Serialisation.
- depends_on: list of ids that must be merged before this starts. Empty if none. Drives order and dependent-freeze.
- description: what to build. Enough for a builder with no other context.
- done_definition: one line. What "exists and works" means. Acceptance criteria are checked against this, not the reverse.
- acceptance_criteria: list. Each verifiable by running something. Never opinion.
- test_notes: what tests must exercise. The behaviour a correct test fails on if the code is wrong.

## Serialisation
The sheet is markdown: a `## Goal` paragraph, then one `### <id>: <title>` heading per increment followed by exactly five bullet fields, in this fixed shape:

```
### <id>: <title>
- depends_on: [<id>, <id>]
- description: <enough for a builder with no other context>
- done_definition: <one line>
- acceptance_criteria:
  - <runnable criterion>
  - <runnable criterion>
- test_notes: <the behaviour a correct test fails on if the code is wrong>
```

- The heading carries id and title: the id is the token before the first colon, the title is the text after it. There is NO separate `id` or `title` bullet, a second copy can disagree with the heading.
- Field labels are plain lowercase, exactly depends_on, description, done_definition, acceptance_criteria, test_notes. No bold, no reordering, no extra fields.
- depends_on is an inline bracketed list, ids comma-separated, `[]` when empty.
- acceptance_criteria is the only multi-value field: a nested bullet list, one runnable criterion per line.
- ids are short and unique within the sheet (validation 2). A short per-feature prefix (e.g. `prod-api`, `prod-ui`) is recommended, not required: it keeps ids self-identifying and, because branch names form one git namespace across feature queues, makes cross-queue branches naturally distinct.

This is the exact shape build validates and state.json keys on. A sheet that varies it (a bare `### 1` heading, a separate `**id**:` bullet, bold labels) is a drift to correct, not an alternative.

## Validation (all must hold)
1. Every increment has all seven fields, non-empty (id and title in the heading per Serialisation, the other five as bullets).
2. ids unique.
3. Every depends_on id exists.
4. No cycle.
5. List order consistent with depends_on (never appears before a dep).
6. Every acceptance criterion runnable, not opinion.
7. Each increment independently buildable and mergeable given its deps merged. The feature as a whole is the shippable unit; an individual increment may be a partial step toward it (a read API before its UI) and need not be a complete user-facing feature on its own, only buildable, testable and mergeable to a green main.
8. Each increment is in the canonical Serialisation: an `### <id>: <title>` heading (the first colon separates a colon-free, whitespace-free id from the title, which may itself contain colons) and exactly the five bullet fields with plain lowercase labels. A bare `### <id>` heading, a separate `id`/`title` bullet, bold labels or extra fields fail validation. Build refuses a sheet that does not conform.

## Excludes
No severity, budgets, commit rules, parallelism, reports. Those are build-contract concerns. Schema describes only the seam. Parallelism is derived from depends_on by the build phase; the author never thinks about it here. Epic-level grouping of features is the human's; this schema describes one feature.
