# State schema (state.json)

The build loop's per-feature recovery record and cross-conversation memory: one JSON file per feature queue at `.building/build/<feature-name>/state.json`. A cross-party interface, not a private scratch file. Read by the loop on entry, by the checkpoint board, by the cross-queue OTHER QUEUES scan (a sibling queue reading this one, see build-judge-loop.md, Multiple feature queues), and rebuilt by the reconstruction recovery path. Referenced by build-judge-loop.md. Single source of truth for the shape; the prose in build-judge-loop.md is operational, this is the structure.

## Structure
- sheet: string. Path to this queue's increment sheet, `.building/features/<feature-name>/increments.md`.
- conventions: string. Path to the project conventions file (CLAUDE.md).
- mode: string, OPTIONAL. `sequential-attended` or `parallel-attended`. Absent means sequential-attended. The loop NEVER writes this field; the human sets it (see build-judge-loop.md, Modes). The orchestrator is sole writer of everything else (except `profile`).
- profile: string, OPTIONAL. `full` or `lite`. Absent means full. Like `mode` the loop NEVER writes this field; the human sets it (see build-judge-loop.md, Build profile, and build-loop-full.md/build-loop-lite.md). `lite` defers the integration tier and the per-increment document agent to a completion gate.
- increments: object, keyed by increment id (the ids from the sheet, see increment-sheet.schema.md). Each value:
  - depends_on: list of increment ids. Mirrors the sheet's depends_on for this id.
  - status: one of `pending`, `building`, `in-review`, `in-judgement`, `documented`, `pr-open`, `merged`, `escalated`, `blocked`. The canonical state set; the increment-states diagram renders exactly these and the contract's stage mapping uses exactly these. In the local-only flow (no remote, see build-judge-loop.md, Remote presence) `pr-open` never occurs: the loop integrates each increment into local main itself, so a documented increment goes straight to `merged`, which then means "on local main" rather than "merged via a remote PR". `documented` means the same in both profiles, an increment past the judge and ready to commit; in full the document agent has run by then, in lite it is deferred to the completion gate (build-loop-lite.md), so `documented` carries no docs yet.
  - review_count: integer, 0 to 3. Review-loop attempts spent (budget 3).
  - judge_count: integer, 0 to 3. Judge-loop attempts spent (budget 3).
  - branch: string or null. The audit-named branch (`feat/<id>-<kebab-title>`, per the project branch-naming standard, see build-judge-loop.md, Branch and PR), and the PR lookup key in the GitHub flow (in local-only flow there is no PR and it is purely the audit name). null until the branch is cut.
- completion: object, OPTIONAL, lite profile only. The loop's record of the lite completion gate (build-loop-lite.md), written by the loop (not human-set) when every increment is merged and the gate begins, absent otherwise and always absent in full. Fields:
  - integration: `pending`, `passed`, or `failed`. Loop-written. `pending` before the run (or while it runs); `passed` once the full accumulated integration suite passes against the finished main; `failed` if that run fails. `failed` is distinct from `pending` so a reclaiming conversation surfaces the failure and waits rather than silently re-running it. The failure handling and the merge re-arm (a merge resetting `failed` to `pending`) are the single source build-loop-lite.md, Completion gate; not restated here.
  - docs: `pending`, `pr-open`, or `merged`. `pending` until the documentation sweep is committed; with a remote it goes to `pr-open` on the docs PR (branch `docs/<feature-name>-completion`) and to `merged` once that PR merges; in local-only flow the loop integrates the docs commit into main itself, so it goes straight to `merged`.

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
9. completion, if present, occurs only when profile is explicitly lite; its integration is one of `pending`/`passed`/`failed` and its docs is one of `pending`/`pr-open`/`merged`. (Created once every increment is first merged, but then legitimately persists while a fix increment appended after an integration failure is in flight, so it may coexist with non-merged increments; this is not a validation constraint.)

## Validation tooling
- Enforced mechanically by `scripts/validate-state.sh <state.json> <sheet>`: all nine rules.
- The script is the source of truth for these checks; on disagreement with this prose, fix the prose (the rules are the spec, the script is the gate).
- It always checks its inputs: rules 4-5 compare state against the sheet, so it re-validates the sheet with validate-sheet.sh first rather than trusting it (exit 5 if the sheet itself fails).
- Run it POST-SYNC: after the loop additively syncs the sheet into state.json, before it acts, so the rule 4-5 agreement holds.
- Exits: 0 valid, 1 rejection (fixable), 3 node absent, 4 structural defect, 5 the sheet failed, 64 usage. A defect outranks a rejection.
- Defect vs rejection: a state<->sheet DISAGREEMENT (rules 4, 5: missing/extra ids, depends_on mismatch) or non-JSON is a structural DEFECT (exit 4) — the producer desynced state from the sheet, an out-of-band reconciliation. Every other failure (bad count, status, branch, mode, profile, completion) is a fixable REJECTION (exit 1).
- Fixtures: tests/fixtures/states/ (valid + one per failing rule), run by tests/run.sh and the tests workflow on every PR into main.

## Who writes it
- The loop, on every status transition: sole writer in normal operation.
- The bootstrap, on a feature's first build (state.json absent): every increment pending, counts 0, branch null, `mode` and `profile` not written. See build-judge-loop.md, Resume after interruption.
- The reconstruction recovery path, rebuilding a lost file from the sheet and the merged PRs.

The `completion` block (lite only) is loop-written like everything except `mode` and `profile`: the loop creates and advances it at the completion gate (build-loop-lite.md). The human sets `mode` and `profile`, and may hand-correct the file as an out-of-band recovery action (for example an increment completed outside the loop, see build-judge-loop.md, Reconciliation). Nothing else writes it.
