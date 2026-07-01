#!/usr/bin/env bash
# setup/ts.sh - the TypeScript per-stack setup module. Sourced by
# scripts/project-setup.sh when it detects a TypeScript project (package.json),
# never executed directly. It defines the stack-specific checks the orchestrator
# calls in order; the orchestrator owns the stack-neutral spine (git, identity,
# .building gitignore, the verdict accounting and the receipt).
#
# Sourced-component discipline (script-layout.md, Multi-file scripts): no shebang
# run, no `set -e` of its own, no argument parsing. It defines functions and reads
# the orchestrator's helpers (ok/bad/note/block/need/consent), its `mode`, and the
# constants it sets (TEMPLATES_DIR). The orchestrator calls ts_setup last.
#
# Provides:
#   ts_setup   run every TypeScript check in order, accumulating into `fail`.
# (the per-check helpers below are its building blocks, kept separate so each
#  reads as one job, matching the generator layers' one-function-per-area shape.)

# node_major <pkg>: the installed major version of a node dependency, or empty.
node_major() { node -e "try{console.log(require('$1/package.json').version.split('.')[0])}catch(e){process.exit(1)}" 2>/dev/null; }
# has_script <name>: '1' if package.json declares the npm script, else empty.
has_script() { node -e "try{process.stdout.write(require('./package.json').scripts['$1']?'1':'')}catch(e){}" 2>/dev/null; }

# run_tier <script> <endpoint?>: run a declared tier through npm, classify the
# result. A zero selection is a hollow suite (hard fail); a connection error on an
# endpoint tier is a BLOCK, not a code failure; any other non-zero is a real fail.
run_tier() { local s="$1" ep="$2" out rc
    out=$(npm run "$s" 2>&1); rc=$?
    if echo "$out" | grep -q "No test files found"; then bad "$s selected zero tests (hollow suite)"; return; fi
    if [ "$rc" -ne 0 ]; then
        if [ "$ep" = yes ] && echo "$out" | grep -qiE "ECONNREFUSED|MongoServerSelectionError|connection refused"; then block "$s endpoint not reachable; bring up the shared Mongo (make db-start, see CLAUDE.md integration endpoints) and re-run"
        else bad "$s failed (see output)"; fi; return; fi
    ok "$s selected tests and passed"; }

# agent_check <tier>: prove the agent test runner (.building/scripts/agent-tests.sh) works
# for one tier. The judge runs tests through this runner, so a project is only
# loop-ready if it produces a terse summary on a passing tier. exit 3 is an
# environment problem (block), other non-zero is a real failure of the path.
agent_check() { local tier="$1" out rc
    out=$(bash .building/scripts/agent-tests.sh "$tier" 2>&1); rc=$?
    case "$rc" in
        0) if printf '%s' "$out" | grep -qE "^$tier: [0-9]+ passed"; then ok "agent test runner works for $tier (terse summary)"
           else bad "agent test runner ran $tier but did not emit a terse summary; check .building/scripts/agent-tests.sh"; fi ;;
        2) note "agent runner reports $tier selects zero tests; section 3 above hard-fails a hollow declared tier, so this only defers, it does not excuse it" ;;
        3) block "agent test runner could not run $tier (environment); fix tooling and re-run" ;;
        *) bad "agent test runner failed for $tier (exit $rc); the judge depends on this path" ;;
    esac
}

# agent_hollow_check: prove the hollow-check runner is present and runnable. A
# full functional proof would need a planted break; verifying it parses and
# answers its usage contract (no args -> exit 64) is enough to know the judge
# can invoke it. The functional proof is the loop using it on a real increment.
agent_hollow_check() {
    local rc
    bash .building/scripts/agent-hollow.sh >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 64 ]; then ok "agent hollow-check runner present and runnable"
    else bad ".building/scripts/agent-hollow.sh usage check failed (exit $rc, expected 64); the judge's hollow check depends on it"; fi
}

# agent_typecheck_check: prove the type-check runner is present and runnable. Setup
# now places all three runners, so it proves this one too. A clean tsconfig type-checks
# (exit 0); a missing tsconfig is an environment block (exit 3). Either proves the
# runner itself works (it parsed and ran); only a usage/exec failure is a hard fail.
agent_typecheck_check() {
    local rc
    bash .building/scripts/agent-typecheck.sh >/dev/null 2>&1; rc=$?
    case "$rc" in
        0) ok "agent type-check runner works (clean)" ;;
        1) ok "agent type-check runner works (reported type errors; the runner ran)" ;;
        3) block "agent type-check runner could not run (no tsconfig or tsc absent); fix tooling and re-run" ;;
        *) bad ".building/scripts/agent-typecheck.sh failed (exit $rc); the judge's type-check gate depends on it" ;;
    esac
}

# format_check: prove the project is prettier-clean. Formatting is a convention
# the reviewer is entitled to bounce on (it cites eslint/prettier), but eslint is
# configured formatting-blind (eslint-config-prettier switches those rules off), so
# nothing gated formatting until here. On drift, fix on consent (prettier --write),
# else FAIL: a formatting-dirty tree must not write a READY receipt.
format_check() {
    npx prettier --check . >/dev/null 2>&1 && { ok "formatting clean (prettier)"; return; }
    note "formatting drift (prettier --check failed)"
    if consent; then
        npx prettier --write . >/dev/null 2>&1 && ok "formatted with prettier --write" || bad "prettier --write failed; format the tree manually"
    else
        need "formatting; re-run without --check to run prettier --write"
    fi
}

# ts_setup: run the whole TypeScript check sequence, in order.
ts_setup() {
    # -----------------------------------------------------------------------
    # 1. Report tooling: derive from vitest, match coverage, verify.
    # -----------------------------------------------------------------------
    local vmaj cmaj
    vmaj=$(node_major vitest)
    if [ -z "$vmaj" ]; then bad "vitest not installed; install it before setup"; else
        cmaj=$(node_major @vitest/coverage-v8)
        if [ -n "$cmaj" ] && [ "$cmaj" = "$vmaj" ]; then ok "coverage tooling matches vitest $vmaj"; else
            [ -n "$cmaj" ] && note "coverage mismatched (vitest $vmaj, coverage $cmaj)" || note "coverage missing (need ^$vmaj)"
            if consent; then npm install -D "@vitest/coverage-v8@^${vmaj}" && ok "installed coverage ^$vmaj" || bad "install failed"
            else need "coverage tooling; re-run without --check"; fi
        fi
    fi

    # -----------------------------------------------------------------------
    # 2. Testing convention: tier scripts + configs, scaffold with consent.
    # -----------------------------------------------------------------------
    local have_unit have_int have_fmt gaps
    have_unit=$(has_script "server:test:unit"); have_int=$(has_script "server:test:integration"); have_fmt=$(has_script "format:check")
    gaps=()
    [ "$have_unit" = "1" ] || gaps+=("npm script server:test:unit")
    [ "$have_int" = "1" ]  || gaps+=("npm script server:test:integration")
    [ "$have_fmt" = "1" ]  || gaps+=("npm script format:check")
    [ -f vitest.unit.config.ts ] || gaps+=("vitest.unit.config.ts")
    [ -f vitest.integration.config.ts ] || gaps+=("vitest.integration.config.ts")
    # The three agent runners the judge calls live under .building/scripts/ (gitignored
    # workflow tooling, not the project proper, so setup places them, not the generator).
    # Setup places ALL THREE so one actor owns runner placement: the TypeScript test and
    # type-check runners come from file-templates/runners/ts/, the shared hollow runner
    # from file-templates/runners/ (one file across stacks; see contracts/agent-runner.md).
    cmp -s .building/scripts/agent-tests.sh "$TEMPLATES_DIR/runners/ts/agent-tests.sh" || gaps+=(".building/scripts/agent-tests.sh (absent or stale)")
    cmp -s .building/scripts/agent-typecheck.sh "$TEMPLATES_DIR/runners/ts/agent-typecheck.sh" || gaps+=(".building/scripts/agent-typecheck.sh (absent or stale)")
    cmp -s .building/scripts/agent-hollow.sh "$TEMPLATES_DIR/runners/agent-hollow.sh" || gaps+=(".building/scripts/agent-hollow.sh (absent or stale)")
    if [ ${#gaps[@]} -gt 0 ]; then
        note "testing convention incomplete; missing: ${gaps[*]}"
        note "scaffold writes the two tier configs, the two npm scripts and the three agent runners (boilerplate)"
        if consent; then
            [ -f vitest.unit.config.ts ] || copy_template vitest.unit.config.ts vitest.unit.config.ts || bad "could not write vitest.unit.config.ts from template"
            [ -f vitest.integration.config.ts ] || copy_template vitest.integration.config.ts vitest.integration.config.ts || bad "could not write vitest.integration.config.ts from template"
            [ "$have_unit" = "1" ] || npm pkg set "scripts.server:test:unit=vitest run -c vitest.unit.config.ts" >/dev/null
            [ "$have_int" = "1" ]  || npm pkg set "scripts.server:test:integration=vitest run -c vitest.integration.config.ts" >/dev/null
            [ "$have_fmt" = "1" ]  || npm pkg set "scripts.format:check=prettier --check ." >/dev/null
            if ! cmp -s .building/scripts/agent-tests.sh "$TEMPLATES_DIR/runners/ts/agent-tests.sh"; then
                mkdir -p .building/scripts
                if copy_template runners/ts/agent-tests.sh .building/scripts/agent-tests.sh; then chmod +x .building/scripts/agent-tests.sh
                else bad "could not write .building/scripts/agent-tests.sh from template"; fi
            fi
            if ! cmp -s .building/scripts/agent-typecheck.sh "$TEMPLATES_DIR/runners/ts/agent-typecheck.sh"; then
                mkdir -p .building/scripts
                if copy_template runners/ts/agent-typecheck.sh .building/scripts/agent-typecheck.sh; then chmod +x .building/scripts/agent-typecheck.sh
                else bad "could not write .building/scripts/agent-typecheck.sh from template"; fi
            fi
            if ! cmp -s .building/scripts/agent-hollow.sh "$TEMPLATES_DIR/runners/agent-hollow.sh"; then
                mkdir -p .building/scripts
                if copy_template runners/agent-hollow.sh .building/scripts/agent-hollow.sh; then chmod +x .building/scripts/agent-hollow.sh
                else bad "could not write .building/scripts/agent-hollow.sh from template"; fi
            fi
            ok "scaffolded testing convention (configs + scripts + agent runners)"
            have_unit=$(has_script "server:test:unit"); have_int=$(has_script "server:test:integration"); have_fmt=$(has_script "format:check")
        else
            need "testing convention; re-run without --check to scaffold"
        fi
    else
        ok "testing convention present (tier configs + scripts + agent runners)"
    fi

    # CLAUDE.md convention sections are project judgement, report only (never scaffold endpoints)
    if [ -f CLAUDE.md ]; then
        grep -qi "Integration endpoints" CLAUDE.md && ok "CLAUDE.md declares integration endpoints" || bad "CLAUDE.md missing an 'Integration endpoints' section; add your endpoint and its bring-up command"
    else
        bad "no CLAUDE.md; add one declaring conventions and integration endpoints"
    fi

    # -----------------------------------------------------------------------
    # 3. Run each tier; non-zero selection + pass.
    # -----------------------------------------------------------------------
    [ "$have_unit" = "1" ] && run_tier "server:test:unit" no
    [ "$have_int" = "1" ]  && run_tier "server:test:integration" yes

    # -----------------------------------------------------------------------
    # 3b. Prove the agent test path works. The judge runs tests through
    # .building/scripts/agent-tests.sh, not the human npm scripts, so a project is only
    # loop-ready if that path runs and reports a terse summary. Verify it against
    # each tier the project declares: unit if declared, integration if declared. An
    # integration-only project (no unit tier) must still have its agent path proven,
    # because the judge will use it for integration.
    # -----------------------------------------------------------------------
    if [ -f .building/scripts/agent-tests.sh ]; then
        # Mirror section 3: prove the agent path for each tier the project declares.
        # Skip integration if the run is already in a blocked state (fail=3): a block
        # means fix the environment and re-run, so the skipped check happens then.
        [ "$have_unit" = "1" ] && agent_check unit
        [ "$have_int" = "1" ] && [ "$fail" -ne 3 ] && agent_check integration
    fi

    # 3c. Prove the hollow-check and type-check runners (the judge's negative-run and
    # gate commands) are present and runnable, on the same loop-ready footing as the
    # test runner above. Setup places all three runners, so it proves all three.
    [ -f .building/scripts/agent-hollow.sh ] && agent_hollow_check
    [ -f .building/scripts/agent-typecheck.sh ] && agent_typecheck_check

    # 3d. Prove the tree is formatter-clean. Only meaningful if the project has the
    # format:check script (scaffolded above); skip silently if it somehow lacks it.
    [ "$have_fmt" = "1" ] && format_check

    # -----------------------------------------------------------------------
    # 4. Coverage runs.
    # -----------------------------------------------------------------------
    [ -n "$vmaj" ] && { npx vitest run --coverage --reporter=dot >/dev/null 2>&1 && ok "coverage runs" || bad "coverage run failed; check the vitest config"; }
}
