# Claude rules (global)

The global Claude Code rules, version-controlled here as the single source of
truth. They load into Claude's context every session, so they are terse on
purpose. These are the GLOBAL layer, applying to every project including this
repo itself.

Stack conventions (TypeScript, Mongo, React) are a separate PER-PROJECT layer
installed into a repo's own `.claude/rules/` by `install-project-rules.sh`, not
kept here.

## Install

Symlink every rule into `~/.claude/rules`, so an edit here is live everywhere with
no re-run:

    scripts/setup-global-claude-rules.sh install

An existing file is replaced in place; one whose content differs from the repo
copy is backed up to `<name>.bak` first.

## Uninstall

    scripts/setup-global-claude-rules.sh uninstall

Removes only the symlinks that point back into this repo (never a real file or a
link owned by something else) and restores any `.bak` it made.

## The rules

| Rule | Covers |
| --- | --- |
| `omero-conventions.md` | universal conventions: prose style (British English, no em dashes) and comment discipline (why not what) |
| `omero-branch-naming.md` | `<type>/<kebab>` branch names (enforced by the git hooks) |
| `omero-git-authorship.md` | commits authored by the user alone, no AI co-author trailers or footers |
