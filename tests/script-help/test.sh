#!/usr/bin/env bash
# Suite: every terminal-callable script answers --help with exit 0 and non-empty
# output. The gate for the convention going forward (contracts/script-layout.md):
# a new callable script with no --help fails here. Sourced and run by tests/run.sh.
#
# Callable = scripts/*.sh and skills/*.sh. EXEMPT are the sourced components, which
# are never executed directly (no shebang-run path; they define functions in an
# orchestrator's scope): scripts/generator/ and scripts/setup/ are not globbed.

suite_begin "script --help convention" structural

# check_help <script>: run it with --help, assert exit 0 and non-empty stdout.
check_help() {
    local s="$1" out rc
    out="$(bash "$s" --help 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then _t_ok "$(basename "$s") --help (exit 0, prints usage)"
    else _t_bad "$(basename "$s") --help: exit $rc, $([ -n "$out" ] && echo 'printed' || echo 'printed NOTHING')"; fi
}

# Every directly-callable script. The glob is non-recursive, so sourced components
# under scripts/generator/ and scripts/setup/ are naturally excluded.
for s in "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/skills/*.sh; do
    [ -f "$s" ] || continue
    check_help "$s"
done

suite_summary
