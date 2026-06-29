# Board fixture: diamond DAG with an off-path tail

## Goal
A graph whose critical path is unambiguous so board-state.sh's star computation can be checked by hand. root -> two middles -> sink is the diamond (longest chains are 3 nodes: root, a middle, sink). An extra increment depending only on root is a 2-node chain, so it is NOT on the critical path and must not be starred.

### root: Foundation
- depends_on: []
- description: The root increment everything builds on.
- done_definition: Exists and is merged.
- acceptance_criteria:
  - A test asserts the foundation is present.
- test_notes: Fails if the foundation is absent.

### mid-a: Middle A
- depends_on: [root]
- description: One arm of the diamond.
- done_definition: Exists.
- acceptance_criteria:
  - A test asserts arm A.
- test_notes: Fails if arm A is wrong.

### mid-b: Middle B
- depends_on: [root]
- description: The other arm of the diamond.
- done_definition: Exists.
- acceptance_criteria:
  - A test asserts arm B.
- test_notes: Fails if arm B is wrong.

### sink: Convergence
- depends_on: [mid-a, mid-b]
- description: Converges both arms; the diamond's bottom.
- done_definition: Exists.
- acceptance_criteria:
  - A test asserts convergence.
- test_notes: Fails if convergence is wrong.

### tail: Off-path tail
- depends_on: [root]
- description: Depends only on root, nothing depends on it. A 2-node chain, off the critical path.
- done_definition: Exists.
- acceptance_criteria:
  - A test asserts the tail.
- test_notes: Fails if the tail is wrong.
