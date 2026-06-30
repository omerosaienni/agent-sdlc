#!/usr/bin/env bash
# setup/python.sh - the Python per-stack setup module. Sourced by
# scripts/project-setup.sh when it detects a Python project (pyproject.toml),
# never executed directly. It defines the stack-specific checks the orchestrator
# calls in order; the orchestrator owns the stack-neutral spine (git, identity,
# .building gitignore, the verdict accounting and the receipt).
#
# Sourced-component discipline (script-layout.md, Multi-file scripts): no shebang
# run, no `set -e` of its own, no argument parsing. It defines functions and reads
# the orchestrator's helpers (ok/bad/note/block/need/consent), its `mode`, and the
# constants it sets (TEMPLATES_DIR). The orchestrator calls python_setup last.
#
# Mirrors setup/ts.sh for Python: uv for the environment, pytest for the tiers
# (split by directory tests/unit and tests/integration), pyright for the type-check
# gate, pytest-cov for coverage. The runners it places honour the same exit-code
# contract the shared agent-hollow.sh reads (contracts/agent-runner.md).
#
# Provides:
#   python_setup   run every Python check in order, accumulating into `fail`.

# uv_run_tier <tier-dir> <label> <endpoint?>: run a declared tier through
# uv run pytest, classify by pytest's exit code (0 pass, 1 failed, 5 no tests).
# A zero selection is a hollow suite (hard fail); a connection error on the
# endpoint tier is a BLOCK, not a code failure.
uv_run_tier() { local dir="$1" label="$2" ep="$3" out rc
    out=$(uv run pytest "$dir" 2>&1); rc=$?
    if [ "$rc" -eq 5 ]; then bad "$label selected zero tests (hollow suite)"; return; fi
    if [ "$rc" -ne 0 ]; then
        # pytest exit 1 can be a real failure or, on the endpoint tier, a connection
        # error surfacing as a failed/errored test. Treat a connection signature on
        # the endpoint tier as a BLOCK so a down endpoint is never a code failure.
        if [ "$ep" = yes ] && printf '%s' "$out" | grep -qiE "Connection refused|ConnectionError|Could not connect|ECONNREFUSED"; then
            block "$label endpoint not reachable; bring it up (see CLAUDE.md integration endpoints) and re-run"
        else bad "$label failed (see output)"; fi
        return
    fi
    ok "$label selected tests and passed"; }

# agent_check <tier>: prove the agent test runner works for one tier. The judge
# runs tests through .building/scripts/agent-tests.sh, so a project is only
# loop-ready if it produces a terse summary on a passing tier. exit 3 is an
# environment problem (block); exit 2 (zero selected) only defers, section above
# hard-fails a hollow declared tier.
agent_check() { local tier="$1" out rc
    out=$(bash .building/scripts/agent-tests.sh "$tier" 2>&1); rc=$?
    case "$rc" in
        0) if printf '%s' "$out" | grep -qE "^$tier: "; then ok "agent test runner works for $tier (terse summary)"
           else bad "agent test runner ran $tier but did not emit a terse summary; check .building/scripts/agent-tests.sh"; fi ;;
        2) note "agent runner reports $tier selects zero tests; the tier-run check above hard-fails a hollow declared tier, so this only defers" ;;
        3) block "agent test runner could not run $tier (environment); fix tooling and re-run" ;;
        *) bad "agent test runner failed for $tier (exit $rc); the judge depends on this path" ;;
    esac
}

# agent_hollow_check: prove the hollow-check runner answers its usage contract.
agent_hollow_check() {
    local rc
    bash .building/scripts/agent-hollow.sh >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 64 ]; then ok "agent hollow-check runner present and runnable"
    else bad ".building/scripts/agent-hollow.sh usage check failed (exit $rc, expected 64); the judge's hollow check depends on it"; fi
}

# agent_typecheck_check: prove the type-check runner is present and runnable. A
# clean type-check (0) or reported type errors (1) both prove it ran; only an
# environment block (3) or a usage/exec failure is a problem to surface here.
agent_typecheck_check() {
    local rc
    bash .building/scripts/agent-typecheck.sh >/dev/null 2>&1; rc=$?
    case "$rc" in
        0) ok "agent type-check runner works (clean)" ;;
        1) ok "agent type-check runner works (reported type errors; the runner ran)" ;;
        3) block "agent type-check runner could not run (pyright absent or no config); fix tooling and re-run" ;;
        *) bad ".building/scripts/agent-typecheck.sh failed (exit $rc); the judge's type-check gate depends on it" ;;
    esac
}

# python_setup: run the whole Python check sequence, accumulating into `fail`.
python_setup() {
    # -----------------------------------------------------------------------
    # 1. Environment: uv present, and the project resolves and installs.
    # -----------------------------------------------------------------------
    if ! command -v uv >/dev/null 2>&1; then
        bad "uv not installed; install uv before setup (https://docs.astral.sh/uv/)"
        return   # nothing else can be proven without the environment manager
    fi
    ok "uv present ($(uv --version 2>/dev/null))"
    if consent; then
        if uv sync >/dev/null 2>&1; then ok "uv sync resolved and installed the environment"
        else bad "uv sync failed; check pyproject.toml and the lockfile"; fi
    else
        # --check must not mutate; prove the lock is resolvable without installing.
        if uv lock --check >/dev/null 2>&1; then ok "uv lockfile is up to date (env not installed under --check)"
        else need "uv environment not synced; re-run without --check to uv sync"; fi
    fi

    # -----------------------------------------------------------------------
    # 2. Coverage tooling: pytest-cov present, install on consent (derive, like
    #    the TypeScript path derives its coverage provider).
    # -----------------------------------------------------------------------
    if uv run python -c "import pytest_cov" >/dev/null 2>&1; then ok "coverage tooling present (pytest-cov)"
    else
        note "coverage tooling missing (pytest-cov)"
        if consent; then
            if uv add --dev pytest-cov >/dev/null 2>&1; then ok "installed pytest-cov"
            else bad "could not add pytest-cov; add it to the dev dependencies"; fi
        else need "coverage tooling; re-run without --check to add pytest-cov"; fi
    fi

    # -----------------------------------------------------------------------
    # 3. Testing convention: tier directories present, place the three runners.
    # -----------------------------------------------------------------------
    local gaps=()
    [ -d tests/unit ] || gaps+=("tests/unit directory")
    [ -d tests/integration ] || gaps+=("tests/integration directory")
    cmp -s .building/scripts/agent-tests.sh "$TEMPLATES_DIR/runners/python/agent-tests.sh" || gaps+=(".building/scripts/agent-tests.sh (absent or stale)")
    cmp -s .building/scripts/agent-typecheck.sh "$TEMPLATES_DIR/runners/python/agent-typecheck.sh" || gaps+=(".building/scripts/agent-typecheck.sh (absent or stale)")
    cmp -s .building/scripts/agent-hollow.sh "$TEMPLATES_DIR/runners/agent-hollow.sh" || gaps+=(".building/scripts/agent-hollow.sh (absent or stale)")
    if [ ${#gaps[@]} -gt 0 ]; then
        note "testing convention incomplete; missing: ${gaps[*]}"
        if consent; then
            mkdir -p tests/unit tests/integration .building/scripts
            if ! cmp -s .building/scripts/agent-tests.sh "$TEMPLATES_DIR/runners/python/agent-tests.sh"; then
                if copy_template runners/python/agent-tests.sh .building/scripts/agent-tests.sh; then chmod +x .building/scripts/agent-tests.sh
                else bad "could not write .building/scripts/agent-tests.sh from template"; fi
            fi
            if ! cmp -s .building/scripts/agent-typecheck.sh "$TEMPLATES_DIR/runners/python/agent-typecheck.sh"; then
                if copy_template runners/python/agent-typecheck.sh .building/scripts/agent-typecheck.sh; then chmod +x .building/scripts/agent-typecheck.sh
                else bad "could not write .building/scripts/agent-typecheck.sh from template"; fi
            fi
            if ! cmp -s .building/scripts/agent-hollow.sh "$TEMPLATES_DIR/runners/agent-hollow.sh"; then
                if copy_template runners/agent-hollow.sh .building/scripts/agent-hollow.sh; then chmod +x .building/scripts/agent-hollow.sh
                else bad "could not write .building/scripts/agent-hollow.sh from template"; fi
            fi
            ok "scaffolded testing convention (tier dirs + agent runners)"
        else
            need "testing convention; re-run without --check to scaffold"
        fi
    else
        ok "testing convention present (tier dirs + agent runners)"
    fi

    # CLAUDE.md must declare integration endpoints (project judgement, report only).
    if [ -f CLAUDE.md ]; then
        grep -qi "Integration endpoints" CLAUDE.md && ok "CLAUDE.md declares integration endpoints" || bad "CLAUDE.md missing an 'Integration endpoints' section; add your endpoint and its bring-up command"
    else
        bad "no CLAUDE.md; add one declaring conventions and integration endpoints"
    fi

    # -----------------------------------------------------------------------
    # 4. Run each tier for real: non-zero selection + pass.
    # -----------------------------------------------------------------------
    [ -d tests/unit ] && uv_run_tier tests/unit "unit tier" no
    [ -d tests/integration ] && uv_run_tier tests/integration "integration tier" yes

    # -----------------------------------------------------------------------
    # 5. Prove the agent runner paths (the judge's surfaces).
    # -----------------------------------------------------------------------
    if [ -f .building/scripts/agent-tests.sh ]; then
        [ -d tests/unit ] && agent_check unit
        [ -d tests/integration ] && [ "$fail" -ne 3 ] && agent_check integration
    fi
    [ -f .building/scripts/agent-hollow.sh ] && agent_hollow_check
    [ -f .building/scripts/agent-typecheck.sh ] && agent_typecheck_check

    # -----------------------------------------------------------------------
    # 6. Coverage runs (verify by running, do not trust the install).
    # -----------------------------------------------------------------------
    if uv run python -c "import pytest_cov" >/dev/null 2>&1; then
        uv run pytest tests/unit --cov >/dev/null 2>&1 && ok "coverage runs" || bad "coverage run failed; check pytest-cov and pyproject.toml"
    fi
}
