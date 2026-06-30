#!/usr/bin/env bash
# Suite for the create-project skills: structural contract of the SKILL.md files
# and that install-skills.sh would place them. Sourced and run by tests/run.sh.
#
# The installer auto-discovers every skills/*/SKILL.md, so a new skill needs no
# installer edit; these checks guard the skill's own frontmatter and scoping.

suite_begin "skills (create-project skill contracts)"

SKILLS="$REPO_ROOT/skills"
PY="$SKILLS/omero-create-python-project/SKILL.md"
TS="$SKILLS/omero-create-ts-project/SKILL.md"

# --- the Python create skill exists and is well-formed -----------------------
expect_exit 0 "python create skill exists"            test -f "$PY"
expect_match 0 'name: omero-create-python-project' "python skill declares its name"   cat "$PY"
expect_match 0 'disable-model-invocation: true'    "python skill is not model-invocable" cat "$PY"
# allowed-tools must scope to the python generator path, not the TS one, not a glob.
expect_match 0 'init-python-project.sh'  "python skill allows the python generator" cat "$PY"
expect_exit 1 "python skill does NOT allow the TS generator" grep -q 'init-ts-project.sh' "$PY"
# the body invokes the python generator and does not chain into the pipeline.
expect_match 0 'init-python-project.sh \$ARGUMENTS' "python skill body runs the generator with args" cat "$PY"
# the skill must explicitly NOT chain into design/setup/build (it only creates).
expect_match 0 'Do NOT run those here' "python skill states it only creates, does not run the pipeline" cat "$PY"

# --- the installer auto-discovers it (no hardcoded skill list to update) ------
# A SKILL.md under skills/<name>/ is enough; prove the installer loops over dirs
# rather than naming skills, so the new one is picked up.
expect_match 0 'for dir in' "installer auto-discovers skill dirs" cat "$SKILLS/install-skills.sh"
expect_exit 1 "installer has no hardcoded skill allowlist" grep -qE 'omero-create-(ts|python)-project' "$SKILLS/install-skills.sh"

# --- it mirrors the TS create skill's shape (same contract, different stack) --
expect_exit 0 "TS create skill still present (untouched)" test -f "$TS"
expect_match 0 'disable-model-invocation: true' "TS skill unchanged in posture" cat "$TS"

suite_summary
