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

suite_begin "project-setup.sh (stack seam)"

G="$REPO_ROOT/scripts/project-setup.sh"
TS="$REPO_ROOT/scripts/setup/ts.sh"

# --- spine intact: argument handling unchanged by the refactor ---------------
expect_exit 0  "--help prints and exits clean"        bash "$G" --help
expect_exit 64 "unknown argument -> usage error"      bash "$G" --bogus

# --- the per-stack module exists and is sourced-discipline clean -------------
expect_exit 0 "scripts/setup/ts.sh exists" test -f "$TS"

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
expect_exit 0 "scripts/setup/python.sh exists" test -f "$PY"
# sourced-component discipline, same as ts.sh.
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
