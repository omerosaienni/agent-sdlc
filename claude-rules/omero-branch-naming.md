# Branch Naming

Name every branch you create `<type>/<kebab-description>`.

- Types: `feat fix docs refactor rename chore test`. Unclear → `chore`.
- Description: lowercase `a-z0-9`, words joined by `-`. No spaces, uppercase, `_`, or a second `/`.
- Example: `fix/vscode-debug-local-bin`.

Branches only. Commit *messages* still take a plain imperative with no type prefix (see omero-git-commits.md) — do not conflate the two surfaces.

Enforced by a global `pre-push` hook (`setup-global-git-hooks.sh`); `main`/`master` exempt.
