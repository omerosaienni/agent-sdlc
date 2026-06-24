# Rules: global and per-project

Conventions are split into two layers, by where they apply.

| Layer | Lives in | Applies to | Installed by |
| --- | --- | --- | --- |
| **Global** | `~/.claude/rules/` | every repo, including this one | `setup-global-claude-rules.sh` (symlink) |
| **Per-project (stack)** | `<repo>/.claude/rules/` | one repo, scoped by file path | `install-project-rules.sh` (copy) |

Claude Code reads both automatically at session start. A rule with `paths:`
frontmatter loads only when Claude touches a matching file, so a stack rule costs
nothing on files it does not apply to.

## Global layer

Universal conventions that hold regardless of stack, version-controlled in
`claude-rules/` as the source of truth and symlinked into `~/.claude/rules/`:

- `omero-conventions.md` — prose style (British English, no em dashes) and comment
  discipline (why not what).
- `omero-branch-naming.md` — `<type>/<kebab>` branch names (the git `pre-push` hook
  enforces the same standard; see [hooks](../hooks/README.md)).

Install (symlink, so an edit in the repo is live everywhere with no re-run):

    scripts/setup-global-claude-rules.sh install

These apply everywhere, so they are NOT installed per project. Editing agent-sdlc
itself is governed by them too.

## Per-project (stack) layer

Stack conventions for the language and tools a repo uses, kept as templates in
`project-rules/` and copied into a repo's `.claude/rules/`:

| Rule | Scope (`paths:`) | Covers |
| --- | --- | --- |
| `omero-typescript.md` | `**/*.ts`, `**/*.tsx` | strict/no-any, module layout, async, test tiers |
| `omero-mongo.md` | `src/server/db/**` | shared client, COLLECTIONS, typed docs, db tests in the integration tier |
| `omero-react.md` | `src/client/**` | function components, hooks, typed props, unit-tier component tests |

The scopes are directories where that is the honest boundary: `src/server/db/**` is
language-neutral (so the Mongo rule stands without assuming TypeScript), and
`src/client/**` keeps React rules out of server `.tsx`. They assume the canonical
layout the generators produce (`src/server`, `src/server/db`, `src/client`).

Install (copy; pick the stacks the repo uses, at least one required):

    scripts/install-project-rules.sh <repo> --typescript --mongo --react

Remove with `--uninstall` (all installed stack rules, or the named ones):

    scripts/install-project-rules.sh <repo> --uninstall [--react ...]

Or invoke the skill `/omero-install-project-rules`, which wraps the installer.

### Copy, and what that means

Stack rules are copied, not symlinked. Because `.claude/` is gitignored, they live
only in the local working copy. A copy that drifts from its template does not
re-sync on its own; re-run the installer to refresh it. The generators install the
stack rules for you (`init-ts-mongo.sh` installs TypeScript + Mongo;
`init-ts-mongo-react.sh` adds React), so a freshly generated project starts current.
