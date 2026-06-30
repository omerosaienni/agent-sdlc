# Build profile: lite

Delta over core build-judge-loop.md (defines roles, review/judge loops, the orchestration gates, branch/PR flow, state, modes, remote presence, checkpoint, escalation, resume). lite defers the integration tier and the per-increment document agent to a completion gate, trading per-increment thoroughness for speed. Everything else (type-check, unit-tier and hollow-test gates, reviewer, budgets, branch rule, checkpoint) is exactly the core.

- Selected by `profile: lite` in state.json (state.schema.md), human-set like `mode`, never written by the loop. Absent = full (build-loop-full.md).
- Orthogonal to `mode`: sequential-attended and parallel-attended still apply.

## Per-increment verification (integration deferred)
- After the type-check gate and the unit tier (judge.md, Test tiers), the judge STOPS: does NOT run the integration tier per increment, does NOT check endpoint readiness. So no live endpoint or Docker needed while iterating.
- Hollow-test still runs. Each increment is gated by the type-check, the unit tier and the hollow-test only.

## Documentation and commit (docs deferred)
- On judge pass the document agent does NOT run; per-module and ARCHITECTURE assembly is deferred.
- Builder still writes its doc-payload.md slice (cheap), so nothing is lost.
- Increment still reaches the `documented` status (here = verified and ready to commit); commit carries code only.
- Orchestrator then opens a PR with a remote or integrates into local main without one (build-judge-loop.md, Remote presence), and renders the post-PR checkpoint.

## Monotonic green
- Per increment, green = type-check and unit tier pass; integration not proven per increment. Integration-green is established once, at the completion gate. So a lite queue is unit-green throughout and integration-green at completion: integration is deferred much as parallel-attended defers its combined re-run (build-judge-loop.md, Monotonic green), but lite establishes it once at the end rather than at each post-merge judge run.
- In parallel-attended a lite queue also inherits parallel's per-mode green caveat: terminal siblings still need the human's final-combine run for the combined UNIT tier (build-judge-loop.md, Monotonic green), but the gate's integration run already discharges the combined integration tier. So the gate replaces only the integration half of that final combine, not the unit half.

## Completion gate (the reconciliation)
A lite feature is NOT complete until the loop runs a completion gate, before declaring the queue complete (build-judge-loop.md, Completion). Runs once, when every increment is merged. The loop records progress in state.json's `completion` block (integration: pending|passed|failed, docs: pending|pr-open|merged; state.schema.md), so a fresh conversation reclaims the gate from that block rather than re-running it (build-judge-loop.md, Resume after interruption).

Order:

1. Integration: run the full accumulated integration suite once against the finished main; it must pass, then `completion.integration` becomes passed. Endpoint needed at setup (project-setup.md proves it once) and again here, not per increment while iterating.
   - A failure is a real behaviour problem, but the offending increment is already `merged` (gate only runs once every increment is merged) and `merged` is terminal, so the loop never silently mutates it: it sets `completion.integration` to failed (distinct from pending, so a fresh conversation surfaces the failure and waits rather than silently re-running it), renders the board with the completion-gate failure note (build-judge-loop.md, Checkpoint) and stops.
   - Resolve by appending a fix increment to the sheet; the loop's on-entry sheet sync brings it into the queue as a pending increment (build-judge-loop.md, Resume after interruption). It then builds, verifies and merges through the normal per-increment cycle like any other increment.
   - That merge re-arms the gate: the loop resets `completion.integration` from failed to pending whenever it records any increment as merged while the block exists, so the next all-merged checkpoint runs the suite again.
   - A failed gate with no merge since the failure stays failed and waits.
   - No feature-level escalation record: the fix is an ordinary increment, using the ordinary machinery.
2. Documentation sweep: run the document agent across all the feature's increments from their doc-payload.md slices, producing docs/modules/* and the docs/ARCHITECTURE.md sections in one pass (document-agent.md). Feature's only documentation step, not an increment, so no entry in `increments`.
   - With a remote: sweep commits on a dedicated `docs/<feature-name>-completion` branch (a `docs`-typed name, passes the branch-naming guard) opened as one PR into main; `completion.docs` becomes pr-open and the PR appears in the board's AWAITING MERGE as the `completion-docs` row, where you merge it like any PR and the loop reconciles it by branch (build-judge-loop.md, Reconciliation), promoting `completion.docs` to merged.
   - With no remote: the loop integrates a single local docs commit into main itself, no PR, so `completion.docs` goes straight to merged.
   - Either way these docs are separate from the per-increment code commits.

The queue is complete only once `completion.integration` is passed AND `completion.docs` is merged (the sweep's docs on main: the completion docs PR merged with a remote, or the local docs commit integrated without one).

## The tradeoff
lite buys speed (no per-increment integration tier, no per-increment documentation) at the cost of per-increment integration-green and per-increment docs, both reconciled at the completion gate before the feature ships. Switch a queue to full (build-loop-full.md) for the thorough per-increment pass.
