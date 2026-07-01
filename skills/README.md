# Skills

The skills that invoke these contracts, version-controlled here so the system is reproducible. Each skill is a thin pointer: it tells Claude which contract to read and follow, and does not restate the workflow. The contract is the single source of truth for behaviour; the skill is the single source of truth for invocation.

## Source of truth and install

This repo is the source of truth for the skills it contains. The installed copies in ~/.claude/skills are generated. Edit the skill here, then run install-skills.sh to update the installed copy. Do not hand-edit the installed copies; they get overwritten on the next install.

```
./skills/install-skills.sh
```

The script resolves this repo's absolute path from its own location and substitutes the {{SDLC_REPO}} placeholder, so the skills are portable: clone the repo anywhere and install writes the correct paths. It regenerates INDEX.md if an index-skills.sh is present.

### Limitation: install is additive

install-skills.sh adds and updates skills; it does NOT remove them. Deleting a skill from this repo does not delete the installed copy, because ~/.claude/skills also holds skills this repo does not manage, and pruning could delete them. To remove a skill, delete it here AND manually delete ~/.claude/skills/<name>.

## Manifest: what this repo manages

Repo-managed (installed from here, the source of truth):
- omero-build-full, points at contracts/build-judge-loop.md
- omero-build-quick, points at contracts/build-quick.md (fast variant: typecheck + unit only, no integration tier, documentation or completion gate)
- omero-design-sheet, points at contracts/design-partner.md (produces the feature sheet)
- omero-review-sheet, points at contracts/design-review.md (reviews the sheet for design soundness before build)
- omero-setup-project, points at contracts/project-setup.md and runs scripts/project-setup.sh
- omero-create-ts-project, runs scripts/init-ts-project.sh (the project generator, no contract: deterministic; TypeScript base, optional --mongo, --react and --express layers)
- omero-create-python-project, runs scripts/init-python-project.sh (the second project generator, no contract: deterministic; src-layout, uv, pytest unit/integration tiers, strict pyright)
- omero-install-project-rules, runs scripts/install-project-rules.sh (installs stack rules into a repo's .claude/rules/)
- omero-install-global-rules, runs scripts/setup-global-claude-rules.sh and scripts/setup-global-git-hooks.sh (the once-per-machine global setup: symlinks the global Claude rules and installs the git guards)
