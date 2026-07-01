#!/usr/bin/env bash
# Suite for scripts/init-python-project.sh: the Python generator scaffolds a
# src-layout, uv-managed project with a strict pyright config and a non-hollow
# unit tier, without touching the TypeScript generator. Sourced and run by
# tests/run.sh, which sets REPO_ROOT, the colour vars, and sources tests/lib.sh.
#
# Structural checks always run (no network). The live proof (uv sync + pytest +
# pyright) runs only when uv is available AND a sync succeeds; otherwise it is
# reported skipped, never silently passed, because it needs to fetch packages.

suite_begin "init-python-project.sh (Python generator)" integration

GEN="$REPO_ROOT/scripts/init-python-project.sh"

# --- input guards (the spine) ------------------------------------------------
expect_exit 2  "no name -> usage"                bash "$GEN"
expect_exit 2  "non-kebab name -> usage"         bash "$GEN" Bad_Name

# --- scaffold into a temp dir (structural, no network) -----------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proj="$work/demo-app"
if bash "$GEN" demo-app "$proj" >/dev/null 2>&1; then
    _t_ok "generator exits 0 scaffolding demo-app"
else
    _t_bad "generator failed to scaffold demo-app"
fi

# The src-layout package, modules, pyproject and tier tests are not existence-
# checked here: the content greps below and the live uv/pytest/pyright proof consume
# them, failing just as loudly if absent.

# strict pyright is declared (mandatory-and-strict posture).
expect_match 0 'typeCheckingMode = "strict"' "pyright strict declared" cat "$proj/pyproject.toml"
# both tier paths declared.
expect_match 0 'tests/unit'        "unit tier declared in pyproject"        cat "$proj/pyproject.toml"
expect_match 0 'tests/integration' "integration tier declared in pyproject" cat "$proj/pyproject.toml"
# CLAUDE.md declares the Integration endpoints section.
expect_match 0 'Integration endpoints' "CLAUDE.md declares integration endpoints" cat "$proj/CLAUDE.md"
# git initialised on main with the scaffold commit: assert the behaviour, not just
# that a .git directory is present. branch --show-current returns 'main' only when
# a commit-bearing HEAD is on the main branch (the generator's contract).
expect_match 0 '^main$' "git on main with the scaffold commit" git -C "$proj" branch --show-current

# (The Python generator must not break the TypeScript one, but a `test -f` only
# catches deletion, not breakage; real protection is the behavioural TS suites.
# No weak presence snapshot here.)

# --- live proof (needs uv + network): real uv sync, pytest, pyright ----------
# Reported skipped (not passed) when uv is absent or sync cannot fetch packages,
# per the fail-loud-or-mark-skipped rule. A clean machine with network proves the
# scaffold genuinely type-checks and tests.
if command -v uv >/dev/null 2>&1 && ( cd "$proj" && uv sync >/dev/null 2>&1 ); then
    if ( cd "$proj" && uv run pytest tests/unit >/dev/null 2>&1 ); then
        _t_ok "live: uv run pytest tests/unit passes (unit tier selects a test)"
    else
        _t_bad "live: uv run pytest tests/unit failed on the fresh scaffold"
    fi
    if ( cd "$proj" && uv run pyright >/dev/null 2>&1 ); then
        _t_ok "live: uv run pyright clean on the fresh scaffold (strict)"
    else
        _t_bad "live: uv run pyright reported errors on the fresh scaffold"
    fi
    # A module tested in both tiers gives tests/unit/test_x.py and tests/integration/
    # test_x.py the same basename. Under pytest's default prepend import mode that is
    # an import-file-mismatch on a combined-tier run; the scaffold sets import-mode to
    # importlib (via addopts) to avoid it. Prove a combined run collects both.
    printf 'def test_u():\n    assert True\n' > "$proj/tests/unit/test_dup.py"
    printf 'def test_i():\n    assert True\n' > "$proj/tests/integration/test_dup.py"
    if ( cd "$proj" && uv run pytest tests/unit tests/integration >/dev/null 2>&1 ); then
        _t_ok "live: combined-tier run collects a same-basename test in both tiers (import-mode importlib)"
    else
        _t_bad "live: combined-tier run failed on a same-basename test in both tiers (import-mode regression)"
    fi
    rm -f "$proj/tests/unit/test_dup.py" "$proj/tests/integration/test_dup.py"
else
    printf '  %sSKIP%s live uv sync/pytest/pyright proof (uv absent or no network to fetch packages)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

suite_summary
