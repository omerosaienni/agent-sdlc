# Build-quick

The fastest build path: verify each increment with the type-check and unit tier only, never integration, never documentation. Read this together with the core contract build-judge-loop.md, which defines everything this shares (the roles, the review and judge loops, the gates, the test-tier definitions, the branch and PR flow, state, modes, remote presence, the checkpoint, escalation and resume). This file states ONLY what build-quick changes; everything not changed here is exactly the core.

build-quick is invoked through its own skill (omero-build-quick), NOT through the profile mechanism. It does NOT read or write the `profile` field, and it does NOT read the core's Build profile section or the build-loop-full.md / build-loop-lite.md contracts: this file IS the per-increment verification spec. There is no completion gate, so the `completion` block of state.json never appears. Everything else in state.json (state.schema.md) is unchanged; `profile`, if present, is ignored.

## Per-increment verification (type-check and unit only)
- After the reviewer approves, the judge runs the type-check gate (agent-typecheck.sh) then the unit tier (agent-tests.sh unit), and proves the unit tests are not hollow (agent-hollow.sh). It does NOT run the integration tier and does NOT check endpoint readiness, so no live endpoint or Docker is ever needed. An increment is gated by the type-check, the unit tier and the hollow-test only; there is no integration tier in this contract at all (not deferred, not run).

## Documentation and commit (no documentation)
- The document agent does NOT run, and the builder does NOT write a doc-payload.md slice. No docs/modules/ files are produced and docs/ARCHITECTURE.md is never touched. On judge pass the increment reaches the `documented` status (here it means verified and ready to commit, carrying no docs), and the commit carries code only. The orchestrator then opens a PR with a remote or integrates into local main without one (build-judge-loop.md, Remote presence), and renders the post-PR checkpoint.

## Monotonic green
- Green means the type-check and the unit tier pass across the accumulated suite; integration is never proven, here or later. A build-quick queue is unit-green throughout. The per-mode rules in the core still apply, scoped to the unit tier: in sequential-attended main is unit-green after every merge; in parallel-attended it is unit-green after the combined re-run the next judge run (or the human's final-combine run) performs (build-judge-loop.md, Monotonic green).

## Completion
- No completion gate. There is nothing deferred to reconcile, so a queue is complete the moment its final increment is on main (build-judge-loop.md, Completion), by the human's PR merge with a remote or the loop's local integration without one.

## What stays exactly the core
The reviewer loop (budget 3, bounce on a critical or major finding), the judge loop (budget 3), the hollow-test, one branch per increment (`feat/<id>-<kebab-title>`), one GitHub PR per increment with a remote or one local commit integrated into main without one, the checkpoint and its decision widget, escalation and escalation recovery, state.json and its resume routing, and the two modes (sequential-attended and parallel-attended). build-quick changes only the per-increment verification depth and removes documentation; it adds nothing and relaxes none of the review or judge discipline.

## The tradeoff
build-quick buys the most speed (no integration tier, no endpoint, no documentation, no completion gate) for the least proof: an increment is verified at the type-check and unit level only, with integration left entirely to you outside this loop. Use it for fast inner-loop work where unit coverage is the bar; use omero-build-loop (full or lite profile) when integration or documentation must be part of the build.
