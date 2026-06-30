#!/usr/bin/env bash
# tests/lib.sh - shared assertions and reporting for the repo's test suites.
# Sourced by each tests/<name>/test.sh, never executed. A suite calls `expect_exit`
# and `expect_match` to record cases; `suite_summary` prints the verdict and returns
# non-zero if any case failed. Expects REPO_ROOT and the colour vars set by the caller.

# Per-suite counters and kind, reset/set by suite_begin.
_t_pass=0
_t_fail=0
_t_kind=""

# Valid suite kinds (agent-sdlc's own test taxonomy, see docs):
#   unit        a pure script or stub, run-anywhere, no external tooling
#   integration runs real external tooling (uv/pytest/pyright/npm), self-skips if absent
#   structural  reads files and asserts conformance, executes nothing under test
_T_KINDS="unit integration structural"

# suite_begin <name> <kind>: start a suite. The kind is a required ARGUMENT (not an
# env var), recorded for the run to group and tally by; run.sh reads _t_kind after
# sourcing the suite. An absent or unknown kind is a hard error: a suite must
# categorise itself.
suite_begin() {
    _t_pass=0; _t_fail=0; _t_kind="${2:-}"
    printf '%s# %s%s' "${C_STEP:-}" "$1" "${C_RESET:-}"
    case " $_T_KINDS " in
        *" $_t_kind "*) printf ' %s[%s]%s\n' "${C_STEP:-}" "$_t_kind" "${C_RESET:-}" ;;
        *) printf '\n'; _t_bad "suite did not declare a valid kind (got '${_t_kind:-<none>}', want one of: $_T_KINDS)" ;;
    esac
}

_t_ok()   { _t_pass=$((_t_pass+1)); printf '  %sOK%s   %s\n' "${C_OK:-}" "${C_RESET:-}" "$1"; }
_t_bad()  { _t_fail=$((_t_fail+1)); printf '  %sFAIL%s %s\n' "${C_ERR:-}" "${C_RESET:-}" "$1"; }

# expect_exit <want> <name> <cmd...>: run cmd, assert its exit code equals <want>.
expect_exit() {
    local want="$1" name="$2"; shift 2
    local out ec
    out="$("$@" 2>&1)"; ec=$?
    if [ "$ec" = "$want" ]; then _t_ok "$name (exit $ec)"
    else _t_bad "$name: got exit $ec, want $want"; printf '       %s\n' "$out"; fi
}

# expect_match <want-exit> <regex> <name> <cmd...>: assert BOTH the exit code and that
# the output matches <regex>. Use when an exit code alone could pass for the wrong reason
# (e.g. a defect exit caused by the wrong rule).
expect_match() {
    local want="$1" regex="$2" name="$3"; shift 3
    local out ec
    out="$("$@" 2>&1)"; ec=$?
    if [ "$ec" = "$want" ] && printf '%s' "$out" | grep -Eq "$regex"; then
        _t_ok "$name (exit $ec, matched /$regex/)"
    else
        _t_bad "$name: exit $ec (want $want), regex /$regex/ $(printf '%s' "$out" | grep -Eq "$regex" && echo matched || echo 'NOT matched')"
        printf '       %s\n' "$out"
    fi
}

# expect_json <name> <node-assert-src> <cmd...>: run cmd, pipe its stdout (a JSON
# object) into `node -e <node-assert-src>` where the parsed object is the global `b`.
# The assertion src must throw on mismatch (or call assert); a clean run passes the case.
expect_json() {
    local name="$1" src="$2"; shift 2
    local out err
    out="$("$@" 2>/dev/null)"
    err="$(printf '%s' "$out" | node -e "const b=JSON.parse(require('fs').readFileSync(0));const assert=require('assert');$src" 2>&1)"
    if [ -z "$err" ]; then _t_ok "$name"
    else _t_bad "$name"; printf '       %s\n' "$err"; fi
}

# suite_summary: print the suite verdict, return 1 if any case failed.
suite_summary() {
    if [ "$_t_fail" -eq 0 ]; then
        printf '  %s%d passed%s\n' "${C_OK:-}" "$_t_pass" "${C_RESET:-}"
        return 0
    fi
    printf '  %s%d passed, %d failed%s\n' "${C_ERR:-}" "$_t_pass" "$_t_fail" "${C_RESET:-}"
    return 1
}
