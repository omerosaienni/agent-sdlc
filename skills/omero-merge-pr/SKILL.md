---
name: omero-merge-pr
description: Ship the current branch's PR deterministically. Requires the PR's required remote checks to pass, then git town ship (merge to main via the GitHub API, delete branch, sync main, reparent any stacked children). Stack-agnostic: it verifies status and merges, it never builds or runs tests. Refuses if a plaintext token sits in git config, so the exposure cannot recur; auth is the gh keyring. The script is the gate; nothing merges unless every check passes.
disable-model-invocation: true
argument-hint: "[squash message] [--dry-run]"
allowed-tools: Bash({{SDLC_REPO}}/scripts/merge-pr.sh:*), Bash(git:*), Bash(gh:*), Read
---
Operate the merge-pr gate defined in {{SDLC_REPO}}/contracts/merge-pr.md. Read that contract, then run the gate:

    {{SDLC_REPO}}/scripts/merge-pr.sh $ARGUMENTS

Do not merge by hand and do not reimplement the checks in prose: run the script. It is the source of truth for this workflow. In order it requires: a feature branch; git, gh and git town present; no plaintext git-town.github-token in git config; gh authenticated via the keyring; an OPEN PR for the branch; the PR's required remote checks all pass (zero required checks is a BLOCK, not a pass); an optional scripts/ci-local.sh if the project ships one; then git town ship.

Interpret the verdict by exit code:
- 0: shipped (or, under --dry-run, every gate passed and the plan was printed).
- 1: BLOCKED. A gate failed; the reason and its remedy are on stderr. Fix that cause; never bypass the script to merge anyway.
- 2: bad usage. An unknown option or an extra positional.

Report the verdict and the specific BLOCKED line to the user. If the script BLOCKS on a plaintext token in git config, that is the exposure gate: remove the token and rotate it, do not merge around it. If git town ship refuses because the branch is not a direct child of main, ship or delete its ancestor branches first rather than forcing --to-parent blindly.

Preview without merging: pass --dry-run.
