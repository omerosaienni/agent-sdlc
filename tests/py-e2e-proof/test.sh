#!/usr/bin/env bash
# Suite for the Python build path end to end (py-e2e-proof): prove the definition
# of done in one flow. Scaffold a Python project, run the setup gate to a READY
# receipt proved by real pytest and pyright, add a small typed application
# increment (a LangGraph-shaped node) with a unit test, then run the judge's own
# verification sequence on it through the placed runners: type-check first, then
# the unit tier, then the hollow negative run, all by exit code. Finally assert
# the stack-agnostic core contracts still name no stack, so the core stayed agnostic.
# Sourced and run by tests/run.sh.
#
# This is the executable form of the walkthrough in docs/python-build-path.md. It
# does not invoke /omero-build-full (agent-sdlc is not a loop target; the loop
# builds generated projects, not the meta-repo): it exercises the same real pieces
# the loop's setup gate and judge use, which is what the proof needs.

suite_begin "py-e2e-proof (Python build path end to end)" integration

GEN="$REPO_ROOT/scripts/init-python-project.sh"
SETUP="$REPO_ROOT/scripts/project-setup.sh"


# --- live end-to-end proof (needs uv + gh + git identity + network) ----------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proj="$work/graphapp"

if command -v uv >/dev/null 2>&1 && command -v gh >/dev/null 2>&1 \
   && [ -n "$(git config --global user.email 2>/dev/null)" ] \
   && bash "$GEN" graphapp "$proj" >/dev/null 2>&1 \
   && ( cd "$proj" && uv sync >/dev/null 2>&1 ); then

    ( cd "$proj" && git config sdlc.identityAllowlist "$(git config user.email)" )

    # 1. setup gate -> READY, proved by real pytest + pyright.
    if ( cd "$proj" && bash "$SETUP" >/dev/null 2>&1 ) && [ -f "$proj/.building/setup-ok" ]; then
        _t_ok "e2e: setup gate reaches READY (receipt written) on the Python project"
    else
        _t_bad "e2e: setup gate did not reach READY on the Python project"
    fi

    # 2. add a small typed application increment: a LangGraph-shaped node that takes
    #    a state dict and returns the next state. Typed so the strict pyright gate
    #    has something real to check; unit-tested so the tier selects it.
    mkdir -p "$proj/src/graphapp"
    cat > "$proj/src/graphapp/node.py" <<'PY'
"""A LangGraph-shaped node: takes the graph state and returns the next state.

Kept dependency-free so the unit tier is run-anywhere; a real app would import
langgraph and register this on a StateGraph.
"""


def greet_node(state: dict[str, str]) -> dict[str, str]:
    """Read the name from the state and write a greeting back into it."""
    name = state.get("name", "world")
    return {**state, "greeting": f"hello {name}"}
PY
    cat > "$proj/tests/unit/test_node.py" <<'PY'
from graphapp.node import greet_node


def test_greet_node_writes_greeting() -> None:
    assert greet_node({"name": "ada"})["greeting"] == "hello ada"


def test_greet_node_defaults_to_world() -> None:
    assert greet_node({})["greeting"] == "hello world"
PY

    # 3. the judge sequence on the increment, through the placed runners, by exit
    #    code: type-check FIRST, then the unit tier, then the hollow negative run.
    rc() { ( cd "$proj" && "$@" >/dev/null 2>&1 ); echo $?; }

    expect_exit 0 "e2e: judge type-check gate clean on the increment (pyright, exit 0)" \
        test "$(rc .building/scripts/agent-typecheck.sh)" = 0
    expect_exit 0 "e2e: judge unit tier passes on the increment (pytest, exit 0)" \
        test "$(rc .building/scripts/agent-tests.sh unit)" = 0
    # hollow negative run via the SHARED runner: a real test catches a real fault.
    expect_exit 0 "e2e: judge hollow check ASSERTS on the increment (real test catches the fault)" \
        test "$(rc .building/scripts/agent-hollow.sh unit src/graphapp/node.py tests/unit/test_node.py 'hello ' 'HELLO ')" = 0

    # 4. a deliberate type error is caught by the gate (the gate is real, not a no-op).
    cp "$proj/src/graphapp/node.py" "$work/node_bak"
    sed -i 's/return {\*\*state, "greeting": f"hello {name}"}/return 42/' "$proj/src/graphapp/node.py"
    expect_exit 0 "e2e: judge type-check gate catches a real type error (exit 1)" \
        test "$(rc .building/scripts/agent-typecheck.sh)" = 1
    cp "$work/node_bak" "$proj/src/graphapp/node.py"

else
    printf '  %sSKIP%s live end-to-end proof (uv/gh/git-identity/network absent)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

# (The Python path must not break the TS path, but a `test -f` only catches
# deletion, not breakage; real protection is the behavioural TS suites. The
# stack-agnostic invariant below IS meaningful, so it stays.)
# invariant: the stack-agnostic core contracts name no stack (the core stayed agnostic).
expect_exit 1 "design-partner contract names no stack"  grep -qiE 'python|typescript|pytest|vitest' "$REPO_ROOT/contracts/design-partner.md"
expect_exit 1 "increment schema names no stack"          grep -qiE 'python|typescript|pytest|vitest' "$REPO_ROOT/contracts/increment-sheet.schema.md"

suite_summary
