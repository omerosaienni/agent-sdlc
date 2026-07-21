# Build stacked

Standalone recipe for the UNATTENDED, incremental, linearly stacked build. A self-contained fork of build-judge-loop.md: it does NOT read that contract and that contract is untouched. Everything the loop needs is here or in the stable shared specs it cites (judge.md for verification, state.schema.md for state, increment-sheet.schema.md for the sheet, epic-manifest.schema.md for the epic, agent-runner.md for the runners). Read this top to bottom; it is the loop.

Deliver a schema-valid increment sheet as small, independently verified increments, each stacked on the previous one, without a human in the build queue.
- Four agent roles (builder, reviewer, judge, document) plus a passive orchestrator, a review loop, a judge loop, objective gates: the per-increment verification core is exactly build-judge-loop.md's and judge.md's, unchanged.
- UNATTENDED: no checkpoint widget, no human merge in the loop. The loop builds every ready increment back to back, opens one stacked PR per increment, and stops only when the sheet is exhausted (then tags) or a role loop escalates (then halts the chain).
- INCREMENTAL and LINEAR: one increment in flight at a time, built on the previous increment's branch, forming a single linear git-town stack. The DAG is linearised (see Linearisation); siblings are chained, never forked.
- STACKED ACROSS FEATURES: the first increment is stacked on the previous feature's stack tip (from the epic and its tag), not on main, so a run continues a stack another feature left open. See Stack base.
- Tags are the index: `feature/<feature-name>` marks each feature's stack tip, `epic/<epic-name>` the epic's overall tip, force-moved so they always point at live tips (see Tags).

This core covers the FULL verification path (both tiers, per-increment docs). The unit-only, no-docs variant is build-quick-stacked.md, a thin delta over this file, exactly as build-quick.md is a delta over build-judge-loop.md.

## Posture
- Unattended: removes the human from the build queue so they work the open PRs (review, merge, ship) WHILE it builds. Never merges, never ships, never pauses. Self-heals within the review/judge loops; halts loudly on escalation.
- Incremental: one increment at a time on the current tip. No concurrency, no fan-out, so one clean stack with one tip to tag.
- Remote REQUIRED (unlike the attended core): no remote means nothing to stack or propose. On entry, `git remote get-url origin` or `gh auth status` failing STOPS; no local-only flow.
- git-town owns topology: parents live in git-town config (`git-town-branch.<b>.parent`), set by `git town append`; state.json carries NO parent field (see State). `git town sync --stack` rebases and reconciles; the loop drives it, never reimplements it.

## Prerequisites: setup, sheet, epic, tooling
On entry, in order:
- Setup receipt `.building/setup-ok` present. Absent: STOP, tell the user to run /omero-setup-project (the loop never runs setup). A head-drift warning is informational, not a stop (see build-judge-loop.md's rationale; drift is expected once any queue merges).
- Sheet valid: `scripts/validate-sheet.sh <sheet>` for the mechanical rules, plus the loop confirms rules 6-7 itself (runnable-not-opinion, independently-buildable), per increment-sheet.schema.md. Non-zero exit STOPS: exit 1 a rejection (fix the sheet), exit 4 a structural defect (a non-DAG or empty sheet, re-run design). No role runs on an invalid sheet.
- Remote and auth: `git remote get-url origin` succeeds and `gh auth status` succeeds. Either missing STOPS (see Posture).
- git-town present: `git town --version` succeeds. Absent STOPS with the install remedy.
- Epic manifest: locate this feature's manifest by scanning `.building/epics/*/epic.json` for one whose `features[].name` includes it (manifests keyed by epic name, so a scan). Found: read this feature's cross feature `depends_on` (Stack base). None: single-feature epic, base origin/main. Read-only, gates nothing (epic-manifest.schema.md carves out this stacked-loop read). Missing: warn, not stop.

## Stack base: where the first increment is cut
First increment cut from the previous feature's stack tip (features chain into one stack), resolved from the `feature/<prev>` tag, never by re-linearising the predecessor. In order:
1. Cross feature `depends_on` empty (from the epic manifest, located in Prerequisites): base `origin/main`, parent `main`. Done.
2. Else predecessor = latest-built of `depends_on` in manifest build order. Its tip BRANCH = `git branch --points-at feature/<prev>` (tag force-moved to the live tip, see Tags):
   - exactly one branch: predecessor stack OPEN; that branch is the parent (Flow step 1).
   - no branch: tag commit already on main (predecessor shipped); base `origin/main`, parent `main`.
   - more than one: base ambiguous (foreign stack); STOP and ask.

Tags are the index: read here to FIND the base, written at Tags to MARK new tips.

## Linearisation (DAG to one chain)
A git-town stack is linear; a sheet's `depends_on` is a DAG with siblings (several increments sharing one dependency). The loop linearises the DAG into one chain and stacks in that order, each increment appended onto the one before it (so `_03 -> {_02,_04,_05,_06}` builds as `_03 -> _02 -> _04 -> _05 -> _06`, one linear stack).
- The order is computed by `scripts/stack-order.sh <state.json> <sheet>` (read-only; validates its inputs via validate-state.sh first, then emits the increment ids in a valid build order as one JSON array), NOT hand-derived: a topological sort with ties broken by lowest id is deterministic, and the stack must be reproducible across conversations, so determinism is the point (mirrors board-state.sh). The orchestrator appends in exactly that order.
- The order respects `depends_on`: an increment never appears before one it depends on. Ties (siblings) are ordered by lowest id, so re-running yields the same chain.
- Each increment's git-town parent is the increment immediately before it in this order (the current tip), EXCEPT the first, whose parent is the Stack base. Parent is a property of the build order, not stored in state.json (git-town config holds it).

## Roles
Exactly build-judge-loop.md's four roles and judge.md's verification, unchanged. The only difference is the orchestrator's terminal action: it opens a stacked PR (it never merges, never ships).
- Orchestrator (passive): sequences in the linearised order, sole writer of state.json, enforces budgets, cuts each branch with `git town append`, opens each stacked PR, force-moves the tags, halts on escalation. No code, no judging, no merge.
- Builder, Reviewer, Judge, Document: identical to build-judge-loop.md, Roles (builder implements one increment and writes its doc payload; reviewer owns the code and can bounce on critical/major with evidence; judge owns behaviour, type-checks then runs the tiers, proves tests aren't hollow; document produces per-module and ARCHITECTURE docs, a producer never a gate). Severity, reviewer rules and the ordering invariant (no code reaches the judge without a prior reviewer pass) are build-judge-loop.md's, unchanged.

## Flow (per increment)
1. Cut the branch. `git town append` childs off the checked-out branch, so position HEAD on the parent first (never assume it):
   - first increment, tag base: `git switch <tip-branch>`.
   - first increment, origin/main base: `git fetch origin`, `git switch main`, fast-forward (local main goes stale as humans merge concurrently).
   - later increment: HEAD is already the previous increment's branch.
   Then `git town append feat/<id>-<kebab-title>` (git-town records the parent).
2. Builder implements; review loop (budget 3): reviewer reviews, bounces to builder on critical/major with evidence, else approves.
3. On approve: judge type-checks (agent-typecheck.sh), then runs the unit tier (agent-tests.sh unit), then the integration tier (agent-tests.sh integration, endpoint readiness per judge.md), proves the suite is not hollow (agent-hollow.sh). Judge loop (budget 3, separate): builder fixes -> reviewer delta-review -> judge, each cycle one attempt.
4. On judge pass: judge writes the pass report; the document agent assembles docs/modules/<id>.md and the idempotent docs/ARCHITECTURE.md section (a producer, never a gate). Single commit carries code and docs (all `.building/` output is gitignored, never committed).
5. Orchestrator opens the stacked PR: `gh pr create --base <parent-branch> --head <branch>` (headless, uses the gh keyring). The `--base` is the PARENT branch, not main; that is what makes it a stacked PR. Status goes to `pr-open`. If this increment is a feature or epic stack tip, force-move the tags (see Tags).
6. Continue: build the next increment in the linearised order, stacked on this one. No checkpoint, no pause. Repeat until the sheet is exhausted.
7. Either loop exhausts 3 -> escalate and HALT the chain (see Escalation).

## Escalation halts the chain
The stack is linear, so a defect above cannot be stacked over. On either loop exhausting 3 attempts:
- Write the escalation record to `.building/build/<feature-name>/work/<branch-name>/escalations/<YYYY-MM-DD-HHMM>.md` with a relative symlink in `.building/build/<feature-name>/escalations/` (identical to build-judge-loop.md, Escalation record): which loop exhausted, the per-pass history, the outstanding critical/major findings, a recommendation.
- HALT the run. Do NOT commit, do NOT open a PR, do NOT stack the next increment (it would build on the broken one). Leave the branch in place.
- The human fixes the increment on its existing branch, then re-runs. On re-entry the loop re-enters verification for that increment from the reviewer (the ordering invariant holds: human-fixed code is reviewed then judged before it can pass), and on pass continues stacking from there. The human may instead abandon it, which stops the run; that is the human's explicit call, never the loop's.
- No skip-and-carry-on: peeling an independent increment onto a parallel lineage would abandon incrementalism (out of scope). Self-heal the fixable, halt the unfixable, never stack over an unverified defect.

## Tags (the index, force-moved)
Tags are how a later feature finds where to stack (read at Stack base) and how a human finds a stack's tip. The loop WRITES two, force-moving each so it always points at the live tip:
- `feature/<feature-name>`: the tip of this feature's stack, force-moved every time this feature's stack tip advances (`git tag -f feature/<feature-name> <tip commit>`). `<feature-name>` is this feature's key (the folder under `.building/features/`), verbatim.
- `epic/<epic-name>`: the tip of the whole epic stack, force-moved when this feature is the epic's current tip. `<epic-name>` is the epic manifest's key (the folder under `.building/epics/`), verbatim.
- Force-move, not refuse: `git tag -f`. A re-run or a `sync --stack` rebase moves the tip commit, so the tag MUST move with it to stay a true index; refusing would leave a stale index and break unattended re-runs. Force-moving is idempotent and re-run safe.
- Tags are LOCAL by default. Push them explicitly when a PR is opened so a human (or a later run on another clone) can see the index: `git push --force origin feature/<feature-name>` (and the epic tag on the epic tip). The force is required because the tag moves.

## git-town command set
- Cut a branch: `git town append feat/<id>-<kebab-title>` (from the current tip; sets the git-town parent automatically). The name satisfies the branch-naming guard (`feat/` prefix, per claude-rules/omero-branch-naming.md).
- Open a PR: `gh pr create --base <parent-branch> --head <branch> --title <title> --body <body>`. Headless, uses the gh keyring directly. NOT `git town propose` (it opens a browser PR page, unusable unattended). `--base <parent>` makes it a stacked PR.
- Re-entry reconcile: `git town sync --stack` (rebases the whole stack onto the updated main, drops branches whose PRs shipped). See Resume.
- NEVER `git town ship`. The loop never merges. Shipping the stack is the human's, through /omero-merge-pr (contracts/merge-pr.md) or `git town ship`, done outside this loop while it keeps building.
- Auth: `gh pr create` and `git town sync` use the gh keyring and need no token prefix. Only `git town ship` needs `GITHUB_TOKEN="$(gh auth token)"` (claude-rules/omero-git-town-auth.md), and this loop never ships, so it never sets that env var. Never `git config git-town.github-token` (a plaintext token on disk is an exposure, merge-pr.md gate 4).

## Monotonic green
Green after every commit (build-judge-loop.md's guarantee), by construction: each increment's branch stacks on the previous, so it already contains all prior increments and the judge runs the full accumulated suite (both tiers) over the whole stack. A later increment cannot silently break an earlier one (its tests re-run on the later branch). The sequential guarantee, without merging into main.

## Completion (per feature queue)
A feature is complete when its final increment is `pr-open` (its PR opened, stacked) AND the `feature/<feature-name>` tag points at that tip, AND (this being the full path) each increment carried its docs. The increments are NOT merged to main by the loop; `pr-open` is the terminal per-increment status here (contrast the attended core, where `merged` is terminal). The human merges the stack later, at their own pace, while or after the queue builds.
- The epic is complete for this run when the last feature in build order is complete and `epic/<epic-name>` points at the overall tip.
- A partially or fully shipped stack (the human merged some PRs) is handled on re-entry (see Resume): merged increments become terminal `merged`, the survivors rebase, the loop continues or declares completion accordingly.

## State (state.json, schema unchanged)
state.json is exactly state.schema.md, no new field. git-town config owns the parents, so no `parent` is stored; the linearised order is recomputed deterministically from `depends_on` (Linearisation), never persisted. The loop does NOT write `mode` or `profile` (this recipe is neither): absent is fine and ignored, and no `completion` block is written (there is no completion gate on the full path).
- Statuses used: `pending`, `building`, `in-review`, `in-judgement`, `documented`, `pr-open`, `escalated`. `merged` appears only for increments the human shipped to main (caught on re-entry). `blocked` occurs only if an integration endpoint is down (judge.md). `pr-open` is the loop's terminal status.
- Sole writer is the orchestrator, on every transition. The bootstrap (state.json absent) initialises every increment `pending`, counts 0, branch null, per state.schema.md.
- The work folder, records, channels, escalation records and gitignore rule are exactly build-judge-loop.md, State and channels: `.building/build/<feature-name>/work/<branch-name>/` holds builder.md, review-pass-N.md, judge.md (on pass), doc-payload.md; nothing under `.building/` is ever committed.

## Resume after interruption (and partial ship)
The loop is resumable from state.json plus git-town config plus the remote. On re-entry, BEFORE building anything, in order:
1. Read state.json (the feature named by the sheet path), additively sync the sheet into it (append any new sheet id as pending, never rewrite an existing key), validate with `scripts/validate-state.sh <state.json> <sheet>`. A non-zero exit STOPS, naming the fix (state.schema.md). If state.json is absent, bootstrap it (see State) and treat as a fresh start.
2. Reconcile the shipped bottom of the stack: for every increment currently `pr-open`, query `gh pr view <branch> --json mergedAt -q .mergedAt`. A populated mergedAt promotes that increment to `merged` (the human shipped it); anything else leaves it `pr-open`. This is how the concurrent-merge flow is picked up: the human ships PRs while the loop is idle, and the loop learns which on re-entry.
3. Rebase the survivors: `git town sync --stack`. git-town rebases the still-open branches onto the updated main and drops the branches whose PRs shipped. This updates the git-town parents (the stack topology) to match reality after the partial ship.
4. Force-move the tags to the post-rebase tips (Tags), since the rebase moved the tip commits.
5. Resume building: continue the linearised order from the first increment not yet terminal. Per-status routing:
   - `pending` = cut and build (stacked on the current tip).
   - `building`/`in-review`/`in-judgement` = resume that role at the recorded count (at most one increment is mid-build, since the loop builds one at a time).
   - `documented` = open the stacked PR.
   - `pr-open` = already terminal for the loop (left after reconcile step 2 found it unmerged); nothing to do but count it done.
   - `merged` = the human shipped it; terminal, skip.
   - `escalated` = waiting for the human's fix on the branch (see Escalation); do not auto-resume, re-enter verification only when the human says continue.
   - `blocked` = endpoint was down; re-check readiness (judge.md) and continue.
   If an increment's branch exists but its status implies it should not, report the conflict and ask; never silently reuse or delete a branch.
6. If every increment is terminal (`pr-open` or `merged`) and the tags point at the tips, the feature is complete (see Completion); say so and stop.

A re-entry never rebuilds a merged or pr-open increment, never re-cuts an existing branch, and never ships. It reconciles reality (what the human merged), rebases, and continues the stack.

## Gates
Exactly build-judge-loop.md's gates, minus the local-only and checkpoint machinery this recipe removes:
- Commit only on green; the judge's green is the commit gate (the only tree change between judgement and commit is the document agent's docs, which cannot affect tests).
- The judge's two behavioural gates (the type-check gate, the hollow-test check) are judge.md's, each a single named `.building/scripts/` runner, verdict by exit code (agent-runner.md).
- Ordering invariant: no code reaches the judge without a prior reviewer pass, in step 2 and every judge cycle.
- Scope guard: builder touches only this increment (reviewer owns).
- Conventional commits. Idempotent infra. Escalation halts the chain (above); an endpoint-down increment is `blocked` per judge.md.

## What this recipe removes versus build-judge-loop.md
Stated so the fork is auditable: this recipe has NO checkpoint and NO decision widget (it runs unattended to exhaustion), NO modes (sequential/parallel; it is always incremental-linear), NO local-only flow (a remote is required), NO merge into main by the loop (it only proposes; the human ships), and NO cross-queue OTHER QUEUES checkpoint slot (there is no checkpoint). Everything else, the four roles, the review and judge loops, the budgets, the gates, judge.md's verification, the `.building/` layout and state.schema.md, is unchanged.
