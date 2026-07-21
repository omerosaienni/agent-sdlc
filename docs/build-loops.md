# The build loop

This page frames the build phase for a human: what it is, the choices it offers, and the trade-offs behind them. The exact rules live in the contracts and are linked throughout; this page summarises and points, it does not restate. The source of truth is [`../contracts/build-judge-loop.md`](../contracts/build-judge-loop.md) (the core), with the profile deltas in [`../contracts/build-loop-full.md`](../contracts/build-loop-full.md) and [`../contracts/build-loop-lite.md`](../contracts/build-loop-lite.md).

The build phase delivers a sheet one increment at a time: a single loop, one [per-increment cycle](roles.md), one set of gates, one `.building/` workspace, one checkpoint. In its attended form (the default, described first below) a human decides at every checkpoint: with a GitHub remote the human merges every PR and the merge is the final gate; with no remote the loop commits each increment locally and the judge's pass is the gate. There is also an [unattended, stacked form](#the-unattended-path-stacked-builds) that removes the human from the build queue, stacking increments as one linear git-town stack and proposing PRs it never merges; it is covered in its own section below.

![The build and judge loop for one increment](diagrams/build-judge-loop.svg)

## The per-increment cycle

The four roles and their ordering are summarised in [roles.md](roles.md); the full cycle, budgets and escalation are in the core contract (Flow). In short: builder, then reviewer (can bounce), then judge (runs the tiers, proves tests aren't hollow), then document, then commit and PR (or local integration). Either loop exhausting three attempts escalates and freezes that increment's dependents. The per-increment state machine is [`diagrams/increment-states.svg`](diagrams/increment-states.svg).

The same cycle seen as an artifact flow, what each role produces and hands to the next (the commit carries code and docs, the reports stay local under `.building/`):

![The per-increment cycle as a data flow: shared inputs to builder to reviewer to judge to document to commit](diagrams/loop-data-flow.svg)

## Two modes: what you are choosing

`mode` is a per-queue setting (sequential-attended default, or parallel-attended); the mechanics are in the core contract (Modes). The choice is about control, not speed:

- **sequential-attended** builds one increment at a time, each on the previous one's merged code, and keeps main provably green after every merge. It fits work that genuinely builds on itself.
- **parallel-attended** decouples build order from merge order: an increment becomes eligible the moment its dependencies are merged, and you can build a fan-out of independent increments back to back, leaving their PRs open to merge as a batch. It fits a wide set of independent increments.

**Parallel means eligible, not concurrent.** It is still one build at a time with a checkpoint between each, never simultaneous builds. The trade is honest: parallel green is per-branch, so two siblings each green alone can combine into a red main, reconciled at the next judge run or a final combined run (Monotonic green in the contract). Sequential pays for its always-green main by serialising. See [`diagrams/git-topology.svg`](diagrams/git-topology.svg) and [`diagrams/parallel-topology.svg`](diagrams/parallel-topology.svg).

## GitHub is optional

A remote is not required to build. The loop detects remote presence itself and picks a flow; this is an environment fact, not a mode. The detection rule and the per-flow behaviour are in the core contract (Remote presence). The human-relevant points:

- **With a remote**: each increment is a PR into main that you merge.
- **No remote**: the loop commits each increment to local main itself, no push, no PR, so the checkpoint never offers **Merge the PR**. The two modes coincide here (no open PRs, so nothing to decouple). Adding a remote later resumes the PR flow for subsequent increments.

## Build profiles: full and lite

`profile` is a per-queue setting orthogonal to `mode` (full default, or lite); the mechanics are in [build-loop-full.md](../contracts/build-loop-full.md) and [build-loop-lite.md](../contracts/build-loop-lite.md). The choice is verification depth vs iteration speed:

- **full** verifies and documents every increment before it ships (both tiers, docs, per increment). No completion gate. The thorough default.
- **lite** gates each increment on the unit tier only and defers the integration tier and the docs to a single **completion gate** at the end, so no live endpoint is needed while iterating. The deferrals are reconciled before the queue is declared complete.

The trade is honest: lite buys speed at the cost of per-increment integration-green and per-increment docs, both established once at the end rather than each increment.

## The fast path: build-quick

`omero-build-quick` is a separate fast build, its own skill rather than a profile (it is not selected by the `profile` field); the deltas over the core are in [`../contracts/build-quick.md`](../contracts/build-quick.md). It runs the same loop, the same four roles and the same review and judge discipline, and changes only two things:

- **verification depth**: the judge gates each increment on the type-check and unit tier only (plus the hollow-test check), never the integration tier and never an endpoint check, so no live endpoint or Docker is ever needed;
- **documentation**: the document role does not run, so increments carry code only and there is no completion gate.

The trade is the sharpest of the three: build-quick buys the most speed for the least proof, an increment is verified at the unit level only, with integration left entirely to you outside the loop. Use it for fast inner-loop work where unit coverage is the bar; use `omero-build-full` (full or lite) when integration or documentation must be part of the build.

## The unattended path: stacked builds

Everything above is attended: the loop stops at a checkpoint after every increment and a human merges each PR. The two **stacked** builders remove the human from the build queue entirely, so you can work the open PRs while the queue keeps building. They are their own skills, `omero-build-full-stacked` and `omero-build-quick-stacked`, with their own contracts ([`../contracts/build-stacked.md`](../contracts/build-stacked.md), the full path, and [`../contracts/build-quick-stacked.md`](../contracts/build-quick-stacked.md), the unit-only delta over it, exactly as build-quick is a delta over the core). They run the same four roles and the same review and judge discipline; what changes is how increments reach the remote and who is in the loop.

![Unattended stacked topology: one linear git-town stack, each increment stacked on the previous, features chained by tag](diagrams/stacked-topology.svg)

- **Unattended, incremental, one linear stack.** The loop builds one increment at a time and stacks each on the previous one's branch, forming a single linear git-town stack (the DAG is linearised into one chain, `scripts/stack-order.sh`; siblings are chained, never forked). There is no checkpoint: it builds every increment back to back and stops only when the sheet is exhausted or an increment escalates.
- **Stacked across features.** A feature's first increment is not cut from main; it is stacked on the previous feature's stack tip, found through the `feature/<name>` tag. So a run continues a stack another feature left open, and a program builds as one growing stack. Tags are the index: `feature/<name>` marks each feature tip, `epic/<name>` the overall tip, force-moved so they always point at the live tip.
- **It proposes, it never merges.** A remote is required (there is no local-only stacked flow). Each increment opens one stacked PR (`gh pr create --base <parent>`, the base being the parent branch, not main), but the loop never merges and never ships. You merge the stack bottom-up at your own pace, with `omero-merge-pr` or `git town ship`, while the queue builds ahead of you. On re-entry the loop reconciles whatever you merged, rebases the survivors (`git town sync --stack`) and continues.
- **git-town owns the stack.** Branch parents live in git-town config, not `state.json` (whose schema is unchanged); `git town append` cuts each branch and `git town sync --stack` reconciles on re-entry. The loop drives git-town, it does not reimplement stacking.

The trade: control for throughput. You give up the per-increment checkpoint and the loop's own merge gate; you get a whole feature (or a chain of features) built without waiting on you, left as a reviewable stack of PRs. Full stacked when integration and docs must be part of the stack, quick stacked for the fastest unit-only path. Escalation halts the whole chain (the stack is linear, so nothing builds past a broken increment) until you fix it on its branch and re-run (see [`../contracts/build-stacked.md`](../contracts/build-stacked.md), Escalation halts the chain).

## Multiple queues

A project can hold several feature queues at once, each its own sheet and state, built and completed independently. The per-queue isolation and the three project-wide shared things (setup, main's greenness, the cross-queue checkpoint reminder) are in the core contract (Multiple feature queues).

## The dependency graph

The sheet's `depends_on` edges form a DAG, acyclic by schema validation, which is what guarantees the loop can never deadlock. An increment is eligible when all its dependencies are merged; merging one frees its dependents. The checkpoint board is this graph filtered by what is merged. The document agent renders the same graph as Mermaid into `docs/ARCHITECTURE.md`.

## The checkpoint

After every increment, and on entry and on reclaim, the loop renders a checkpoint: a board (rendered verbatim from a template so it reads identically across conversations) then a fixed decision widget. The board's four sections, the widget verbs and their per-mode applicability are specified in the core contract (Checkpoint); the human point is that the wording never changes between conversations, and the only mode difference is when **Carry on** / **Build a specific one** appear (always in parallel when the ready set is non-empty; in sequential only when nothing else is in flight). See [`diagrams/checkpoint.svg`](diagrams/checkpoint.svg).

## Validating the loop itself

Before a real build, exercise the orchestration on a trivial increment. [`../examples/smoke-test-sheet.md`](../examples/smoke-test-sheet.md) is a one-increment sheet (a function returning 42 with a unit test) that runs the whole loop quickly. If it passes cleanly the orchestration works; if it breaks you have found the problem on a trivial case.

## Recovery

The loop is robust to interruption and keeps you in control. Re-running after an interruption reads `state.json`, reconciles open PRs, finds where it stopped, and renders the checkpoint before doing anything; declining (Wait) changes nothing. An escalated increment waits for your fix on its branch, then re-enters verification from the reviewer. The full resume and escalation-recovery rules are in [`../contracts/build-judge-loop.md`](../contracts/build-judge-loop.md) (Resume, Escalation recovery).

## Where the loop keeps its work

Everything the loop generates lives under one gitignored folder, `.building/`; commits carry only the increment. See [building-folder.md](building-folder.md).

## Tests

Two tiers (unit, integration), the judge's responsibility; the rules are in the judge contract (judge.md, Test tiers). Unit runs anywhere, integration needs live endpoints, a tier that should have tests but selects zero is a hollow suite and fails.
