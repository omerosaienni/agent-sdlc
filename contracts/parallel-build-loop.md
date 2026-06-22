# Parallel build loop (PARKED, not deployed)

PARKED. The skill is not installed. Do not run. Reinstate only when both prerequisites hold AND the unattended posture is actually wanted:
- installs hoisted out of the loop (no mid-run install dialog),
- consequential dialogs made suppressible via pre-authorisation.
> NOTE (merge-model drift): this parked contract predates the move to one branch per deliverable cut from main with a PR straight to main, and audit-named branches (<id>-<kebab-title>). Its build/<id> naming, integration-branch references, and old .build-loop/.deliverable/reports paths must all be reconciled with build-judge-loop.md (now: branches cut from main, audit-named; all loop output under .building/) before reinstating. Parked, so not fixed in place.


Wraps build-judge-loop with level scheduling, git worktree isolation, and a serialised merge gate. Same sheet, same schema, same four roles, same reports. It adds only the parallelism around the per-deliverable loop.

## Levels
Topological from depends_on. Level 0 = empty depends_on. Level N = every deliverable whose deps are all in levels 0..N-1. Levels run in order; level N waits for N-1 to close. Deliverables in a level are independent by construction, so they build concurrently.

## Isolation
Each deliverable builds in its own git worktree on build/<id> cut from the integration head. Concurrency cap default 4; wider levels run in waves. The orchestrator seeds each worktree .claude/settings.local.json so subagents are not prompted. .gitignore covers .claude/ and .build-loop/.

## Merge gate (serialised, one passed deliverable at a time)
1. Rebase inside the worktree (git locks a branch to its worktree; rebasing from elsewhere fails "already used by worktree"): cd worktree, git fetch . integration, git rebase integration. Conflict -> merge-gate failure, re-enter the per-deliverable loop.
2. From the main checkout, merge the rebased branch into integration, run the full accumulated suite on integration.
3. Reviewer/judge gates as in build-judge-loop.
4. Green and conventions hold -> keep the merge, mark merged, remove the worktree, delete the branch. Else re-enter the loop, consume an attempt.

## Monotonic green / partial failure
Integration is green after every individual merge. An escalation freezes only its dependents; the rest of the level still merges.

## Note
This worktree layout differs from the sequential branch layout in build-judge-loop. Sequential is the live path; this is the deferred parallel design.
