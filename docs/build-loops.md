# The build loop

The build phase delivers a sheet one increment at a time. It is a single loop with a single [per-deliverable cycle](roles.md), one set of gates, one `.building/` workspace and one checkpoint. A project-level `mode` selects between two behaviours that differ in exactly one thing: what the loop offers after a PR opens.

Both modes are attended: a human merges every PR, and the merge is the final gate.

## The per-deliverable cycle

For each deliverable: the builder implements and writes tests; the reviewer reviews (budget 3, bounce on a critical or major finding with evidence); on approval the judge runs the unit tier then the integration tier and proves the tests are not hollow; on a pass the document agent runs; the orchestrator commits code and docs and opens a PR into main. Either the review or the judge loop exhausting three attempts escalates and freezes that deliverable's dependents. This cycle is identical in both modes. See [`diagrams/build-judge-loop.svg`](diagrams/build-judge-loop.svg) and the per-deliverable state machine [`diagrams/deliverable-states.svg`](diagrams/deliverable-states.svg).

## Two modes, one difference

`mode` lives in `state.json`, set once per project and persisting across conversations. It is not an invocation flag. The loop reads it and never writes it; if it is absent the loop defaults to sequential-attended.

| | sequential-attended (default) | parallel-attended |
| --- | --- | --- |
| In flight at once | one deliverable | several |
| After a PR opens | wait; do not cut the next branch until that PR merges | you may build any ready sibling while open PRs sit unmerged |
| Each branch cut from | updated origin/main (after the previous merge) | a freshly-fetched origin/main, never stacked on a sibling |
| main greenness | green after every merge | green after the combined re-run (see below) |
| When it fits | each deliverable builds on the previous one's merged code | a wide fan-out of independent deliverables |

Everything else, the four roles, the gates, the budgets, the `.building/` layout, the hollow-test, the board and the widget mechanism, is the same. The single behavioural fork is the cut rule at the checkpoint. See [`diagrams/git-topology.svg`](diagrams/git-topology.svg) for the sequential topology and [`diagrams/parallel-topology.svg`](diagrams/parallel-topology.svg) for the parallel one.

## Parallel means eligible, not concurrent

Parallel-attended does not run builds at the same time. It is still one checkout and one build at a time, with a checkpoint between each. What "parallel" names is that a deliverable becomes **eligible** the moment all its dependencies are merged, and the loop will offer every eligible deliverable rather than forcing you to merge one before starting the next.

The win is not a wall-clock speedup. It is decoupling build order from merge order: you can build 13, 14 and 15 back to back, leaving their PRs open, and merge them as a batch when you are ready. In sequential mode each build waits behind the previous merge. Same total work, different control over when merges happen.

The trade is honest. In parallel mode green is per-branch, not per-main: each sibling is verified green only against the main it was cut from, in isolation. Two siblings that are each green alone can combine into a red main (a shared-file append, or a semantic collision the loop never sees because it never holds two siblings together). The combined suite is re-run at the next deliverable's judge run; when the merged siblings are terminal, the human runs the full suite once after the final combine. Sequential keeps main provably green after every merge and pays for it by serialising.

## The dependency graph

The sheet's `depends_on` edges form a DAG: roots at the top (deliverables with no dependencies), edges fanning down to terminals (deliverables nothing depends on). It is acyclic by schema validation, which is what guarantees the loop can never deadlock, there is always a next eligible node until everything is merged.

A deliverable is eligible when all its dependencies are merged. Merging a deliverable frees its dependents. The loop offers any eligible node; in sequential it offers them one merge at a time, in parallel it offers the whole eligible set.

The document agent already generates this graph as Mermaid into `docs/ARCHITECTURE.md` from `depends_on`. The checkpoint board is that same graph filtered by what is merged: the ready set is the eligible frontier, the blocked set is everything still waiting upstream, and the starred chain is the longest root-to-terminal path through it.

## The checkpoint

After every PR, and on entry and on reclaim after an interruption, the loop renders a checkpoint: a board, rendered verbatim from an on-disk template so it reads identically across conversations, then a fixed decision widget. The board sorts every deliverable by state into READY, AWAITING MERGE, BLOCKED and POSSIBLY STALLED, with the critical-path chain starred. See [`diagrams/checkpoint.svg`](diagrams/checkpoint.svg).

The widget shows only the applicable verbs, with Wait always available:

- **Carry on** builds the lowest-id ready deliverable, no choosing.
- **Build a specific one** lets you name which ready deliverable.
- **Merge the PR** merges (you are the gate), then the loop reconciles.
- **Resume the stalled one** resumes a possibly-stalled deliverable, routed by its actual status.
- **Wait** stops safely; nothing changes.

The only mode difference is when **Carry on** and **Build a specific one** appear. In parallel-attended they appear whenever the ready set is non-empty, so you can keep building while PRs sit open. In sequential-attended they appear only when nothing else is in flight, so an open PR suppresses them and you must merge first. The labels never reword between conversations; identical wording is the point.

If subagent dispatch is unavailable the loop degrades to one deliverable per conversation (the roles run inline, so a second build would exhaust the context); you continue by starting a fresh conversation, which reclaims the run from `state.json` and the remote.

## Tests

Two tiers. Unit tests have no external dependencies and run anywhere; integration tests need live endpoints. One test file per module under test, co-located, tier by suffix (`<module>.test.ts`, `<module>.integration.test.ts`), with shared helpers in one support module. The judge runs unit first (cheap, fail fast), then integration. A tier that should have tests but selects zero is a hollow suite and fails.

## Where the loop keeps its work

Everything the loop generates while building (state, the agents' working files, escalation records) lives under one gitignored folder, `.building/`. None of it is committed; your commits and PRs carry only code and docs. See [`building-folder.md`](building-folder.md) for the full layout.

## Validating the loop itself

Before a real build, exercise the orchestration on a trivial deliverable. [`../examples/smoke-test-sheet.md`](../examples/smoke-test-sheet.md) is a one-deliverable sheet (a function returning 42 with a unit test) that runs the whole loop quickly: branch cut, builder, reviewer, judge, document, PR, merge. If it passes cleanly the orchestration works; if it breaks you have found the problem on a trivial case.

## Recovery

The loop is robust to interruption and keeps you in control at both recovery points. After an interruption (crash, closed terminal, a new conversation continuing a run) re-running reads `state.json`, reconciles open PRs against the remote, finds where it stopped, and renders the checkpoint before doing anything; declining (Wait) is safe and changes nothing. When a deliverable escalates after three failed attempts the loop waits: you fix it on its existing branch and tell it to continue, and the fix re-enters verification from the reviewer (reviewed and judged, never waved through). Full resume and escalation-recovery behaviour is in [`../contracts/build-judge-loop.md`](../contracts/build-judge-loop.md).
