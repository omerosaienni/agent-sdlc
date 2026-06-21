---
name: omero-project-setup
description: Prove a project is ready to build, by execution, at a single idempotent gate before the build loop. Derives and matches tooling, runs both test tiers and asserts non-zero selection, places and proves the agent test runner the judge uses, checks git and endpoints. Safe to re-run as a health check.
disable-model-invocation: true
argument-hint: "[--yes to install/push where needed, or --check to verify only]"
allowed-tools: Bash(./scripts/*:*), Bash(git:*), Bash(gh:*), Bash(npm:*), Bash(npx:*), Bash(node:*), Bash(docker:*), Bash(cat:*), Bash(ls:*), Read
---
Operate the project setup gate defined in
{{SDLC_REPO}}/contracts/project-setup.md. Read that contract, then run the gate
script:
    {{SDLC_REPO}}/scripts/project-setup.sh $ARGUMENTS

Interpret the verdict by exit code: 0 READY, 1 fix the FAIL lines, 2 re-run with
--yes to install or push, 3 bring the endpoint up and re-run. Report the verdict
and the specific lines to the user. Do not start the build loop unless setup
reports READY. The gate is idempotent; re-running it is always safe and is the
way to re-check readiness after any change.

If the gate reports BLOCKED on an endpoint, tell the user the bring-up step from
the project CLAUDE.md and wait; do not treat it as a code failure.
