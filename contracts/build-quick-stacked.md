# Build quick stacked

Fastest UNATTENDED stacked path: verify each increment with the type-check and unit tier only, never integration, never documentation. Delta over build-stacked.md (defines the unattended posture, the incremental linear stack, the stack base, linearisation, the roles, the review/judge loops, the git-town command set, tagging, completion, state and resume). This file states ONLY what quick changes; everything not changed here is exactly build-stacked.md. It stands to build-stacked.md exactly as build-quick.md stands to build-judge-loop.md.

Invocation and scope:
- Invoked through its own skill (omero-build-quick-stacked), NOT selected by any field.
- Reads build-stacked.md's stacking behaviour but neutralises the same profile machinery build-quick.md does: no `profile` field, no `completion` block, the nine canonical statuses reused unchanged.
- Wherever build-stacked.md runs the full verification path (both tiers, per-increment docs), THIS file is the decision, resolved below.

## Per-increment verification (type-check and unit only)
- After the reviewer approves, the judge runs the type-check gate (agent-typecheck.sh) then the unit tier (agent-tests.sh unit), and proves the unit tests are not hollow (agent-hollow.sh).
- Does NOT run the integration tier and does NOT check endpoint readiness, so no live endpoint or Docker is ever needed. `blocked` (endpoint-down) never occurs.
- Acceptance criteria whose tests are integration or client are not gated by this loop, never trip it, and are not flagged judge-unreachable; their proof is the human's, outside the loop. Scoping is exactly build-quick.md, Per-increment verification.
- The unit tier is NOT exempt: the hollow-suite and hollow-test checks stay live on it.

## Documentation and commit (no documentation)
- The document agent does NOT run and the builder does NOT write a doc-payload.md slice. No docs/modules/ files, docs/ARCHITECTURE.md never touched. The reviewer does not flag a missing slice (none is expected).
- On judge pass the increment reaches `documented` (here = verified and ready to commit, carrying no docs); the commit carries code only.
- Orchestrator then opens the stacked PR (`gh pr create --base <parent>`, build-stacked.md, git-town command set) and continues stacking the next increment. No checkpoint, no pause.

## Monotonic green
- Green = type-check and unit tier pass across the accumulated stack; integration is never proven, here or later. A quick-stacked queue is unit-green throughout. The accumulation-by-stacking guarantee (build-stacked.md, Monotonic green) holds, scoped to the unit tier.

## Completion
- A feature is complete when its final increment is `pr-open` and `feature/<feature-name>` marks the tip (build-stacked.md, Completion); the epic when the last feature is complete and `epic/<epic-name>` marks the overall tip. No completion gate, nothing deferred to reconcile.

## What stays exactly build-stacked.md
- The unattended posture (no checkpoint, no merge, runs to exhaustion or escalation), the required remote, git-town owns topology.
- The stack base resolution (previous feature's tip via the epic and its tag), linearisation (scripts/stack-order.sh), the single linear stack cut with `git town append`.
- The reviewer loop (budget 3) and the ordering invariant, the judge loop (budget 3), the hollow-test.
- One stacked PR per increment via `gh pr create --base <parent>`, never `git town ship`; `git town sync --stack` on re-entry.
- Escalation halts the chain (build-stacked.md, Escalation halts the chain).
- Tags force-moved (feature/<name>, epic/<name>), state.json schema unchanged, the resume-and-partial-ship reconciliation.
- quick-stacked changes only the per-increment verification depth and removes documentation; it adds nothing and relaxes none of the review or judge discipline.

## The tradeoff
quick-stacked buys the most speed (no integration tier, no endpoint, no documentation) on the unattended stacked path, for the least proof: an increment is verified at the type-check and unit level only, with integration left to you outside this loop, on the open PRs. Use it for fast unattended stacking where unit coverage is the bar; use omero-build-full-stacked when integration or documentation must be part of the stack.
