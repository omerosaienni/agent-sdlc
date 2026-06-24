# The .building folder

Everything the build loop generates while it works, plus the design sheets it builds from, lives under one folder: `.building/`. It is gitignored in full, so none of it is ever committed. Your commits and pull requests carry only code and docs, the actual deliverable. `.building/` is the loop's private workspace on your machine.

![Committed versus gitignored at a glance](diagrams/file-layout.svg)

## Structure

```
.building/
  setup-ok                        the setup receipt (project-level, proves the environment was ready)
  scripts/                        the loop's own runners, placed by setup (project-level, never committed)
    agent-tests.sh                the judge's terse test runner
    agent-hollow.sh               the judge's hollow-check runner
    agent-typecheck.sh            the judge's type-check runner
  design/                         the design sheets, one folder per design
    greeting-spike/               keyed by the design name
      deliverables.md             the schema-valid sheet the loop builds
  build/                          the loop's own state, one folder per design (deliverable queue)
    greeting-spike/               mirrors design/greeting-spike/
      state.json                  this queue's mode, sheet/conventions paths, per-unit status, loop counts, branches
      work/                       the agents' working files, one folder per unit
        d3-connection-helper/     keyed by the audit-named branch
          builder.md              what the builder did
          review-pass-1.md        the reviewer's record for each pass
          judge.md                the judge's verdict (written on pass)
          doc-payload.md          the builder's slice for the document agent
        d4-crud/
          review-pass-1..3.md
          escalations/            present only if this unit escalated
            2026-06-21-1430.md    the escalation record (single source of truth)
      escalations/                this queue's flat chronological index
        2026-06-21-1430.md  ->  ../work/d4-crud/escalations/2026-06-21-1430.md
```

## The parts

**design/** holds the design sheets the build loop builds from, one folder per design, keyed by a short kebab-case design name you give the design partner (so `greeting-spike`, not a path). The design partner writes `deliverables.md` here; re-running the same design name overwrites it, and different designs sit side by side. The sheet is the build's input, but it lives under gitignored `.building/` like everything else in the pipeline workspace, so it stays local rather than being committed.

**build/** is the loop's own bookkeeping, one folder per design so two designs never overwrite each other. `build/<design-name>/` mirrors `design/<design-name>/`: a `state.json` for that deliverable queue (its structure is [`../contracts/state.schema.md`](../contracts/state.schema.md)), its `work/` folders, and its `escalations/` index. The state file carries that queue's `mode` (sequential-attended or parallel-attended, set per queue and persisting across conversations) alongside the sheet and conventions paths, and tracks where each unit is (its status, how many review and judge attempts it has had, its branch name). The loop knows which queue you mean from the sheet path you pass it, so switching designs never touches another's state. `setup-ok` and `scripts/` sit one level up, at the top of `.building/`, because setup proves the project (not a design) and every queue shares it.

**scripts/** holds the loop's own runners: the agent test runner the judge uses for its terse verification passes, the hollow-check runner it uses for the negative run, and the type-check runner it runs as a gate before the tiers. They are project-level (the same runners serve every design), so they sit at the top of `.building/`, not under any one design. The setup gate writes the test and hollow-check runners here from the shared templates and proves them; the type-check runner is placed and run by the build loop's judge. They are loop machinery, not part of the project, so they live under gitignored `.building/` rather than the committed `scripts/`, which carries only the project's own scripts.

**work/** is where the agents record what they did, one folder per unit, named after that unit's audit-named branch (so `d3-connection-helper`, not `build/3`). The builder, reviewer, judge, and document agent each write their file here. These files ARE the record: there is no second copy kept anywhere. Re-running a unit overwrites its folder, only the latest run is kept. Within one run, the review passes accumulate (review-pass-1, review-pass-2, and so on) so you can see the back-and-forth.

**escalations/** is a convenience index, one per design queue at `build/<design-name>/escalations/`. When a unit escalates (a review or judge loop hit its limit), the escalation record is written once, inside that unit's own folder at `build/<design-name>/work/<branch-name>/escalations/<date-time>.md`. A symlink of the same name is then placed in that queue's `escalations/`, so you can list every escalation in the queue in date order without hunting through the work folders. The symlink is a relative pointer (`../work/...`), not a copy, so the real file stays in one place and the folder can be moved or renamed without breaking the links.

## Why one folder

Before, loop output was scattered across three hidden folders and copied between two of them, which made it unclear what was a working file, what was a kept record, and what was committed. Now there is one rule to remember: everything the loop produces is under `.building/`, and `.building/` is never committed. The gitignore is a single line:

```
.building/
```

## What you actually read

If you want to see how a unit was built, open `build/<design-name>/work/<branch-name>/` and read the files in order: builder, review passes, judge. If you want to see what has gone wrong in a queue, list `build/<design-name>/escalations/`. You will not normally need to touch `build/`, that is the loop's own state, though a queue's `state.json` is readable if you want to see its progress at a glance.

## Migrating an existing project

A project built under the old layout (separate `.build-loop/`, `.deliverable/`, and `reports/` folders) moves to the new structure like this. The receipt regenerates and the work folders are regenerated per run; the only thing worth preserving is each design's `state.json`, and even that is a cache the loop can rebuild from git (see below).

```
# from the project root
mkdir -p .building

# the receipt is now project-level, at the top of .building/
mv .build-loop/setup-ok .building/setup-ok 2>/dev/null || true

# state is now per design: place each old state.json under its design name,
# matching the design folder it builds (here, greeting-spike)
mkdir -p .building/build/greeting-spike
git mv .build-loop/state.json .building/build/greeting-spike/state.json 2>/dev/null \
  || mv .build-loop/state.json .building/build/greeting-spike/state.json 2>/dev/null || true

# the old working and report folders are not migrated, they are regenerated per run
rm -rf .build-loop .deliverable reports

# gitignore: drop the old rules, add the one new rule
# (edit .gitignore: remove .build-loop/, .deliverable/, reports/ ; add .building/)

# re-run the setup gate so the receipt lands at the new path
# (via the skill: /omero-project-setup --yes)
```

After this, the receipt is at `.building/setup-ok` and each queue's state is at `.building/build/<design-name>/state.json`. If a state file is lost or was never per-design, it can be rebuilt: it is a cache, and the source of truth for which deliverables merged is git, which the loop reconciles from the remote on the next run.
