# Build judge loop

Deliver a schema-valid deliverable sheet as small, independently verified increments. Four roles, a review loop and a judge loop, objective gates. Attended: a human merges every PR. Two modes, sequential-attended and parallel-attended, read from `mode` in state.json (see Modes). Branch per deliverable, GitHub PR per deliverable. Consumes deliverable-sheet.schema.md (the sheet) and a project conventions file (CLAUDE.md).

## Posture
- Attended only: a human is present and merges every PR, which is the final gate. Unattended operation (auto-merge on a green pass) is out of scope and not built.
- Two modes, both attended, selected by `mode` in state.json: sequential-attended (default) and parallel-attended (see Modes). They share every role, gate, budget, the .building layout and the hollow-test; they differ in one thing only, the cut-and-checkpoint behaviour after a PR opens.

## Modes
`mode` is a project-level setting in state.json (e.g. "sequential-attended"). It is set once per project and persists across conversations; it is not an invocation flag. The loop reads it on entry and at every checkpoint and never writes it. If `mode` is absent, default to sequential-attended and say so.

Two values, both attended:
- sequential-attended (default): one deliverable in flight at a time. After a PR opens the loop waits; it does not cut the next branch until that PR is merged, and cuts the next branch from the updated origin/main. main is green after every merge.
- parallel-attended: several deliverables may be in flight at once. After a PR opens you may build any ready sibling while open PRs sit unmerged; every branch is cut fresh from a freshly-fetched origin/main, never stacked on a sibling. This decouples build order from merge order. It is not a wall-clock speedup: one checkout, one build at a time, with a checkpoint between each.

The single behavioural fork is the cut rule at a checkpoint (see Checkpoint, the decision widget). Readiness, the board, the widget mechanism, the roles, the gates, resume routing and the hollow-test are identical in both modes.

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
- Bounce only on critical/major in evidence categories: conventions (cite CLAUDE.md), architecture (named anti-pattern), scope (touched another deliverable), concrete defect (leak, unhandled error, race, N+1, measured slowness), test-tier misclassification (a test with an external dependency placed in the unit tier, OR a gating test placed outside the declared tiers, behind a side command the judge never runs, OR a test not named per the per-module convention: named after the module under test, co-located, tier by suffix, helpers in the shared support module).
- An issue may bounce only if tied to a category with evidence. Everything else is record-only and cannot bounce.
- Evidence bounces, opinion suggests. Suggestions (efficiency, readability beyond conventions, alternatives) go in the report, never to the builder.
- Readability is a convention concern (cite CLAUDE.md or eslint/prettier). Taste beyond that does not bounce.
- Efficiency: concrete cost (stated requirement, known-bad algorithm on known-large data, or measured) = major. Speculative = suggestion.

## Test tiers
- Two tiers, no third. A test's tier is decided by what it touches, not by which feature or script it came from: a test with no external dependency is a unit test (fast, run-anywhere) wherever in the codebase it lives, a test needing a live endpoint is an integration test (slow).
- The project declares two test tiers: a unit tier and an integration tier (conventionally the npm scripts test:unit and test:integration, which are the human verbose path). The judge does NOT hardcode test globs; the tiers are driven through declared configs. The split mechanism (naming, directories) is the project's choice; the convention is: name a test file after the module under test, in the same directory, with the tier as a suffix (src/examples/crud.ts has src/examples/crud.test.ts for unit and src/examples/crud.integration.test.ts for integration). ONE file per module per tier, never two shared monolith files (those collide across branches and overwrite). Shared test helpers live in one support module (e.g. src/test-support/), imported not duplicated. The reviewer checks tests are in the right file and tier.
- For its repeated verification runs (each judge cycle) the judge invokes the project's agent test runner, .building/scripts/agent-tests.sh <tier>, which the setup gate places under .building/scripts/ (gitignored, so the loop's own machinery never enters the committed repo) and proves (placing and proving the hollow-check runner .building/scripts/agent-hollow.sh on the same footing; the hollow-test check's negative and restore-verify runs go through agent-hollow.sh, which drives this same runner internally, see Gates). It prints one terse summary line on pass and the full output on failure, so a passing run costs a few tokens of context rather than the whole test dump. It drives the same two tiers through the same configs as the human commands; only the verbosity differs. The judge's pass REPORT still draws coverage, inventory and quality signals from the full tooling (a single coverage run plus tsc and lint); the terse runner is for the repeated pass/fail verification, not a replacement for the report's measured data.  The judge calls the runner as one bare command and relies on its terse line and exit code; it never appends shell to the call (no `; echo` of the exit status, no `| tail`), which would recreate a compound command and can truncate the full failure output the runner prints on purpose.
- Order: the judge runs the unit tier FIRST. If unit fails, reject without running integration (units are cheap; fail fast on them). The agent runner's `both` mode enforces this order and short-circuit; the judge runs a single tier only for the negative runs, where it isolates one tier to prove a test fails when the code is wrong.
- If unit passes, run the integration tier. The judge passes only if BOTH tiers pass.
- A tier with no tests, or that the project does not declare at all, is a vacuous pass ONLY where the deliverable genuinely has no behaviour for that tier. A tier that SHOULD have tests but selects zero is a hollow suite and is a hard fail, re-checked by the judge every deliverable (setup proves selection once at the start, but a later deliverable can reintroduce a hollow tier through a misclassified test or a config drift, so the judge re-checks the selected count each run, it is free since it already reads the count). Every test that gates a deliverable must be reachable through the declared tier configs the judge runs via .building/scripts/agent-tests.sh <tier>, because those configs are the only surface the judge runs. The judge confirms each gating acceptance criterion is covered by a test it actually ran through .building/scripts/agent-tests.sh; a gating test reachable only behind a side command the judge never invokes leaves that criterion's main path untested through the declared tiers, a hollow tier by omission that is a hard fail even when the tier selects other tests.
- The reviewer checks tier classification: a test with an external dependency MUST be in the integration tier, never the unit tier, so the unit tier stays dependency-free and run-anywhere. A test that gates a deliverable MUST be reachable through the declared tiers; a real gating test parked outside them, behind a side command the judge never invokes, is the same class of fault as a misclassified test, because the tier is decided by what the test touches, not by the feature or script it came from. Misclassification is a major.

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
5. On judge pass: judge writes the pass report (to the local, gitignored reports area). Then the document agent runs (document-agent.md): it assembles the doc payload plus the reviewer and judge reports into docs/modules/<id>-<module>.md and an idempotent section of docs/ARCHITECTURE.md. It is a producer, not a gate, and never blocks: the deliverable commits and the PR opens regardless of documentation outcome, with any gaps marked. Orchestrator opens a PR into main carrying code and docs only (the deliverable, what actually ships). Reports are NOT committed; they stay local (see State and channels). The orchestrator then renders the post-PR checkpoint (see Checkpoint) and stops there; what happens next is the human's choice through the fixed widget.
6. Either loop exhausts 3 -> escalate to human, do not commit, do not advance, freeze dependents.

## Ordering invariant (inviolable)
No code reaches the judge without a prior reviewer pass. Holds in step 2 and in every judge cycle (delta-review before judge). The reviewer is the only conventions gate (the judge does not check them), so any relaxation reopens the conventions hole. Never relax for efficiency.

## Monotonic green
Branch green after every commit. A commit may not lower greenness. The judge runs the full accumulated suite, unit tier then integration tier, across every merged deliverable so far, not just this deliverable's tests, so an earlier deliverable cannot be silently broken by a later one. Green means both tiers pass.
- sequential-attended: the next branch is cut from origin/main only after the previous PR merged, so the branch the judge tests already contains all prior merged work and accumulated-suite-green holds on main itself, after every merge.
- parallel-attended: green is per-branch, not per-main. Each sibling is verified green only against the origin/main it was cut from, in isolation. Two siblings each green alone can still combine into a red main (a shared-file append, or a semantic collision the loop never sees because it never holds two siblings together). The combined suite is re-run at the next deliverable's judge run, which is cut from the post-merge origin/main and so contains the combined work. When the merged siblings are terminal (no further deliverable is cut from them), no later judge run covers the combination, so at project completion the human runs the full suite once after the final combine. This is the explicit trade against sequential: parallel buys decoupled build-and-merge order at the cost of main not being provably green until that combined re-run.

## Branch and PR
- One branch per deliverable, named after the work: <id>-<kebab-title> (e.g. d03-connection-helper), so the branch list is an audit trail. No worktree, in either mode.
- Every branch is cut from a freshly-fetched origin/main, never a stale local main, in both modes. The loop runs `git fetch origin` then cuts from origin/main (e.g. `git switch -c <branch> origin/main`); it does not depend on local main being current, and it pushes the branch to origin/<branch> explicitly when it opens the PR. A human merge on the remote does not update local main until fetched, so cutting from local main can silently miss merged work.
- sequential-attended: branches are cut one at a time. The next branch is cut only after the previous PR has merged (confirmed, see Reconciliation), so each branch starts from all previously merged deliverables and the accumulated suite is genuinely green on main.
- parallel-attended: a branch is cut the moment the deliverable is ready (all deps merged), regardless of open PRs, always fresh from origin/main, never stacked on a sibling. You merge the siblings in your own order and resolve any append conflicts.
- If a branch of the target name already exists from an abandoned or escalated run, the orchestrator reports it and does not silently reuse or overwrite it; the human resolves it before the loop proceeds.
- Code and docs/ are what the commit carries. All loop output lives under .building/ (gitignored, never committed), so the commit is exactly the deliverable: code plus docs.
- On pass: the agents' records already sit in .building/work/<branch-name>/ (no copy step, they are the record). Stage only code and docs, single commit, open a PR into main.
- The PR carries code and docs only. The code and docs are the review surface (what actually ships); the judge's pass is the gate, and the reports stay local under .building/ as diagnostics you can consult if something looks off.
- The branch name is the PR's audit key: the loop never stores a PR number, it resolves the PR from its branch (`gh pr view <branch>`, see Reconciliation). One branch carries one PR, so this is unambiguous.
- Judge meaning: authoritative up to the merge; the human merge is the final gate.

## Project completion
Every deliverable PRs into main directly; there is no integration branch. main accumulates verified deliverables one merge at a time. In sequential-attended it is green after every merge; in parallel-attended it is green after the combined re-run that the next judge run (or the human's final-combine run) performs, per Monotonic green. The project is complete when the final deliverable's PR is merged into main. Each PR is one deliverable's audit record.

## State and channels (file-based, no memory layer)
All loop output lives under a single gitignored folder, .building/, with this structure:

```
.building/
  build/                          the loop's own state
    state.json
    setup-ok                      the setup receipt
  scripts/                        the loop's own runners (setup places them, gitignored, never committed)
    agent-tests.sh                the judge's test runner
    agent-hollow.sh               the judge's hollow-check runner
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

- .building/build/state.json: orchestrator sole writer (except `mode`, see below). Top-level: the sheet path, the conventions path, and `mode` (the project-level mode, sequential-attended or parallel-attended, set once and not written by the loop, see Modes). Per-unit status, one of: pending, building, in-review, in-judgement, documented, pr-open, merged, escalated, blocked. (Mapping to stages: building is the builder; in-review is the review loop; in-judgement is the judge loop; documented is after the judge passes and the document agent has run; pr-open is the PR awaiting your merge; merged is the confirmed merge into main; escalated and blocked are the two interruption states.) Also per unit: review loop count, judge loop count, branch name (the audit key, also the PR lookup key, null until cut). The sheet is read-only, never written. This enum is the canonical state set; the deliverable-states diagram renders exactly these states and must match.
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
- Hollow-test check: the judge proves a test fails when the code is wrong (negative run), run as one named command per check: .building/scripts/agent-hollow.sh <tier> <src-file> <test-file> <old-string> <new-string>. The judge supplies only the fault (an exact behavioural change that compiles, flip a value or comparison); the script owns the rest. It backs the file up under .building/ as a filesystem copy, which works on the UNTRACKED files a new deliverable adds where git checkout, git restore and git stash silently no-op and leave the break in the tree. It applies the fault, runs the tier scoped to this deliverable's own test file, classifies, restores from an exit trap whatever happens, then re-verifies green. Verdict by exit code: 0 the test caught the fault (asserts), 1 the tier stayed green so the test is HOLLOW (a major, deliverable fails), 2 the fault ran no tests so it was not behavioural (re-pick), 3 the file did not return to green after restore (halt). The check clears only on exit 0; a green negative run is the hollow failure, never a pass. The reviewer may suspect on read; the judge proves on run.
- Scope guard: builder touches only this deliverable (reviewer owns).
- Idempotent infra: any setup script is safe to run twice.
- Blocked halts the chain; an escalated deliverable freezes its dependents.

## Scripts and permissions
- Multi-step project operations are committed named scripts under scripts/, invoked as a single command, not inline compound bash. The loop's own runners are not committed: the setup gate places the agent test runner and the hollow-check runner under .building/scripts/ (gitignored), and the judge invokes them from there. Grant each script explicitly by path (e.g. Bash(.building/scripts/agent-tests.sh:*)), never a directory glob, plus a minimal atomic set.
- Side-effecting scripts (install, network, destructive) announce intent and ask via an informative dialog before acting, even under the allowlist. Repo-local read-only scripts run silently. Consent is passed explicitly (a flag such as --yes), never a hidden environment variable.

## Resume after interruption
The loop can be interrupted (crash, closed terminal, exhausted context). state.json is the recovery record. On re-entry, BEFORE doing anything, the orchestrator reads state.json and runs Reconciliation (see Checkpoint). It then chooses the checkpoint template by what state.json shows, NOT by a blanket assumption of interruption:
- if no deliverable is mid-build or interrupted (POSSIBLY STALLED is empty: every non-merged deliverable is pending or pr-open), this is a clean continuation, render the entry checkpoint (templates/checkpoint-entry.md). A post-PR stop that a fresh conversation re-enters is this case, not an interruption.
- if any deliverable is mid-build or interrupted (POSSIBLY STALLED is non-empty), render the reclaim checkpoint (templates/checkpoint-reclaim.md): the RESUME REPORT then the board then the fixed widget.
The RESUME REPORT describes the in-progress build, of which there is at most one because the loop builds one deliverable at a time even in parallel: the single deliverable in building, in-review, in-judgement or documented, if any, is the "stopped at" deliverable, with its attempt counts. Deliverables that are escalated or blocked are not "stopped at" a build; they are awaiting the human and appear in POSSIBLY STALLED on the board, addressed through Resume the stalled one. If there is no in-progress build (only escalated or blocked work), the RESUME REPORT says so and points at the board. The loop does not auto-resume and does not start over. If the human declines (chooses Wait), the loop stops without changing state.json or any branch, so the human can inspect or intervene manually and re-run later; declining is safe and non-destructive.
Per-status resume action (also the routing for the Resume the stalled one widget action): pending = cut the branch and build; building = resume the builder on the existing branch as-is; in-review = resume the review loop at the recorded count; in-judgement = resume the judge loop at the recorded attempt; documented = open the PR (work passed, PR not yet opened); pr-open = run Reconciliation for that branch (gh pr view <branch> --json mergedAt) and either promote to merged or keep waiting; escalated = the loop is waiting for the human (see Escalation recovery), needs a human code fix first; blocked = the endpoint was down, re-check readiness and continue. If a deliverable's branch exists but its status implies it should not, report the conflict and ask; never silently reuse or delete a branch.

## Escalation recovery
When a deliverable escalates (either loop exhausted 3), the loop does not abandon it. It WAITS. The deliverable's branch and its .building/work/<branch-name>/escalations/ record is left in place. The human fixes the deliverable on its existing branch (using the record: the outstanding findings, what each attempt tried), then tells the loop to continue. On continue, the orchestrator does NOT reset the work; it re-enters verification for that deliverable from the reviewer (the ordering invariant still holds: human-fixed code is reviewed, then judged, before it can pass), and on pass proceeds normally to document, PR, merge. The human may instead tell the loop to abandon the deliverable, which freezes it and its dependents and stops the run; that is an explicit human decision, never the loop's. Escalation never silently drops work.
## Escalation record
Written to .building/work/<branch-name>/escalations/<YYYY-MM-DD-HHMM>.md, with a relative symlink of the same name in .building/escalations/. It names which loop exhausted (review or judge) and carries that loop's per-pass history: the deliverable and its criteria, the outstanding critical/major findings, what each attempt tried and why it was rejected, a recommendation. A judge-loop escalation additionally surfaces any delta-review findings from the fix attempts. An environment block is reported separately and is never part of an escalation record.

## Checkpoint
The single decision point for both modes. Reached at three moments, rendered identically at all three from an on-disk template. The discriminator is what state.json shows, not which moment in code reached it:
- entry: a fresh start, or a clean continuation a fresh conversation re-enters with nothing mid-build or interrupted (POSSIBLY STALLED empty). A post-PR stop re-entered later is this case (templates/checkpoint-entry.md).
- post-PR: immediately after the loop opens a PR within the same conversation (templates/checkpoint-post-pr.md).
- reclaim: re-entry when state.json shows mid-build or interrupted work (POSSIBLY STALLED non-empty); the resume discipline (see Resume after interruption) prepends a RESUME REPORT, then the board (templates/checkpoint-reclaim.md).
The three templates differ only in preamble. The STATE BLOCK (the board) is byte-identical across all three and is rendered VERBATIM, filling only the angle-bracket slots. There is no freeform prose anywhere in a checkpoint: the board reads identically across conversations by construction, and the decision is always the fixed widget below. Identical wording across conversations is the point; a checkpoint that paraphrases is a defect.

### Reconciliation (before every render)
`merged` is never set on the loop's own say-so, and it is the only way a dep frees its dependents. For every deliverable currently pr-open (merged is terminal and not re-queried), confirm against the remote, keyed by branch:

```
gh pr view <branch> --json mergedAt -q .mergedAt
```

A PR is merged or it is not: mergedAt populated promotes the deliverable to merged; anything else leaves it pr-open (still awaiting your merge). That is the whole check, two outcomes. A PR that is closed without merging is out of scope (not a case the loop is designed for). Reconciliation runs at all three render points and on a pr-open resume, so the board always reflects the remote, not stale belief.

### The board (verbatim, identical across modes)
Sorts every deliverable into four sections, lowest id first within each, marked with a star if on the critical path. Every non-merged deliverable falls in exactly one section; merged deliverables appear in none, only in the "M of T merged" line:
- READY: deps all merged, the deliverable itself not in flight or merged. The full ready set (the level), not a single pick.
- AWAITING MERGE: every pr-open deliverable, with the dependents its merge unblocks (or "no dependents" if terminal).
- BLOCKED: every pending deliverable with at least one unmerged dep, each blocking dep named with its status. This is dependency-blocked. It is distinct from the `blocked` status (an endpoint-down deliverable), which is mid-run work and renders under POSSIBLY STALLED, not here.
- POSSIBLY STALLED: every deliverable whose state is not pending, merged or pr-open (so building, in-review, in-judgement, documented, escalated, or the `blocked` endpoint-down status), each with "deliverable <id> is in state <x>, this may be stalled".
An empty section renders the literal word None.

The star is a static property of the full sheet dependency graph, not of the remaining-work subgraph, so it does not drift as deliverables merge and two conversations render the same starred set. Compute the maximum root-to-terminal path length L over depends_on (a terminal is a deliverable nothing depends on; there may be several). The star marks every deliverable lying on some root-to-terminal path of length L (if several paths tie, all their deliverables are starred). The legend states this longest-chain property, the longest path to done, not importance or priority. Starred rows appear in every section so the whole critical path is visible.

### The decision widget (fixed labels, only applicable shown, Wait always)
After the board, call ask_user_input, single-select, with fixed labels that are never reworded. Only the applicable verbs are shown; Wait is always shown:
- Carry on -> build the lowest-id READY deliverable, no choosing. Shown iff READY is non-empty AND the cut rule allows a cut now.
- Build a specific one -> the human names which READY deliverable to build. Same applicability as Carry on.
- Merge the PR -> the human merges; the loop reconciles. Shown iff at least one deliverable is pr-open. If more than one, the loop asks which.
- Resume the stalled one -> resume a POSSIBLY STALLED deliverable, routed by its actual status (see Resume after interruption). Shown iff POSSIBLY STALLED is non-empty. If more than one, the loop asks which.
- Wait -> nothing changes; the loop stops safely. Always shown.

Cut rule (the only mode fork):
- parallel-attended: a cut is allowed iff READY is non-empty. Siblings in flight (pr-open or mid-build) do not block a new cut.
- sequential-attended: a cut is allowed iff READY is non-empty AND every non-merged deliverable is pending. So an open PR, a mid-build, an escalation or a block all suppress Carry on and Build a specific one until resolved, leaving Merge the PR (if a PR is open), Resume the stalled one (if stalled), and Wait. This is what keeps sequential to one deliverable in flight and the green-on-main guarantee real.

Every non-Wait choice acts, reconciles, then returns to this same checkpoint. The loop halts at a checkpoint after every PR; it never chains builds without passing through the board. When READY, AWAITING MERGE and POSSIBLY STALLED are all empty and every deliverable is merged, the project is complete (see Project completion) and the loop says so instead of rendering an empty widget.

### Degraded mode (subagent dispatch unavailable)
The roles run inline rather than as spawned subagents. Build exactly ONE deliverable, then stop: open its PR, render the post-PR checkpoint, and for the rest of this conversation suppress Carry on, Build a specific one, and any build-like Resume action (a second inline build would exhaust the context), overriding the cut rule. The board then shows only Merge the PR (if applicable) and Wait, and the degraded note explains that a fresh conversation is needed to build or resume more. Hard cap one build per conversation, in both modes, never a batch inline. A fresh conversation reclaims the run from state.json and the remote.
