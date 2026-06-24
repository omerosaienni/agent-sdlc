# Project stack rules (templates)

The PER-PROJECT rule layer: stack conventions installed into a repo's own
`.claude/rules/` by `install-project-rules.sh`. These are templates (the source of
truth); the installer copies the chosen ones into a target repo. Because generated
projects gitignore `.claude/`, the copies live only in the local working tree, not
in git; re-run the installer to re-sync a copy that has drifted from its template.

Distinct from the GLOBAL layer in `claude-rules/` (universal conventions that apply
everywhere via `~/.claude/rules`). Stack rules are project-specific and copied, not
symlinked.

## The rules and their scope

Each rule is path-scoped via `paths:` frontmatter, so it loads only when Claude
touches matching files. Scope is by directory where that is the honest boundary
(a directory glob is language-neutral; a file-extension glob is not).

| Rule | Scope | Covers |
| --- | --- | --- |
| `omero-typescript.md` | `**/*.ts`, `**/*.tsx` | the TypeScript substrate: strict/no-any, module layout, async, test tiers |
| `omero-mongo.md` | `src/server/db/**` | Mongo access: shared client, COLLECTIONS, typed docs, db tests in the integration tier |
| `omero-react.md` | `src/client/**` | React client: function components, hooks, typed props, unit-tier component tests |

## Layout contract

The directory scopes assume the canonical layout the generator produces. The base
is always `src/server/`; the db, client, and common trees are added by their layers:

```
src/
  server/          always (the TypeScript base)
    index.ts
    db/            <- omero-mongo.md  (added by --mongo)
  client/          <- omero-react.md  (added by --react)
  common/          (added by --react)
```

## Install

    install-project-rules.sh <repo> --typescript --mongo --react

Pick any combination; at least one stack flag is required. See the script for
install/uninstall detail.
