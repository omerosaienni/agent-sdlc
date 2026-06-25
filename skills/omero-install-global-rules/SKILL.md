---
name: omero-install-global-rules
description: Run this repo's global setup, the two installers that apply machine-wide. Symlinks the global Claude rules into ~/.claude/rules (setup-global-claude-rules.sh) and installs the global git guards, commit-identity and branch-name, for every repo (setup-global-git-hooks.sh). The global, once-per-machine counterpart to omero-install-project-rules (which is per repo). Both installers are idempotent, safe to re-run.
disable-model-invocation: true
argument-hint: "[install|uninstall] [--email <commit-email>]"
allowed-tools: Bash({{SDLC_REPO}}/scripts/setup-global-claude-rules.sh:*), Bash({{SDLC_REPO}}/scripts/setup-global-git-hooks.sh:*)
---
Run this repo's two global installers, the scripts that do the machine-wide setup, in
order. Both are idempotent, so re-running is safe.

Pick the verb from $ARGUMENTS: `install` (the default when no verb is given) or
`uninstall`. Run the SAME verb through both scripts.

1. Global Claude rules (symlinks, so an edit in the repo is live everywhere with no
   re-run):
       {{SDLC_REPO}}/scripts/setup-global-claude-rules.sh <verb>
2. Global git guards (sets git's global core.hooksPath to the shared hooks, seeds the
   commit-identity allowlist, tidies known-stale per-repo hooks):
       {{SDLC_REPO}}/scripts/setup-global-git-hooks.sh <verb> [--email <addr>]

If the user passes `--email <addr>`, forward it ONLY to the git-hooks installer (it
seeds sdlc.identityAllowlist; omitted, that script defaults the allowlist from your
global user.email). The rules installer takes no `--email`. The git-hooks installer
also accepts extra directories after the verb as stale-hook scan roots; forward any
the user gives.

Run both, then report each script's summary: how many rules were linked; that
core.hooksPath and the identity allowlist were set and how many stale hooks were
tidied. If either exits non-zero, report its exact error line, the common ones being
core.hooksPath already pointing somewhere that is not ours (the git-hooks installer
refuses to overwrite it) and no global user.email to default the allowlist from, so
the user can resolve and re-run.

This is global, once-per-machine setup. It is distinct from /omero-install-project-rules,
which installs per-project stack rules into one repo's .claude/rules/. Run this once per
machine (or after pulling new global rules or hooks); run that once per repo.
