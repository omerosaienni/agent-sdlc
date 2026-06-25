# Build-quick

Fastest build path: verify each increment with the type-check and unit tier only, never integration, never documentation. Delta over core build-judge-loop.md (defines roles, review/judge loops, gates, test-tier definitions, branch/PR flow, state, modes, remote presence, checkpoint, escalation, resume). This file states ONLY what build-quick changes; everything not changed here is exactly the core.

Invocation and neutralising the profile machinery:
- build-quick is invoked through its own skill (omero-build-quick), NOT selected by the `profile` field.
- DISREGARD the core's Build profile section. Do NOT read build-loop-full.md or build-loop-lite.md. Do NOT read, require or write a `profile` field (state.schema.md permits only `full` or `lite`, so writing `quick` would fail validation; an absent profile is fine and is ignored here).
- Wherever the core defers a decision to "the profile's call" (the Document role's timing, the judge's post-unit-tier verification, the integration-endpoint check, Flow steps 3 and 5, the per-increment commit contents, Monotonic green, Gates and Completion), THIS contract is that decision, resolved below.
- No completion gate, so the loop never writes a `completion` block (state.schema.md forbids one unless `profile` is explicitly lite).
- The nine canonical status values (state.schema.md) are reused unchanged; build-quick invents none.
- Everything else in state.json is exactly the core, minus `profile` and `completion`.

## Per-increment verification (type-check and unit only)
- After the reviewer approves, the judge runs the type-check gate (agent-typecheck.sh) then the unit tier (agent-tests.sh unit), and proves the unit tests are not hollow (agent-hollow.sh).
- Does NOT run the integration tier and does NOT check endpoint readiness, so no live endpoint or Docker is ever needed.
- An increment is gated by the type-check, the unit tier and the hollow-test only. There is no integration tier in this contract at all (not deferred, not run).

## Documentation and commit (no documentation)
- The document agent does NOT run, and the builder does NOT write a doc-payload.md slice. No docs/modules/ files are produced and docs/ARCHITECTURE.md is never touched. The core's missing-slice reviewer suggestion (build-judge-loop.md, Roles) does not apply: no slice is expected, so the reviewer does not flag its absence.
- On judge pass the increment reaches the `documented` status (here = verified and ready to commit, carrying no docs); the commit carries code only.
- Orchestrator then opens a PR with a remote or integrates into local main without one (build-judge-loop.md, Remote presence), and renders the post-PR checkpoint.

## Monotonic green
- Green = type-check and unit tier pass across the accumulated suite; integration is never proven, here or later. A build-quick queue is unit-green throughout.
- Per-mode rules in the core still apply, scoped to the unit tier: sequential-attended main is unit-green after every merge; parallel-attended is unit-green after the combined re-run the next judge run (or the human's final-combine run) performs (build-judge-loop.md, Monotonic green).

## Completion
- No completion gate. Nothing deferred to reconcile, so a queue is complete the moment its final increment is on main (build-judge-loop.md, Completion), by the human's PR merge with a remote or the loop's local integration without one.

## What stays exactly the core
- Reviewer loop (budget 3, bounce on a critical or major finding) and the ordering invariant (no code reaches the judge without a reviewer pass).
- Judge loop (budget 3), the hollow-test.
- One branch per increment (`feat/<id>-<kebab-title>`), one GitHub PR per increment with a remote or one local commit integrated into main without one.
- Remote detection, the checkpoint and its decision widget, escalation and escalation recovery, state.json and its resume routing, the two modes (sequential-attended and parallel-attended).
- build-quick changes only the per-increment verification depth and removes documentation; it adds nothing and relaxes none of the review or judge discipline.

Checkpoint:
- The checkpoint is the core's, rendered verbatim. In the shared checkpoint preamble (file-templates/checkpoint-*.md) the `Profile: <profile>` slot reads `build-quick` (this contract stands in for the profile).
- The lite-only completion-gate note and the `completion-docs` AWAITING MERGE row never appear, since there is no `completion` block.
- Resume routing has no completion-gate branch here: a build-quick queue with every increment merged is simply complete (see Completion).

## The tradeoff
build-quick buys the most speed (no integration tier, no endpoint, no documentation, no completion gate) for the least proof: an increment is verified at the type-check and unit level only, with integration left entirely to you outside this loop. Use it for fast inner-loop work where unit coverage is the bar; use omero-build-loop (full or lite profile) when integration or documentation must be part of the build.
