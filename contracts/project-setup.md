# Project setup gate

Prove a project is ready to build, by execution not assertion, at a single point before the build loop runs. Setup proves the static environment facts once; the build loop then assumes them and checks only dynamic liveness. Runs scripts/project-setup.sh and interprets its verdict.

## Idempotency (invariant, inviolable)
Safe to run any number of times. On an already-ready project it changes nothing and reports READY. Every acting step is guarded on current state and acts only on the gap:
- install tooling only if absent or mismatched
- push a branch only if the remote lacks it
- set scripts to a fixed value, never append
A second run mutates nothing. Being idempotent and reporting ready-or-not with specifics, it doubles as a re-runnable health check.

## What it proves (all by execution)
- Report tooling present AND matching the installed test runner. Derive the runner's major version from the project, install the matching coverage provider, verify coverage actually runs. Never hardcode a version; derive it.
- Project declares its test-tier commands (server:test:unit, server:test:integration).
- Agent test runner (.building/scripts/agent-tests.sh) present and matching the shared template. Setup creates .building/scripts/ and places the runner there if absent or out of date, then runs it to prove the agent test path the build loop's judge depends on actually runs and reports. Not loop-ready if that path is broken even when the human test commands pass, because the judge runs tests through the agent runner, not the human scripts.
- Hollow-check runner (.building/scripts/agent-hollow.sh) present, matching the shared template, and runnable. Setup places it under .building/scripts/ if absent or out of date and proves it answers its usage contract, because the judge invokes it for the hollow-test negative run.
- Type-check runner (.building/scripts/agent-typecheck.sh) present, matching the stack's template, and runnable. Setup places all three agent runners (test, hollow-check, type-check) so one actor owns runner placement, and proves each one runs. The type-check runner is the build loop judge's gate, run by the judge first, before the tiers, because the tiers strip types: clean type-check (exit 0) passes, type error (exit 1) is a hard fail, type-check that cannot run at all (exit 3) is an environment block. Setup proves the runner is placed and runnable; the judge runs it per increment.
- Each tier, run for real, selects a NON-ZERO number of tests and passes. A declared tier that runs zero tests is a hollow suite: a hard stop, never a pass. This is the suite-level form of the hollow-test rule.
- Coverage runs (verify by running, do not trust the install).
- git repo, gh authenticated, and a local main branch. A GitHub remote (and main pushed to it) is needed only to push branches and open PRs, not to build, commit and iterate locally, so a missing remote is a warning, never a hard FAIL: setup still reports READY and adding the remote stays the user's action before the loop's PRs can flow. Never create the GitHub repo or remote; that is the user's action. Each increment branch is cut from main by the build loop, not by setup.
- Commit identity on the allowlist: git config user.email must be one of the allowed addresses, so the loop's commits attribute to the right GitHub account. Allowlist is read from git config sdlc.identityAllowlist, space-separated, so no email is baked into the repo; set it once globally, or via setup-global-git-hooks.sh install. Hard FAIL if wrong or if sdlc.identityAllowlist is unset, because a misattributed identity is otherwise only discovered at PR time. Pairs with the per-commit pre-commit hook (defence in depth: the gate blocks a misconfigured repo before the loop starts, the hook blocks any single commit with a wrong email mid-run).
- .building is gitignored, so the receipt and all loop output stay local and cannot be committed and travel to a machine that never ran setup. Add .building to .gitignore on consent if missing.

## Endpoint handling
Integration tiers need live endpoints. Setup runs the integration tier; if it fails with a connection error (endpoint down), setup reports BLOCKED with the bring-up step, distinct from a test failure. Human brings the endpoint up and re-runs setup. An endpoint being down is never reported as a code failure.

## Consent for side effects
Installs, scaffolds and pushes are side effects. The default acts: invoking the gate IS the consent, so it performs them as needed. --check is the read-only preview: it performs none, and on a needed action reports NOT READY (exit 2) with the re-run-without-check instruction. Consent is never a hidden environment variable.

## Verdict and exit codes
- 0 READY: build may proceed.
- 1 NOT READY: a check failed; fix the FAIL lines.
- 2 NOT READY: only under --check; an install, scaffold or push is needed; re-run without --check to apply.
- 3 BLOCKED: an environment endpoint is down; bring it up and re-run.

## Relationship to the build loop
Build loop assumes setup has passed. Build loop keeps only the DYNAMIC endpoint-liveness check (is the endpoint up right now, the environment-block pause), because that can change during a run. All STATIC proving (tooling matches, commands select tests, configs load, git ready) belongs here and is not repeated per increment. Run setup once before building, and again any time the environment may have drifted.
