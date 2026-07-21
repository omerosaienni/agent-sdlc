#!/usr/bin/env bash
# install-project-rules.sh - install stack convention rules into one repo's
# .claude/rules/, so Claude Code follows them when working in that project.
#
# These are the PER-PROJECT rule layer. They are COPIED (not symlinked) so each
# repo gets its own independent copy. Generated projects gitignore .claude/, so the
# copies live only in the local working tree, not in git. The repo at project-rules/
# is the source of truth; a copy drifts if a template changes - re-run install to
# re-sync.
#
# Stack rules only. The universal base conventions are a separate GLOBAL layer
# (claude-rules/, installed by setup-global-claude-rules.sh), not installed here.
# At least one stack flag is required - with none there is nothing to do.
#
# Each rule is path-scoped via its paths: frontmatter, so it loads only for the
# matching part of the tree (typescript: *.ts/*.tsx; go: *.go; mongo:
# src/server/db/**; react: the client tree). Those scopes assume the canonical
# layout the generators produce.
#
# Usage:
#   install-project-rules.sh <repo> --typescript --go --mongo --react  # any combination, >=1 required
#   install-project-rules.sh <repo> --uninstall [--typescript ...] # remove (all installed, or the named)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SRC="$SCRIPT_DIR/../project-rules"

# stack flag -> rule filename
rule_file() {
    case "$1" in
        typescript) echo "omero-typescript.md" ;;
        go)         echo "omero-go.md" ;;
        mongo)      echo "omero-mongo.md" ;;
        react)      echo "omero-react.md" ;;
        *)          return 1 ;;
    esac
}

C_RESET=$'\033[0m'; C_STEP=$'\033[1;36m'; C_NOTE=$'\033[2m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'
[ -t 1 ] || { C_RESET=; C_STEP=; C_NOTE=; C_OK=; C_ERR=; }
step() { printf '%s==>%s %s\n' "$C_STEP" "$C_RESET" "$1"; }
note() { printf '%s    %s%s\n' "$C_NOTE" "$1" "$C_RESET"; }
ok()   { printf '%s%s%s\n' "$C_OK" "$1" "$C_RESET"; }
err()  { printf '%s%s%s\n' "$C_ERR" "$1" "$C_RESET" >&2; }

usage() {
    err "usage: install-project-rules.sh <repo> [--uninstall] --typescript --go --mongo --react"
    err "  at least one stack flag is required"
    exit 2
}

# ============================================================================
# Parse arguments
# ============================================================================

REPO=""
UNINSTALL=0
STACKS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall)
            UNINSTALL=1
            ;;
        --typescript | --go | --mongo | --react)
            STACKS+=("${1#--}")
            ;;
        -h | --help)
            awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0
            ;;
        -*)
            err "unknown flag: $1"
            usage
            ;;
        *)
            if [ -z "$REPO" ]; then
                REPO="$1"
            else
                err "unexpected argument: $1"
                usage
            fi
            ;;
    esac
    shift
done

[ -n "$REPO" ] || usage

# The target must be a git repo, so .claude/rules sits at a real project root.
if [ ! -d "$REPO/.git" ]; then
    err "not a git repository: $REPO (rules install at a project root)"
    exit 1
fi

DEST="$REPO/.claude/rules"

# ============================================================================
# install
# ============================================================================

do_install() {
    [ ${#STACKS[@]} -gt 0 ] || { err "no stack flags given; nothing to install"; usage; }
    step "Install stack rules into $DEST"
    mkdir -p "$DEST"

    for stack in "${STACKS[@]}"; do
        local name src
        name="$(rule_file "$stack")"
        src="$RULES_SRC/$name"
        [ -f "$src" ] || { err "missing rule template: $src"; exit 1; }
        # Copy, overwriting, so a re-run re-syncs a drifted copy to the template.
        cp "$src" "$DEST/$name"
        note "installed $name (--$stack)"
    done
    ok "Installed ${#STACKS[@]} stack rule(s). They take effect next session in $REPO."
}

# ============================================================================
# uninstall - remove the named stacks, or every stack rule if none named
# ============================================================================

do_uninstall() {
    step "Uninstall stack rules from $DEST"
    [ -d "$DEST" ] || { note "no .claude/rules in $REPO - nothing to remove"; return; }

    local targets=()
    if [ ${#STACKS[@]} -gt 0 ]; then
        for stack in "${STACKS[@]}"; do targets+=("$(rule_file "$stack")"); done
    else
        # No stacks named: remove every stack rule this script owns.
        for stack in typescript go mongo react; do targets+=("$(rule_file "$stack")"); done
    fi

    local removed=0
    for name in "${targets[@]}"; do
        if [ -f "$DEST/$name" ]; then
            rm -f "$DEST/$name"
            note "removed $name"
            removed=$((removed + 1))
        fi
    done
    # Tidy an empty .claude/rules so uninstall leaves no husk, but never touch a
    # rules dir that still holds other files (e.g. a hand-written project rule).
    rmdir "$DEST" 2>/dev/null && note "removed empty .claude/rules" || true
    ok "Removed $removed stack rule(s)."
}

# ============================================================================
# Dispatch
# ============================================================================

if [ "$UNINSTALL" = 1 ]; then
    do_uninstall
else
    do_install
fi
