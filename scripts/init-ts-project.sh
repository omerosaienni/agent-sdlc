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
# config/ holds services.yaml when a service layer is present (express/mongo/react).
if [ "$WITH_MONGO" = 1 ] || [ "$WITH_REACT" = 1 ] || [ "$WITH_EXPRESS" = 1 ]; then
    mkdir -p "$DIR/config"
fi
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

# The start script loads .env (generated from config/services.yaml) when the Express
# server layer is present, so SERVER_HOST/SERVER_PORT reach the bootstrap; the base
# stub has no server, so it stays a plain run. --env-file-if-exists tolerates a
# missing .env (a fresh clone before `make config`), falling back to code defaults.
START_SCRIPT="tsx src/server/index.ts"
[ "$WITH_EXPRESS" = 1 ] && START_SCRIPT="tsx --env-file-if-exists=.env src/server/index.ts"

# package.json
write_file "$DIR/package.json" <<EOF
{
  "name": "${NAME}",
  "version": "0.1.0",
  "description": "A TypeScript project",
  "type": "module",
  "private": true,
  "scripts": {
    "server:start": "${START_SCRIPT}",
    "server:test:unit": "vitest run -c vitest.unit.config.ts"${MONGO_SERVER_SCRIPTS:-}${REACT_SCRIPTS:-}${MONGO_DB_SCRIPTS:-},
    "lint": "eslint src",
    "typecheck": "tsc --noEmit",
    "format": "prettier --write .",
    "format:check": "prettier --check ."
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
TEST_PREREQS="server-test-unit"
[ "$WITH_MONGO" = 1 ] && TEST_PREREQS="server-test-unit server-test-integration"

# config target: present whenever a service layer contributed a services.yaml block.
# Regenerates .env from the YAML so the server, client and docker read one config.
# Its own group in the help and target sections.
CONFIG_MAKE_HELP=""
CONFIG_MAKE_TARGET=""
if [ -n "${SERVER_YAML:-}${MONGO_YAML:-}${CLIENT_YAML:-}" ]; then
    CONFIG_MAKE_HELP='	@echo ""
	@echo " config"
	@echo "  config      Regenerate .env from config/services.yaml"'
    CONFIG_MAKE_TARGET='
# --- config --------------------------------------------------------------
.PHONY: config

config: ## Regenerate .env from config/services.yaml
	./scripts/config-env.sh'
fi

# Grouped by service (db, server, client), then cross-service tests, quality, graph
# and config. The db group and client group come from the Mongo and React layers; the
# server group, tests, quality, graph and the help skeleton are the base's. Names are
# <service>-<action> (bare service-action verbs only; no qualifiers), mirroring the
# package.json <service>:<action> scripts.
write_file "$DIR/Makefile" <<EOF
# help is the default goal so a bare \`make\` documents the project
.DEFAULT_GOAL := help

.PHONY: help
help: ## List available targets
	@echo "${NAME} - available targets:"
	@echo ""
	@echo "  help        Show this list"
${MONGO_DB_HELP:-}
	@echo ""
	@echo " server"
	@echo "  server-start             Start the entry point (src/server/index.ts)"
	@echo "  server-test-unit         Run the unit tier (no external services)"
${MONGO_SERVER_TEST_HELP:-}
${REACT_CLIENT_HELP:-}
	@echo ""
	@echo " tests"
	@echo "  test        Run the server tier(s)"
${REACT_TESTALL_HELP:-}
	@echo ""
	@echo " quality"
	@echo "  lint          Run eslint over src"
	@echo "  typecheck     Type-check without emitting (tsc --noEmit)"
	@echo "  format        Format the repo with prettier (writes changes)"
	@echo "  format-check  Check formatting without writing"
	@echo "  check         Run all quality gates (format-check, lint, typecheck, test)"
	@echo ""
	@echo " graph"
	@echo "  graph       Rebuild the knowledge graph (code + docs) and HTML"
	@echo "  graph-viz   Regenerate graph.html and report from the existing graph"
${CONFIG_MAKE_HELP:-}
${MONGO_DB_TARGETS:-}
# --- server --------------------------------------------------------------
.PHONY: server-start server-test-unit

server-start: ## Start the entry point (src/server/index.ts)
	npm run server:start

server-test-unit: ## Run the unit tier (no external services)
	npm run server:test:unit
${MONGO_SERVER_TEST_TARGET:-}
${REACT_CLIENT_TARGETS:-}
# --- tests (cross-service) -----------------------------------------------
.PHONY: test

# unit first so a logic break fails fast; integration (with Mongo) needs db up
test: ${TEST_PREREQS} ## Run the server tier(s)
${REACT_TESTALL_TARGET:-}
# --- quality -------------------------------------------------------------
.PHONY: lint typecheck format format-check check

lint: ## Run eslint over src
	npm run lint

typecheck: ## Type-check without emitting (tsc --noEmit)
	npm run typecheck

format: ## Format the repo with prettier (writes changes)
	npm run format

format-check: ## Check formatting without writing (CI-friendly)
	npm run format:check

# Aggregate gate for CI and pre-push: format-check (not format) so unformatted
# code fails rather than being silently rewritten. test pulls in the integration
# tier with Mongo, so check needs the db up (make db-start).
check: format-check lint typecheck test ## Run all quality gates

# --- graph ---------------------------------------------------------------
# Knowledge graph (graphify). Model/env pinned so the target is self-contained.
.PHONY: graph graph-viz
GRAPHIFY_ENV := OLLAMA_MODEL=graphify OLLAMA_API_KEY=x

graph: ## Rebuild the knowledge graph: code (AST) + docs (LLM) + HTML
	\$(GRAPHIFY_ENV) graphify . --backend ollama --token-budget 8000 --max-concurrency 1

graph-viz: ## Regenerate graph.html and the report from the existing graph
	\$(GRAPHIFY_ENV) graphify cluster-only . --backend ollama
${CONFIG_MAKE_TARGET:-}
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
      - run: npm run server:test:unit${MONGO_CI_JOB:-}${REACT_CI_JOB:-}
EOF

# ---------------------------------------------------------------------------
# Service config: ports and addresses in one YAML, assembled from the layer
# fragments (server, mongo, client). scripts/config-env.sh turns it into .env, which
# the server (--env-file-if-exists), the Vite client (loadEnv) and docker compose
# (\${MONGO_PORT}) all read. Written only when a service layer contributed a block.
# ---------------------------------------------------------------------------
SERVICES_YAML="${SERVER_YAML:-}${MONGO_YAML:-}${CLIENT_YAML:-}"
if [ -n "$SERVICES_YAML" ]; then
    step "service config (config/services.yaml)"

    # %$'\n' strips the fragments' trailing newline so the heredoc's own line break
    # leaves exactly one at end-of-file.
    write_file "$DIR/config/services.yaml" <<EOF
# Service ports and addresses for this project, in one place. Edit here, then run
# \`make config\` (or ./scripts/config-env.sh) to regenerate .env, which the server,
# the Vite client and docker compose read. Defaults match the code, so a fresh
# checkout runs without regenerating.
${SERVICES_YAML%$'\n'}
EOF

    write_file "$DIR/scripts/config-env.sh" <<'EOF'
#!/usr/bin/env bash
# Generate .env from config/services.yaml so the server, the Vite client and docker
# compose all read their ports and addresses from one place. Re-run after editing
# the YAML (or via `make config`). No YAML dependency: services.yaml is a fixed
# two-level shape (a `section:` line, then two-space `key: value` lines) that this
# awk reads deterministically, emitting SECTION_KEY=value pairs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/config/services.yaml"
OUT="$ROOT/.env"

if [ ! -f "$SRC" ]; then
    echo "config-env.sh: $SRC not found" >&2
    exit 1
fi

awk '
  # A top-level "section:" line (nothing after the colon) opens a section.
  /^[a-z][a-z0-9_]*:[[:space:]]*$/ { section = $1; sub(/:.*/, "", section); next }
  # An indented "key: value" line under the current section.
  /^[[:space:]]+[a-z]/ {
    if (section == "") next
    line = $0
    sub(/^[[:space:]]+/, "", line)                   # strip indent
    key = line; sub(/:.*/, "", key)                  # key before the colon
    val = line; sub(/^[^:]*:[[:space:]]*/, "", val)  # value after the colon
    sub(/[[:space:]]*#.*/, "", val)                  # strip a trailing comment
    sub(/[[:space:]]+$/, "", val)                    # strip trailing space
    if (key != "" && val != "") printf "%s_%s=%s\n", toupper(section), toupper(key), val
  }
' "$SRC" > "$OUT"

echo "config-env.sh: wrote $OUT from config/services.yaml"
EOF
    chmod +x "$DIR/scripts/config-env.sh"

    # Seed the initial .env so the freshly scaffolded project runs immediately. .env
    # is gitignored (derived); regenerate with `make config` after editing the YAML.
    ( cd "$DIR" && ./scripts/config-env.sh >/dev/null )

    # CLAUDE.md note (woven into the Layout section below). Backticks are escaped so
    # they land literally in the variable rather than running a command substitution.
    CONFIG_CLAUDE_MD="
- Service ports and addresses live in config/services.yaml; \`make config\`
  regenerates .env from it, read by the server, the Vite client and docker compose."
fi

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
  Entry point: src/server/index.ts, run via \`make server-start\`.${CONFIG_CLAUDE_MD:-}

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
npm install$([ -n "$SERVICES_YAML" ] && printf '\nmake config        # regenerate .env from config/services.yaml (edit ports there)')$([ "$WITH_MONGO" = 1 ] && printf '\nmake db-start      # start the shared Mongo and init the replica set')
$(if [ "$WITH_REACT" = 1 ]; then printf 'make test-all      # server tier(s) then the client tier\nmake client-start  # start the Vite client'; else printf 'make test          # run the server tier(s)'; fi)$([ "$WITH_EXPRESS" = 1 ] && printf '\nmake server-start  # start the Express server (GET /api/v1/health)')
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
[ -n "$SERVICES_YAML" ] && echo "  make config             # regenerate .env from config/services.yaml (ports live there)"
[ "$WITH_MONGO" = 1 ] && echo "  make db-start           # start the shared Mongo and init the replica set"
if [ "$WITH_REACT" = 1 ]; then
    echo "  make test-all           # server tier(s) then the client tier"
    echo "  make client-start       # start the Vite client"
else
    echo "  make test               # the server tier(s)"
fi
[ "$WITH_EXPRESS" = 1 ] && echo "  make server-start       # start the Express server (GET /api/v1/health)"
echo
echo "Then drive it through the pipeline. Two independent prerequisites, in either order:"
echo "  /omero-design-partner   converges your intent into feature sheet(s)"
echo "                          (.building/features/<feature-name>/increments.md)"
echo "  /omero-project-setup    proves the project environment ready (writes the receipt)"
echo "Then /omero-build-loop builds the sheet (it needs both the sheet and the receipt)."
