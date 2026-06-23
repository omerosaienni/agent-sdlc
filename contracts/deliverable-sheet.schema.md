# Deliverable sheet schema

Typed interface between design and build. Design emits a sheet conforming to this. Build refuses to start unless it validates. Single source of truth. Referenced by design-partner and build-judge-loop.

## Document
- goal: one paragraph. Context only, not built against.
- deliverables: ordered list, each conforming below.

## Deliverable fields (all required, non-empty)
- id: unique short id. Used by state.json and depends_on. Carried in the heading, see Serialisation.
- title: one line. Carried in the heading, see Serialisation.
- depends_on: list of ids that must be merged before this starts. Empty if none. Drives order and dependent-freeze.
- description: what to build. Enough for a builder with no other context.
- done_definition: one line. What "exists and works" means. Acceptance criteria are checked against this, not the reverse.
- acceptance_criteria: list. Each verifiable by running something. Never opinion.
- test_notes: what tests must exercise. The behaviour a correct test fails on if the code is wrong.

## Serialisation
The sheet is markdown: a `## Goal` paragraph, then one `### <id>: <title>` heading per deliverable followed by exactly five bullet fields, in this fixed shape:

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
- ids are short and unique within the sheet (validation 2). A short per-design prefix (D1, D2, or m1, m2) is recommended, not required: it keeps ids self-identifying and, because branch names form one git namespace across design queues, makes cross-queue branches naturally distinct.

This is the exact shape build validates and state.json keys on. A sheet that varies it (a bare `### 1` heading, a separate `**id**:` bullet, bold labels) is a drift to correct, not an alternative.

## Validation (all must hold)
1. Every deliverable has all seven fields, non-empty (id and title in the heading per Serialisation, the other five as bullets).
2. ids unique.
3. Every depends_on id exists.
4. No cycle.
5. List order consistent with depends_on (never appears before a dep).
6. Every acceptance criterion runnable, not opinion.
7. Each independently buildable given its deps merged.
8. Each deliverable is in the canonical Serialisation: an `### <id>: <title>` heading (the first colon separates a colon-free, whitespace-free id from the title, which may itself contain colons) and exactly the five bullet fields with plain lowercase labels. A bare `### <id>` heading, a separate `id`/`title` bullet, bold labels or extra fields fail validation. Build refuses a sheet that does not conform.

## Excludes
No severity, budgets, commit rules, parallelism, reports. Those are build-contract concerns. Schema describes only the seam. Parallelism is derived from depends_on by the build phase; the author never thinks about it here.
