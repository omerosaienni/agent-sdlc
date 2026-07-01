# The .building folder

Everything the build loop generates while it works, plus the feature sheets it builds from, lives under one folder: `.building/`. It is gitignored in full, so none of it is ever committed. Your commits and pull requests carry only the actual increment (code, and docs too in the full profile), never anything under `.building/`. `.building/` is the loop's private workspace on your machine.

![Committed versus gitignored at a glance](diagrams/file-layout.svg)

The canonical `.building/` tree (the source of truth for the layout) is in [`../contracts/build-judge-loop.md`](../contracts/build-judge-loop.md) (State and channels). This page explains what each part is for and what you actually read, rather than repeating the tree.

## The parts

**features/** holds the feature sheets the build loop builds from, one folder per feature, keyed by a short kebab-case feature name you give the design partner (so `greeting-spike`, not a path). The design partner writes `increments.md` here; re-running the same feature name overwrites it, and different features sit side by side. The sheet is the build's input, but it lives under gitignored `.building/` like everything else in the pipeline workspace, so it stays local rather than being committed.

**build/** is the loop's own bookkeeping, one folder per feature so two features never overwrite each other. `build/<feature-name>/` mirrors `features/<feature-name>/`: a `state.json` for that feature queue (its structure is [`../contracts/state.schema.md`](../contracts/state.schema.md)), its `work/` folders, and its `escalations/` index. The state file carries that queue's `mode` (sequential-attended or parallel-attended) and `profile` (full or lite), both set per queue and persisting across conversations, alongside the sheet and conventions paths, and tracks where each unit is (its status, how many review and judge attempts it has had, its branch name). The loop knows which queue you mean from the sheet path you pass it, so switching features never touches another's state. `setup-ok` and `scripts/` sit one level up, at the top of `.building/`, because setup proves the project (not a feature) and every queue shares it.

**scripts/** holds the loop's own runners: the agent test runner the judge uses for its terse verification passes, the hollow-check runner it uses for the negative run, and the type-check runner it runs as a gate before the tiers. They are project-level (the same runners serve every feature), so they sit at the top of `.building/`, not under any one feature. The setup gate writes all three runners (test, hollow-check and type-check) here from the shared templates and proves each runnable, so one actor owns runner placement; the build loop's judge runs the type-check as a gate before the tiers. They are loop machinery, not part of the project, so they live under gitignored `.building/` rather than the committed `scripts/`, which carries only the project's own scripts.

**work/** is where the agents record what they did, one folder per unit, named after that unit's audit-named branch (so `feat/db-pool-connection-helper`, not an opaque `build/3`). The builder, the reviewer and the judge each write their file here (the builder also writes the documentation slice, `doc-payload.md`, for the document agent); the document agent reads these but writes its output into the committed `docs/` tree, not here. These files ARE the record: there is no second copy kept anywhere. Re-running a unit overwrites its folder, only the latest run is kept. Within one run, the review passes accumulate (review-pass-1, review-pass-2, and so on) so you can see the back-and-forth.

**escalations/** is a convenience index, one per feature queue at `build/<feature-name>/escalations/`. When a unit escalates (a review or judge loop hit its limit), the escalation record is written once, inside that unit's own folder at `build/<feature-name>/work/<branch-name>/escalations/<date-time>.md`. A symlink of the same name is then placed in that queue's `escalations/`, so you can list every escalation in the queue in date order without hunting through the work folders. The symlink is a relative pointer (`../work/...`), not a copy, so the real file stays in one place and the folder can be moved or renamed without breaking the links.

## Why one folder

Before, loop output was scattered across three hidden folders and copied between two of them, which made it unclear what was a working file, what was a kept record, and what was committed. Now there is one rule to remember: everything the loop produces is under `.building/`, and `.building/` is never committed. The gitignore is a single line:

```
.building/
```

## What you actually read

If you want to see how a unit was built, open `build/<feature-name>/work/<branch-name>/` and read the files in order: builder, review passes, judge. If you want to see what has gone wrong in a queue, list `build/<feature-name>/escalations/`. You will not normally need to touch `build/`, that is the loop's own state, though a queue's `state.json` is readable if you want to see its progress at a glance.
