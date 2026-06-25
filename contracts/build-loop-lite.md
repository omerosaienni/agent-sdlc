# Build profile: lite

A fast iteration profile. Read this together with the core contract build-judge-loop.md, which defines everything both profiles share (the roles, the review and judge loops, the gates, the test-tier and endpoint definitions, the branch and PR flow, state, modes, remote presence, the checkpoint, escalation and resume). This file states ONLY what lite changes: it defers the integration tier and the per-increment document agent to a completion gate, trading per-increment thoroughness for speed. Everything else, the type-check, unit-tier and hollow-test gates, the reviewer, the budgets, the branch rule, the checkpoint, is exactly the core.

Selected by `profile: lite` in state.json (state.schema.md), human-set like `mode` and never written by the loop; absent means full (build-loop-full.md). Orthogonal to `mode`: sequential-attended and parallel-attended still apply.

## Per-increment verification (integration deferred)
- After the type-check gate and the unit tier (build-judge-loop.md, Test tiers), the judge STOPS: it does NOT run the integration tier per increment and does NOT check endpoint readiness, so no live endpoint or Docker is needed while iterating. The hollow-test still runs. Each increment is gated by the type-check, the unit tier and the hollow-test only.

## Documentation and commit (docs deferred)
- On judge pass the document agent does NOT run; the per-module and ARCHITECTURE assembly is deferred. The builder still writes its doc-payload.md slice (cheap), so nothing is lost. The increment still reaches the `documented` status (here it means verified and ready to commit), and the commit carries code only. The orchestrator then opens a PR with a remote or integrates into local main without one (build-judge-loop.md, Remote presence), and renders the post-PR checkpoint.

## Monotonic green
- Per increment, green means the type-check and unit tier pass; integration is not proven per increment. Integration-green is established once, at the completion gate. So a lite queue is unit-green throughout and integration-green at completion, the same shape as parallel-attended's deferred combined re-run (build-judge-loop.md, Monotonic green).

## Completion gate (the reconciliation)
A lite feature is NOT complete until the loop runs a completion gate, before declaring the queue complete (build-judge-loop.md, Completion):
1. Integration: run the full accumulated integration suite once against the finished main; it must pass. A failure is a normal behaviour rejection, fixed on the increment that introduced it and re-judged, before completion. The endpoint is needed once, here, not while iterating.
2. Documentation sweep: run the document agent across all the feature's increments from their doc-payload.md slices, producing docs/modules/* and the docs/ARCHITECTURE.md sections in one pass (document-agent.md). The sweep's docs are committed at completion (a docs PR with a remote, a local docs commit without one), separate from the per-increment code commits.

The queue is complete only once that integration run is green and the docs are produced.

## The tradeoff
lite buys speed (no per-increment integration tier, no per-increment documentation) at the cost of per-increment integration-green and per-increment docs, both reconciled at the completion gate before the feature ships. Switch a queue to full (build-loop-full.md) for the thorough per-increment pass.
