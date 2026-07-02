# Git-town auth

git-town ships via the GitHub API and needs a token. It does NOT read the gh keyring itself.

- Ship: `GITHUB_TOKEN="$(gh auth token)" git town ship -m "<msg>"`. Without the env var: "the Git Town driver for your forge does not support shipping via the API".
- Never `git config git-town.github-token` (plaintext on disk = exposure). Env var for the ship child only, never exported or written.
- `git town sync --stack` and local ops need no token.
- No git-town: `gh pr merge --squash --delete-branch` (keyring), then `git town sync --stack` to reparent.

Enforced by the `omero-merge-pr` skill: refuses if a config token exists, injects the keyring token for the ship child. This rule is the instruction; the script is the backstop.
