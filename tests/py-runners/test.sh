#!/usr/bin/env bash
# Suite for the Python agent runners (file-templates/runners/python/): agent-tests.sh
# (pytest) and agent-typecheck.sh (pyright) must honour the stack-neutral exit-code
# contract (contracts/agent-runner.md) so the shared agent-hollow.sh drives them.
# Sourced and run by tests/run.sh.
#
# Structural checks always run. The live exit-code matrix scaffolds a real project,
# places the runners, uv-syncs and exercises every code path including an
# end-to-end hollow check through the SHARED runner; it runs only when uv and the
# Python generator are available and a sync succeeds, else it is reported skipped.

suite_begin "py-runners (pytest + pyright exit-code contract)"

PYDIR="$REPO_ROOT/file-templates/runners/python"

# --- the templates exist under the python runner dir -------------------------
expect_exit 0 "python agent-tests.sh template exists"     test -f "$PYDIR/agent-tests.sh"
expect_exit 0 "python agent-typecheck.sh template exists"  test -f "$PYDIR/agent-typecheck.sh"
# they drive the Python tooling, not vitest/tsc.
expect_match 0 'uv run pytest'   "agent-tests.sh drives uv run pytest"   cat "$PYDIR/agent-tests.sh"
expect_match 0 'uv run pyright'  "agent-typecheck.sh drives uv run pyright" cat "$PYDIR/agent-typecheck.sh"
# usage guards (the spine).
expect_exit 64 "agent-tests.sh no tier -> usage"       bash "$PYDIR/agent-tests.sh"
expect_exit 64 "agent-typecheck.sh bad arg -> usage"   bash "$PYDIR/agent-typecheck.sh" bogus

# --- live exit-code matrix (needs uv + network) ------------------------------
GEN="$REPO_ROOT/scripts/init-python-project.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proj="$work/runtest"

if command -v uv >/dev/null 2>&1 && [ -f "$GEN" ] \
   && bash "$GEN" runtest "$proj" >/dev/null 2>&1 \
   && ( cd "$proj" && uv sync >/dev/null 2>&1 ); then

    mkdir -p "$proj/.building/scripts"
    cp "$PYDIR/agent-tests.sh" "$PYDIR/agent-typecheck.sh" "$REPO_ROOT/file-templates/runners/agent-hollow.sh" "$proj/.building/scripts/"
    chmod +x "$proj/.building/scripts/"*.sh

    # rc <cmd...>: run in the project, echo the exit code.
    rc() { ( cd "$proj" && "$@" >/dev/null 2>&1 ); echo $?; }

    expect_exit 0 "live: unit tier passes -> 0"  test "$(rc .building/scripts/agent-tests.sh unit)" = 0
    expect_exit 0 "live: pyright clean -> 0"     test "$(rc .building/scripts/agent-typecheck.sh)" = 0

    # zero collected -> 2 (a test file with no test functions).
    mkdir -p "$proj/tests/empty"; echo '# no tests' > "$proj/tests/empty/test_none.py"
    expect_exit 0 "live: zero tests selected -> 2" test "$(rc .building/scripts/agent-tests.sh unit tests/empty/test_none.py)" = 2
    rm -rf "$proj/tests/empty"

    # test failure -> 1.
    cp "$proj/tests/unit/test_app.py" "$work/bak_test"
    sed -i 's/== "app starting"/== "WRONG"/' "$proj/tests/unit/test_app.py"
    expect_exit 0 "live: failing test -> 1" test "$(rc .building/scripts/agent-tests.sh unit)" = 1
    cp "$work/bak_test" "$proj/tests/unit/test_app.py"

    # type error -> 1.
    cp "$proj/src/runtest/app.py" "$work/bak_app"
    sed -i 's/return "app starting"/return 42/' "$proj/src/runtest/app.py"
    expect_exit 0 "live: type error -> 1" test "$(rc .building/scripts/agent-typecheck.sh)" = 1
    cp "$work/bak_app" "$proj/src/runtest/app.py"

    # import/collection error -> 3, NOT 1 (must not bounce to the builder).
    cp "$proj/src/runtest/app.py" "$work/bak_app2"
    echo 'import nonexistent_module_xyz' >> "$proj/src/runtest/app.py"
    expect_exit 0 "live: import error -> 3 (not a test failure)" test "$(rc .building/scripts/agent-tests.sh unit)" = 3
    cp "$work/bak_app2" "$proj/src/runtest/app.py"

    # END-TO-END: the SHARED hollow runner drives the Python runner by exit code.
    # A real test catching the fault -> ASSERTS (hollow exit 0).
    expect_exit 0 "live: shared hollow ASSERTS on a real test" \
        test "$(rc .building/scripts/agent-hollow.sh unit src/runtest/app.py tests/unit/test_app.py 'app starting' 'broken')" = 0

    # A non-asserting test -> HOLLOW (hollow exit 1).
    cat > "$proj/tests/unit/test_hollow.py" <<'PY'
from runtest.app import main
def test_calls_main() -> None:
    main()
PY
    expect_exit 0 "live: shared hollow HOLLOW on a non-asserting test" \
        test "$(rc .building/scripts/agent-hollow.sh unit src/runtest/app.py tests/unit/test_hollow.py 'app starting' 'broken')" = 1
    rm -f "$proj/tests/unit/test_hollow.py"
else
    printf '  %sSKIP%s live exit-code matrix (uv absent, generator missing, or no network to fetch packages)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

suite_summary
