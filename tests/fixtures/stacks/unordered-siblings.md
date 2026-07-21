# Unordered siblings fixture

## Goal
Two siblings declared out of id order (zeta before alpha), so the linearise's exact output distinguishes a lowest-id tie-break from a sheet-order one: a lowest-id tie-break emits alpha before zeta, a sheet-order tie-break would emit zeta before alpha.

### root: Foundation
- depends_on: []
- description: A foundation increment the two siblings both build on.
- done_definition: The foundation exists, is typed, and is covered by a unit test.
- acceptance_criteria:
  - The foundation unit test passes on a correct implementation.
  - The foundation exposes its declared surface for a known input.
- test_notes:
  - A wrong implementation fails the foundation unit test.
  - A wrong implementation exposes the wrong surface for a known input.

### zeta: Sibling declared first, higher id
- depends_on: [root]
- description: A sibling of alpha, both depending only on root, declared before alpha.
- done_definition: zeta exists, is typed, and is covered by a unit test.
- acceptance_criteria:
  - The zeta unit test passes on a correct implementation.
  - zeta behaves per its contract for a known input.
- test_notes:
  - A wrong implementation fails the zeta unit test.
  - A wrong implementation mishandles the zeta known input.

### alpha: Sibling declared second, lower id
- depends_on: [root]
- description: A sibling of zeta, both depending only on root, declared after zeta.
- done_definition: alpha exists, is typed, and is covered by a unit test.
- acceptance_criteria:
  - The alpha unit test passes on a correct implementation.
  - alpha behaves per its contract for a known input.
- test_notes:
  - A wrong implementation fails the alpha unit test.
  - A wrong implementation mishandles the alpha known input.

### omega: Join of both siblings
- depends_on: [zeta, alpha]
- description: A join increment depending on both siblings, so it is last in every valid order.
- done_definition: omega exists, is typed, and is covered by a unit test.
- acceptance_criteria:
  - The omega unit test passes on a correct implementation.
  - omega combines both siblings for a known input.
- test_notes:
  - A wrong implementation fails the omega unit test.
  - A wrong implementation drops one sibling for a known input.
