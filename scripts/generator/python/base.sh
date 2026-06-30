#!/usr/bin/env bash
# generator/python/base.sh - the Python base layer. Sourced by
# init-python-project.sh, never run. Writes the project files for a modern
# src-layout, uv-managed Python project with a strict pyright config and a pytest
# unit/integration tier split. Expects DIR, NAME, PKG and the lib helpers
# (step/note/write_file) in scope.
#
# Tier split: by directory (tests/unit, tests/integration), the project's choice of
# split mechanism (build-judge-loop.md leaves this to the project). The two tier
# commands are uv run pytest over each directory; the agent test runner the setup
# gate places drives the same split.

python_base_layer() {
    step "project manifest (pyproject.toml)"

    # pyproject.toml: uv-managed. Declares the package (src-layout via the hatchling
    # build backend pointing at src/), the runtime and dev dependencies (pytest,
    # pyright), the two pytest tier paths, and a STRICT pyright config inline (the
    # type-check gate is mandatory-and-strict, the settled posture). The unit and
    # integration tiers are split by directory under tests/.
    write_file "$DIR/pyproject.toml" <<EOF
[project]
name = "${NAME}"
version = "0.1.0"
description = "A Python project"
requires-python = ">=3.11"
dependencies = []

[dependency-groups]
# Dev tooling uv installs into the project venv on \`uv sync\`. pytest is the test
# runner both tiers use; pyright is the type-check gate (strict, configured below).
dev = ["pytest>=8", "pyright>=1.1.390"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
# src-layout: the importable package lives under src/, so tests run against the
# installed package, not the working tree (catches packaging mistakes).
packages = ["src/${PKG}"]

[tool.pytest.ini_options]
# Tiers split by directory. The human verbose paths are \`uv run pytest tests/unit\`
# and \`uv run pytest tests/integration\`; the agent runner drives the same split.
testpaths = ["tests/unit", "tests/integration"]

[tool.pyright]
# Mandatory and strict: this is the type-check gate, the analogue of tsc --noEmit.
# Nothing else type-checks, so strict here is what keeps a type error from reaching
# a green pass. Points at src so the package is the checked surface.
include = ["src", "tests"]
typeCheckingMode = "strict"
pythonVersion = "3.11"
EOF

    step "entry point"

    write_file "$DIR/src/$PKG/__init__.py" <<EOF
"""${NAME}: package marker."""
EOF

    # The entry module. Grow this into the real app (for a LangGraph app, build the
    # graph here and expose it). main() is importable for tests; the __main__ guard
    # runs it directly. Typed, so the strict pyright gate has something to check.
    write_file "$DIR/src/$PKG/app.py" <<EOF
"""The program entry point. Grow this into the real app.

For a LangGraph app this is where the graph is built and compiled; keep main()
importable so tests can exercise it without running the process.
"""


def main() -> str:
    """Return the startup message. Replace with the real bootstrap."""
    return "app starting"


if __name__ == "__main__":
    print(main())
EOF

    step "tests"

    # Unit tier: no external dependency, run-anywhere. One file per module, named
    # after the module under test, in the tier directory.
    write_file "$DIR/tests/unit/test_app.py" <<EOF
"""Unit tier (no external dependencies). Grows alongside the entry point."""

from ${PKG}.app import main


def test_main_returns_startup_message() -> None:
    assert main() == "app starting"
EOF

    # Integration tier: starts empty of real tests but must not be hollow. A single
    # skipped placeholder keeps the tier declared and selecting a (skipped) test
    # rather than zero; the first integration increment replaces it with real tests
    # against the declared endpoint.
    write_file "$DIR/tests/integration/test_smoke.py" <<EOF
"""Integration tier (needs a live endpoint). Replace this placeholder with real
integration tests against the endpoint declared in CLAUDE.md."""

import pytest


@pytest.mark.skip(reason="placeholder: add real integration tests for your endpoint")
def test_integration_placeholder() -> None:
    pass
EOF

    step "tooling configs"

    write_file "$DIR/.gitignore" <<'EOF'
# Python
__pycache__/
*.py[cod]
.pytest_cache/
.ruff_cache/
# uv-managed virtual environment and caches
.venv/
# build artefacts
dist/
build/
*.egg-info/
# loop output stays local
.building/
graphify-out/
.claude/
EOF

    step "docs"

    write_file "$DIR/CLAUDE.md" <<EOF
# ${NAME}

TODO: one or two lines on what this project is and is not (its scope).

## Layout

- Source under src/${PKG}/ (src-layout, uv-managed). Entry point: src/${PKG}/app.py,
  run via \`uv run python -m ${PKG}.app\`.
- Tests split by tier: tests/unit/ (no external dependency) and tests/integration/
  (needs a live endpoint). Run with \`uv run pytest tests/unit\` and
  \`uv run pytest tests/integration\`.

## Conventions

- Type-checking is mandatory and strict (pyright, configured in pyproject.toml).
  This is the build loop judge's gate.

## Integration endpoints

TODO: declare each integration endpoint this project needs, and for each:
- a readiness check (a command that succeeds only when the endpoint is up), and
- a bring-up command (how the human starts it).

The build loop's judge checks readiness before running the integration tier and
raises an environment block, not a failure, when an endpoint is down. Until this
project has a real integration endpoint, the integration tier holds only the
skipped placeholder.
EOF

    write_file "$DIR/README.md" <<EOF
# ${NAME}

A Python project (src-layout, uv-managed).

## Quick start

\`\`\`
uv sync
uv run pytest tests/unit
uv run pyright
\`\`\`
EOF

    # ---------------------------------------------------------------------------
    # CI workflow: the Python gates (type-check, unit tier) on every PR into main,
    # which the build loop opens one of per increment. Mirrors the TypeScript
    # generator's CI role. uv sets up Python and installs deps from the lockfile.
    # ---------------------------------------------------------------------------
    step "CI workflow"

    write_file "$DIR/.github/workflows/ci.yml" <<'EOF'
# Python CI from init-python-project.sh: the type-check and unit gates on every PR
# into main, which the build loop opens one of per increment.
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: uv sync
      - run: uv run pyright

  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: uv sync
      - run: uv run pytest tests/unit
EOF
}
