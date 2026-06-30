#!/usr/bin/env bash
# Suite for scripts/init-python-project.sh: the Python generator scaffolds a
# src-layout, uv-managed project with a strict pyright config and a non-hollow
# unit tier, without touching the TypeScript generator. Sourced and run by
# tests/run.sh, which sets REPO_ROOT, the colour vars, and sources tests/lib.sh.
#
# Structural checks always run (no network). The live proof (uv sync + pytest +
# pyright) runs only when uv is available AND a sync succeeds; otherwise it is
# reported skipped, never silently passed, because it needs to fetch packages.

suite_begin "init-python-project.sh (Python generator)"

GEN="$REPO_ROOT/scripts/init-python-project.sh"

# --- input guards (the spine) ------------------------------------------------
expect_exit 2  "no name -> usage"                bash "$GEN"
expect_exit 2  "non-kebab name -> usage"         bash "$GEN" Bad_Name
expect_exit 0  "the orchestrator exists"         test -f "$GEN"

# --- scaffold into a temp dir (structural, no network) -----------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proj="$work/demo-app"
if bash "$GEN" demo-app "$proj" >/dev/null 2>&1; then
    _t_ok "generator exits 0 scaffolding demo-app"
else
    _t_bad "generator failed to scaffold demo-app"
fi

# src-layout: the package is src/<underscored-name>/, not a flat package.
expect_exit 0 "src-layout package dir exists"        test -d "$proj/src/demo_app"
expect_exit 1 "no flat package at repo root"         test -d "$proj/demo_app"
expect_exit 0 "entry module present"                 test -f "$proj/src/demo_app/app.py"
expect_exit 0 "pyproject.toml present"               test -f "$proj/pyproject.toml"
expect_exit 0 "unit tier dir + test present"         test -f "$proj/tests/unit/test_app.py"
expect_exit 0 "integration tier dir + test present"  test -f "$proj/tests/integration/test_smoke.py"
expect_exit 0 "CI workflow present"                  test -f "$proj/.github/workflows/ci.yml"

# strict pyright is declared (mandatory-and-strict posture).
expect_match 0 'typeCheckingMode = "strict"' "pyright strict declared" cat "$proj/pyproject.toml"
# both tier paths declared.
expect_match 0 'tests/unit'        "unit tier declared in pyproject"        cat "$proj/pyproject.toml"
expect_match 0 'tests/integration' "integration tier declared in pyproject" cat "$proj/pyproject.toml"
# CLAUDE.md declares the Integration endpoints section.
expect_match 0 'Integration endpoints' "CLAUDE.md declares integration endpoints" cat "$proj/CLAUDE.md"
# git initialised on main.
expect_exit 0 "git repo initialised" test -d "$proj/.git"

# the TypeScript generator is untouched (this increment adds, never replaces).
expect_exit 0 "TS generator still present" test -f "$REPO_ROOT/scripts/init-ts-project.sh"

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
else
    printf '  %sSKIP%s live uv sync/pytest/pyright proof (uv absent or no network to fetch packages)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

suite_summary
