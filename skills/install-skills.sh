#!/usr/bin/env bash
# Install the repo's skills into ~/.claude/skills, substituting the repo path.
# The repo is the source of truth. Never hand-edit the installed copies; edit the
# repo skill and re-run this. Idempotent: safe to run repeatedly.
set -euo pipefail

# resolve this repo's absolute location from the script's own path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDLC_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$SDLC_REPO/skills"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

[ -d "$SRC" ] || { echo "no skills/ directory at $SRC"; exit 1; }
mkdir -p "$DEST"

echo "Installing skills from $SRC"
echo "into $DEST"
echo "repo path substituted as: $SDLC_REPO"
echo

installed=0
for dir in "$SRC"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    [ -f "$dir/SKILL.md" ] || { echo "skip $name (no SKILL.md)"; continue; }
    mkdir -p "$DEST/$name"
    # substitute the {{SDLC_REPO}} placeholder with the resolved absolute path
    sed "s#{{SDLC_REPO}}#$SDLC_REPO#g" "$dir/SKILL.md" > "$DEST/$name/SKILL.md"
    # carry any other files in the skill dir verbatim
    find "$dir" -mindepth 1 -maxdepth 1 -type f ! -name SKILL.md -exec cp {} "$DEST/$name/" \;
    echo "installed $name"
    installed=$((installed+1))
done

echo
echo "installed $installed skill(s)"

# regenerate the index if the regen script exists
if [ -x "$DEST/index-skills.sh" ]; then
    "$DEST/index-skills.sh" && echo "regenerated INDEX.md"
elif [ -x "$HOME/.claude/index-skills.sh" ]; then
    "$HOME/.claude/index-skills.sh" && echo "regenerated INDEX.md"
else
    echo "note: no index-skills.sh found; INDEX.md not regenerated"
fi

# sanity: warn if any installed skill still contains the placeholder
if grep -rl "{{SDLC_REPO}}" "$DEST" >/dev/null 2>&1; then
    echo "WARNING: a placeholder survived substitution; check the installed skills"
    exit 1
fi
echo "done. The repo is the source of truth; edit skills here and re-run to update."
