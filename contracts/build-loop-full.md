# Build profile: full

Delta over core build-judge-loop.md (defines roles, review/judge loops, the orchestration gates, branch/PR flow, state, modes, remote presence, checkpoint, escalation, resume). This file adds ONLY what full changes.

- full = default profile. Every increment is fully verified and documented before it ships, so there is no completion gate.
- Selected by `profile: full` (or absent) in state.json (state.schema.md). A queue runs full unless the human sets `profile` to lite (build-loop-lite.md). The loop never writes the field.

## Per-increment verification
- After the type-check gate and the unit tier (judge.md, Test tiers), the judge runs the integration tier.
- Before running integration, judge checks declared endpoint readiness (judge.md, Integration endpoints). Unready endpoint = environment block, not rejection, consumes no attempt.
- Judge passes an increment only if BOTH unit tier AND integration tier pass (type-check clean, hollow-test satisfied). So every increment is type-checked, unit-tested and integration-tested before passing.

## Documentation and commit
- On judge pass the document agent runs per increment (document-agent.md): assembles doc payload + reports into docs/modules/<id>.md and an idempotent docs/ARCHITECTURE.md section, before the commit. Producer, never a gate.
- Commit carries code and docs. Orchestrator then opens a PR with a remote or integrates into local main without one (build-judge-loop.md, Remote presence), and renders the post-PR checkpoint.

## Monotonic green
- Branch green after every commit = BOTH tiers pass across the accumulated suite (build-judge-loop.md, Monotonic green).
- sequential-attended: main is green (both tiers) after every merge. parallel-attended and local-only: follow the per-mode rules in the core.

## Completion
- No completion gate. Each increment is already integration-green and documented, so a full queue is complete the moment its final increment is on main (build-judge-loop.md, Completion).
