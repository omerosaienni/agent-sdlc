---
name: omero-build-quick-stacked
description: Deliver a feature sheet as small, independently verified increments, UNATTENDED and STACKED, the fast way. Builder, reviewer and judge (no document role), review loop and judge loop, incremental and linear: each increment is stacked on the previous one (one git-town branch appended per increment, one stacked GitHub PR each), the first stacked on the previous feature's stack tip (from the epic and its tag), not on main. No checkpoint, no human merge in the loop: it builds every increment back to back and stops at sheet exhaustion (then tags feature/<name> and epic/<name>) or an escalation (then halts the chain). Judge type-checks then runs the unit tier only, no integration tier, no documentation. A remote is required; the loop proposes PRs but never ships, so a human can work the open PRs while the queue keeps building.
disable-model-invocation: true
argument-hint: "[path to the feature sheet]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm:*), Bash(npx:*), Bash(make:*), Bash(docker:*), Bash(cd:*), Bash(ls:*), Bash(cat:*), Bash(echo:*), Bash(mkdir:*), Bash(rm:*), Bash(find:*), Bash(grep:*), Bash(printf:*), Bash(chmod:*), Bash(tail:*), Bash(head:*), Bash(.building/scripts/agent-tests.sh:*), Bash(.building/scripts/agent-hollow.sh:*), Bash(.building/scripts/agent-typecheck.sh:*), Read, Edit, Write
---
Operate the fast unattended stacked build loop defined in
{{SDLC_REPO}}/contracts/build-quick-stacked.md. Read that contract now and follow it
exactly. It is a thin delta over {{SDLC_REPO}}/contracts/build-stacked.md (unit-only
verification, no documentation); read build-stacked.md ALONGSIDE it for everything the
delta does not change, exactly as build-quick.md is read alongside build-judge-loop.md.
Together they are the source of truth for this workflow.

The feature sheet for this run is at: $ARGUMENTS

On entry, do exactly what the contract says: check the setup receipt
(.building/setup-ok), validate the sheet against
{{SDLC_REPO}}/contracts/increment-sheet.schema.md, confirm a remote and gh auth and
git-town are present (this path REQUIRES a remote; there is no local-only flow), read
the epic manifest to resolve the stack base, read the project CLAUDE.md, and proceed
per the contract. Do not build against an invalid sheet, and do not run setup yourself.

The loop is UNATTENDED: it never merges to main and never ships (never `git town
ship`); it only proposes stacked PRs (`gh pr create --base <parent>`). It builds every
ready increment in the linearised order, gating each on the type-check and unit tier
only (no integration, no docs), and stops at sheet exhaustion or an escalation.

If anything in the contract is ambiguous for this project, stop and ask rather than
guessing.
