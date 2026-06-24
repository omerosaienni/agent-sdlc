#!/usr/bin/env bash
# setup-global-claude-rules.sh - install this repo's Claude rules globally by
# symlinking them into ~/.claude/rules, so the repo stays the single source of
# truth and an edit here is live everywhere with no re-run.
#
# Symlink, not copy: ~/.claude/rules/<rule>.md -> claude-rules/<rule>.md in this
# repo. Editing a rule in the repo updates it everywhere instantly. A copy would
# freeze and drift, the problem this avoids.
#
# Global or nothing: install links every rule, uninstall removes the links it owns.
# Call the verb you want explicitly.
#
# Usage:
#   setup-global-claude-rules.sh install      # symlink every rule into ~/.claude/rules
#   setup-global-claude-rules.sh uninstall    # remove the symlinks this repo owns
set -euo pipefail

# ============================================================================
# Where things live
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SRC="$SCRIPT_DIR/../claude-rules"
RULES_DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules"

# ============================================================================
# Output helpers
# ============================================================================

C_RESET=$'\033[0m'; C_STEP=$'\033[1;36m'; C_NOTE=$'\033[2m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'
[ -t 1 ] || { C_RESET=; C_STEP=; C_NOTE=; C_OK=; C_ERR=; }

step() { printf '%s==>%s %s\n' "$C_STEP" "$C_RESET" "$1"; }
note() { printf '%s    %s%s\n' "$C_NOTE" "$1" "$C_RESET"; }
ok()   { printf '%s%s%s\n' "$C_OK" "$1" "$C_RESET"; }
err()  { printf '%s%s%s\n' "$C_ERR" "$1" "$C_RESET" >&2; }

# ============================================================================
# install - symlink every repo rule into ~/.claude/rules
# ============================================================================

do_install() {
    step "Install global Claude rules (symlink -> $RULES_DEST)"

    [ -d "$RULES_SRC" ] || { err "no rules dir at $RULES_SRC"; exit 1; }
    mkdir -p "$RULES_DEST"

    local linked=0
    for src in "$RULES_SRC"/*.md; do
        [ -e "$src" ] || continue
        local name dest
        name="$(basename "$src")"
        # README.md documents the dir, it is not a rule - never link it.
        [ "$name" = "README.md" ] && continue
        dest="$RULES_DEST/$name"

        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            note "already linked: $name"
        elif [ -e "$dest" ] && [ ! -L "$dest" ]; then
            # A real file is already here. If it is byte-identical to the repo copy
            # (the common case: this is the original we imported from), there is
            # nothing to preserve, so just replace it - no redundant .bak. Only back
            # up when the content genuinely differs, so a local edit is recoverable.
            if cmp -s "$dest" "$src"; then
                ln -sfn "$src" "$dest"
                note "linked $name (replaced an identical copy)"
            else
                mv "$dest" "$dest.bak"
                ln -s "$src" "$dest"
                note "linked $name (backed up your differing copy to $name.bak)"
            fi
            linked=$((linked + 1))
        else
            ln -sfn "$src" "$dest"
            note "linked $name"
            linked=$((linked + 1))
        fi
    done

    ok "Installed. $linked rule(s) linked; edits in the repo are now live."
}

# ============================================================================
# uninstall - remove only the symlinks that point back into this repo
# ============================================================================

do_uninstall() {
    step "Uninstall global Claude rules"

    local removed=0
    for src in "$RULES_SRC"/*.md; do
        [ -e "$src" ] || continue
        local name dest
        name="$(basename "$src")"
        # README.md documents the dir, it is not a rule - never link it.
        [ "$name" = "README.md" ] && continue
        dest="$RULES_DEST/$name"
        # Remove only a symlink that points at our copy; never touch a real file
        # or a link owned by something else.
        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            rm "$dest"
            note "removed link $name"
            removed=$((removed + 1))
            if [ -e "$dest.bak" ]; then
                mv "$dest.bak" "$dest"
                note "restored $name from $name.bak"
            fi
        fi
    done

    ok "Uninstalled. Removed $removed link(s)."
}

# ============================================================================
# Dispatch
# ============================================================================

case "${1:-}" in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    *)
        err "usage: setup-global-claude-rules.sh install|uninstall"
        exit 2
        ;;
esac
