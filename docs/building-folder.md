# The .building folder

Everything the build loop generates while it works lives under one folder: `.building/`. It is gitignored in full, so none of it is ever committed. Your commits and pull requests carry only code and docs, the actual deliverable. `.building/` is the loop's private workspace on your machine.

## Structure

```
.building/
  build/                          the loop's own state
    state.json                    mode, sheet/conventions paths, per-unit status, loop counts, branch names
    setup-ok                      the setup receipt (proves the environment was ready)
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

## The three parts

**build/** is the loop's own bookkeeping. `state.json` carries the project-level `mode` (sequential-attended or parallel-attended, set once and persisting across conversations) alongside the sheet and conventions paths, and tracks where each unit is (its status, how many review and judge attempts it has had, its branch name). `setup-ok` is the receipt the setup gate writes to prove the environment was ready; the loop checks for it on entry.

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
./scripts/project-setup.sh --yes
```

After this, `state.json` is at `.building/build/state.json`, the receipt is regenerated at `.building/build/setup-ok`, and the next loop run uses the new structure throughout.
