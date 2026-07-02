# Merge PR gate

Ship the current branch's PR, deterministically. Merging after the PR's remote checks pass is not a judgement call, so it is a script that gates itself, not a rule an agent might skip. Runs scripts/merge-pr.sh and interprets its verdict. The script is the gate; this contract is its spec.

The gate is stack-agnostic: it verifies status and merges, it never builds or runs tests. CI is the check authority; the script trusts `gh pr checks --required`, so one gate serves this repo's TypeScript and Python paths alike. The one local step (scripts/ci-local.sh) is optional-by-presence: run if the project ships it, skipped with a warning if not. Nothing stack-specific runs here.

## Why it exists
A private repo on GitHub's free plan has no branch protection: a PR merges even when its checks are red or missing. So the merge must be gated client-side. This script is that gate.

## Idempotency
Read-until-ship: every step before the merge is read-only (status queries, config reads), so a run that blocks on any gate mutates nothing and is safe to re-run. `git town ship` is the sole side effect, and once a branch is shipped its PR is no longer OPEN, so a second run blocks at the open-PR gate rather than re-merging. `--dry-run` performs no merge at all.

## The gate (in order, each failure BLOCKS)
Every failure exits 1 with a `BLOCKED:` reason on stderr and its remedy. Order matters: the cheap, safe checks run before anything that could touch the remote.

1. **Inside a git repo.** Repo root resolved from git, never from CWD.
2. **On a feature branch.** main, master or a detached HEAD is refused: ship only from the work branch whose PR is being merged.
3. **Tooling present.** `git`, `gh` and `git town` must all be installed. A missing tool is a loud block, never a silent skip.
4. **No plaintext token in git config.** If `git config --get git-town.github-token` returns anything, BLOCK. A plaintext token in `.git/config` is a real exposure that has happened once, so a config token is dangerous. Remedy: `git config --unset git-town.github-token` (add `--global` if global) and rotate the leaked token. This is the exposure-prevention gate. It is unrelated to how the script authenticates the ship (gate 5): the token that ships comes transiently from the keyring, never from config.
5. **gh authenticated, with a shippable token.** `gh auth status` must succeed AND `gh auth token` must return a non-empty token. git town ships via the GitHub API and needs a real token; it does not read the gh keyring itself, but it does honour a `GITHUB_TOKEN` env var, so the script passes `gh auth token` to the ship child (gate 9) only. An empty token BLOCKs now with the `gh auth login` remedy, because shipping would otherwise fail with a driver-does-not-support-API-shipping error. The token stays in the keyring and reaches only the ship child process; it is never written to git config or disk, so this is the accepted mechanism, not an exposure.
6. **An OPEN PR exists for this branch.** Resolved in one call for its number (the checks gate), state (refuse a non-open PR) and title (the default squash message).
7. **Required remote checks pass.** `gh pr checks <n> --required` must exit 0 AND print at least one check. GOTCHA: with zero required checks it exits 0 with empty output; the script treats the empty case as a BLOCK, because absence of checks is not confirmation of safety. Pending or failing checks also BLOCK.
8. **Optional local CI, by presence.** If the project ships an executable `scripts/ci-local.sh`, run it (a verbatim local CI run, e.g. via act) and BLOCK on failure. If it is present but not executable, BLOCK with the chmod remedy. If it is absent, print a warning and continue. This is the merge-time home for the heavy full-CI run; the pre-push hook runs only the fast per-commit gates, so this is not a duplicate. It is optional-by-presence so the skill stays stack-agnostic: a project without the script simply skips the step. The skill never creates ci-local.sh, it only runs an existing one.
9. **Ship.** `GITHUB_TOKEN="$(gh auth token)" git town ship -m "<message>"`. The `GITHUB_TOKEN` prefix is required: it is what lets git town ship via the API, set on the child process only (the omero-script-args exempt case, a script configuring a child it spawns), never exported or persisted. Message defaults to the PR title; a positional arg overrides it. git town merges the direct child of main into main via the GitHub API (respecting a squash-only policy), deletes the branch, syncs main and reparents any stacked children. It ships only DIRECT children of main. If the branch is deeper in a stack, git town refuses; the script surfaces that refusal so the operator ships or deletes ancestors first. It does NOT pre-check the parent and does NOT force `--to-parent`.

## Arguments
Caller-chosen behaviour is a positional or a flag, never an env var.
- `[MESSAGE]` positional: the squash commit message. Default: the PR title.
- `--dry-run`: pass through to `git town ship --dry-run`. Verifies every gate, prints the ship plan, merges nothing.
- `--help` / `-h`: print the header and exit 0.

There is no `--no-verify-local`: there are no local gates to skip. CI is the check authority.

## Verdict and exit codes
- **0**: shipped (or, under `--dry-run`, every gate passed and the plan was printed).
- **1**: BLOCKED. A gate failed; the reason and its remedy are on stderr. Fix the cause, never bypass the script to merge by hand.
- **2**: bad usage. An unknown option or an extra positional; the header is printed to stderr.

## Relationship to the pipeline
Not a pipeline script: the create-verify-build flow (generate, setup gate, build loop) stands a project up and iterates on it. merge-pr.sh is the ship step after an increment's PR is green, run per PR by the operator. It shares the repo's script layout (contracts/script-layout.md) but sits outside the pipeline the setup gate and build loop form.
