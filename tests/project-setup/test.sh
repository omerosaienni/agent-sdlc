#!/usr/bin/env bash
# Suite for the setup gate's stack seam: scripts/project-setup.sh is the
# stack-neutral orchestrator, scripts/setup/ts.sh holds the TypeScript checks.
# Sourced and run by tests/run.sh, which sets REPO_ROOT, the colour vars, and
# sources tests/lib.sh first.
#
# These cases prove the SEAM, not a full TypeScript setup (which needs a real
# project, an npm install and tooling the CI runner does not provision). They
# check: the orchestrator parses arguments and detects the stack; the per-stack
# module exists and follows the sourced-component discipline; and the TypeScript
# check bodies no longer live inline in the orchestrator. A full scaffold-to-READY
# run is proven by py-e2e-proof and by running the gate against a real project.

suite_begin "project-setup.sh (stack seam)" integration

G="$REPO_ROOT/scripts/project-setup.sh"
TS="$REPO_ROOT/scripts/setup/ts.sh"

# --- spine intact: argument handling unchanged by the refactor ---------------
expect_exit 0  "--help prints and exits clean"        bash "$G" --help
expect_exit 64 "unknown argument -> usage error"      bash "$G" --bogus

# --- the per-stack module is sourced-discipline clean (the grep checks below
#     also prove it exists) --------------------------------------------------
# ts.sh must not run its own set -e, parse arguments, or be executed standalone:
# it is sourced into the orchestrator's scope (script-layout.md, Multi-file).
expect_exit 1 "ts.sh declares no own 'set -e/-euo'" \
    grep -qE '^set -e|^set -euo' "$TS"
expect_exit 1 "ts.sh parses no arguments (no \$@ loop)" \
    grep -qE 'for [a-z]+ in "\$@"|while \[ "\$#"' "$TS"

# ts.sh must define the entry function the orchestrator calls.
expect_exit 0 "ts.sh defines ts_setup" grep -qE '^ts_setup\(\)' "$TS"

# --- the orchestrator no longer carries TypeScript check bodies --------------
# The seam's point: package.json/vitest/npm/prettier logic lives in ts.sh, not
# the orchestrator. The orchestrator may NAME the stack in a comment or detection
# line, but must not run vitest/prettier or read package.json scripts inline.
expect_exit 1 "orchestrator runs no 'npx vitest'"   grep -qE 'npx vitest'  "$G"
expect_exit 1 "orchestrator runs no 'npx prettier'" grep -qE 'npx prettier' "$G"
expect_exit 1 "orchestrator runs no 'npm run'"      grep -qE 'npm run '     "$G"
expect_exit 1 "orchestrator defines no has_script"  grep -qE '^has_script\(\)' "$G"
expect_exit 1 "orchestrator defines no run_tier"    grep -qE '^run_tier\(\)'   "$G"

# --- the orchestrator owns detection and the verdict spine -------------------
expect_exit 0 "orchestrator defines detect_stack"   grep -qE '^detect_stack\(\)' "$G"
expect_exit 0 "orchestrator sources the stack module" grep -qE '\$SETUP_DIR/ts.sh' "$G"
expect_exit 0 "orchestrator still owns the receipt"  grep -qE 'setup-ok' "$G"

# --- the Python per-stack module (py-setup-module) ---------------------------
PY="$REPO_ROOT/scripts/setup/python.sh"
# sourced-component discipline, same as ts.sh (the grep checks also prove it exists).
expect_exit 1 "python.sh declares no own 'set -e/-euo'" grep -qE '^set -e|^set -euo' "$PY"
expect_exit 1 "python.sh parses no arguments"           grep -qE 'for [a-z]+ in "\$@"|while \[ "\$#"' "$PY"
expect_exit 0 "python.sh defines python_setup"          grep -qE '^python_setup\(\)' "$PY"
# python.sh drives Python tooling, not TypeScript.
expect_exit 1 "python.sh references no vitest"  grep -qE 'vitest' "$PY"
expect_exit 1 "python.sh references no npm"     grep -qE 'npm ' "$PY"
expect_exit 0 "python.sh drives uv"             grep -qE 'uv (sync|run|add|lock)' "$PY"
# the orchestrator dispatches python and rejects an ambiguous double-marker.
expect_exit 0 "orchestrator sources python module"  grep -qE '\$SETUP_DIR/python.sh' "$G"
expect_exit 0 "orchestrator detects pyproject.toml" grep -qE 'pyproject.toml' "$G"
expect_exit 0 "orchestrator handles ambiguous stack" grep -qE 'ambiguous' "$G"

# --- the Go per-stack module (go-build-path) ---------------------------------
GO="$REPO_ROOT/scripts/setup/go.sh"
# sourced-component discipline, same as ts.sh and python.sh (the grep checks also
# prove it exists).
expect_exit 1 "go.sh declares no own 'set -e/-euo'" grep -qE '^set -e|^set -euo' "$GO"
expect_exit 1 "go.sh parses no arguments"           grep -qE 'for [a-z]+ in "\$@"|while \[ "\$#"' "$GO"
expect_exit 0 "go.sh defines go_setup"              grep -qE '^go_setup\(\)' "$GO"
# go.sh drives the Go toolchain, not the other stacks'.
expect_exit 1 "go.sh references no pytest"  grep -qE 'pytest' "$GO"
expect_exit 1 "go.sh references no vitest"  grep -qE 'vitest' "$GO"
expect_exit 0 "go.sh drives go mod/build/test" grep -qE 'go (mod|build|test) ' "$GO"
# The two Go-specific simplifications must be REPORTED, not silently skipped: a
# check that vanishes without a line is indistinguishable from one that was missed.
expect_exit 0 "go.sh reports coverage as built in (no provider to install)" \
    grep -qE 'coverage tooling built in' "$GO"
# Coverage is measured over the packages that HOLD tests, derived with go list, not
# over ./... . Covering ./... needs `covdata` to merge the profile of every package
# without tests, and Go 1.25 builds that tool on demand into GOROOT/pkg/tool, which
# is read-only when the toolchain came from the module cache. The result is a
# coverage run that dies on a missing tool while every instrumented package passed.
expect_exit 0 "go.sh derives the covered package list from go list" \
    grep -qE 'go list -f .*TestGoFiles' "$GO"
expect_exit 1 "go.sh does not run coverage over ./... (would require covdata)" \
    grep -qE 'go test -cover \./\.\.\.' "$GO"
# The orchestrator registers the marker and dispatches the module.
expect_exit 0 "orchestrator sources the go module" grep -qE '\$SETUP_DIR/go.sh' "$G"
expect_exit 0 "orchestrator registers the go.mod marker" grep -qE 'go\.mod:go' "$G"

# --- three markers: detection generalised from a pair to a registry ----------
# The old spine hard-coded "both present" as the ambiguous case. With three markers
# that must become "more than one present", proved by execution rather than by
# reading the source: each marker alone detects, any two together are ambiguous.
mwork="$(mktemp -d)"
# gate_out <dir>: run the gate read-only in <dir> and echo what it printed. --check
# so nothing is installed or pushed; detection happens before any of that anyway.
# The output is CAPTURED rather than piped into grep, because the run sets pipefail
# and the gate exits non-zero on any NOT READY verdict: piping would hand the whole
# pipeline the gate's exit code and every match would read as a miss.
gate_out() { ( cd "$1" && bash "$G" --check 2>&1 ); }

# gate_says <dir> <regex> <want: yes|no> <case-name>: assert the gate's output does
# or does not contain <regex>.
gate_says() {
    local dir="$1" regex="$2" want="$3" name="$4" out hit=no
    out="$(gate_out "$dir")"
    printf '%s' "$out" | grep -Eq "$regex" && hit=yes
    if [ "$hit" = "$want" ]; then
        _t_ok "$name"
    else
        _t_bad "$name: wanted match=$want for /$regex/, got match=$hit"
        printf '       %s\n' "$out"
    fi
}

for m in package.json pyproject.toml go.mod; do
    mkdir -p "$mwork/only-$m" && : > "$mwork/only-$m/$m"
    gate_says "$mwork/only-$m" 'more than one stack marker' no \
        "single marker $m is not reported ambiguous"
done

# Any two markers together is the hard fail, whichever two: the old spine only knew
# about package.json plus pyproject.toml, so the go.mod pairings are the new cases.
for pair in "go.mod package.json" "go.mod pyproject.toml" "package.json pyproject.toml"; do
    d="$mwork/two-$(echo "$pair" | tr ' .' '__')"
    mkdir -p "$d"
    # shellcheck disable=SC2086 # pair is a deliberate two-word list
    for m in $pair; do : > "$d/$m"; done
    gate_says "$d" 'more than one stack marker' yes "two markers ($pair) -> ambiguous hard fail"
done

mkdir -p "$mwork/none"
gate_says "$mwork/none" 'could not detect a supported stack' yes \
    "no marker present -> hard fail naming the registered markers"
rm -rf "$mwork"

# --- live READY proof: scaffold a Go project, run the gate to READY ----------
# The base Go scaffold pulls no third-party module, so this needs only the
# toolchain, gh and a git identity: no network.
GOGEN="$REPO_ROOT/scripts/init-go-project.sh"
gowork="$(mktemp -d)"
goproj="$gowork/gosetup"
# Gated on absent tooling ALONE: a generator regression must fail this suite, not
# skip the live READY proof and leave the run green.
if ! command -v go >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1 \
   || [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    printf '  %sSKIP%s live Go READY proof (go/gh/git-identity absent)\n' "${C_NOTE:-}" "${C_RESET:-}"
elif ! bash "$GOGEN" gosetup "$goproj" >/dev/null 2>&1; then
    _t_bad "the generator failed to scaffold the setup fixture; the live Go READY proof could not run"
else
    ( cd "$goproj" && git config sdlc.identityAllowlist "$(git config user.email)" )
    if ( cd "$goproj" && bash "$G" >/dev/null 2>&1 ); then
        _t_ok "live: setup gate reaches READY on a scaffolded Go project"
    else
        _t_bad "live: setup gate did NOT reach READY on a scaffolded Go project"
    fi
    expect_exit 0 "live: Go receipt written" test -f "$goproj/.building/setup-ok"
    # The gate owns runner placement: all three must be down and executable, or the
    # judge has nothing to run.
    expect_exit 0 "live: gate placed the Go test runner"      test -x "$goproj/.building/scripts/agent-tests.sh"
    expect_exit 0 "live: gate placed the Go type-check runner" test -x "$goproj/.building/scripts/agent-typecheck.sh"
    expect_exit 0 "live: gate placed the shared hollow runner" test -x "$goproj/.building/scripts/agent-hollow.sh"
    if ( cd "$goproj" && bash "$G" >/dev/null 2>&1 ); then
        _t_ok "live: setup gate idempotent on the Go project (second run still READY)"
    else
        _t_bad "live: setup gate not idempotent on the Go project"
    fi
    # --check on an un-set-up project must report ACTION NEEDED (2), never FAILED.
    # The runners being absent is precisely what --check exists to report.
    fresh="$gowork/freshcheck"
    if bash "$GOGEN" freshcheck "$fresh" >/dev/null 2>&1; then
        ( cd "$fresh" && git config sdlc.identityAllowlist "$(git config user.email)" )
        ( cd "$fresh" && bash "$G" --check >/dev/null 2>&1 )
        expect_exit 0 "live: --check on an un-set-up Go project reports action needed, not failure" \
            test "$( ( cd "$fresh" && bash "$G" --check >/dev/null 2>&1 ); echo $? )" = 2
    fi
fi
rm -rf "$gowork"

# --- live READY proof: scaffold a Python project, run the gate to READY ------
# Needs uv + network (uv sync) + git identity. Reported skipped otherwise.
GEN="$REPO_ROOT/scripts/init-python-project.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proj="$work/setuptest"
if command -v uv >/dev/null 2>&1 && command -v gh >/dev/null 2>&1 \
   && [ -n "$(git config --global user.email 2>/dev/null)" ] \
   && bash "$GEN" setuptest "$proj" >/dev/null 2>&1 \
   && ( cd "$proj" && uv sync >/dev/null 2>&1 ); then
    # the gate requires the identity allowlist; set it for this scratch repo.
    ( cd "$proj" && git config sdlc.identityAllowlist "$(git config user.email)" )
    if ( cd "$proj" && bash "$G" >/dev/null 2>&1 ); then
        _t_ok "live: setup gate reaches READY on a scaffolded Python project"
    else
        _t_bad "live: setup gate did NOT reach READY on a scaffolded Python project"
    fi
    expect_exit 0 "live: receipt written" test -f "$proj/.building/setup-ok"
    # idempotency: a second run is still READY.
    if ( cd "$proj" && bash "$G" >/dev/null 2>&1 ); then
        _t_ok "live: setup gate idempotent (second run still READY)"
    else
        _t_bad "live: setup gate not idempotent on Python project"
    fi
else
    printf '  %sSKIP%s live Python READY proof (uv/gh/git-identity/network absent)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

suite_summary
