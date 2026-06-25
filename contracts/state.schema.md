# State schema (state.json)

The build loop's per-feature recovery record and cross-conversation memory: one JSON file per feature queue at `.building/build/<feature-name>/state.json`. This is a cross-party interface, not a private scratch file. It is read by the loop on entry, by the checkpoint board, by the cross-queue OTHER QUEUES scan (a sibling queue reading this one, see build-judge-loop.md, Multiple feature queues), and it is rebuilt by the reconstruction recovery path. Referenced by build-judge-loop.md. Single source of truth for the shape; the prose in build-judge-loop.md is operational, this is the structure.

## Structure
- sheet: string. Path to the feature's increment sheet this queue builds, `.building/features/<feature-name>/increments.md`.
- conventions: string. Path to the project conventions file (CLAUDE.md).
- mode: string, OPTIONAL. `sequential-attended` or `parallel-attended`. Absent means sequential-attended. The loop NEVER writes this field; the human sets it (see Modes). The orchestrator is sole writer of everything else (except `profile`).
- profile: string, OPTIONAL. `full` or `lite`. Absent means full. Like `mode` the loop NEVER writes this field; the human sets it (see build-judge-loop.md, Build profile, and build-loop-full.md/build-loop-lite.md). `lite` defers the integration tier and the per-increment document agent to a completion gate.
- increments: object, keyed by increment id (the ids from the sheet, see increment-sheet.schema.md). Each value:
  - depends_on: list of increment ids. Mirrors the sheet's depends_on for this id.
  - status: one of `pending`, `building`, `in-review`, `in-judgement`, `documented`, `pr-open`, `merged`, `escalated`, `blocked`. The canonical state set; the increment-states diagram renders exactly these and the contract's stage mapping uses exactly these. In the local-only flow (no remote, see build-judge-loop.md, Remote presence) `pr-open` never occurs: the loop integrates each increment into local main itself, so a documented increment goes straight to `merged`, which then means "on local main" rather than "merged via a remote PR". The `documented` status means the same in both profiles, an increment past the judge and ready to commit; in full the document agent has run by then, in lite it is deferred to the completion gate (build-loop-lite.md), so `documented` carries no docs yet.
  - review_count: integer, 0 to 3. Review-loop attempts spent (budget 3).
  - judge_count: integer, 0 to 3. Judge-loop attempts spent (budget 3).
  - branch: string or null. The audit-named branch (`feat/<id>-<kebab-title>`, per the project branch-naming standard, see build-judge-loop.md, Branch and PR), and the PR lookup key in the GitHub flow (in the local-only flow there is no PR and it is purely the audit name). null until the branch is cut.
- completion: object, OPTIONAL, lite profile only. The loop's record of the lite completion gate (build-loop-lite.md), written by the loop (not human-set) when every increment is merged and the gate begins, absent otherwise and always absent in full. Fields:
  - integration: `pending` or `passed`. `pending` until the full accumulated integration suite passes against the finished main, then `passed`. A failure leaves it `pending` (the gate is resolved by appending a fix increment to the sheet, which builds and merges through the normal flow, after which the gate re-runs).
  - docs: `pending`, `pr-open`, or `merged`. `pending` until the documentation sweep is committed; with a remote it goes to `pr-open` on the docs PR (branch `docs/<feature-name>-completion`) and to `merged` once that PR merges; in the local-only flow the loop integrates the docs commit into main itself, so it goes straight to `merged`.

## Example
```
{
  "sheet": ".building/features/ci-pr-checks/increments.md",
  "conventions": "CLAUDE.md",
  "mode": "parallel-attended",
  "profile": "lite",
  "increments": {
    "ci-workflow": { "depends_on": [], "status": "merged", "review_count": 1, "judge_count": 1, "branch": "feat/ci-workflow-pr-checks" }
  },
  "completion": { "integration": "passed", "docs": "pr-open" }
}
```

## Validation (all must hold)
1. sheet and conventions are present, non-empty strings.
2. mode, if present, is one of the two allowed values.
3. profile, if present, is one of the two allowed values (`full` or `lite`).
4. Every increment key is an id in the sheet, and every sheet id has a key.
5. depends_on equals the sheet's depends_on for that id.
6. status is one of the nine canonical values.
7. review_count and judge_count are integers in 0..3.
8. branch is null or a non-empty string, unique across this file and across sibling queues (branch names are one git namespace).
9. completion, if present, occurs only when profile is lite; its integration is one of `pending`/`passed` and its docs is one of `pending`/`pr-open`/`merged`.

## Who writes it
- The loop, on every status transition: sole writer in normal operation.
- The bootstrap, on a feature's first build (state.json absent): every increment pending, counts 0, branch null, `mode` and `profile` not written. See build-judge-loop.md, Resume after interruption.
- The reconstruction recovery path, rebuilding a lost file from the sheet and the merged PRs.

The `completion` block (lite only) is loop-written like everything except `mode` and `profile`: the loop creates and advances it at the completion gate (build-loop-lite.md). The human sets `mode` and `profile`, and may hand-correct the file as an out-of-band recovery action (for example an increment completed outside the loop, see Reconciliation). Nothing else writes it.
