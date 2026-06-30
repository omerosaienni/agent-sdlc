---
name: omero-create-python-project
description: Scaffold a new Python project (a modern src-layout, uv-managed package with a strict pyright type-check gate and a pytest unit/integration tier split), suitable for a LangGraph app. Inits git on main and emits a CI workflow running the pyright and unit gates. Sits alongside omero-create-ts-project; the pipeline picks the stack from the project the generator produces.
disable-model-invocation: true
argument-hint: "<project-name> [target-dir]"
allowed-tools: Bash({{SDLC_REPO}}/scripts/init-python-project.sh:*), Bash(git:*), Read
---
Create a new Python project by running the generator:
    {{SDLC_REPO}}/scripts/init-python-project.sh $ARGUMENTS

Deterministic. Scaffolds a modern src-layout, uv-managed Python project:
- pyproject.toml declaring pytest and a strict pyright config (the type-check gate).
- src/<package>/ with a typed entry module (grow this into the LangGraph app).
- A pytest tier split: tests/unit/ (no external dependency) and tests/integration/ (needs a live endpoint).
- A CLAUDE.md skeleton with an Integration endpoints section, a Python .gitignore, and a CI workflow running the pyright and unit gates on PRs into main.

Inits git on main with an initial commit. It requires a configured global git identity (git config --global user.email ...) and fails before scaffolding if none is set; it never invents an author.

Pass the project name (kebab-case); the importable package is its underscore form (a-b -> a_b). Optionally pass a target directory.

On success the generator prints the created project and the next steps (uv sync, uv run pytest, uv run pyright). Report those next steps to the user as printed; do NOT re-list them inline here. On a non-zero exit, report the error line it printed (a name that is not kebab-case, a target that already exists, or no git identity configured) so the user can correct and re-run.

This is the create step, separate from the pipeline. After the project exists, the user runs /omero-design-feature and /omero-setup-project in either order (independent prerequisites: design writes the feature sheet(s), setup proves the project environment ready), then /omero-build-full builds the sheet. Do NOT run those here; this skill only creates the project.
