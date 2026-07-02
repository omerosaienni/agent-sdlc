#!/usr/bin/env bash
# init-python-project.sh - scaffold a modern src-layout Python project, uv-managed,
# with a strict pyright config and a pytest unit/integration tier split. The
# orchestrator: it parses args, validates, then calls the base layer to write the
# project files. It sits ALONGSIDE init-ts-project.sh (the TypeScript generator),
# never replacing it; the pipeline picks a stack by which generator created the
# project (the setup gate then detects it from pyproject.toml).
#
# Construction mirrors init-ts-project.sh: an orchestrator that sources shared
# helpers (generator/lib.sh) and a layer under generator/python/ (sourced, not run).
# Python-specific knowledge lives in the layer, exactly where stack lives.
#
# Decisions baked in (settled for the python-build-path feature): uv for the
# environment, src-layout, pyright (strict) for the type-check gate.
#
# This is the GENERATOR half of project provisioning. After it runs, the project
# still needs: uv sync (or the setup gate, which proves it), to be build-ready.
#
# Usage:
#   init-python-project.sh <project-name> [target-dir] [--verbose] [--no-color] [--debug]
#
#   project-name : kebab-case, used for the project name; the importable package is
#                  its underscore form (a-b -> a_b), since Python packages cannot
#                  contain hyphens.
#   target-dir   : where to create it (default: ./<project-name>)
#   --verbose    : print each file as it is written (default prints one line per area).
#   --no-color   : force plain output (colour is auto-detected, on only at a terminal).
#   --debug      : trace every shell command (set -x).
set -euo pipefail

# ============================================================================
# Helpers and layers
# ============================================================================

VERBOSE=0
USE_COLOR=auto   # auto | always | never (set by --no-color or detection in lib.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR_DIR="$SCRIPT_DIR/generator"

# Reuse the generator's shared helpers (output, colour, write_file, copy_template):
# one definition of each helper across every generator, the script-layout rule.
# shellcheck source=generator/lib.sh
. "$GENERATOR_DIR/lib.sh"
# shellcheck source=generator/python/base.sh
. "$GENERATOR_DIR/python/base.sh"

usage() {
    echo "usage: init-python-project.sh <project-name> [target-dir] [--verbose] [--no-color] [--debug]" >&2
    exit 2
}

# ============================================================================
# Parse arguments (flags, never environment variables)
# ============================================================================

NAME=""
DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --verbose) VERBOSE=1; shift ;;
        --no-color | --no-colour) USE_COLOR=never; shift ;;
        --debug) set -x; shift ;;
        -h | --help) awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *)
            if [ -z "$NAME" ]; then NAME="$1"
            elif [ -z "$DIR" ]; then DIR="$1"
            else echo "unexpected argument: $1" >&2; usage
            fi
            shift ;;
    esac
done

setup_color

# ============================================================================
# Resolve and validate all inputs before writing anything
# ============================================================================

[ -z "$NAME" ] && usage

# kebab-case: the project name. Fail early, same rule as the TypeScript generator.
case "$NAME" in
    *[!a-z0-9-]*) echo "project-name must be kebab-case (lowercase, digits, hyphens): '$NAME'" >&2; exit 2 ;;
esac

DIR="${DIR:-./$NAME}"
if [ -e "$DIR" ]; then
    echo "target '$DIR' already exists; refusing to overwrite" >&2
    exit 1
fi

# A git identity is a precondition: the scaffold makes an initial commit in the NEW
# repo, and the generator never invents an author. The new repo inherits only the
# global (and system) identity, not this directory's repo-local one, so check the
# global identity, the one the scaffold's commit will actually use. Fail here,
# before writing anything, rather than half-scaffolding then dying at commit time.
# CI must configure a global identity before running the generator, same as a human.
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    echo "no global git identity configured (git config --global user.email is empty)." >&2
    echo "Set one before scaffolding: git config --global user.email '<you@example.com>'" >&2
    exit 1
fi

# The importable package name: hyphens are illegal in Python identifiers, so map
# them to underscores (a-b -> a_b). src/<package>/ uses this.
PKG="${NAME//-/_}"

# ============================================================================
# Scaffold
# ============================================================================

step "Scaffolding '$NAME' into '$DIR' (package: $PKG)"
mkdir -p "$DIR"/{src/"$PKG",tests/unit,tests/integration,.github/workflows}

# The base layer writes every project file (pyproject, configs, entry module, tests,
# CLAUDE.md, README, CI). Expects DIR, NAME, PKG and the lib helpers in scope.
python_base_layer

# ---------------------------------------------------------------------------
# Git: init the repo and make the first commit. Idempotent: git init on an existing
# repo is a no-op, and the commit is skipped if history already exists.
# ---------------------------------------------------------------------------
step "git repository"
(
    cd "$DIR"
    if [ ! -d .git ]; then
        git init -q
        # default the unborn branch to main, the branch the pipeline builds into.
        git symbolic-ref HEAD refs/heads/main
    fi
    git add -A
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        # The scaffold's initial commit, authored by the configured git identity
        # (proven non-empty in validation above). The generator never invents an
        # author: a missing identity is a setup error caught before any file is
        # written, not papered over here.
        git commit -q -m "Initial scaffold"
        note "initialised and committed initial scaffold"
    else
        note "repo already has history, left as is"
    fi
)

printf '\n%sScaffolded %s%s\n' "$C_OK" "$NAME" "$C_RESET"
# Bare commands, one per line, so the block is safe to copy-paste.
echo "Next:"
echo "  cd $DIR"
echo "  uv sync          # create the venv and install deps (pytest, pyright)"
echo "  uv run pytest    # run the unit tier"
echo "  uv run pyright   # type-check (strict)"
echo
echo "Then drive it through the pipeline. Two independent prerequisites, in either order:"
echo "  /omero-design-sheet     converges your intent into a feature sheet"
echo "  /omero-review-sheet     reviews the sheet for design soundness before build"
echo "  /omero-setup-project    proves the project environment ready"
echo "Then /omero-build-full builds the sheet (needs both the sheet and the receipt)."
