---
name: omero-build-full
description: Deliver a feature sheet as small, independently verified increments. Four agent roles (builder, reviewer, judge, document) plus a passive orchestrator, a review loop and a judge loop, one branch per increment into main (one GitHub PR per increment with a remote, otherwise a local commit). Attended, mode-driven (sequential-attended or parallel-attended, read from state.json) and profile-driven (full or lite, also read from state.json). Judge type-checks, then runs the unit tier and, per profile, the integration tier.
disable-model-invocation: true
argument-hint: "[path to the feature sheet]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm:*), Bash(npx:*), Bash(make:*), Bash(docker:*), Bash(cd:*), Bash(ls:*), Bash(cat:*), Bash(echo:*), Bash(mkdir:*), Bash(rm:*), Bash(find:*), Bash(grep:*), Bash(printf:*), Bash(chmod:*), Bash(tail:*), Bash(head:*), Bash(.building/scripts/agent-tests.sh:*), Bash(.building/scripts/agent-hollow.sh:*), Bash(.building/scripts/agent-typecheck.sh:*), Read, Edit, Write
---
Operate the build-judge loop defined in
{{SDLC_REPO}}/contracts/build-judge-loop.md. Read that contract now and follow it
exactly. It is the source of truth for the shared workflow; this skill does not
restate it.

That contract is the profile-agnostic core. After reading it, read the active
profile's thin contract ALONGSIDE it: {{SDLC_REPO}}/contracts/build-loop-full.md
when `profile` in state.json is full or absent (the default), or
{{SDLC_REPO}}/contracts/build-loop-lite.md when it is lite. Read only the active
profile, not both. The profile decides per-increment verification depth and when
documentation runs; the core owns everything else.

The feature sheet for this run is at: $ARGUMENTS

On entry, do exactly what the contract says: validate the sheet against
{{SDLC_REPO}}/contracts/increment-sheet.schema.md, check the setup receipt,
read the project CLAUDE.md, and proceed per the contract. Do not build against an
invalid sheet, and do not run setup yourself (the contract explains the receipt).

If anything in the contract is ambiguous for this project, stop and ask rather
than guessing. Do not improvise workflow behaviour that the contract does not
state.
