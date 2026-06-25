---
name: omero-build-quick
description: Deliver a feature sheet as small, independently verified increments, the fast way. Builder, reviewer and judge plus a passive orchestrator, a review loop and a judge loop, one branch per increment into main (one GitHub PR per increment with a remote, otherwise a local commit). Attended, mode-driven (sequential-attended or parallel-attended, read from state.json). Judge type-checks then runs the unit tier only, no integration tier and no documentation.
disable-model-invocation: true
argument-hint: "[path to the feature sheet]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm:*), Bash(npx:*), Bash(make:*), Bash(docker:*), Bash(cd:*), Bash(ls:*), Bash(cat:*), Bash(echo:*), Bash(mkdir:*), Bash(rm:*), Bash(find:*), Bash(grep:*), Bash(printf:*), Bash(chmod:*), Bash(tail:*), Bash(head:*), Bash(.building/scripts/agent-tests.sh:*), Bash(.building/scripts/agent-hollow.sh:*), Bash(.building/scripts/agent-typecheck.sh:*), Read, Edit, Write
---
Operate the build-quick loop defined in {{SDLC_REPO}}/contracts/build-quick.md. Read that contract now and follow it exactly. It is the source of truth for this workflow.

The feature sheet for this run is at: $ARGUMENTS

On entry: validate the sheet against {{SDLC_REPO}}/contracts/increment-sheet.schema.md, check the setup receipt at .building/setup-ok, read the project CLAUDE.md, and proceed per the contract. Do not build against an invalid sheet and do not run setup yourself.

If anything in the contract is ambiguous for this project, stop and ask rather than guessing.
