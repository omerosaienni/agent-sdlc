#!/usr/bin/env bash
# setup-global-git-hooks.sh - install this repo's git guards globally, for every
# repo at once, with no drift.
#
# It points git's global core.hooksPath at one shared dir (~/.config/git/hooks)
# holding three hooks:
#   pre-commit  identity guard     - blocks a commit whose author email is off the allowlist
#   commit-msg  authorship guard   - blocks a commit message that credits an AI assistant
#   pre-push    branch-name guard   - blocks a push from a branch not named <type>/<kebab>
# core.hooksPath is a global redirect: git consults ONLY that dir, so there is one
# source of truth and no per-repo copies to drift. Each hook then CHAINS - after
# its own check passes it execs the repo's own .git/hooks/<name> if one exists, so
# a per-repo tool installed later (husky, pre-commit, lefthook) keeps working
# rather than being silently shadowed. Our guard runs first; if it blocks, the
# local hook never runs.
#
# Global or nothing: there is no per-repo mode. install sets it up for every repo,
# uninstall restores git's default. Call the verb you want explicitly.
#
# The identity guard reads its allowlist from your own git config
# (sdlc.identityAllowlist), so no email is baked into this repo. install sets that
# key from --email, or from your global user.email if you omit it.
#
# Usage:
#   setup-global-git-hooks.sh install [--email <addr>]   # place hooks, set core.hooksPath + allowlist, tidy stale
#   setup-global-git-hooks.sh uninstall                  # unset core.hooksPath, remove the placed hooks
set -euo pipefail

# ============================================================================
# Where things live
# ============================================================================

# This script's own dir, so the source hooks resolve regardless of the cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$SCRIPT_DIR/../hooks"

# XDG-standard home for git config (sits next to ~/.config/git/config).
# XDG_CONFIG_HOME is a standard, widely-honoured env var, so it is an allowed
# exemption from the args-not-env-vars rule (claude-rules/omero-script-args.md):
# honouring it is the convention, not a caller-specific behaviour override.
HOOKS_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/git/hooks"

# The hooks this repo owns and installs.
HOOK_NAMES="pre-commit commit-msg pre-push"

# Known-stale hooks install is allowed to delete when it finds them shadowing,
# matched by md5 so it never removes something unrecognised:
#   0e1a4bd... an older copy of our identity guard (stale allowlist)
#   caa572f... a dead pre-commit-framework shim (broken pipx path)
STALE_MD5S="0e1a4bd2bb182e678e0aad3fde3ac24f caa572f5ad7c13c3af5210b82bcaa58f"

# Where the stale-hook tidy looks for repos: a conventional dev root as the default.
# If your repos live elsewhere (~/src, ~/code, ~/projects, ...), pass one or more
# roots as arguments after the verb to scan those instead.
SCAN_ROOTS_DEFAULT="$HOME/source-code"

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
# Parse arguments
# ============================================================================

VERB="${1:-}"
# --help/-h reprints the header block and exits, before requiring a verb.
case "$VERB" in
    -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
shift || true
EMAIL=""
ROOTS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --email)
            EMAIL="${2:-}"
            shift 2
            ;;
        *)
            ROOTS+=("$1")
            shift
            ;;
    esac
done
[ ${#ROOTS[@]} -gt 0 ] || ROOTS=("$SCAN_ROOTS_DEFAULT")

# ============================================================================
# Tidy: remove known-stale per-repo hooks that this global install would shadow,
# so they do not sit dead in .git/hooks. Only md5-matched files are removed;
# anything unrecognised is left and reported.
# ============================================================================

tidy_stale() {
    step "Tidy known-stale per-repo hooks under: ${ROOTS[*]}"
    local found=0 sum
    while IFS= read -r hookfile; do
        [ -f "$hookfile" ] || continue
        sum="$(md5sum "$hookfile" | cut -d' ' -f1)"
        case " $STALE_MD5S " in
            *" $sum "*)
                found=$((found + 1))
                note "rm $hookfile  (known-stale $sum)"
                rm -f "$hookfile"
                ;;
        esac
    done < <(find "${ROOTS[@]}" -type f -path '*/.git/hooks/*' ! -name '*.sample' 2>/dev/null)
    [ "$found" -eq 0 ] && note "none found" || ok "removed $found stale hook(s)"
}

# ============================================================================
# install
# ============================================================================

do_install() {
    step "Install global git hooks"

    for h in $HOOK_NAMES; do
        [ -f "$HOOKS_SRC/$h" ] || { err "missing source hook: $HOOKS_SRC/$h"; exit 1; }
    done

    mkdir -p "$HOOKS_DEST"
    for h in $HOOK_NAMES; do
        install -m 0755 "$HOOKS_SRC/$h" "$HOOKS_DEST/$h"
        note "installed $h -> $HOOKS_DEST/$h"
    done

    local current
    current="$(git config --global --get core.hooksPath || true)"
    if [ "$current" = "$HOOKS_DEST" ]; then
        note "core.hooksPath already points here"
    elif [ -n "$current" ]; then
        err "core.hooksPath is already set to '$current' (not ours). Refusing to overwrite."
        err "Unset it yourself first if you meant to replace it."
        exit 1
    else
        git config --global core.hooksPath "$HOOKS_DEST"
        note "set core.hooksPath -> $HOOKS_DEST"
    fi

    # The identity guard reads the allowlist from git config (no email is baked
    # into the repo). Set it here so the guard works right after install. Prefer
    # an explicit --email; fall back to the configured global user.email. If
    # neither is available, leave it unset - the guard fails closed and tells you.
    local allow
    allow="$(git config --global --get sdlc.identityAllowlist || true)"
    if [ -n "$allow" ]; then
        note "sdlc.identityAllowlist already set ($allow)"
    elif [ -n "$EMAIL" ]; then
        git config --global sdlc.identityAllowlist "$EMAIL"
        note "set sdlc.identityAllowlist -> $EMAIL"
    elif [ -n "$(git config --global --get user.email || true)" ]; then
        allow="$(git config --global --get user.email)"
        git config --global sdlc.identityAllowlist "$allow"
        note "set sdlc.identityAllowlist -> $allow (from global user.email)"
    else
        err "sdlc.identityAllowlist not set and no global user.email to default from."
        err "Set it: git config --global sdlc.identityAllowlist '<your-commit-email>'"
    fi

    tidy_stale
    ok "Installed. Every repo now runs the identity, authorship and branch-name guards."
}

# ============================================================================
# uninstall - restore git's default (per-repo .git/hooks)
# ============================================================================

do_uninstall() {
    step "Uninstall global git hooks"

    local current
    current="$(git config --global --get core.hooksPath || true)"
    if [ "$current" = "$HOOKS_DEST" ]; then
        # Unset, not set-to-empty: an empty value is still an override. Unsetting
        # restores git's built-in default (each repo's own .git/hooks).
        git config --global --unset core.hooksPath
        note "unset core.hooksPath (restored git default)"
    elif [ -n "$current" ]; then
        note "core.hooksPath points at '$current', not ours - left untouched"
    else
        note "core.hooksPath not set - nothing to restore"
    fi

    for h in $HOOK_NAMES; do
        if [ -f "$HOOKS_DEST/$h" ]; then
            rm -f "$HOOKS_DEST/$h"
            note "removed $HOOKS_DEST/$h"
        fi
    done
    ok "Uninstalled. Git is back to its default hook behaviour."
}

# ============================================================================
# Dispatch
# ============================================================================

case "$VERB" in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    *)
        err "usage: setup-global-git-hooks.sh install|uninstall [scan-root...]"
        exit 2
        ;;
esac
