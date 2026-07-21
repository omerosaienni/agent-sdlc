---
name: omero-build-full-stacked
description: Deliver a feature sheet as small, independently verified increments, UNATTENDED and STACKED. The same four agent roles (builder, reviewer, judge, document), review loop and judge loop as omero-build-full, but incremental and linear: each increment is stacked on the previous one (one git-town branch appended per increment, one stacked GitHub PR each), and the first increment is stacked on the previous feature's stack tip (from the epic and its tag), not on main. No checkpoint, no human merge in the loop: it builds every increment back to back and stops only when the sheet is exhausted (then tags feature/<name> and epic/<name> at the tips) or a role loop escalates (then halts the chain). Full verification: judge type-checks, runs both tiers, documents. A remote is required; the loop proposes PRs but never ships, so a human can work the open PRs while the queue keeps building.
disable-model-invocation: true
argument-hint: "[path to the feature sheet]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm:*), Bash(npx:*), Bash(go:*), Bash(gofmt:*), Bash(goimports:*), Bash(make:*), Bash(docker:*), Bash(cd:*), Bash(ls:*), Bash(cat:*), Bash(echo:*), Bash(mkdir:*), Bash(rm:*), Bash(find:*), Bash(grep:*), Bash(printf:*), Bash(chmod:*), Bash(tail:*), Bash(head:*), Bash(.building/scripts/agent-tests.sh:*), Bash(.building/scripts/agent-hollow.sh:*), Bash(.building/scripts/agent-typecheck.sh:*), Read, Edit, Write
---
Operate the unattended stacked build loop defined in
{{SDLC_REPO}}/contracts/build-stacked.md. Read that contract now and follow it
exactly. It is a self-contained recipe (a fork of build-judge-loop.md, which it does
NOT read); it is the source of truth for this workflow. It cites the stable shared
specs (judge.md, state.schema.md, increment-sheet.schema.md, epic-manifest.schema.md,
agent-runner.md); read a cited spec when the recipe points you at it.

The feature sheet for this run is at: $ARGUMENTS

On entry, do exactly what the contract says: check the setup receipt
(.building/setup-ok), validate the sheet against
{{SDLC_REPO}}/contracts/increment-sheet.schema.md, confirm a remote and gh auth and
git-town are present (this path REQUIRES a remote; there is no local-only flow), read
the epic manifest to resolve the stack base, read the project CLAUDE.md, and proceed
per the contract. Do not build against an invalid sheet, and do not run setup yourself.

The loop is UNATTENDED: it never merges to main and never ships (never `git town
ship`); it only proposes stacked PRs (`gh pr create --base <parent>`). It builds every
ready increment in the linearised order and stops at sheet exhaustion or an escalation.

If anything in the contract is ambiguous for this project, stop and ask rather than
guessing. Do not improvise workflow behaviour that the contract does not state.
