# Smoke test sheet

## Goal
Exercises the whole build loop end to end on one trivial increment, so the orchestration (cut, builder, reviewer, judge, document, integrate, resume) is validated without a real project's weight. Run this first to verify the loop itself, not the code it produces.

### smoke-answer: Answer function with a unit test
- depends_on: []
- description: A pure exported function returning the integer 42, no arguments, in the conventional source location (e.g. src/answer.ts exporting `answer`) with a co-located unit test (e.g. src/answer.test.ts).
- done_definition: The function exists, is exported, and its unit test passes.
- acceptance_criteria:
  - test:unit selects at least one test and passes.
  - The function returns 42 when called with no arguments.
- test_notes:
  - A correct test fails if the function returns anything but 42.
  - A correct test fails if the function takes an argument.
