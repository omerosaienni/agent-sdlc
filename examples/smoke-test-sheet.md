# Smoke test sheet

## Goal
A minimal sheet that exercises the whole build loop end to end on a trivial increment, so the orchestration (branch cut, builder, reviewer, judge, document agent, PR, merge detection, resume) can be validated without the weight of a real project. Run this first when verifying the loop itself, not the code it produces.

### smoke-answer: Answer function with a unit test
- depends_on: []
- description: Add a single pure function in the project's primary language that returns the integer 42 and takes no arguments. Place it in the conventional source location for this project (e.g. src/answer.ts exporting `answer`). Add one unit test in the per-module convention (e.g. src/answer.test.ts) asserting it returns 42. No external dependencies, no integration tier needed for this increment.
- done_definition: The function exists, is exported, returns 42, and its unit test passes.
- acceptance_criteria:
  - The unit test command (test:unit) selects at least one test and passes.
  - Calling the function returns the integer 42.
  - The function takes no arguments (calling it with none returns 42).
- test_notes: The unit test must fail if the function returns anything other than 42 or takes arguments. A correct test asserts the exact return value, so a builder that returned 41 or 0 would be caught by the judge's negative run.
