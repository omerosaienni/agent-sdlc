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
- omero-build-loop, points at contracts/build-judge-loop.md
- omero-design-partner, points at contracts/design-partner.md
- omero-project-setup, points at contracts/project-setup.md and runs scripts/project-setup.sh
- omero-create-ts-mongo, runs scripts/init-ts-mongo.sh (the project generator, no contract: deterministic)
