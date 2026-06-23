#!/usr/bin/env bash
# Project setup gate. Prove a project is ready to build, by execution not
# assertion. Idempotent: safe to run any number of times. Acts only on the gap.
# On READY it writes a receipt (.building/setup-ok) the build loop checks.
#
# Usage:
#   project-setup.sh            check; ask before installing or scaffolding
#   project-setup.sh --yes      install and scaffold gaps without asking
#   project-setup.sh --check    verify only; never install or scaffold
#
# Exit: 0 READY, 1 NOT READY (fix FAILs), 2 needs --yes, 3 BLOCKED (endpoint down)
#
# No -e: this gate accumulates failures in `fail` and decides its own exit code,
# so a single failing check must not abort the run.
set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

# Git commit-identity allowlist: the loop's commits must be authored by one of
# these emails, so they attribute to the right GitHub account. Override per
# machine with GIT_IDENTITY_ALLOWLIST (space-separated) if your identity differs.
IDENTITY_ALLOWLIST="${GIT_IDENTITY_ALLOWLIST:-39497847+omerosaienni@users.noreply.github.com}"

# ============================================================================
# Helpers
# ============================================================================

fail=0
note(){ printf '  %s\n' "$1"; }
ok(){ printf 'OK    %s\n' "$1"; }
bad(){ printf 'FAIL  %s\n' "$1"; fail=1; }
block(){ printf 'BLOCK %s\n' "$1"; [ "$fail" -lt 3 ] && fail=3; }
need(){ printf 'NEED  %s\n' "$1"; [ "$fail" -lt 2 ] && fail=2; }

# consent: true if the gate may install/scaffold/push, given the mode.
consent(){ case "$mode" in
    yes) return 0 ;;
    check) return 1 ;;
    ask) if [ -t 0 ]; then read -r -p "  do it now? [y/N] " r; case "$r" in y|Y|yes|YES) return 0;; *) return 1;; esac; fi; return 1 ;;
esac; }

node_major(){ node -e "try{console.log(require('$1/package.json').version.split('.')[0])}catch(e){process.exit(1)}" 2>/dev/null; }
has_script(){ node -e "try{process.stdout.write(require('./package.json').scripts['$1']?'1':'')}catch(e){}" 2>/dev/null; }

# Templates: the vitest tier configs the scaffold path writes come from shared
# templates (also used by init-ts-mongo.sh), so the two scripts never drift.
# Resolve relative to this script's own location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"
copy_template(){ local src="$TEMPLATES_DIR/$1" dest="$2"
    if [ ! -f "$src" ]; then echo "missing template: $src" >&2; return 1; fi
    cp "$src" "$dest"; }

run_tier(){ local s="$1" ep="$2" out rc
    out=$(npm run "$s" 2>&1); rc=$?
    if echo "$out" | grep -q "No test files found"; then bad "$s selected zero tests (hollow suite)"; return; fi
    if [ "$rc" -ne 0 ]; then
        if [ "$ep" = yes ] && echo "$out" | grep -qiE "ECONNREFUSED|MongoServerSelectionError|connection refused"; then block "$s endpoint not reachable; bring up the shared Mongo (make up, see CLAUDE.md integration endpoints) and re-run"
        else bad "$s failed (see output)"; fi; return; fi
    ok "$s selected tests and passed"; }

# agent_check <tier>: prove the agent test runner (.building/scripts/agent-tests.sh) works
# for one tier. The judge runs tests through this runner, so a project is only
# loop-ready if it produces a terse summary on a passing tier. exit 3 is an
# environment problem (block), other non-zero is a real failure of the path.
agent_check(){ local tier="$1" out rc
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
# can invoke it. The functional proof is the loop using it on a real deliverable.
agent_hollow_check(){
    local rc
    bash .building/scripts/agent-hollow.sh >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 64 ]; then ok "agent hollow-check runner present and runnable"
    else bad ".building/scripts/agent-hollow.sh usage check failed (exit $rc, expected 64); the judge's hollow check depends on it"; fi
}

# format_check: prove the project is prettier-clean. Formatting is a convention
# the reviewer is entitled to bounce on (it cites eslint/prettier), but eslint is
# configured formatting-blind (eslint-config-prettier switches those rules off), so
# nothing gated formatting until here. On drift, fix on consent (prettier --write),
# else FAIL: a formatting-dirty tree must not write a READY receipt.
format_check(){
    npx prettier --check . >/dev/null 2>&1 && { ok "formatting clean (prettier)"; return; }
    note "formatting drift (prettier --check failed)"
    if consent; then
        npx prettier --write . >/dev/null 2>&1 && ok "formatted with prettier --write" || bad "prettier --write failed; format the tree manually"
    else
        need "formatting; re-run with --yes to run prettier --write"
    fi
}

# ============================================================================
# Parse arguments
# ============================================================================

mode="ask"
for a in "$@"; do case "$a" in
    -y|--yes) mode="yes" ;;
    --check) mode="check" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 64 ;;
esac; done

echo "== Project setup gate =="

# ---------------------------------------------------------------------------
# 1. Report tooling: derive from vitest, match coverage, verify.
# ---------------------------------------------------------------------------
vmaj=$(node_major vitest)
if [ -z "$vmaj" ]; then bad "vitest not installed; install it before setup"; else
    cmaj=$(node_major @vitest/coverage-v8)
    if [ -n "$cmaj" ] && [ "$cmaj" = "$vmaj" ]; then ok "coverage tooling matches vitest $vmaj"; else
        [ -n "$cmaj" ] && note "coverage mismatched (vitest $vmaj, coverage $cmaj)" || note "coverage missing (need ^$vmaj)"
        if consent; then npm install -D "@vitest/coverage-v8@^${vmaj}" && ok "installed coverage ^$vmaj" || bad "install failed"
        else need "coverage tooling; re-run with --yes"; fi
    fi
fi

# ---------------------------------------------------------------------------
# 2. Testing convention: tier scripts + configs, scaffold with consent.
# ---------------------------------------------------------------------------
have_unit=$(has_script "test:unit"); have_int=$(has_script "test:integration"); have_fmt=$(has_script "format:check")
gaps=()
[ "$have_unit" = "1" ] || gaps+=("npm script test:unit")
[ "$have_int" = "1" ]  || gaps+=("npm script test:integration")
[ "$have_fmt" = "1" ]  || gaps+=("npm script format:check")
[ -f vitest.unit.config.ts ] || gaps+=("vitest.unit.config.ts")
[ -f vitest.integration.config.ts ] || gaps+=("vitest.integration.config.ts")
# .building/scripts/agent-tests.sh is the agent test path the build loop's judge calls
# (terse on pass, full on failure). It is workflow tooling, not part of the
# project proper, so the setup gate places it rather than the generator.
cmp -s .building/scripts/agent-tests.sh "$TEMPLATES_DIR/agent-tests.sh" || gaps+=(".building/scripts/agent-tests.sh (absent or stale)")
cmp -s .building/scripts/agent-hollow.sh "$TEMPLATES_DIR/agent-hollow.sh" || gaps+=(".building/scripts/agent-hollow.sh (absent or stale)")
if [ ${#gaps[@]} -gt 0 ]; then
    note "testing convention incomplete; missing: ${gaps[*]}"
    note "scaffold writes the two tier configs, the two npm scripts and the agent test runner (boilerplate)"
    if consent; then
        [ -f vitest.unit.config.ts ] || copy_template vitest.unit.config.ts vitest.unit.config.ts || bad "could not write vitest.unit.config.ts from template"
        [ -f vitest.integration.config.ts ] || copy_template vitest.integration.config.ts vitest.integration.config.ts || bad "could not write vitest.integration.config.ts from template"
        [ "$have_unit" = "1" ] || npm pkg set "scripts.test:unit=vitest run -c vitest.unit.config.ts" >/dev/null
        [ "$have_int" = "1" ]  || npm pkg set "scripts.test:integration=vitest run -c vitest.integration.config.ts" >/dev/null
        [ "$have_fmt" = "1" ]  || npm pkg set "scripts.format:check=prettier --check ." >/dev/null
        if ! cmp -s .building/scripts/agent-tests.sh "$TEMPLATES_DIR/agent-tests.sh"; then
            mkdir -p .building/scripts
            if copy_template agent-tests.sh .building/scripts/agent-tests.sh; then chmod +x .building/scripts/agent-tests.sh
            else bad "could not write .building/scripts/agent-tests.sh from template"; fi
        fi
        if ! cmp -s .building/scripts/agent-hollow.sh "$TEMPLATES_DIR/agent-hollow.sh"; then
            mkdir -p .building/scripts
            if copy_template agent-hollow.sh .building/scripts/agent-hollow.sh; then chmod +x .building/scripts/agent-hollow.sh
            else bad "could not write .building/scripts/agent-hollow.sh from template"; fi
        fi
        ok "scaffolded testing convention (configs + scripts + agent test runner)"
        have_unit=$(has_script "test:unit"); have_int=$(has_script "test:integration"); have_fmt=$(has_script "format:check")
    else
        need "testing convention; re-run with --yes to scaffold"
    fi
else
    ok "testing convention present (tier configs + scripts + agent test runner)"
fi

# CLAUDE.md convention sections are project judgement, report only (never scaffold endpoints)
if [ -f CLAUDE.md ]; then
    grep -qi "Integration endpoints" CLAUDE.md && ok "CLAUDE.md declares integration endpoints" || bad "CLAUDE.md missing an 'Integration endpoints' section; add your endpoint and its bring-up command"
else
    bad "no CLAUDE.md; add one declaring conventions and integration endpoints"
fi

# ---------------------------------------------------------------------------
# 3. Run each tier; non-zero selection + pass.
# ---------------------------------------------------------------------------
[ "$have_unit" = "1" ] && run_tier "test:unit" no
[ "$have_int" = "1" ]  && run_tier "test:integration" yes

# ---------------------------------------------------------------------------
# 3b. Prove the agent test path works. The judge runs tests through
# .building/scripts/agent-tests.sh, not the human npm scripts, so a project is only
# loop-ready if that path runs and reports a terse summary. Verify it against
# each tier the project declares: unit if declared, integration if declared. An
# integration-only project (no unit tier) must still have its agent path proven,
# because the judge will use it for integration.
# ---------------------------------------------------------------------------
if [ -f .building/scripts/agent-tests.sh ]; then
    # Mirror section 3: prove the agent path for each tier the project declares.
    # Skip integration if the run is already in a blocked state (fail=3): a block
    # means fix the environment and re-run, so the skipped check happens then.
    [ "$have_unit" = "1" ] && agent_check unit
    [ "$have_int" = "1" ] && [ "$fail" -ne 3 ] && agent_check integration
fi

# 3c. Prove the hollow-check runner (the judge's negative-run command) is present
# and runnable, on the same loop-ready footing as the test runner above.
[ -f .building/scripts/agent-hollow.sh ] && agent_hollow_check

# 3d. Prove the tree is formatter-clean. Only meaningful if the project has the
# format:check script (scaffolded above); skip silently if it somehow lacks it.
[ "$have_fmt" = "1" ] && format_check

# ---------------------------------------------------------------------------
# 4. Coverage runs.
# ---------------------------------------------------------------------------
[ -n "$vmaj" ] && { npx vitest run --coverage --reporter=dot >/dev/null 2>&1 && ok "coverage runs" || bad "coverage run failed; check the vitest config"; }

# ---------------------------------------------------------------------------
# 5. Git, remote, gh, identity, main on remote.
# ---------------------------------------------------------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then ok "git repository"
    git remote get-url origin >/dev/null 2>&1 && ok "origin remote" || bad "no origin remote; add a GitHub remote (your action)"
    gh auth status >/dev/null 2>&1 && ok "gh authenticated" || bad "gh not authenticated; run gh auth login"
    # commit identity must be on the allowlist, so the loop's commits attribute to the right account
    commit_email="$(git config user.email 2>/dev/null)"
    case " $IDENTITY_ALLOWLIST " in
        *" $commit_email "*) ok "commit identity ($commit_email)";;
        *) bad "commit email '$commit_email' not on the allowlist; set git config user.email to one of: $IDENTITY_ALLOWLIST";;
    esac
    if git show-ref --verify --quiet refs/heads/main; then ok "local main branch"
        if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then ok "main on remote"
        elif consent; then git push -u origin main >/dev/null 2>&1 && ok "pushed main" || bad "push failed"
        else need "main not on remote; re-run with --yes to push"; fi
    else bad "no local main branch; the build loop cuts each deliverable branch from main"; fi
else bad "not a git repository; init and add a GitHub remote"; fi

# ---------------------------------------------------------------------------
# 6. Loop output stays local: .building must be gitignored.
# ---------------------------------------------------------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
    if git check-ignore -q .building 2>/dev/null; then
        ok ".building is gitignored (loop output stays local)"
    else
        note ".building is not gitignored; loop output could be committed and travel to machines that never ran setup"
        if consent; then
            printf '\n.building/\n' >> .gitignore
            git check-ignore -q .building 2>/dev/null && ok "added .building to .gitignore" || bad "added to .gitignore but still not ignored; check .gitignore"
        else
            need ".building not gitignored; re-run with --yes to add it"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Verdict and receipt.
# ---------------------------------------------------------------------------
echo "========================"
mkdir -p .building
if [ "$fail" -eq 0 ]; then
    head=$(git rev-parse HEAD 2>/dev/null || echo unknown)
    printf '{ "ready": true, "head": "%s", "at": "%s" }\n' "$head" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .building/setup-ok
    echo "READY (receipt written to .building/setup-ok)"; exit 0
else
    rm -f .building/setup-ok   # stale receipt must not survive a non-ready result
    case "$fail" in
        2) echo "NOT READY: install/scaffold/push needed, re-run with --yes"; exit 2 ;;
        3) echo "BLOCKED: endpoint down, bring it up and re-run"; exit 3 ;;
        *) echo "NOT READY: fix the FAIL lines and re-run"; exit 1 ;;
    esac
fi
