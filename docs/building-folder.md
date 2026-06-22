# The .building folder

Everything the build loop generates while it works, plus the design sheets it builds from, lives under one folder: `.building/`. It is gitignored in full, so none of it is ever committed. Your commits and pull requests carry only code and docs, the actual deliverable. `.building/` is the loop's private workspace on your machine.

## Structure

```
.building/
  design/                         the design sheets, one folder per design
    greeting-spike/               keyed by the design slug
      deliverables.md             the schema-valid sheet the loop builds
  build/                          the loop's own state
    state.json                    mode, sheet/conventions paths, per-unit status, loop counts, branch names
    setup-ok                      the setup receipt (proves the environment was ready)
  scripts/                        the loop's own runners, placed by setup (never committed)
    agent-tests.sh                the judge's terse test runner
    agent-hollow.sh               the judge's hollow-check runner
  work/                           the agents' working files, one folder per unit
    d3-connection-helper/         keyed by the audit-named branch
      builder.md                  what the builder did
      review-pass-1.md            the reviewer's record for each pass
      judge.md                    the judge's verdict (written on pass)
      doc-payload.md              the builder's slice for the document agent
    d4-crud/
      builder.md
      review-pass-1.md
      review-pass-2.md
      review-pass-3.md
      escalations/                present only if this unit escalated
        2026-06-21-1430.md        the escalation record (single source of truth)
  escalations/                    a flat chronological index across all units
    2026-06-21-1430.md  ->  ../work/d4-crud/escalations/2026-06-21-1430.md
```

## The parts

**design/** holds the design sheets the build loop builds from, one folder per design, keyed by a short slug you give the design partner (so `greeting-spike`, not a path). The design partner writes `deliverables.md` here; re-running the same slug overwrites it, and different designs sit side by side. The sheet is the build's input, but it lives under gitignored `.building/` like everything else in the pipeline workspace, so it stays local rather than being committed.

**build/** is the loop's own bookkeeping. `state.json` carries the project-level `mode` (sequential-attended or parallel-attended, set once and persisting across conversations) alongside the sheet and conventions paths, and tracks where each unit is (its status, how many review and judge attempts it has had, its branch name). `setup-ok` is the receipt the setup gate writes to prove the environment was ready; the loop checks for it on entry.

**scripts/** holds the loop's own runners: the agent test runner the judge uses for its terse verification passes, and the hollow-check runner it uses for the negative run. The setup gate writes them here from the shared templates and proves them; they are loop machinery, not part of the project, so they live under gitignored `.building/` rather than the committed `scripts/`, which carries only the project's own scripts.

**work/** is where the agents record what they did, one folder per unit, named after that unit's audit-named branch (so `d3-connection-helper`, not `build/3`). The builder, reviewer, judge, and document agent each write their file here. These files ARE the record: there is no second copy kept anywhere. Re-running a unit overwrites its folder, only the latest run is kept. Within one run, the review passes accumulate (review-pass-1, review-pass-2, and so on) so you can see the back-and-forth.

**escalations/** is a convenience index. When a unit escalates (a review or judge loop hit its limit), the escalation record is written once, inside that unit's own folder at `work/<branch-name>/escalations/<date-time>.md`. A symlink of the same name is then placed in the top-level `.building/escalations/`, so you can list every escalation across all units in date order without hunting through the work folders. The symlink is a relative pointer, not a copy, so the real file stays in one place and the folder can be moved or renamed without breaking the links.

## Why one folder

Before, loop output was scattered across three hidden folders and copied between two of them, which made it unclear what was a working file, what was a kept record, and what was committed. Now there is one rule to remember: everything the loop produces is under `.building/`, and `.building/` is never committed. The gitignore is a single line:

```
.building/
```

## What you actually read

If you want to see how a unit was built, open `work/<branch-name>/` and read the files in order: builder, review passes, judge. If you want to see what has gone wrong across the project, list `.building/escalations/`. You will not normally need to touch `build/`, that is the loop's own state, though `state.json` is readable if you want to see progress at a glance.

## Migrating an existing project

A project built under the old layout (separate `.build-loop/`, `.deliverable/`, and `reports/` folders) moves to the new structure like this. The loop state is the only thing that must be preserved; the rest is regenerated.

```
# from the project root
mkdir -p .building/build
git mv .build-loop/state.json .building/build/state.json 2>/dev/null || mv .build-loop/state.json .building/build/state.json
mv .build-loop/setup-ok .building/build/setup-ok 2>/dev/null || true

# the old working and report folders are not migrated, they are regenerated per run
rm -rf .build-loop .deliverable reports

# gitignore: drop the old rules, add the one new rule
# (edit .gitignore: remove .build-loop/, .deliverable/, reports/ ; add .building/)

# re-run the setup gate so the receipt lands at the new path
# (via the skill: /omero-project-setup --yes)
```

After this, `state.json` is at `.building/build/state.json`, the receipt is regenerated at `.building/build/setup-ok`, and the next loop run uses the new structure throughout.
