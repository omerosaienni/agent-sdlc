# Git-town auth

Applies only in a git-town repo: agent-sdlc, auto-agent-sdlc, and the repos they build. Check before running any `git town` command:

    git config --get git-town.main-branch

Empty means this is not a git-town repo, so use plain git (`git checkout -b`, `gh pr merge --squash --delete-branch`) and do not invoke `git town` at all. Everything below applies only when it is set.

git-town ships via the GitHub API and needs a token. It does NOT read the gh keyring itself.

- The token prefix is ONLY for `git town ship`. `gh` itself reads its own keyring: never prefix `gh` (`gh pr merge`, `gh pr view`, `gh pr create`, ...) with `GITHUB_TOKEN=...`.
- Ship: `GITHUB_TOKEN="$(gh auth token)" git town ship -m "<msg>"`. Without the env var: "the Git Town driver for your forge does not support shipping via the API".
- Never `git config git-town.github-token` (plaintext on disk = exposure). Env var for the ship child only, never exported or written.
- `git town sync --stack` and local ops need no token.
- git-town configured but not installed: `gh pr merge --squash --delete-branch` (keyring), then reparent the stack by hand.

Enforced by the `omero-merge-pr` skill: refuses if a config token exists, injects the keyring token for the ship child. This rule is the instruction; the script is the backstop.
