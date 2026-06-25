# Project setup gate

Prove a project is ready to build, by execution not assertion, at a single point before the build loop runs. Setup proves the static environment facts once; the build loop then assumes them and checks only dynamic liveness. Runs the script scripts/project-setup.sh and interprets its verdict.

## Idempotency (invariant, inviolable)
Setup is safe to run any number of times. On an already-ready project it changes nothing and reports READY. Every acting step is guarded on current state and acts only on the gap: install tooling only if absent or mismatched, push a branch only if the remote lacks it, set scripts to a fixed value (never append). A second run mutates nothing. Because it is idempotent and reports ready-or-not with specifics, it doubles as a re-runnable health check.

## What it proves (all by execution)
- Report tooling is present AND matches the installed test runner. Derive the runner's major version from the project, install the matching coverage provider, verify coverage actually runs. Never hardcode a version; derive it.
- The project declares its test-tier commands (server:test:unit, server:test:integration).
- The agent test runner (.building/scripts/agent-tests.sh) is present and matches the shared template. Setup creates .building/scripts/ and places the runner there if absent or out of date, then runs it to prove the agent test path the build loop's judge depends on actually runs and reports. A project is not loop-ready if that path is broken, even when the human test commands pass, because the judge runs tests through the agent runner, not the human scripts.
- The hollow-check runner (.building/scripts/agent-hollow.sh) is present, matches the shared template, and is runnable. Setup places it under .building/scripts/ if absent or out of date and proves it answers its usage contract, because the judge invokes it for the hollow-test negative run.
- (The type-check runner, .building/scripts/agent-typecheck.sh from the shared template, is the build loop judge's gate, placed and run by the loop, not by this setup gate. The judge runs it first, before the tiers, because the tiers strip types: a clean type-check (exit 0) passes, a type error (exit 1) is a hard fail, and a type-check that cannot run at all (exit 3) is an environment block. The setup gate places and proves only the test and hollow-check runners.)
- Each tier, run for real, selects a NON-ZERO number of tests and passes. A tier that the project declares but that runs zero tests is a hollow suite: a hard stop, never a pass. This is the suite-level form of the hollow-test rule.
- Coverage runs (verify by running, do not trust the install).
- git repo, gh authenticated, and a local main branch. A GitHub remote (and main pushed to it) is needed only to push branches and open PRs, not to build, commit and iterate locally, so a missing remote is a warning, never a hard FAIL: setup still reports READY and adding the remote stays the user's action before the loop's PRs can flow. Never create the GitHub repo or remote; that is the user's action. Each increment branch is cut from main by the build loop, not by setup.
- Commit identity on the allowlist: git config user.email must be one of the allowed addresses, so the loop's commits attribute to the right GitHub account (the allowlist is read from git config sdlc.identityAllowlist, space-separated, so no email is baked into the repo; set it once globally, or via setup-global-git-hooks.sh install). This is a hard FAIL if wrong or if sdlc.identityAllowlist is unset, because a misattributed identity is only discovered at PR time otherwise. It pairs with the per-commit pre-commit hook (defence in depth: the gate blocks a misconfigured repo before the loop starts, the hook blocks any single commit with a wrong email mid-run).
- .building is gitignored, so the receipt and all loop output stay local and cannot be committed and travel to a machine that never ran setup. Add .building to .gitignore on consent if missing.

## Endpoint handling
Integration tiers need live endpoints. Setup runs the integration tier; if it fails with a connection error (endpoint down), setup reports BLOCKED with the bring-up step, distinct from a test failure. The human brings the endpoint up and re-runs setup. An endpoint being down is never reported as a code failure.

## Consent for side effects
Installs and pushes are side effects. Consent is explicit: a --yes flag, or an interactive prompt at a terminal. Never a hidden environment variable. With --check, setup verifies only and never installs or pushes; a needed-but-unconsented action makes it report NOT READY with the re-run instruction.

## Verdict and exit codes
- 0 READY: build may proceed.
- 1 NOT READY: a check failed; fix the FAIL lines.
- 2 NOT READY: an install or push is needed but was not consented; re-run with --yes.
- 3 BLOCKED: an environment endpoint is down; bring it up and re-run.

## Relationship to the build loop
The build loop assumes setup has passed. The build loop keeps only the DYNAMIC endpoint-liveness check (is the endpoint up right now, the environment-block pause), because that can change during a run. All STATIC proving (tooling matches, commands select tests, configs load, git ready) belongs here and is not repeated per increment. Run setup once before building, and again any time the environment may have drifted.
