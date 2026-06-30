# Build judge loop

CORE build-loop contract: everything both build profiles share. Read alongside the active profile (see Build profile); per-increment verification depth and documentation timing live in build-loop-full.md (default) and build-loop-lite.md. Do not duplicate profile behaviour here.

Deliver a schema-valid increment sheet as small, independently verified increments.
- Four agent roles (builder, reviewer, judge, document) plus a passive orchestrator, a review loop, a judge loop, objective gates.
- Attended always: with a remote a human merges every PR; with no remote the judge's pass is the gate, the loop integrates into local main, and the human decides at the per-increment checkpoint whether to continue.
- Two modes (sequential-attended, parallel-attended) read from `mode` in state.json (see Modes). Two build profiles (full default, lite) read from `profile` in state.json (see Build profile).
- Branch per increment; one GitHub PR per increment with a remote, else a local commit into main (see Remote presence).
- Consumes increment-sheet.schema.md (the sheet) and a project conventions file (CLAUDE.md).

## Posture
- Attended only: a human is present at every increment. With a remote the human merge is the final gate. With no remote there is no PR, so the judge's pass is the gate, the loop integrates into local main, and the human still decides at the per-increment checkpoint whether to continue. Unattended operation (auto-merge on green) is out of scope and not built.
- GitHub is optional, not assumed. A remote enables push/PR/merge; its absence is a warning, never a stop (see Remote presence). The receipt does not promise a remote, so the loop detects one itself.
- Two modes, both attended, from `mode`: sequential-attended (default), parallel-attended (see Modes). They share every role, gate, budget, the .building layout and the hollow-test; they differ only in the cut-and-checkpoint behaviour after a PR opens.

## Modes
`mode` is a per-queue setting in each feature's state.json (e.g. "sequential-attended"), set per feature, persists across conversations, not an invocation flag. One queue can run parallel-attended while another runs sequential-attended (a single-feature queue gains nothing from parallel; a large one may). The loop reads it on entry and at every checkpoint, never writes it. Absent: default to sequential-attended and say so.

- sequential-attended (default): one increment in flight. After a PR opens the loop waits; it does not cut the next branch until that PR merges, and cuts the next from the updated origin/main. main is green after every merge.
- parallel-attended: several increments may be in flight. After a PR opens you may build any ready sibling while open PRs sit unmerged; every branch is cut fresh from a freshly-fetched origin/main, never stacked on a sibling. Decouples build order from merge order. Not a wall-clock speedup: one checkout, one build at a time, with a checkpoint between each.

The single behavioural fork is the cut rule at a checkpoint (see Checkpoint, the decision widget). Readiness, the board, the widget mechanism, roles, gates, resume routing and the hollow-test are identical in both modes. Both descriptions assume a remote; in the local-only flow (no remote, see Remote presence) the two modes coincide, since with no open PRs there is no merge order to decouple from build order.

## Build profile
`profile` is a per-queue setting in state.json, full (default) or lite, human-set like `mode`, never written by the loop; absent, default to full and say so. Orthogonal to `mode`. Per increment, the profile decides what verification the judge runs after the unit tier, when documentation is produced, and whether a completion gate runs; nothing else (roles, budgets, branch rule, checkpoint, and the type-check, unit-tier and hollow-test gates are this core's, shared by both). Profile-specific behaviour lives in two thin contracts the loop reads ALONGSIDE this one:
- build-loop-full.md (default): every increment is integration-tested and documented before it ships; no completion gate.
- build-loop-lite.md: integration tier and per-increment document agent deferred to a completion gate, for fast iteration.

Where behaviour depends on the profile, this core points to those files rather than repeating, so a lite run never loads full-only detail and vice versa.

## Prerequisites: setup must have passed
The static environment (git with a local main, gh, matching report tooling, test-tier commands that select non-zero tests, valid configs, .building gitignored so loop output stays local) is proven once by the project setup gate (project-setup.md), not re-checked here. A GitHub remote is NOT in that proven set: the gate only warns when it is missing and still reports READY (project-setup.md), so the receipt does not guarantee a remote. The loop detects remote presence itself on entry and chooses the GitHub flow or the local-only flow (see Remote presence); a missing remote is a warning, not a stop.

On entry:
- Check for the setup receipt .building/setup-ok. Absent: STOP and tell the user to run /omero-project-setup first (the loop never runs setup itself).
- If the receipt's head differs from current git HEAD: WARN that commits have landed since setup ran and suggest re-running setup (idempotent, so free), but do not hard-block. In a multi-queue project this drift is EXPECTED whenever a sibling queue merged an increment into shared main, and is not by itself a reason to re-run (see Multiple feature queues). Heuristic for committed drift only; it does not detect uncommitted working-tree changes, so re-run setup whenever the environment may have changed regardless.

The receipt proves the ENVIRONMENT was ready at a HEAD. It proves nothing about an increment sheet. The build loop validates the sheet on entry against increment-sheet.schema.md: it runs `scripts/validate-sheet.sh <sheet>` for the mechanical rules (1-5, 8, goal presence) and confirms rules 6-7 (runnable-not-opinion, independently-buildable) itself, the two the script cannot check. A non-zero exit STOPS the loop; no role runs on a failed sheet, so the builder only ever sees a validated increment. The exit names the fix: 1 a REJECTION (a locatable flaw, correct the sheet), 4 a STRUCTURAL DEFECT (a non-DAG or empty sheet, an upstream design-partner bug, re-run design not patch). The two gates (sheet, receipt) are independent, neither implies the other. The build loop owns only the DYNAMIC endpoint-liveness check (see judge.md, Integration endpoints): whether the declared endpoint is up right now, which can change during a run.

## Remote presence: GitHub flow or local-only
A remote is optional. The setup gate proves git, a local main, gh auth and commit identity, but only WARNS when origin is missing and still writes the READY receipt (project-setup.md), so the receipt does not tell the loop whether a remote exists. The loop detects remote presence ITSELF, on entry and again whenever it is about to integrate an increment, and chooses one of two flows. NOT a mode (mode is sequential vs parallel, see Modes); an environment fact the loop reads, never stored in state.json. Detection: origin is present iff `git remote get-url origin` succeeds (gh auth already proven by the receipt).

- With a remote (origin configured, gh authenticated): the GitHub flow, the default, unchanged. Each branch cut from a freshly-fetched origin/main, pushed and opened as one PR per increment; the human merges; the loop reconciles against the remote (see Branch and PR, Reconciliation).
- No remote (origin absent): the local-only flow. The loop does NOT stop. It WARNS that no remote is configured, so no branch can be pushed and no PR can open yet (a one-line notice in the checkpoint preamble, see Checkpoint, not a per-increment nag), then continues locally: cuts each branch from local main, builds and commits the increment (code, plus docs in full, single commit; see Build profile) and integrates it into local main itself with a fast-forward, no push, no PR. The local commit is the increment's terminal state: it goes straight to merged, the loop's local integration standing in for the human PR-merge that has nothing to merge, so there is no pr-open stage. Not every increment is pushed or PR'd in this flow, which is expected and acceptable.

Adding a remote mid-run is picked up because detection is re-read each time it matters: increments built before the remote was added stay as local commits on main (pushed with main when the human first pushes it); every increment cut AFTER the remote is added uses the full GitHub flow. The two flows can interleave across one feature queue over time.

In the local-only flow the two modes coincide: with no open PRs there is no merge order to decouple from build order, so the loop integrates each increment into local main as soon as committed and cuts the next branch from that updated main. main is green after every increment, the sequential guarantee, regardless of the queue's mode.

## Roles
- Orchestrator (passive): sequences by dependency order, sole writer of state.json, enforces budgets, opens PRs (or integrates into local main when there is no remote, see Remote presence), halts on escalation. No code, no judging.
- Builder: implements one increment against acceptance criteria, writes tests, follows CLAUDE.md, touches only this increment. No self-certify. Observes runtime behaviour only through the project's committed runnable surface (the runnable examples or entry points the acceptance criteria invoke, and the test tiers run through the agent test runner), never a throwaway executable script written outside the source tree to inspect it (an untracked oracle the reviewer and judge never see). To see an error shape or runtime value, add a temporary log or scratch test case inside the increment, run it through that surface, then remove it before handoff. Also writes its documentation slice (purpose, public interface, gotchas) to .building/build/<feature-name>/work/<branch-name>/doc-payload.md per doc-payload.schema.md; a missing slice does not block, the document agent degrades, but the reviewer notes it as a non-blocking suggestion.
- Reviewer: owns the code. Informed context (reads the codebase). Checks conventions, architecture/patterns, scope, code-level defects, test-tier classification. Can bounce to builder. Writes a report each completed pass.
- Judge: owns behaviour. Fresh context per review. Type-checks first (the type-check gate: nothing else type-checks, the tiers strip or do not check types), then runs the tests itself, does not trust reports. Checks acceptance criteria met, tests genuinely pass, hollow-test by negative run. Writes a pass report only on pass. Does NOT check conventions, style, or architecture.
- Document: produces per-module and project documentation from the doc payload and the reports. A producer, not a gate; never blocks a passed increment (document-agent.md). WHEN it runs is the profile's call: per increment after the judge passes in full, or once as a completion sweep in lite (build-loop-full.md/build-loop-lite.md). Named to sit parallel with Builder, Reviewer, Judge; "the document agent" in prose refers to this role.

## Severity (pinned)
- critical: breaks build, corrupts data, security hole, or the core promise fails.
- major: correctness/robustness gap, main path untested, hollow test, evidence-backed convention breach, scope breach, named anti-pattern, concrete defect, test-tier misclassification.
- minor: style, naming, polish. Logged, never blocks, never consumes a loop.

## Reviewer rules
- Two outputs: a record (for the human, non-blocking) and a bounce (to the builder).
- Bounce only on critical/major in evidence categories:
  - conventions (cite CLAUDE.md)
  - architecture (named anti-pattern)
  - scope (touched another increment)
  - concrete defect (leak, unhandled error, race, N+1, measured slowness)
  - test-tier misclassification (the cases are defined once in judge.md, Test tiers: a unit-tier test with an external dependency, a gating test parked behind a side command the judge never runs, or a test not named per the per-module convention).
- An issue may bounce only if tied to a category with evidence. Everything else is record-only and cannot bounce.
- Evidence bounces, opinion suggests. Suggestions (efficiency, readability beyond conventions, alternatives) go in the report, never to the builder.
- Readability is a convention concern (cite CLAUDE.md or eslint/prettier). Taste beyond that does not bounce.
- Efficiency: concrete cost (stated requirement, known-bad algorithm on known-large data, or measured) = major. Speculative = suggestion.

## Test tiers, integration endpoints, the judge's gates
The judge's verification spec, the test tiers (definitions, the agent runner, hollow-by-omission and misclassification rules), the integration-endpoint readiness-and-block handling, and the judge's behavioural gates (the type-check gate and the hollow-test check) live in contracts/judge.md, read alongside this contract. This contract owns orchestration; judge.md owns verification. The orchestration-level gates stay here (see Gates); the two behavioural gates are judge.md's.

## Flow (per increment)
1. Builder implements, writes builder channel.
2. Review loop, budget 3: reviewer reviews the full increment, writes a report each pass; bounce to builder on critical/major, else approve.
3. On approve: judge runs the type-check gate first, then the unit tier, then the profile's further per-increment verification (the integration tier in full, deferred in lite; see Build profile).
4. Judge loop, budget 3 (separate): each cycle = builder fixes -> reviewer delta-review (the change only; reviewer has prior context) -> judge. A delta-review bounce OR a judge rejection both consume the cycle's one attempt and return findings to the builder.
5. On judge pass: judge writes the pass report (to the local, gitignored reports area). Then the profile's documentation-and-commit step runs (build-loop-full.md/build-loop-lite.md): in full the document agent assembles docs/modules/<id>-<module-filename>.md and an idempotent docs/ARCHITECTURE.md section (a producer, never a gate) and the commit carries code and docs; in lite documentation is deferred and the commit carries code only. With a remote the orchestrator opens a PR into main; with no remote it integrates into local main (see Remote presence). Reports are NOT committed; they stay local (see State and channels). The orchestrator then renders the post-PR checkpoint (see Checkpoint) and stops there; what happens next is the human's choice through the fixed widget.
6. Either loop exhausts 3 -> escalate to human, do not commit, do not advance, freeze dependents.

## Ordering invariant (inviolable)
No code reaches the judge without a prior reviewer pass. Holds in step 2 and in every judge cycle (delta-review before judge). The reviewer is the only conventions gate (the judge does not check them), so any relaxation reopens the conventions hole. Never relax for efficiency.

## Monotonic green
Branch green after every commit. A commit may not lower greenness. The judge runs the full accumulated suite the profile gates with, across every merged increment so far, not just this increment's tests, so an earlier increment cannot be silently broken by a later one. In full that suite is both tiers per increment (green = both pass); in lite it is the unit tier per increment, with integration verified once at the completion gate (see Build profile, build-loop-full.md/build-loop-lite.md). The per-mode rules below are the same for both profiles.
- sequential-attended: the next branch is cut from origin/main only after the previous PR merged, so the branch the judge tests already contains all prior merged work and accumulated-suite-green holds on main itself, after every merge.
- parallel-attended: green is per-branch, not per-main. Each sibling is verified green only against the origin/main it was cut from, in isolation. Two siblings each green alone can still combine into a red main (a shared-file append, or a semantic collision the loop never sees because it never holds two siblings together). The combined suite is re-run at the next increment's judge run, cut from the post-merge origin/main and so containing the combined work. When the merged siblings are terminal (no further increment is cut from them), no later judge run covers the combination, so at project completion the human runs the full suite once after the final combine. Explicit trade against sequential: parallel buys decoupled build-and-merge order at the cost of main not being provably green until that combined re-run.
- local-only flow (no remote): the modes coincide, since with no open PRs there is nothing to hold apart. The loop integrates each increment into local main as soon as committed and cuts the next branch from that updated main, so main is green after every increment exactly as sequential-attended is (see Remote presence).

## Branch and PR
- One branch per increment, named to the project branch-naming standard (claude-rules/omero-branch-naming.md): `feat/<id>-<kebab-title>` (e.g. feat/db-pool-connection-helper, the `feat` type then the increment id db-pool plus its kebab title), so the branch list is an audit trail. Increments deliver a feature, so the type is always `feat`. The work folder and records are keyed by this branch name. No worktree, in either mode.
- With a remote, every branch is cut from a freshly-fetched origin/main, never a stale local main, in both modes. Run `git fetch origin` then cut from origin/main (e.g. `git switch -c feat/<id>-<kebab-title> origin/main`); does not depend on local main being current, and pushes the branch to origin/<branch> explicitly when opening the PR. The branch name satisfies the project branch-naming guard (the `feat/` type prefix), so the push is not rejected. A human merge on the remote does not update local main until fetched, so cutting from local main can silently miss merged work.
- In the local-only flow (no remote, see Remote presence) there is no origin to fetch or push to: the branch is cut from local main (e.g. `git switch -c feat/<id>-<kebab-title> main`), which already carries every previously integrated increment because the loop integrates each into local main as it completes. The branch is never pushed.
- sequential-attended: branches cut one at a time. The next branch is cut only after the previous PR merged (confirmed, see Reconciliation), so each branch starts from all previously merged increments and the accumulated suite is genuinely green on main.
- parallel-attended: a branch is cut the moment the increment is ready (all deps merged), regardless of open PRs, always fresh from origin/main, never stacked on a sibling. You merge the siblings in your own order and resolve any append conflicts.
- If a branch of the target name already exists from an abandoned or escalated run, the orchestrator reports it and does not silently reuse or overwrite it; the human resolves it before the loop proceeds.
- What the per-increment commit carries is the profile's call (see Build profile): code plus docs/ in full, code only in lite (lite produces its docs at the completion gate, build-loop-lite.md). All loop output lives under .building/ (gitignored, never committed), so the commit is exactly the increment and nothing else.
- On pass: the agents' records already sit in .building/build/<feature-name>/work/<branch-name>/ (no copy step, they are the record). Stage only the increment's tracked output (code, plus docs in full), single commit. With a remote, push the branch and open a PR into main; in the local-only flow, integrate the branch into local main instead (a fast-forward, since the branch was cut from current local main and is one commit ahead), no push, no PR.
- The committed code (and docs, in full) is the review surface (what actually ships); the judge's pass is the gate, and the reports stay local under .building/ as diagnostics you can consult if something looks off.
- With a remote, the branch name is the PR's audit key: the loop never stores a PR number, it resolves the PR from its branch (`gh pr view <branch>`, see Reconciliation). One branch carries one PR, so this is unambiguous. In the local-only flow there is no PR; the branch name is purely the audit name and the increment is already integrated into local main.
- Judge meaning: authoritative up to integration. With a remote the human merge is the final gate; with no remote the judge's pass is the gate and the loop's local integration is the terminal step.

## Completion (per feature queue)
Every increment reaches main directly; there is no integration branch. With a remote each increment PRs into main; in the local-only flow the loop integrates each into local main itself (see Remote presence). Either way main accumulates verified increments one at a time. In sequential-attended it is green after every merge; in parallel-attended it is green after the combined re-run the next judge run (or the human's final-combine run) performs, per Monotonic green (in the local-only flow the modes coincide and main is green after every increment). A feature queue is complete when its final increment is on main, by the human's PR merge with a remote or by the loop's local integration without one, AND any completion gate the profile requires has passed: full has none; lite first runs the full accumulated integration suite and a documentation sweep, whose docs must reach main, before the queue is complete (see Build profile, build-loop-lite.md). A project (repo) can host several feature queues over time, each an independent sheet under .building/features/ completing on its own, so completing one says nothing about the others. Each increment's audit record is its PR with a remote, or its branch and local commit without one.

## Multiple feature queues
A project (repo) can hold several feature queues at once, each a sheet under .building/features/<feature-name>/ with its own state at .building/build/<feature-name>/. The sheet path passed to the loop selects the queue; queues are reclaimed, resumed and completed independently, and one queue's run never reads or writes another's state. Three things are shared project-wide, not per queue:

- Setup is project-level. The receipt (.building/setup-ok) and the runners (.building/scripts/) prove and serve the project, shared by every queue. Because every queue merges into the same main, main's HEAD advances whenever ANY queue merges an increment, so the receipt's head-drift warning (see the entry check) is expected in a multi-queue project and is not by itself a reason to re-run. Re-run setup only when tooling, configs, test tiers or commit identity actually changed.
- Greenness is a property of main, project-wide. Every branch is cut from a freshly-fetched origin/main (or local main in the local-only flow), so it carries the merged work of ALL queues, and the judge's accumulated suite (see Monotonic green) spans every merged increment across every queue. main is re-greened by whichever queue's judge runs next, not per queue. An increment in one queue is validated against the whole merged tree: no queue can silently break another's merged work. When queues run in different modes at once, main's continuous-green property is the weakest concurrent mode's: a sequential queue's "green after every merge" holds only while no parallel queue has uncombined merges in flight; a concurrent parallel queue means main is provably green only after the next combined judge run, project-wide.
- Cross-queue visibility is the human's, with a reminder. The board renders the ACTIVE queue only. So open work in other queues is not silently forgotten, every checkpoint carries an OTHER QUEUES slot in its preamble, a fixed-format line per sibling queue filled from a scan of each sibling .building/build/*/state.json (state.schema.md), blank when there are none, sitting above the STATE BLOCK (which stays byte-identical): "other queue <feature-name>: <n> in flight, <n> awaiting merge, <n> escalated, <n> blocked". A lite sibling parked at its completion gate has open work no increment status shows, so the scan also reads the sibling's `completion` block and appends ", completion gate: <integration|docs state>" to that line when its gate is present and not yet complete (integration pending/failed, or docs pending/pr-open), so the docs PR awaiting a merge and a failed gate awaiting a fix are not silently forgotten. Like every checkpoint element it is a filled slot, not freeform prose; it changes no state, and the human still switches queues by invoking that queue's sheet.

## State and channels (file-based, no memory layer)
All loop output, plus the feature sheets it builds from, lives under a single gitignored folder, .building/, with this structure:

```
.building/
  setup-ok                        the setup receipt (project-level: setup proves the project, shared by every feature)
  scripts/                        the loop's own runners (project-level; setup places all three runners, test, hollow-check and type-check; gitignored, never committed)
    agent-tests.sh                the judge's test runner
    agent-hollow.sh               the judge's hollow-check runner
    agent-typecheck.sh            the judge's type-check runner
  features/                       the feature sheets (build input), one folder per feature
    <feature-name>/                keyed by the feature name (e.g. greeting-spike)
      increments.md             the schema-valid sheet the loop builds
  build/                          the loop's own state, one folder per feature (an independent feature queue)
    <feature-name>/                mirrors features/<feature-name>/; selected by the sheet path passed to the loop
      state.json                  this queue's state (carries its own mode and profile); orchestrator sole writer
      work/                       the agents' working files, one folder per unit
        <branch-name>/            keyed by the audit-named branch (e.g. feat/db-pool-connection-helper)
          builder.md
          review-pass-N.md
          judge.md                on pass only
          doc-payload.md
          escalations/            only if this unit escalated
            <YYYY-MM-DD-HHMM>.md
      escalations/                this queue's flat chronological index, symlinks only
        <YYYY-MM-DD-HHMM>.md  ->  ../work/<branch-name>/escalations/<YYYY-MM-DD-HHMM>.md
```

- .building/build/<feature-name>/state.json: one file per feature, an independent feature queue. Its structure, the status enum, the per-unit fields and validation are defined in state.schema.md (canonical; the cross-queue scan and the reconstruction path read it too). The points operational to the loop:
  - Queue selection: the feature name is derived from the sheet path passed to the loop, so building one feature never reads or writes another's state.
  - Writer: orchestrator is sole writer, except `mode` and `profile`, which the human sets (see Modes, Build profile; defaults sequential-attended and full when absent).
  - The sheet is read-only, never written. The status enum is canonical: the increment-states diagram renders exactly those states and must match.
  - Status-to-stage mapping: building = builder; in-review = review loop; in-judgement = judge loop; documented = judge passed and (full) the document agent has run, or (lite) verified and ready to commit with docs deferred (build-loop-lite.md); pr-open = PR awaiting your merge (GitHub flow only); merged = on main (a remote merge, or local integration in the local-only flow); escalated and blocked = the two interruption states.
  - Branch names share one global git namespace, so they must be unique across features. The audit-naming convention (`feat/<id>-<kebab-title>`) makes this natural; on a cross-queue collision, prefix the feature name (`feat/<feature>-<id>-<kebab-title>`).
  - `completion` block (lite only, loop-written): tracks the completion gate (its integration run and its docs PR on branch `docs/<feature-name>-completion`); absent in full (build-loop-lite.md). The gate is not an increment, so it has no `increments` entry and no `work/<branch-name>/` folder; its docs PR reconciles and renders through the same surfaces as an increment PR (see Reconciliation, The board).
- .building/setup-ok: the setup receipt (written by the setup gate, read by the loop on entry). Project-level, not per feature: setup proves the project environment, which every feature shares, so the receipt sits at the top of .building/, beside scripts/, not under any one feature's build folder.
- .building/build/<feature-name>/work/<branch-name>/: the agents' working files for one unit, keyed by its audit-named branch. builder.md, review-pass-N.md, judge.md (on pass), doc-payload.md. These ARE the record; there is no separate reports copy. Channels and records are the same files (machine reads them as channels, human reads them as records).
- Re-running a unit overwrites its work folder in place: only the latest run is kept, not a dated history. Within a single run, review passes accumulate (review-pass-1, review-pass-2, ...).
- Escalation: the record is written ONCE to .building/build/<feature-name>/work/<branch-name>/escalations/<YYYY-MM-DD-HHMM>.md (the single source of truth, beside the failed passes). A relative symlink of the same name is created in .building/build/<feature-name>/escalations/ pointing at it, giving a flat chronological index across this queue's units. The symlink MUST be relative (target starts ../work/...) so it survives the folder being moved or renamed; an absolute symlink breaks on a move. The symlink is a pointer, never a copy.
- Nothing under .building/ is ever committed. The whole folder is gitignored with one rule: .building/. The commit and PR carry only the increment (code, plus docs/ in full; see Build profile).

## Record contents (the files under work/<branch-name>/)
- Reviewer record (review-pass-N.md), each completed pass: what changed; architecture/pattern/idiom and why; blocking findings (or none); suggestions (efficiency primary, the human comprehension layer); outcome.
- Judge record (judge.md), on pass only: acceptance-criteria results; per-tier coverage (unit and integration separately, lines/branches/functions/statements plus uncovered) from tooling; per-tier test inventory (count, per-file, pass/skip, durations) from tooling json; per-function -> test -> one-line mapping, labelled asserted not measured; quality signals (eslint counts, hollow-test result, slowest test) and the type-check gate result (clean, which a pass requires). Coverage is always shown with the hollow-test result, never alone. Coverage is per tier, not merged.
- Templates: file-templates/reviewer-report.md, file-templates/judge-report.md.

## Gates
- Commit only on green. Never commit then judge. Failed work stays uncommitted. The judge's green IS the commit gate: the orchestrator does not re-run the suite before committing, because the only change to the tree between judgement and commit is the profile's documentation step (the document agent's docs in full, nothing in lite), which cannot affect test results.
- Conventional commits.
- The judge's two behavioural gates, the type-check gate and the hollow-test check (each a single named .building/scripts/ runner, verdict by exit code per contracts/agent-runner.md), are specified in contracts/judge.md, Gates the judge runs. They are the judge's, not orchestration's; the rest of this list is the orchestration-level gates.
- Scope guard: builder touches only this increment (reviewer owns).
- Idempotent infra: any setup script is safe to run twice.
- Blocked halts the chain; an escalated increment freezes its dependents.

## Scripts and permissions
- Multi-step project operations are committed named scripts under scripts/, invoked as a single command, not inline compound bash. The loop's own runners are not committed: the setup gate places all three agent runners (test, hollow-check, type-check) under .building/scripts/ (gitignored), and the judge invokes them all from there. Grant each script explicitly by path (e.g. Bash(.building/scripts/agent-tests.sh:*)), never a directory glob, plus a minimal atomic set.
- Side-effecting scripts (install, network, destructive) announce intent and ask via an informative dialog before acting, even under the allowlist. Repo-local read-only scripts run silently. Consent is passed explicitly (a flag or confirmation), never a hidden environment variable.

## Resume after interruption
The loop can be interrupted (crash, closed terminal, exhausted context). state.json is the recovery record.

If the active queue's state.json is ABSENT (a feature's first build: no .building/build/<feature-name>/state.json yet), there is nothing to recover. The orchestrator creates .building/build/<feature-name>/ and initialises state.json (state.schema.md) from the sheet it just validated: the sheet path, the conventions path, and every increment pending with review and judge counts 0 and branch null. It does NOT write `mode` or `profile` (the loop never writes either; absent, mode defaults to sequential-attended and profile to full, and the human sets them to run a queue parallel or lite). It then renders the entry checkpoint as a fresh start.

Otherwise, on re-entry, BEFORE doing anything, the orchestrator reads the active queue's state.json (the feature named by the sheet path, at .building/build/<feature-name>/state.json), then in order: syncs the validated sheet into it, validates the synced state with `scripts/validate-state.sh <state.json> <sheet>` (state.schema.md, Validation tooling), then runs Reconciliation (see Checkpoint).
- The sync is additive only and runs BEFORE validate-state.sh, so the schema's sheet-and-state agreement holds when the validator checks it. Any sheet id with no key in `increments` is appended as pending, counts 0, branch null, mirroring its depends_on (the bootstrap rule applied incrementally). The loop never removes or rewrites an existing key.
- A non-zero validate-state.sh exit STOPS the loop, naming the fix: exit 1 a rejection (a fixable flaw), exit 4 a defect (a state<->sheet disagreement to reconcile out of band), exit 5 the sheet itself fails (fix it first).
- Appending a new id is safe (the common case, including the fix increment a lite completion-gate integration failure asks for, build-loop-lite.md) and is how a mid-run sheet addition enters the queue. Editing an existing id's depends_on or identity, or deleting one, is NOT safe: the additive sync will not update the existing key, so state.json then disagrees with the sheet and fails validation (state.schema.md, the depends_on-equals-sheet and id-agreement rules). That edit is the human's out-of-band reconciliation: hand-correct state.json to match, the same correction that rebuilds a lost state file.
- Each feature queue is reclaimed independently; re-entering one feature never reads or resumes another.

It then chooses the checkpoint template by what state.json shows, NOT by a blanket assumption of interruption:
- no increment mid-build or interrupted (POSSIBLY STALLED empty: every non-merged increment is pending or pr-open): a clean continuation, render the entry checkpoint (file-templates/checkpoint-entry.md). A post-PR stop that a fresh conversation re-enters is this case, not an interruption.
- any increment mid-build or interrupted (POSSIBLY STALLED non-empty): render the reclaim checkpoint (file-templates/checkpoint-reclaim.md): the RESUME REPORT then the board then the fixed widget.

The RESUME REPORT describes the in-progress build, of which there is at most one in this queue because the loop builds one increment at a time even in parallel-attended mode: the single increment in building, in-review, in-judgement or documented, if any, is the "stopped at" increment, with its attempt counts. Increments that are escalated or blocked are not "stopped at" a build; they are awaiting the human and appear in POSSIBLY STALLED on the board, addressed through Resume the stalled one. If there is no in-progress build (only escalated or blocked work), the RESUME REPORT says so and points at the board. The loop does not auto-resume and does not start over. If the human declines (chooses Wait), the loop stops without changing state.json or any branch, so the human can inspect or intervene manually and re-run later; declining is safe and non-destructive.

Per-status resume action (also the routing for the Resume the stalled one widget action):
- pending = cut the branch and build.
- building = resume the builder on the existing branch as-is.
- in-review = resume the review loop at the recorded count.
- in-judgement = resume the judge loop at the recorded attempt.
- documented = open the PR with a remote, or integrate into local main in the local-only flow (work passed, not yet on main).
- pr-open = run Reconciliation for that branch (gh pr view <branch> --json mergedAt) and either promote to merged or keep waiting (pr-open does not occur in the local-only flow, where the loop integrates locally and the increment goes straight to merged).
- escalated = the loop is waiting for the human (see Escalation recovery), needs a human code fix first.
- blocked = the endpoint was down, re-check readiness and continue.
If an increment's branch exists but its status implies it should not, report the conflict and ask; never silently reuse or delete a branch.

In the lite profile, when every increment is merged the resume is the completion gate, routed by the `completion` block rather than by any increment:
- absent or `integration` pending = run the integration suite from the top.
- `integration` failed = render the board with the completion-gate failure note and WAIT (do NOT auto-re-run; reaching this with every increment merged means no increment has merged since the failure, because a merge would have re-armed the gate, resetting integration to pending, see build-loop-lite.md, Completion gate; the human resolves it by appending a fix increment, which the sheet sync above brings into the queue as pending so it becomes READY, and whose eventual merge flips integration back to pending).
- `integration` passed with `docs` pending = run the documentation sweep and commit it.
- `docs` pr-open = run Reconciliation for the `docs/<feature-name>-completion` branch and either promote to merged (queue complete) or keep waiting.
A re-entry never re-runs a passed integration nor re-cuts an existing docs branch, so the existing-branch guard does not fire on `docs/<feature-name>-completion` when `completion.docs` is pr-open: that branch is expected, not an abandoned collision.

## Escalation recovery
When an increment escalates (either loop exhausted 3), the loop does not abandon it. It WAITS. The increment's branch and its .building/build/<feature-name>/work/<branch-name>/escalations/ record are left in place. The human fixes the increment on its existing branch (using the record: the outstanding findings, what each attempt tried), then tells the loop to continue. On continue, the orchestrator does NOT reset the work; it re-enters verification for that increment from the reviewer (the ordering invariant still holds: human-fixed code is reviewed, then judged, before it can pass), and on pass proceeds normally to document, PR, merge. The human may instead tell the loop to abandon the increment, which freezes it and its dependents and stops the run; that is an explicit human decision, never the loop's. Escalation never silently drops work.

## Escalation record
Written to .building/build/<feature-name>/work/<branch-name>/escalations/<YYYY-MM-DD-HHMM>.md, with a relative symlink of the same name in .building/build/<feature-name>/escalations/. It names which loop exhausted (review or judge) and carries that loop's per-pass history: the increment and its criteria, the outstanding critical/major findings, what each attempt tried and why it was rejected, a recommendation. A judge-loop escalation additionally surfaces any delta-review findings from the fix attempts. An environment block is reported separately and is never part of an escalation record.

## Checkpoint
The single decision point for both modes. Reached at three moments, rendered identically at all three from an on-disk template. The discriminator is what state.json shows, not which moment in code reached it:
- entry: a fresh start, or a clean continuation a fresh conversation re-enters with nothing mid-build or interrupted (POSSIBLY STALLED empty). A post-PR stop re-entered later is this case (file-templates/checkpoint-entry.md).
- post-PR: immediately after the loop finishes an increment within the same conversation, opening a PR with a remote or integrating into local main in the local-only flow (file-templates/checkpoint-post-pr.md).
- reclaim: re-entry when state.json shows mid-build or interrupted work (POSSIBLY STALLED non-empty); the resume discipline (see Resume after interruption) prepends a RESUME REPORT, then the board (file-templates/checkpoint-reclaim.md).

The three templates differ only in preamble. Each preamble carries the same fixed optional notes (no-remote, degraded, OTHER QUEUES) and, in the lite profile, a completion-gate note keyed on the `completion` block: blank until the gate is reached; with `integration` pending, "Completion gate: running the full integration suite."; with `integration` failed, "Completion gate: the integration suite failed; append a fix increment to the sheet and I will build it, then re-run the gate."; with `integration` passed and `docs` pending, "Completion gate: running the documentation sweep." (once the docs PR is open it shows in AWAITING MERGE, not here, and the note goes blank). The STATE BLOCK (the board) is the shared file-templates/checkpoint-board.md, inserted into each template verbatim (filling only the angle-bracket slots) so it cannot drift across the three. No freeform prose anywhere in a checkpoint: the board reads identically across conversations, and the decision is always the fixed widget below. A checkpoint that paraphrases is a defect.

### Reconciliation (before every render)
`merged` is never set on the loop's own say-so, and it is the only way a dep frees its dependents. For every increment currently pr-open (merged is terminal and not re-queried), and in the lite profile also the completion docs PR when `completion.docs` is pr-open (keyed by its branch `docs/<feature-name>-completion`, promoting `completion.docs` to merged on a populated mergedAt), confirm against the remote, keyed by branch:

```
gh pr view <branch> --json mergedAt -q .mergedAt
```

A PR is merged or it is not: mergedAt populated promotes the increment to merged; anything else leaves it pr-open (still awaiting your merge). Two outcomes, the whole check. A PR closed without merging is out of scope. Reconciliation runs at all three render points and on a pr-open resume, so the board always reflects the remote, not stale belief. The cases:
- local-only flow: no pr-open increments exist (the loop integrates each into local main itself, so each goes straight to merged), so reconciliation has nothing to query and is a no-op; the local integration is the terminal transition the loop records directly.
- remote added mid-run: any increment still pr-open from an earlier GitHub phase reconciles here normally.
- out-of-band merge: reconciliation covers only increments the loop cut (those with a recorded branch), so a pr-open increment the human merges out of band is caught here and promoted at the next checkpoint, no notice to the loop needed.
- out-of-loop completion: an increment the loop never cut but completed outside it (a direct commit, a hand-named PR) has no recorded branch to query, so reconciliation cannot see it; it stays pending and the loop will offer to build it. That one is the human's to reconcile before resuming (mark it merged with its branch, the same out-of-band correction that rebuilds a lost state file), so the loop does not rebuild already-done work.

### The board (verbatim, identical across modes)
Sorts every increment into four sections, lowest id first within each, marked with a star if on the critical path. Every non-merged increment falls in exactly one section; merged increments appear in none, only in the "this queue: M of T merged" line:
- READY: deps all merged, the increment itself not in flight or merged. The full ready set (the level), not a single pick.
- AWAITING MERGE: every pr-open increment, with the dependents its merge unblocks (or "no dependents" if terminal). In the lite profile this section also carries the completion docs PR when `completion.docs` is pr-open, as a single row placed last, after the increment rows (id `completion-docs`, title "documentation sweep", no star, branch `docs/<feature-name>-completion`, no dependents); merging it is the last step before the queue completes. Always None in the local-only flow, where no increment and no docs commit is ever pr-open.
- BLOCKED: every pending increment with at least one unmerged dep, each blocking dep named with its status. This is dependency-blocked. Distinct from the `blocked` status (an endpoint-down increment), which is mid-run work and renders under POSSIBLY STALLED, not here.
- POSSIBLY STALLED: every increment whose state is not pending, merged or pr-open (so building, in-review, in-judgement, documented, escalated, or the `blocked` endpoint-down status), each with "increment <id> is in state <x>, this may be stalled".
An empty section renders the literal word None.

The board partition, the star set, the ready set and the cut-rule boolean are computed by `scripts/board-state.sh <state.json> <sheet>` (read-only; it validates its inputs via validate-state.sh first, then emits one JSON object), NOT hand-derived: an LLM hand-computing longest-path-with-ties drifts, yet the board must render byte-identical across conversations, so determinism is the point. (One known gap: the script does not yet emit the lite-only synthetic `completion-docs` row below; full and build-quick have no completion block and are fully covered. Until added, the orchestrator appends that one row by hand in lite when `completion.docs` is pr-open.) The orchestrator pastes the script's output into the verbatim template and stays the SOLE WRITER of state.json (the script only reads). The star is a static property of the full sheet dependency graph, not the remaining-work subgraph, so it does not drift as increments merge: the longest root-to-terminal chain measured in NODES (length L), with every increment on any longest chain starred on a tie. The legend states this longest-chain property, the longest path to done, not importance or priority. Starred rows appear in every section so the whole critical path is visible.

### The decision widget (fixed labels, only applicable shown, Wait always)
After the board, call ask_user_input, single-select, with fixed labels never reworded. Only the applicable verbs are shown; Wait is always shown:
- Carry on -> build the lowest-id READY increment, no choosing. Shown iff READY is non-empty AND the cut rule allows a cut now.
- Build a specific one -> the human names which READY increment to build. Same applicability as Carry on.
- Merge the PR -> the human merges; the loop reconciles. Shown iff at least one increment is pr-open, or (lite) the completion docs PR is pr-open. If more than one, the loop asks which. Never shown in the local-only flow, where the loop integrates each increment and the docs commit into local main itself so nothing is ever pr-open to merge.
- Resume the stalled one -> resume a POSSIBLY STALLED increment, routed by its actual status (see Resume after interruption). Shown iff POSSIBLY STALLED is non-empty. If more than one, the loop asks which.
- Wait -> nothing changes; the loop stops safely. Always shown.

Cut rule (the only mode fork):
- parallel-attended: a cut is allowed iff READY is non-empty. Siblings in flight (pr-open or mid-build) do not block a new cut.
- sequential-attended: a cut is allowed iff READY is non-empty AND every non-merged increment is pending. So an open PR, a mid-build, an escalation or a block all suppress Carry on and Build a specific one until resolved, leaving Merge the PR (if a PR is open), Resume the stalled one (if stalled), and Wait. This keeps sequential to one increment in flight and the green-on-main guarantee real.

Every non-Wait choice acts, reconciles, then returns to this same checkpoint. The loop halts at a checkpoint after every increment (after the PR opens with a remote, or after the local integration without one); it never chains builds without passing through the board. When READY, AWAITING MERGE and POSSIBLY STALLED are all empty and every increment in this queue is merged, the feature queue is complete (see Completion) and the loop says so instead of rendering an empty widget. Lite adds one step before that point; the full mechanism is the single source build-loop-lite.md, Completion gate, not restated here: once every increment is merged the loop runs the completion gate, records it in `completion`, and does NOT declare the queue complete until the gate fully passes (`completion.integration` passed AND `completion.docs` merged). While the gate is unfinished the loop still renders the board, carrying the completion-gate note (keyed on `completion.integration`, see the preamble) and the completion-docs row in AWAITING MERGE while the docs PR is open. So in lite, all four sections empty with every increment merged does NOT by itself mean complete.

### Degraded mode (subagent dispatch unavailable)
The roles run inline rather than as spawned subagents. Build exactly ONE increment, then stop: finish it (open its PR with a remote, or integrate into local main without one), render the post-PR checkpoint, and for the rest of this conversation suppress Carry on, Build a specific one and any build-like Resume action (a second inline build would exhaust the context), overriding the cut rule. The board then shows only Merge the PR (if applicable) and Wait, and the degraded note explains that a fresh conversation is needed to build or resume more. Hard cap one build per conversation, in both modes, never a batch inline. A fresh conversation reclaims the run from state.json (and the remote, if one exists). The lite completion gate (the integration run plus the one-pass documentation sweep) is not an increment build: in degraded mode it still runs inline, but it counts as the conversation's single heavy action, so after it the loop stops the same way and a fresh conversation handles anything further.
