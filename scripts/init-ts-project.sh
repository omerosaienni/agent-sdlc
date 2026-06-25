#!/usr/bin/env bash
# init-ts-project.sh - scaffold a TypeScript project, with optional Mongo, React and
# Express layers. The orchestrator: it parses args, validates, then assembles the shared
# files (package.json, tsconfig.json, Makefile, CLAUDE.md) from fragments each
# enabled layer contributes, and calls each layer to write its own exclusive files.
#
# The work is split into layers under generator/ (sourced, not run):
#   generator/lib.sh    shared helpers (output, colour, write_file, copy_template)
#   generator/base.sh   always: TS tooling, entry point + unit test, editor, configs
#   generator/mongo.sh  --mongo: db helper, docker infra, integration tier, seed
#   generator/react.sh  --react: src/client React+Vite, src/common, frontend tier
#   generator/express.sh --express: versioned Express server + supertest unit tests
#
# Any combination is valid. The base is always TypeScript under src/server; Mongo,
# React and Express are additive. Express replaces the base stub entry point with a
# long-running server, and with Mongo its shutdown closes the shared client.
#
# This is the GENERATOR half of project provisioning. After it runs, the project
# still needs: npm install, the setup gate (project-setup.sh), and (with Mongo)
# docker bring-up, to be ready for the build loop.
#
# Usage:
#   init-ts-project.sh <project-name> [target-dir] [--mongo] [--react] [--express] [--verbose] [--no-color] [--debug]
#
#   project-name : kebab-case, used for the npm package name (and, with --mongo, the
#                  Mongo database name).
#   target-dir   : where to create it (default: ./<project-name>)
#   --mongo      : add the MongoDB layer (db helper, docker infra, integration tier).
#   --react      : add the React + Vite client layer (src/client, frontend tier).
#   --express    : add a versioned Express HTTP server (src/server/app.ts + tests).
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
TEMPLATES_DIR="$SCRIPT_DIR/../file-templates"

# shellcheck source=generator/lib.sh
. "$GENERATOR_DIR/lib.sh"
# shellcheck source=generator/base.sh
. "$GENERATOR_DIR/base.sh"
# shellcheck source=generator/mongo.sh
. "$GENERATOR_DIR/mongo.sh"
# shellcheck source=generator/react.sh
. "$GENERATOR_DIR/react.sh"
# shellcheck source=generator/express.sh
. "$GENERATOR_DIR/express.sh"

usage() {
    echo "usage: init-ts-project.sh <project-name> [target-dir] [--mongo] [--react] [--express] [--verbose] [--no-color] [--debug]" >&2
    exit 2
}

# ============================================================================
# Parse arguments (flags, never environment variables)
# ============================================================================

NAME=""
DIR=""
WITH_MONGO=0
WITH_REACT=0
WITH_EXPRESS=0
while [ $# -gt 0 ]; do
    case "$1" in
        --mongo | --with-mongo) WITH_MONGO=1; shift ;;
        --react | --with-react) WITH_REACT=1; shift ;;
        --express | --with-express) WITH_EXPRESS=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        --no-color | --no-colour) USE_COLOR=never; shift ;;
        --debug) set -x; shift ;;
        -h | --help) usage ;;
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

# kebab-case: the name becomes the npm package name (and, with Mongo, the database
# name), both of which dislike spaces and uppercase. Fail early.
case "$NAME" in
    *[!a-z0-9-]*) echo "project-name must be kebab-case (lowercase, digits, hyphens): '$NAME'" >&2; exit 2 ;;
esac

DIR="${DIR:-./$NAME}"
if [ -e "$DIR" ]; then
    echo "target '$DIR' already exists; refusing to overwrite" >&2
    exit 1
fi

# The kebab-case name is already a valid Mongo database name (lowercase, digits,
# hyphens, well under the 63 byte limit), so it is used verbatim. Only meaningful
# with --mongo; harmless otherwise.
DB_NAME="$NAME"

# ============================================================================
# Scaffold
# ============================================================================

step "Scaffolding '$NAME' into '$DIR'$([ "$WITH_MONGO" = 1 ] && echo " (db: $DB_NAME)")"
mkdir -p "$DIR"/{src/server,scripts,docs,docs/modules,.github/workflows}
[ "$WITH_MONGO" = 1 ] && mkdir -p "$DIR/src/server/db"
# React adds the client tree (omero-react.md scopes to src/client/**) and a common
# tree for types crossing the client/server boundary.
[ "$WITH_REACT" = 1 ] && mkdir -p "$DIR"/{src/client,src/common}

# Base layer always runs; the optional layers write their exclusive files and set
# the fragment variables the shared-file assembly below reads.
base_layer
[ "$WITH_MONGO" = 1 ] && mongo_layer
[ "$WITH_REACT" = 1 ] && react_layer
# Express last: it replaces the base entry point and its test, and reads WITH_MONGO
# to decide whether shutdown closes the shared Mongo client.
[ "$WITH_EXPRESS" = 1 ] && express_layer

# ---------------------------------------------------------------------------
# Shared files: assembled from the base plus whatever fragments the enabled layers
# exported. Mongo fragments first, then React, so output is deterministic.
# ---------------------------------------------------------------------------
step "build surface (package.json, tsconfig, Makefile)"

# package.json
write_file "$DIR/package.json" <<EOF
{
  "name": "${NAME}",
  "version": "0.1.0",
  "description": "A TypeScript project",
  "type": "module",
  "private": true,
  "scripts": {
    "start": "tsx src/server/index.ts",
    "test:unit": "vitest run -c vitest.unit.config.ts",
    "lint": "eslint src",
    "typecheck": "tsc --noEmit",
    "format:check": "prettier --check ."${MONGO_SCRIPTS:-}${REACT_SCRIPTS:-}
  },
  "dependencies": {
    "tsx": "^4.22.4"${MONGO_DEPS:-}${REACT_DEPS:-}${EXPRESS_DEPS:-}
  },
  "devDependencies": {
    "@eslint/js": "^9.17.0",
    "@faker-js/faker": "^10.5.0",
    "@types/node": "^22.10.2",
    "@vitest/coverage-v8": "^4.1.9",
    "@vitest/ui": "^4.1.9",
    "eslint": "^9.17.0",
    "eslint-config-prettier": "^9.1.0",
    "prettier": "^3.4.2",
    "typescript": "^5.7.2",
    "typescript-eslint": "^8.18.1",
    "vitest": "^4.1.9"${REACT_DEV_DEPS:-}${EXPRESS_DEV_DEPS:-}
  }
}
EOF

# tsconfig include: assemble the list, then format it as prettier would, one line
# when it fits printWidth (100) and wrapped one per line when the React configs push
# it over, so the generated tsconfig is prettier-clean for every layer combination.
ts_inc=('"src"' '"vitest.unit.config.ts"' '"eslint.config.js"')
[ "$WITH_MONGO" = 1 ] && ts_inc+=('"vitest.integration.config.ts"')
[ "$WITH_REACT" = 1 ] && ts_inc+=('"vitest.client.config.ts"' '"vite.config.ts"')
inc_oneline=""
for e in "${ts_inc[@]}"; do inc_oneline="${inc_oneline:+$inc_oneline, }$e"; done
TSCONFIG_INCLUDE="  \"include\": [$inc_oneline]"
if [ "${#TSCONFIG_INCLUDE}" -gt 100 ]; then
    TSCONFIG_INCLUDE="  \"include\": ["
    for e in "${ts_inc[@]}"; do TSCONFIG_INCLUDE+=$'\n'"    $e,"; done
    TSCONFIG_INCLUDE="${TSCONFIG_INCLUDE%,}"$'\n'"  ]"
fi

# tsconfig.json
write_file "$DIR/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"${REACT_TS_LIB:-}],${REACT_TS_JSX:-}
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "types": ["node"]
  },
${TSCONFIG_INCLUDE}
}
EOF

# Makefile: base targets, then the help lines and target blocks each layer added.
# The base `test` runs the unit tier; with Mongo it also runs the integration tier.
TEST_PREREQS="test-unit"
[ "$WITH_MONGO" = 1 ] && TEST_PREREQS="test-unit test-integration"

write_file "$DIR/Makefile" <<EOF
# help is the default goal so a bare \`make\` documents the project
.DEFAULT_GOAL := help

.PHONY: help start test test-unit lint typecheck graph graph-viz

help: ## List available targets
	@echo "${NAME} - available targets:"
	@echo ""
	@echo "  help        Show this list"
	@echo "  start       Run the entry point (src/server/index.ts)"
${MONGO_MAKE_HELP:-}
	@echo "  test-unit   Run the unit tier (no external services)"
	@echo "  test        Run the backend tier(s)"
	@echo "  lint        Run eslint over src"
	@echo "  typecheck   Type-check without emitting (tsc --noEmit)"
	@echo "  graph       Rebuild the knowledge graph (code + docs) and HTML"
	@echo "  graph-viz   Regenerate graph.html and report from the existing graph"
${REACT_MAKE_HELP:-}

start: ## Run the entry point (src/server/index.ts)
	npm start

test-unit: ## Run the unit tier (no external services)
	npm run test:unit

# unit first so a logic break fails fast; integration (with Mongo) needs the server up
test: ${TEST_PREREQS} ## Run the backend tier(s)

lint: ## Run eslint over src
	npm run lint

typecheck: ## Type-check without emitting (tsc --noEmit)
	npm run typecheck

# Knowledge graph (graphify). Model/env pinned so the target is self-contained.
GRAPHIFY_ENV := OLLAMA_MODEL=graphify OLLAMA_API_KEY=x

graph: ## Rebuild the knowledge graph: code (AST) + docs (LLM) + HTML
	\$(GRAPHIFY_ENV) graphify . --backend ollama --token-budget 8000 --max-concurrency 1

graph-viz: ## Regenerate graph.html and the report from the existing graph
	\$(GRAPHIFY_ENV) graphify cluster-only . --backend ollama
${MONGO_MAKE_TARGETS:-}
${REACT_MAKE_TARGETS:-}
EOF

# ---------------------------------------------------------------------------
# CI workflow: one job per gate, assembled from layer fragments like the Makefile.
# Base contributes lint, format, typecheck and unit; --mongo appends the integration
# job, --react appends the client job. Runs on every PR into main, which is what the
# build loop opens per increment, so each increment is checked before you merge it.
# A single typecheck job covers the whole project (tsc spans all of src, client
# included). npm ci needs the committed package-lock.json: npm install writes it,
# commit it with the project.
# ---------------------------------------------------------------------------
step "CI workflow"

write_file "$DIR/.github/workflows/ci.yml" <<EOF
# Layer-aware CI from init-ts-project.sh: jobs scale with the layers added.
# Runs on every PR into main, which the build loop opens one of per increment.
# npm ci needs the committed package-lock.json (npm install writes it; commit it).
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run lint

  format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run format:check

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run typecheck

  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run test:unit${MONGO_CI_JOB:-}${REACT_CI_JOB:-}
EOF

# ---------------------------------------------------------------------------
# Docs: CLAUDE.md (project identity + runtime facts; conventions are in
# .claude/rules), README. The Mongo layer contributes the endpoints section.
# ---------------------------------------------------------------------------
step "docs"

write_file "$DIR/CLAUDE.md" <<EOF
# ${NAME}

TODO: one or two lines on what this project is and is not (its scope).

## Layout

- Backend source under src/server/. A frontend, if present, lives under src/client/.
  Entry point: src/server/index.ts, run via \`npm start\`.

## Conventions

- Stack conventions (TypeScript, and any others) are path-scoped rules under
  .claude/rules/, installed by install-project-rules.sh and read automatically.
  Universal conventions (prose, comments) come from the global rules. This file
  carries only what is specific to THIS project: its scope and runtime facts.${MONGO_CLAUDE_MD:-}
EOF

write_file "$DIR/README.md" <<EOF
# ${NAME}

A TypeScript project.

## Quick start

\`\`\`
npm install$([ "$WITH_MONGO" = 1 ] && printf '\nmake up            # start the shared Mongo and init the replica set')
$(if [ "$WITH_REACT" = 1 ]; then printf 'make test-all      # backend tier(s) then the frontend tier\nmake dev-client    # run the Vite dev server'; else printf 'make test          # run the backend tier(s)'; fi)$([ "$WITH_EXPRESS" = 1 ] && printf '\nnpm start          # run the Express server (GET /api/v1/health)')
\`\`\`
EOF

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
        # symbolic-ref sets it before the first commit, regardless of init.defaultBranch.
        git symbolic-ref HEAD refs/heads/main
    fi
    git add -A
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        git commit -q -m "Initial scaffold"
        note "initialised and committed initial scaffold"
    else
        note "repo already has history, left as is"
    fi
)

# ---------------------------------------------------------------------------
# Stack convention rules: delegate to the installer rather than inline them, so
# there is one source of truth for the conventions. The flags match the enabled
# layers. Runs after git init (the installer requires a .git). Non-fatal: a rules
# hiccup must not fail an otherwise good scaffold.
# ---------------------------------------------------------------------------
step "stack rules"
RULE_FLAGS="--typescript"
[ "$WITH_MONGO" = 1 ] && RULE_FLAGS="$RULE_FLAGS --mongo"
[ "$WITH_REACT" = 1 ] && RULE_FLAGS="$RULE_FLAGS --react"
rules_rc=0
# shellcheck disable=SC2086 # RULE_FLAGS is a deliberate list of flags, word-split on purpose
"$SCRIPT_DIR/install-project-rules.sh" "$DIR" $RULE_FLAGS || rules_rc=$?
if [ "$rules_rc" -ne 0 ]; then
    err "stack-rule install failed (exit $rules_rc); scaffold is fine, run install-project-rules.sh manually"
fi

# ---------------------------------------------------------------------------
# Nudge: the git guards are global via core.hooksPath, not seeded per project.
# ---------------------------------------------------------------------------
if [ -z "$(git config --global --get core.hooksPath || true)" ]; then
    echo
    echo "${C_NOTE}Note: global git hooks are not installed (core.hooksPath unset)."
    echo "Run scripts/setup-global-git-hooks.sh install to enable the identity and"
    echo "branch-name guards for every repo, including this one.${C_RESET}"
fi

printf '\n%sScaffolded %s%s\n' "$C_OK" "$NAME" "$C_RESET"
echo "Next:"
echo "  cd $DIR"
echo "  npm install"
[ "$WITH_MONGO" = 1 ] && echo "  make up                 # start the shared Mongo and init the replica set"
if [ "$WITH_REACT" = 1 ]; then
    echo "  make test-all           # backend tier(s) then the frontend tier"
    echo "  make dev-client         # run the Vite dev server"
else
    echo "  make test               # the backend tier(s)"
fi
[ "$WITH_EXPRESS" = 1 ] && echo "  npm start               # run the Express server (GET /api/v1/health)"
echo
echo "Then drive it through the pipeline. Two independent prerequisites, in either order:"
echo "  /omero-design-partner   converges your intent into feature sheet(s)"
echo "                          (.building/features/<feature-name>/increments.md)"
echo "  /omero-project-setup    proves the project environment ready (writes the receipt)"
echo "Then /omero-build-loop builds the sheet (it needs both the sheet and the receipt)."
