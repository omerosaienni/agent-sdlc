#!/usr/bin/env bash
# Suite: every terminal-callable script answers --help with exit 0 and non-empty
# output. The gate for the convention going forward (contracts/script-layout.md):
# a new callable script with no --help fails here. Sourced and run by tests/run.sh.
#
# Callable = scripts/*.sh and skills/*.sh. EXEMPT are the sourced components, which
# are never executed directly (no shebang-run path; they define functions in an
# orchestrator's scope): scripts/generator/ and scripts/setup/ are not globbed.

suite_begin "script --help convention" structural

# check_help <script>: run it with --help, assert exit 0, non-empty stdout, and that
# help prints the header block ONLY. The convention (contracts/script-layout.md) stops
# at the first non-comment line, so a leaked section banner (`# ====`) in help means the
# script used the old grep-all-comments idiom; that is a failure, not a warning.
check_help() {
    local s="$1" out rc b
    out="$(bash "$s" --help 2>/dev/null)"; rc=$?
    b="$(printf '%s\n' "$out" | grep -c '====')"
    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
        _t_bad "$(basename "$s") --help: exit $rc, $([ -n "$out" ] && echo 'printed' || echo 'printed NOTHING')"
    elif [ "$b" -ne 0 ]; then
        _t_bad "$(basename "$s") --help: leaked $b section banner line(s); help must print the header block only"
    else
        _t_ok "$(basename "$s") --help (exit 0, header block only)"
    fi
}

# Every directly-callable script. The glob is non-recursive, so sourced components
# under scripts/generator/ and scripts/setup/ are naturally excluded.
for s in "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/skills/*.sh; do
    [ -f "$s" ] || continue
    check_help "$s"
done

# --- directly-callable scripts must be executable -----------------------------
# The skills invoke the generators by absolute path, so a script committed without
# its executable bit is broken for every user of the skill while every test that
# runs it as `bash <script>` still passes. That is exactly how it shipped once.
# Sourced components (scripts/generator/, scripts/setup/, tests/lib.sh) are exempt:
# they are never executed directly.
for s in "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/skills/*.sh "$REPO_ROOT"/file-templates/runners/*.sh "$REPO_ROOT"/file-templates/runners/*/*.sh; do
    [ -f "$s" ] || continue
    rel="${s#"$REPO_ROOT"/}"
    if [ -x "$s" ]; then
        _t_ok "$rel is executable"
    else
        _t_bad "$rel is not executable; a skill invoking it by path gets 'Permission denied'"
    fi
done

suite_summary
