# Hooks

Two git guards, installed globally for every repo at once.

| Hook | Guards | Blocks |
| --- | --- | --- |
| `pre-commit` | commit author identity | a commit whose `user.email` is not on your allowlist, so the loop's commits always attribute to the right GitHub account |
| `pre-push` | branch naming | a push from a branch not named `<type>/<kebab-description>` |

The identity allowlist is your own, read from git config (`sdlc.identityAllowlist`, space-separated), so no personal email is baked into this repo. It is a persistent config key, not a per-shell env var, so there is no bypass to forget about. If it is unset, `pre-commit` fails closed (an empty allowlist that waved everything through would defeat the guard).

## Branch naming

`pre-push` requires `<type>/<kebab-description>`, with `type` one of `feat fix docs refactor rename chore test`. `main` and `master` are exempt (the trunk is never a work branch). Examples: `fix/vscode-debug-local-bin`, `feat/typecheck-gate`. To rename an off-spec branch: `git branch -m <type>/<description>`.

## Install

The guards are installed globally, not per repo. One shared copy under `~/.config/git/hooks` becomes git's `core.hooksPath`, so every repo runs them and there are no per-repo copies to drift.

    scripts/setup-global-git-hooks.sh install --email '<your-commit-email>'

This places both hooks, points global `core.hooksPath` at them, sets `sdlc.identityAllowlist` so the identity guard works immediately, and removes any known-stale copies of these guards it finds lingering in repos under `~/source-code` (so they don't sit dead in `.git/hooks`). It refuses to run if `core.hooksPath` already points somewhere else, rather than clobber a path you set for another tool.

`--email` is optional: omitted, install defaults the allowlist from your global `user.email`. Allow more than one identity by setting the key yourself: `git config --global sdlc.identityAllowlist '<email-a> <email-b>'`.

Because `core.hooksPath` is a global redirect, git consults only that dir and stops auto-running each repo's own `.git/hooks`. To keep per-repo tooling working, each guard **chains**: after its own check passes, it execs the repo's own `.git/hooks/<name>` if one exists. So a tool installed later by `npm install` (husky, pre-commit, lefthook) still runs — our guard first, then the repo's hook. If our guard blocks, the local hook never runs.

## Uninstall

    scripts/setup-global-git-hooks.sh uninstall

Unsets `core.hooksPath` (restoring git's default of each repo's own `.git/hooks`) and removes the placed hook files. It leaves `core.hooksPath` alone if it points somewhere that isn't ours.

## Generated projects

The project generator (`scripts/init-ts-mongo.sh`) installs no hooks: the global install already covers every repo the moment it exists, and a seeded per-repo copy would be ignored and would drift. If `core.hooksPath` is unset, the generator's closing output nudges you to run the install once.
