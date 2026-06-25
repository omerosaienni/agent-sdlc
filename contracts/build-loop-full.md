# Build profile: full

The default build profile. Read this together with the core contract build-judge-loop.md, which defines everything both profiles share (the roles, the review and judge loops, the gates, the test-tier and endpoint definitions, the branch and PR flow, state, modes, remote presence, the checkpoint, escalation and resume). This file states ONLY what the full profile adds: every increment is fully verified and documented before it ships, so there is no completion gate.

Selected by `profile: full` (or absent) in state.json (state.schema.md). full is the default; a queue runs full unless the human sets `profile` to lite (build-loop-lite.md). The loop never writes the field.

## Per-increment verification
- After the type-check gate and the unit tier (build-judge-loop.md, Test tiers), the judge runs the integration tier. Before running it, the judge checks the declared endpoint readiness (build-judge-loop.md, Integration endpoints); an unready endpoint is an environment block, not a rejection, and consumes no attempt.
- The judge passes an increment only if BOTH the unit tier and the integration tier pass (with the type-check clean and the hollow-test satisfied). So every increment is type-checked, unit-tested and integration-tested before it can pass.

## Documentation and commit
- On judge pass the document agent runs per increment (document-agent.md): it assembles the doc payload and the reports into docs/modules/<id>-<module-filename>.md and an idempotent docs/ARCHITECTURE.md section, before the commit. It is a producer, never a gate.
- The commit carries code and docs. The orchestrator then opens a PR with a remote or integrates into local main without one (build-judge-loop.md, Remote presence), and renders the post-PR checkpoint.

## Monotonic green
- Branch green after every commit means BOTH tiers pass across the accumulated suite (build-judge-loop.md, Monotonic green). In sequential-attended main is green (both tiers) after every merge; parallel-attended and the local-only flow follow the per-mode rules in the core.

## Completion
- No completion gate. Each increment is already integration-green and documented, so a full queue is complete the moment its final increment is on main (build-judge-loop.md, Completion).
