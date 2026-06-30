#!/usr/bin/env bash
# Suite for the create-project skills: structural contract of the SKILL.md files
# and that install-skills.sh would place them. Sourced and run by tests/run.sh.
#
# The installer auto-discovers every skills/*/SKILL.md, so a new skill needs no
# installer edit; these checks guard the skill's own frontmatter and scoping.

suite_begin "skills (create-project skill contracts)" structural

SKILLS="$REPO_ROOT/skills"
PY="$SKILLS/omero-create-python-project/SKILL.md"
TS="$SKILLS/omero-create-ts-project/SKILL.md"

# --- the Python create skill is well-formed (the cat checks below also prove it
#     exists: a missing file fails them just as loudly) -------------------------
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
# (the cat check proves the TS skill is still present and untouched in posture.)
expect_match 0 'disable-model-invocation: true' "TS skill unchanged in posture" cat "$TS"

# --- naming convention: /omero-<verb>-<what>, dir matches name, no stale names --
# Every skill directory's name matches the name: in its SKILL.md (a rename must
# change both), and no renamed-away skill name lingers anywhere in the tree.
for d in "$SKILLS"/omero-*/; do
    sk="$(basename "$d")"
    decl="$(grep -m1 '^name:' "$d/SKILL.md" 2>/dev/null | sed -E 's/^name:[[:space:]]*//')"
    expect_exit 0 "skill dir $sk matches its name: frontmatter" test "$sk" = "$decl"
done

# Renamed-away names must not reappear anywhere in the tracked tree (the rename's
# whole point). Each rename increment adds its old name here as it lands; only
# completed renames are listed so the check stays green increment by increment.
for old in omero-build-loop omero-project-setup omero-design-partner; do
    found="$(grep -rl "$old" "$REPO_ROOT" --include='*.md' --include='*.sh' 2>/dev/null | grep -v '/.building/' | grep -v '/tests/skills/test.sh')"
    if [ -z "$found" ]; then _t_ok "no lingering reference to renamed skill $old"
    else _t_bad "renamed skill $old still referenced in: $found"; fi
done

suite_summary
