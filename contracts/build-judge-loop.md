# Build judge loop

Deliver a schema-valid deliverable sheet as small, independently verified increments. Four roles, two loops, objective gates. Sequential and attended. Branch per deliverable, GitHub PR per deliverable. Consumes deliverable-sheet.schema.md (the sheet) and a project conventions file (CLAUDE.md).

## Posture
- Sequential and attended only. Parallel and unattended are parked (parallel-build-loop.md), gated on: installs hoisted out of the loop, consequential dialogs made suppressible.
- A human is present and merges every PR.

## Prerequisites: setup must have passed
The static environment (git, remote, gh, main present on the remote, matching report tooling, test-tier commands that select non-zero tests, valid configs, and that .building is gitignored so all loop output stays local) is proven once by the project setup gate (project-setup.md), not re-checked here. On entry, check for the setup receipt .building/build/setup-ok. If it is absent, STOP and tell the user to run /omero-project-setup first (the loop never runs setup itself). If the receipt's head differs from the current git HEAD, WARN that commits have landed since setup ran and suggest re-running setup (idempotent, so free), but do not hard-block. This is a heuristic for committed drift only; it does not detect uncommitted working-tree changes, so re-run setup whenever the environment may have changed regardless.
The receipt proves the ENVIRONMENT was ready at a HEAD. It does NOT prove anything about a deliverable sheet. The build loop independently validates the sheet it is about to build against deliverable-sheet.schema.md on entry (see below); the two gates (sheet, receipt) are independent and neither implies the other. The build loop owns only the DYNAMIC endpoint-liveness check (see Integration endpoints): whether the declared endpoint is up right now, which can change during a run.

## Roles
- Orchestrator (passive): sequences by dependency order, sole writer of state.json, enforces budgets, opens PRs, halts on escalation. No code, no judging.
- Builder: implements one deliverable against acceptance criteria, writes tests, follows CLAUDE.md, touches only this deliverable. No self-certify. Observes runtime behaviour only through the project's committed runnable surface (the runnable examples or entry points the acceptance criteria invoke, and the test tiers run through the agent test runner), never a throwaway executable script written outside the source tree to inspect it, which is an untracked oracle the reviewer and judge never see. To see an error shape or a runtime value, add a temporary log or scratch test case inside the deliverable and run it through that surface, then remove it before handoff. Also writes its documentation slice (purpose, public interface, gotchas) to .building/work/<branch-name>/doc-payload.md per doc-payload.schema.md; a missing slice does not block, the document agent degrades, but the reviewer notes it as a non-blocking suggestion.
- Reviewer: owns the code. Informed context (reads the codebase). Checks conventions, architecture/patterns, scope, code-level defects, and test-tier classification. Can bounce to builder. Writes a report each completed pass.
- Judge: owns behaviour. Fresh context per review. Runs tests itself, does not trust reports. Checks acceptance criteria met, tests genuinely pass, hollow-test by negative run. Writes a pass report only on pass. Does NOT check conventions, style, or architecture.
- Document: runs after the judge passes, before the PR. Produces per-module and project documentation from the doc payload and the reports. A producer, not a gate; never blocks a passed deliverable (document-agent.md). Named to sit parallel with Builder, Reviewer, and Judge; "the document agent" in prose refers to this role.

## Severity (pinned)
- critical: breaks build, corrupts data, security hole, or the core promise fails.
- major: correctness/robustness gap, main path untested, hollow test, evidence-backed convention breach, scope breach, named anti-pattern, concrete defect, test-tier misclassification.
- minor: style, naming, polish. Logged, never blocks, never consumes a loop.

## Reviewer rules
- Two outputs: a record (for the human, non-blocking) and a bounce (to the builder).
- Bounce only on critical/major in evidence categories: conventions (cite CLAUDE.md), architecture (named anti-pattern), scope (touched another deliverable), concrete defect (leak, unhandled error, race, N+1, measured slowness), test-tier misclassification (a test with an external dependency placed in the unit tier, OR a test not named per the per-module convention: named after the module under test, co-located, tier by suffix, helpers in the shared support module).
- An issue may bounce only if tied to a category with evidence. Everything else is record-only and cannot bounce.
- Evidence bounces, opinion suggests. Suggestions (efficiency, readability beyond conventions, alternatives) go in the report, never to the builder.
- Readability is a convention concern (cite CLAUDE.md or eslint/prettier). Taste beyond that does not bounce.
- Efficiency: concrete cost (stated requirement, known-bad algorithm on known-large data, or measured) = major. Speculative = suggestion.

## Test tiers
- Two tiers: unit (no external dependencies, fast) and integration (needs live endpoints, slow).
- The project declares two test tiers: a unit tier and an integration tier (conventionally the npm scripts test:unit and test:integration, which are the human verbose path). The judge does NOT hardcode test globs; the tiers are driven through declared configs. The split mechanism (naming, directories) is the project's choice; the convention is: name a test file after the module under test, in the same directory, with the tier as a suffix (src/examples/crud.ts has src/examples/crud.test.ts for unit and src/examples/crud.integration.test.ts for integration). ONE file per module per tier, never two shared monolith files (those collide across branches and overwrite). Shared test helpers live in one support module (e.g. src/test-support/), imported not duplicated. The reviewer checks tests are in the right file and tier.
- For its repeated verification runs (each judge cycle) the judge invokes the project's agent test runner, ./scripts/agent-tests.sh <tier>, placed and proven by the setup gate (which places and proves the hollow-check runner ./scripts/agent-hollow.sh on the same footing; the hollow-test check's negative and restore-verify runs go through agent-hollow.sh, which drives this same runner internally, see Gates). It prints one terse summary line on pass and the full output on failure, so a passing run costs a few tokens of context rather than the whole test dump. It drives the same two tiers through the same configs as the human commands; only the verbosity differs. The judge's pass REPORT still draws coverage, inventory and quality signals from the full tooling (a single coverage run plus tsc and lint); the terse runner is for the repeated pass/fail verification, not a replacement for the report's measured data.  The judge calls the runner as one bare command and relies on its terse line and exit code; it never appends shell to the call (no `; echo` of the exit status, no `| tail`), which would recreate a compound command and can truncate the full failure output the runner prints on purpose.
- Order: the judge runs the unit tier FIRST. If unit fails, reject without running integration (units are cheap; fail fast on them). The agent runner's `both` mode enforces this order and short-circuit; the judge runs a single tier only for the negative runs, where it isolates one tier to prove a test fails when the code is wrong.
- If unit passes, run the integration tier. The judge passes only if BOTH tiers pass.
- A tier with no tests, or that the project does not declare at all, is a vacuous pass ONLY where the deliverable genuinely has no behaviour for that tier. A tier that SHOULD have tests but selects zero is a hollow suite and is a hard fail, re-checked by the judge every deliverable (setup proves selection once at the start, but a later deliverable can reintroduce a hollow tier through a misclassified test or a config drift, so the judge re-checks the selected count each run, it is free since it already reads the count).
- The reviewer checks tier classification: a test with an external dependency MUST be in the integration tier, never the unit tier, so the unit tier stays dependency-free and run-anywhere. Misclassification is a major.

## Integration endpoints
- Integration endpoints (e.g. a Mongo replica set) are an attended prerequisite the human provides, like gh auth. The loop does not start them.
- The project declares, in CLAUDE.md, for each endpoint: a readiness check and a bring-up command.
- Before running the integration tier, the judge checks the declared readiness. If an endpoint is not ready, the judge does NOT run integration: it raises an ENVIRONMENT BLOCK, reports the project's bring-up command, and waits for the human to bring the endpoint up and confirm, then re-checks and continues. An environment block is NOT a behaviour rejection and does NOT consume a judge attempt. It never emits a raw connection error as a verdict.
- The agent runner distinguishes a test failure (a tier ran and a test failed: a behaviour rejection that returns to the builder and consumes a judge attempt) from an environment failure (a tier could not run at all, e.g. a broken or missing config, absent tooling: the runner exits 3). An exit-3 result is handled as an ENVIRONMENT BLOCK on the same terms as an unready endpoint: it does NOT consume a judge attempt and is never reported as a behaviour rejection. The distinction matters because a broken environment is not the builder's defect.

## Flow (per deliverable)
1. Builder implements, writes builder channel.
2. Review loop, budget 3: reviewer reviews the full deliverable, writes a report each pass; bounce to builder on critical/major, else approve.
3. On approve: judge runs (behaviour only): unit tier, then integration tier.
4. Judge loop, budget 3 (separate): each cycle = builder fixes -> reviewer delta-review (the change only; reviewer has prior context) -> judge. A delta-review bounce OR a judge rejection both consume the cycle's one attempt and return findings to the builder.
5. On judge pass: judge writes the pass report (to the local, gitignored reports area). Then the document agent runs (document-agent.md): it assembles the doc payload plus the reviewer and judge reports into docs/modules/<id>-<module>.md and an idempotent section of docs/ARCHITECTURE.md. It is a producer, not a gate, and never blocks: the deliverable commits and the PR opens regardless of documentation outcome, with any gaps marked. Orchestrator opens a PR into main carrying code and docs only (the deliverable, what actually ships). Reports are NOT committed; they stay local (see State and channels). Attended: human reviews the code and docs and merges it (the per-deliverable checkpoint). Auto-merge only in unattended (parked).
6. Either loop exhausts 3 -> escalate to human, do not commit, do not advance, freeze dependents.

## Ordering invariant (inviolable)
No code reaches the judge without a prior reviewer pass. Holds in step 2 and in every judge cycle (delta-review before judge). The reviewer is the only conventions gate (the judge does not check them), so any relaxation reopens the conventions hole. Never relax for efficiency.

## Monotonic green
Branch green after every commit. A commit may not lower greenness. The judge runs the full accumulated suite, unit tier then integration tier, across every merged deliverable so far, not just this deliverable's tests. An earlier deliverable cannot be silently broken by a later one. Green means both tiers pass. Because branches are cut sequentially (the next deliverable's branch is cut from main only after the previous deliverable's PR is merged, see below), the branch the judge tests already contains all prior merged work, so "accumulated suite green" holds on main itself, not merely at cut time.

## Branch and PR
- One branch per deliverable, cut fresh from main, named after the work: <id>-<kebab-title> (e.g. d03-connection-helper), so the branch list is an audit trail. No worktree (worktrees belong to parallel-build-loop.md only). Branches are cut sequentially: the next deliverable's branch is cut from main only after the previous deliverable's PR has merged, so each branch starts from all previously merged deliverables and the accumulated suite is genuinely green on main. If a branch of the target name already exists from an abandoned or escalated run, the orchestrator reports it and does not silently reuse or overwrite it; the human resolves it before the loop proceeds.
- Code and docs/ are what the commit carries. All loop output lives under .building/ (gitignored, never committed), so the commit is exactly the deliverable: code plus docs.
- On pass: the agents' records already sit in .building/work/<branch-name>/ (no copy step, they are the record). Stage only code and docs, single commit, open a PR into main.
- The PR carries code and docs only. The code and docs are the review surface (what actually ships); the judge's pass is the gate, and the reports stay local under .building/ as diagnostics you can consult if something looks off.
- Attended: the human reviews and merges the PR; this is the per-deliverable checkpoint (see Attended checkpoint for how the orchestrator waits for and confirms the merge before advancing).
- Judge meaning: authoritative up to the merge; the human merge is the final gate. Unattended (parked): judge pass plus green full suite triggers auto-merge.

## Project completion
Every deliverable PRs into main directly; there is no integration branch. main accumulates verified deliverables one merge at a time and is always green. The project is complete when the final deliverable's PR is merged into main. Each PR is one deliverable's audit record.

## State and channels (file-based, no memory layer)
All loop output lives under a single gitignored folder, .building/, with this structure:

```
.building/
  build/                          the loop's own state
    state.json
    setup-ok                      the setup receipt
  work/                           the agents' working files, one folder per unit
    <branch-name>/                keyed by the audit-named branch (e.g. d3-connection-helper)
      builder.md
      review-pass-N.md
      judge.md                    on pass only
      doc-payload.md
      escalations/                only if this unit escalated
        <YYYY-MM-DD-HHMM>.md
  escalations/                    a flat chronological index, symlinks only
    <YYYY-MM-DD-HHMM>.md  ->  ../work/<branch-name>/escalations/<YYYY-MM-DD-HHMM>.md
```

- .building/build/state.json: orchestrator sole writer. Per-unit status, one of: pending, building, in-review, in-judgement, documented, pr-open, merged, escalated, blocked. (Mapping to stages: building is the builder; in-review is the review loop; in-judgement is the judge loop; documented is after the judge passes and the document agent has run; pr-open is the PR awaiting your merge; merged is the confirmed merge into main; escalated and blocked are the two interruption states.) Also: review loop count, judge loop count, branch name. The sheet is read-only, never written. This enum is the canonical state set; the deliverable-states diagram renders exactly these states and must match.
- .building/build/setup-ok: the setup receipt (written by the setup gate, read by the loop on entry).
- .building/work/<branch-name>/: the agents' working files for one unit, keyed by its audit-named branch. builder.md, review-pass-N.md, judge.md (on pass), doc-payload.md. These ARE the record; there is no separate reports copy. Channels and records are the same files (machine reads them as channels, human reads them as records).
- Re-running a unit overwrites its work folder in place: only the latest run is kept, not a dated history. Within a single run, the review passes accumulate (review-pass-1, review-pass-2, ...).
- Escalation: the record is written ONCE to .building/work/<branch-name>/escalations/<YYYY-MM-DD-HHMM>.md (the single source of truth, beside the failed passes). A relative symlink of the same name is created in .building/escalations/ pointing at it, giving a flat chronological index across all units. The symlink MUST be relative (target starts ../work/...) so it survives the folder being moved or renamed; an absolute symlink breaks on a move. The symlink is a pointer, never a copy.
- Nothing under .building/ is ever committed. The whole folder is gitignored with one rule: .building/. The commit and PR carry only code and docs/.

## Record contents (the files under work/<branch-name>/)
- Reviewer record (review-pass-N.md), each completed pass: what changed; architecture/pattern/idiom and why; blocking findings (or none); suggestions (efficiency primary, the human comprehension layer); outcome.
- Judge record (judge.md), on pass only: acceptance-criteria results; per-tier coverage (unit and integration separately, lines/branches/functions/statements plus uncovered) from tooling; per-tier test inventory (count, per-file, pass/skip, durations) from tooling json; per-function -> test -> one-line mapping, labelled asserted not measured; quality signals (tsc errors, eslint counts, hollow-test result, slowest test). Coverage is always shown with the hollow-test result, never alone. Coverage is per tier, not merged.
- Templates: templates/reviewer-report.md, templates/judge-report.md.

## Gates
- Commit only on green. Never commit then judge. Failed work stays uncommitted. The judge's green IS the commit gate: the orchestrator does not re-run the suite before committing, because the only change to the tree between judgement and commit is the document agent's docs, which cannot affect test results.
- Conventional commits.
- Hollow-test check: the judge proves a test fails when the code is wrong (negative run), run as one committed command per check: ./scripts/agent-hollow.sh <tier> <src-file> <test-file> <old-string> <new-string>. The judge supplies only the fault (an exact behavioural change that compiles, flip a value or comparison); the script owns the rest. It backs the file up under .building/ as a filesystem copy, which works on the UNTRACKED files a new deliverable adds where git checkout, git restore and git stash silently no-op and leave the break in the tree. It applies the fault, runs the tier scoped to this deliverable's own test file, classifies, restores from an exit trap whatever happens, then re-verifies green. Verdict by exit code: 0 the test caught the fault (asserts), 1 the tier stayed green so the test is HOLLOW (a major, deliverable fails), 2 the fault ran no tests so it was not behavioural (re-pick), 3 the file did not return to green after restore (halt). The check clears only on exit 0; a green negative run is the hollow failure, never a pass. The reviewer may suspect on read; the judge proves on run.
- Scope guard: builder touches only this deliverable (reviewer owns).
- Idempotent infra: any setup script is safe to run twice.
- Blocked halts the chain; an escalated deliverable freezes its dependents.

## Scripts and permissions
- Multi-step operations are committed named scripts under scripts/, invoked as a single command, not inline compound bash. Allowlist Bash(./scripts/*:*) plus a minimal atomic set.
- Side-effecting scripts (install, network, destructive) announce intent and ask via an informative dialog before acting, even under the allowlist. Repo-local read-only scripts run silently. Consent is passed explicitly (a flag such as --yes), never a hidden environment variable.

## Resume after interruption
The loop can be interrupted (crash, closed terminal, exhausted context). state.json is the recovery record. On re-entry, BEFORE doing anything, the orchestrator reads state.json and determines the resume point: the first deliverable whose status is not merged. It reports to the human where the loop stopped (the deliverable, its status, attempt counts, and how many are merged) and what resuming will do, then ASKS for confirmation before resuming. It does not auto-resume and does not start over. If the human declines, the loop stops without changing state.json or any branch, so the human can inspect or intervene manually and re-run later; declining is safe and non-destructive.
Per-status resume action: pending = cut the branch and build; building = resume the builder on the existing branch as-is; in-review = resume the review loop at the recorded count; in-judgement = resume the judge loop at the recorded attempt; documented = open the PR (work passed, PR not yet opened); pr-open = check whether the PR merged using the same merge-confirmation mechanism as the Attended checkpoint (it is one mechanism entered at two points: first-time after opening the PR, and again on re-entry after an interruption) and either advance or keep waiting; escalated = the loop is waiting for the human (see Escalation recovery); blocked = the endpoint was down, re-check readiness and continue. If a deliverable's branch exists but its status implies it should not, report the conflict and ask; never silently reuse or delete a branch.

## Escalation recovery
When a deliverable escalates (either loop exhausted 3), the loop does not abandon it. It WAITS. The deliverable's branch and its .building/work/<branch-name>/escalations/ record is left in place. The human fixes the deliverable on its existing branch (using the record: the outstanding findings, what each attempt tried), then tells the loop to continue. On continue, the orchestrator does NOT reset the work; it re-enters verification for that deliverable from the reviewer (the ordering invariant still holds: human-fixed code is reviewed, then judged, before it can pass), and on pass proceeds normally to document, PR, merge. The human may instead tell the loop to abandon the deliverable, which freezes it and its dependents and stops the run; that is an explicit human decision, never the loop's. Escalation never silently drops work.
## Escalation record
Written to .building/work/<branch-name>/escalations/<YYYY-MM-DD-HHMM>.md, with a relative symlink of the same name in .building/escalations/. It names which loop exhausted (review or judge) and carries that loop's per-pass history: the deliverable and its criteria, the outstanding critical/major findings, what each attempt tried and why it was rejected, a recommendation. A judge-loop escalation additionally surfaces any delta-review findings from the fix attempts. An environment block is reported separately and is never part of an escalation record.

## Attended checkpoint
The waiting PR per deliverable is the checkpoint (it replaces a per-level pause). The human reviews the reports in the PR and merges. After opening the PR, the orchestrator WAITS: it does not cut the next deliverable's branch until it has confirmed the PR is merged. It confirms either by the human saying so in-session or by checking the PR state (gh pr view --json state,mergedAt). Only a confirmed merge advances the loop; an open or closed-unmerged PR holds it. This is what makes the sequential-cut rule and the green-on-main guarantee real rather than nominal: the next branch is cut from a main that provably contains this deliverable.

## Conventions
British English. No em dashes.
