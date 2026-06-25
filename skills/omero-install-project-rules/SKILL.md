---
name: omero-install-project-rules
description: Install per-project stack convention rules (TypeScript, Mongo, React) into a repo's .claude/rules/, so Claude follows them when working in that project. Copies the chosen rules from the agent-sdlc templates. Pick the stacks the repo actually uses; at least one is required.
disable-model-invocation: true
argument-hint: "<repo> --typescript --mongo --react"
allowed-tools: Bash({{SDLC_REPO}}/scripts/install-project-rules.sh:*), Read
---
Install stack convention rules into a project by running the installer:
    {{SDLC_REPO}}/scripts/install-project-rules.sh $ARGUMENTS

Deterministic: copies the path-scoped stack rules (omero-typescript.md, omero-mongo.md, omero-react.md) from the agent-sdlc templates into the target repo's .claude/rules/, where Claude Code reads them automatically.

Pass the repo path and one or more stack flags for the stacks that repo actually uses (--typescript, --mongo, --react). At least one is required.

These are the PER-PROJECT rule layer. The universal base conventions are a separate GLOBAL layer (installed once via setup-global-claude-rules.sh), not handled here.

Rules are COPIED, not symlinked, so each repo gets its own copy. Generated projects gitignore .claude/, so the copy lives only in the local working tree, not in git; if a template changes later, re-run this to re-sync.

Remove rules with --uninstall (all installed stack rules, or the named ones):
    {{SDLC_REPO}}/scripts/install-project-rules.sh <repo> --uninstall [--react ...]

On success it prints the rules installed and that they take effect next session. Report that to the user. On a non-zero exit, report the error (no stack flag given, or the target is not a git repository) so the user can correct and re-run.
