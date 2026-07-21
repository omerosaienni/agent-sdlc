#!/usr/bin/env bash
# setup/go.sh - the Go per-stack setup module. Sourced by scripts/project-setup.sh
# when it detects a Go project (go.mod), never executed directly. It defines the
# stack-specific checks the orchestrator calls in order; the orchestrator owns the
# stack-neutral spine (git, identity, .building gitignore, the verdict accounting
# and the receipt).
#
# Sourced-component discipline (script-layout.md, Multi-file scripts): no shebang
# run, no `set -e` of its own, no argument parsing. It defines functions and reads
# the orchestrator's helpers (ok/bad/note/block/need/consent), its `mode`, and the
# constants it sets (TEMPLATES_DIR). The orchestrator calls go_setup last.
#
# Mirrors setup/python.sh for Go, with two simplifications that are real, not gaps:
#
#   1. Coverage needs no provider. `go test -cover` is part of the toolchain, so the
#      "install a coverage provider matching the runner" step the TypeScript and
#      Python modules perform has nothing to install here. It is still VERIFIED by
#      running, because the contract says verify by running, never trust an install.
#   2. This stack declares NO external endpoint. Its integration tier is in process
#      (a temp SQLite file plus httptest), so the BLOCKED-endpoint path is
#      unreachable and setup never waits on a service to come up.
#
# Tiers split by BUILD TAG, not directory: the unit tier is every untagged test, the
# integration tier is the files behind //go:build integration. So "is the
# integration tier declared" is a source grep, not a directory test.
#
# Provides:
#   go_setup   run every Go check in order, accumulating into `fail`.

# run_tier <tier> <label>: run a tier THROUGH THE PLACED RUNNER and classify by its
# exit code alone.
#
# The gate deliberately does not carry its own copy of go test's output
# classification. It used to, and the two drifted: a benchmark-only package made the
# gate say "selected tests and passed" while the runner returned 2 for the same
# module. The gate's whole job is proving the path the judge will use, so it proves
# it by walking it, and there is one classifier to keep correct instead of two.
run_tier() { local tier="$1" label="$2" out rc
    out=$(bash .building/scripts/agent-tests.sh "$tier" 2>&1); rc=$?
    case "$rc" in
        0) if printf '%s' "$out" | grep -qE "^$tier: "; then ok "$label selected tests and passed (through the agent runner)"
           else bad "$label passed but the agent runner emitted no terse summary; check .building/scripts/agent-tests.sh"; fi ;;
        1) bad "$label failed (see output)"; printf '%s\n' "$out" ;;
        2) bad "$label selected zero tests (hollow suite)" ;;
        3) block "$label could not run (environment); fix the toolchain or the module and re-run"; printf '%s\n' "$out" ;;
        *) bad "agent test runner returned an unexpected exit $rc for $label; the judge depends on this path" ;;
    esac; }

# agent_hollow_check: prove the hollow-check runner answers its usage contract.
agent_hollow_check() {
    local rc
    bash .building/scripts/agent-hollow.sh >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 64 ]; then ok "agent hollow-check runner present and runnable"
    else bad ".building/scripts/agent-hollow.sh usage check failed (exit $rc, expected 64); the judge's hollow check depends on it"; fi
}

# agent_typecheck_check: prove the type-check runner is present and runnable. A
# clean check (0) or reported errors (1) both prove it ran; only an environment
# block (3) or a usage/exec failure is a problem to surface here.
agent_typecheck_check() {
    local rc
    bash .building/scripts/agent-typecheck.sh >/dev/null 2>&1; rc=$?
    case "$rc" in
        0) ok "agent type-check runner works (clean)" ;;
        1) ok "agent type-check runner works (reported build or vet errors; the runner ran)" ;;
        3) block "agent type-check runner could not run (go absent or the module unresolved); fix tooling and re-run" ;;
        *) bad ".building/scripts/agent-typecheck.sh failed (exit $rc); the judge's type-check gate depends on it" ;;
    esac
}

# go_setup: run the whole Go check sequence, accumulating into `fail`.
go_setup() {
    # -----------------------------------------------------------------------
    # 1. Environment: the toolchain is present and the module resolves.
    # -----------------------------------------------------------------------
    if ! command -v go >/dev/null 2>&1; then
        bad "go not installed; install the Go toolchain before setup (https://go.dev/dl/)"
        return   # nothing else can be proven without the compiler
    fi
    ok "go present ($(go version 2>/dev/null))"

    if consent; then
        # tidy is the Go analogue of `uv sync`: it resolves every import to a module,
        # writes go.sum, and prunes what is no longer imported. It is idempotent.
        if go mod tidy >/dev/null 2>&1; then ok "go mod tidy resolved the module's dependencies"
        else bad "go mod tidy failed; check go.mod and network access to the module proxy"; fi
    else
        # --check must not mutate. verify only reads the module cache, so it proves
        # the dependencies are present and unmodified without writing go.sum.
        if go mod verify >/dev/null 2>&1; then ok "module dependencies verified (not tidied under --check)"
        else need "module dependencies not resolved; re-run without --check to go mod tidy"; fi
    fi

    # A module that does not compile cannot have anything else proven about it, and
    # the message would otherwise be buried in the tier output below. -o discards any
    # linked executable: the gate is idempotent and must leave nothing in the tree.
    # -o discards any linked executable so the gate leaves nothing in the tree, but
    # only when there IS something to link: with no main package `go build -o <dir>/`
    # fails outright, which would report a clean library as a build error.
    local build_dir build_ok
    build_dir="$(mktemp -d)"
    if go list -f '{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./... 2>/dev/null | grep -q .; then
        go build -o "$build_dir/" ./... >/dev/null 2>&1 && build_ok=1 || build_ok=0
    else
        go build ./... >/dev/null 2>&1 && build_ok=1 || build_ok=0
    fi
    rm -rf "$build_dir"
    if [ "$build_ok" = 1 ]; then ok "go build ./... compiles the module"
    else bad "go build ./... failed; fix the compile errors and re-run"; fi

    # -----------------------------------------------------------------------
    # 2. Coverage tooling: built into the toolchain, so there is nothing to
    #    install. Reported explicitly so its absence from the output is not read
    #    as a skipped check.
    # -----------------------------------------------------------------------
    ok "coverage tooling built in (go test -cover; no provider to install)"

    # -----------------------------------------------------------------------
    # 3. Testing convention: place the three runners.
    # -----------------------------------------------------------------------
    local gaps=()
    cmp -s .building/scripts/agent-tests.sh "$TEMPLATES_DIR/runners/go/agent-tests.sh" || gaps+=(".building/scripts/agent-tests.sh (absent or stale)")
    cmp -s .building/scripts/agent-typecheck.sh "$TEMPLATES_DIR/runners/go/agent-typecheck.sh" || gaps+=(".building/scripts/agent-typecheck.sh (absent or stale)")
    cmp -s .building/scripts/agent-hollow.sh "$TEMPLATES_DIR/runners/agent-hollow.sh" || gaps+=(".building/scripts/agent-hollow.sh (absent or stale)")
    if [ ${#gaps[@]} -gt 0 ]; then
        note "testing convention incomplete; missing: ${gaps[*]}"
        if consent; then
            mkdir -p .building/scripts
            if ! cmp -s .building/scripts/agent-tests.sh "$TEMPLATES_DIR/runners/go/agent-tests.sh"; then
                if copy_template runners/go/agent-tests.sh .building/scripts/agent-tests.sh; then chmod +x .building/scripts/agent-tests.sh
                else bad "could not write .building/scripts/agent-tests.sh from template"; fi
            fi
            if ! cmp -s .building/scripts/agent-typecheck.sh "$TEMPLATES_DIR/runners/go/agent-typecheck.sh"; then
                if copy_template runners/go/agent-typecheck.sh .building/scripts/agent-typecheck.sh; then chmod +x .building/scripts/agent-typecheck.sh
                else bad "could not write .building/scripts/agent-typecheck.sh from template"; fi
            fi
            if ! cmp -s .building/scripts/agent-hollow.sh "$TEMPLATES_DIR/runners/agent-hollow.sh"; then
                if copy_template runners/agent-hollow.sh .building/scripts/agent-hollow.sh; then chmod +x .building/scripts/agent-hollow.sh
                else bad "could not write .building/scripts/agent-hollow.sh from template"; fi
            fi
            ok "scaffolded testing convention (agent runners)"
        else
            need "testing convention; re-run without --check to scaffold"
        fi
    else
        ok "testing convention present (agent runners)"
    fi

    # CLAUDE.md must declare integration endpoints (project judgement, report only).
    # For this stack the honest answer is usually "none, the tier is in process";
    # the section must still be present so the judge knows it was considered.
    if [ -f CLAUDE.md ]; then
        grep -qi "Integration endpoints" CLAUDE.md && ok "CLAUDE.md declares integration endpoints" || bad "CLAUDE.md missing an 'Integration endpoints' section; declare your endpoints (or state there are none)"
    else
        bad "no CLAUDE.md; add one declaring conventions and integration endpoints"
    fi

    # -----------------------------------------------------------------------
    # 4. Run each tier for real, through the runner the judge will use: non-zero
    #    selection + pass. The integration tier is DECLARED by a build-tag line
    #    existing, not by a directory.
    # -----------------------------------------------------------------------
    # Both are driven through the placed runner, so running the tier and proving the
    # judge's surface are the same act rather than two classifiers that can disagree.
    if [ -f .building/scripts/agent-tests.sh ]; then
        run_tier unit "unit tier"
        if grep -rlq --include='*_test.go' '//go:build integration' . 2>/dev/null; then
            [ "$fail" -ne 3 ] && run_tier integration "integration tier"
        else
            note "no integration tier declared (no //go:build integration test files); nothing to run"
        fi
    elif consent; then
        bad ".building/scripts/agent-tests.sh is not present, so no tier can be proven"
    else
        # Under --check the runner is legitimately absent: placing it is the very
        # action --check is reporting as outstanding. A FAIL here would make the
        # read-only preview of an un-set-up project look broken rather than pending.
        need "the agent test runner is not placed yet, so no tier can be proven; re-run without --check"
    fi
    [ -f .building/scripts/agent-hollow.sh ] && agent_hollow_check
    [ -f .building/scripts/agent-typecheck.sh ] && agent_typecheck_check

    # -----------------------------------------------------------------------
    # 6. Coverage runs (verify by running, do not trust that it is built in).
    #
    #    Scoped to the packages that HOLD tests, not ./..., for two reasons. The
    #    coverage of a package with no test files is not information, it is a
    #    guaranteed zero. And covering ./... drags in `covdata`, the tool that
    #    merges profiles across packages, which Go 1.25 builds on demand into
    #    GOROOT/pkg/tool: when the toolchain was fetched as a module that
    #    directory is read-only, so the build cannot happen and the run dies with
    #    "no such tool covdata" even though every instrumented package passed.
    #    Measuring what can be measured is the stronger check, not the weaker one.
    # -----------------------------------------------------------------------
    local covered
    covered=$(go list -f '{{if or .TestGoFiles .XTestGoFiles}}{{.ImportPath}}{{end}}' ./... 2>/dev/null)
    if [ -z "$covered" ]; then
        bad "no package in the module holds a test file; coverage has nothing to measure"
    # shellcheck disable=SC2086 # covered is a deliberate whitespace-separated package list
    elif go test -cover $covered >/dev/null 2>&1; then
        ok "coverage runs (go test -cover over the packages holding tests)"
    else
        bad "coverage run failed (go test -cover); the unit tier must pass under -cover"
    fi
}
