# Board fixture: an increment id that is a Mermaid keyword

## Goal
Pin the Mermaid emission against reserved words. The id `graph` is a Mermaid flowchart
keyword, so emitting it as a bare node id (`graph["..."]`) is a parse error. board-state.sh
must prefix node ids so the graph still renders; the raw id survives only in the label.

### graph: Bare graph increment
- depends_on: []
- description: An increment whose id collides with the Mermaid grammar.
- done_definition: Exists.
- acceptance_criteria:
  - A test asserts the node renders.
- test_notes:
  - Fails if the id is emitted bare.

### run: Downstream of graph
- depends_on: [graph]
- description: Depends on the keyword-id root so an edge is emitted.
- done_definition: Exists.
- acceptance_criteria:
  - A test asserts the edge.
- test_notes:
  - Fails if the edge is wrong.
