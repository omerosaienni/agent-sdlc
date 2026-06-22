# Deliverable sheet schema

Typed interface between design and build. Design emits a sheet conforming to this. Build refuses to start unless it validates. Single source of truth. Referenced by design-partner, build-judge-loop, parallel-build-loop.

## Document
- goal: one paragraph. Context only, not built against.
- deliverables: ordered list, each conforming below.

## Deliverable fields (all required, non-empty)
- id: unique short id. Used by state.json and depends_on.
- title: one line.
- depends_on: list of ids that must be merged before this starts. Empty if none. Drives order and dependent-freeze.
- description: what to build. Enough for a builder with no other context.
- done_definition: one line. What "exists and works" means. Acceptance criteria are checked against this, not the reverse.
- acceptance_criteria: list. Each verifiable by running something. Never opinion.
- test_notes: what tests must exercise. The behaviour a correct test fails on if the code is wrong.

## Validation (all must hold)
1. Every deliverable has all seven fields, non-empty.
2. ids unique.
3. Every depends_on id exists.
4. No cycle.
5. List order consistent with depends_on (never appears before a dep).
6. Every acceptance criterion runnable, not opinion.
7. Each independently buildable given its deps merged.

## Excludes
No severity, budgets, commit rules, parallelism, reports. Those are build-contract concerns. Schema describes only the seam. Parallelism is derived from depends_on by the build phase; the author never thinks about it here.
