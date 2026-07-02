# Branch Naming

Name every branch you create `<type>/<kebab-description>`.

- Types: `feat fix docs refactor rename chore test`. Unclear → `chore`.
- Description: lowercase `a-z0-9`, words joined by `-`, with `_` allowed to carry a build increment id verbatim (`feat/<feature>_<NN>-<increment>`). No spaces, uppercase, or a second `/`.
- Example: `fix/vscode-debug-local-bin`; a build branch: `feat/claude-metrics_03-metrics-persist`.

Branches only. Commit *messages* still take a plain imperative with no type prefix. Do not conflate the two surfaces.

Enforced by a global `pre-push` hook, installed by `scripts/setup-global-git-hooks.sh install` in the agent-sdlc repo (re-run it to propagate a source edit to the live hook); `main`/`master` exempt.
