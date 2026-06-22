---
name: omero-build-loop
description: Deliver a deliverable sheet as small, independently verified increments. Four roles, a review loop and a judge loop, one branch and one GitHub PR per deliverable into main. Attended, mode-driven (sequential-attended or parallel-attended, read from state.json). Judge runs unit then integration tiers.
disable-model-invocation: true
argument-hint: "[path to the deliverable sheet]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm:*), Bash(npx:*), Bash(make:*), Bash(docker:*), Bash(cd:*), Bash(ls:*), Bash(cat:*), Bash(echo:*), Bash(mkdir:*), Bash(rm:*), Bash(find:*), Bash(grep:*), Bash(printf:*), Bash(chmod:*), Bash(tail:*), Bash(head:*), Bash(graphify query:*), Bash(./scripts/agent-tests.sh:*), Bash(./scripts/agent-hollow.sh:*), Read, Edit, Write
---
Operate the build-judge loop defined in
{{SDLC_REPO}}/contracts/build-judge-loop.md. Read that contract now and follow it
exactly. It is the single source of truth for the workflow; this skill does not
restate it.

The deliverable sheet for this run is at: $ARGUMENTS

On entry, do exactly what the contract says: validate the sheet against
{{SDLC_REPO}}/contracts/deliverable-sheet.schema.md, check the setup receipt,
read the project CLAUDE.md, and proceed per the contract. Do not build against an
invalid sheet, and do not run setup yourself (the contract explains the receipt).

If anything in the contract is ambiguous for this project, stop and ask rather
than guessing. Do not improvise workflow behaviour that the contract does not
state.
