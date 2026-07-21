#!/usr/bin/env bash
# init-go-project.sh - scaffold a single-binary Go project, with optional SQLite,
# React and HTTP layers. The orchestrator: it parses args, validates, then assembles
# the shared files (Makefile, CLAUDE.md, README, CI, services.yaml) from fragments
# each enabled layer contributes, and calls each layer to write its own exclusive
# files.
#
# It sits ALONGSIDE init-ts-project.sh and init-python-project.sh, never replacing
# them; the pipeline picks a stack by which generator created the project (the setup
# gate then detects it from go.mod).
#
# The work is split into layers under generator/go/ (sourced, not run):
#   generator/lib.sh       shared helpers (output, colour, write_file)
#   generator/go/base.sh   always: module, cmd/<app> + internal/, embedded assets
#   generator/go/sqlite.sh --sqlite: modernc.org/sqlite store, migration, seed, tiers
#   generator/go/react.sh  --react: Vite client under client/, embedded into the binary
#   generator/go/http.sh   --http: net/http server + httptest tests, replaces main
#
# Any combination is valid. The base is always a Go module with a single binary;
# SQLite, React and HTTP are additive. HTTP replaces the base entry point with a
# long-running server.
#
# Decisions baked in (see docs/go-build-path.md): pure-Go dependencies only (never
# CGo, so cross-compilation stays clean), tiers split by BUILD TAG rather than
# directory, and one embed point (internal/assets/static) for everything served.
#
# This is the GENERATOR half of project provisioning. After it runs, the project
# still needs `go mod tidy` (or the setup gate, which proves it) to be build-ready.
#
# Usage:
#   init-go-project.sh <project-name> [target-dir] [--sqlite] [--react] [--http] [--verbose] [--no-color] [--debug]
#
#   project-name : kebab-case; used as the module path and the binary name.
#   target-dir   : where to create it (default: ./<project-name>)
#   --sqlite     : add the SQLite store layer (pure-Go driver, migration, seed).
#   --react      : add the React + Vite client layer, embedded into the binary.
#   --http       : add a net/http server (serves the embedded client and the API).
#   --verbose    : print each file as it is written (default prints one line per area).
#   --no-color   : force plain output (colour is auto-detected, on only at a terminal).
#   --debug      : trace every shell command (set -x).
set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

# The language version written into go.mod. Names what the generated code targets
# (range-over-int and net/http method patterns are 1.22, http.FileServerFS is 1.22),
# not the toolchain that must build it: a newer toolchain builds it unchanged.
GO_VERSION="1.23"

# ============================================================================
# Helpers and layers
# ============================================================================

VERBOSE=0
USE_COLOR=auto   # auto | always | never (set by --no-color or detection in lib.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR_DIR="$SCRIPT_DIR/generator"

# Reuse the generator's shared helpers (output, colour, write_file): one definition
# of each helper across every generator, the script-layout rule.
# shellcheck source=generator/lib.sh
. "$GENERATOR_DIR/lib.sh"
# shellcheck source=generator/go/base.sh
. "$GENERATOR_DIR/go/base.sh"
# shellcheck source=generator/go/sqlite.sh
. "$GENERATOR_DIR/go/sqlite.sh"
# shellcheck source=generator/go/react.sh
. "$GENERATOR_DIR/go/react.sh"
# shellcheck source=generator/go/http.sh
. "$GENERATOR_DIR/go/http.sh"

usage() {
    echo "usage: init-go-project.sh <project-name> [target-dir] [--sqlite] [--react] [--http] [--verbose] [--no-color] [--debug]" >&2
    exit 2
}

# ============================================================================
# Parse arguments (flags, never environment variables)
# ============================================================================

NAME=""
DIR=""
WITH_SQLITE=0
WITH_REACT=0
WITH_HTTP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --sqlite | --with-sqlite) WITH_SQLITE=1; shift ;;
        --react | --with-react)   WITH_REACT=1; shift ;;
        --http | --with-http)     WITH_HTTP=1; shift ;;
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

# kebab-case: the name becomes the module path and the binary name. Fail early,
# same rule as the TypeScript and Python generators.
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
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    echo "no global git identity configured (git config --global user.email is empty)." >&2
    echo "Set one before scaffolding: git config --global user.email '<you@example.com>'" >&2
    exit 1
fi

# The binary name. Kebab-case is legal in a directory and a binary name, so the
# project name is used verbatim; unlike Python, Go has no identifier to sanitise.
APP="$NAME"

# ============================================================================
# Scaffold
# ============================================================================

layers=""
[ "$WITH_SQLITE" = 1 ] && layers="$layers sqlite"
[ "$WITH_REACT" = 1 ] && layers="$layers react"
[ "$WITH_HTTP" = 1 ] && layers="$layers http"
step "Scaffolding '$NAME' into '$DIR'${layers:+ (layers:$layers)}"

mkdir -p "$DIR"/{cmd/"$APP",internal/app,internal/assets/static,.github/workflows}
[ "$WITH_SQLITE" = 1 ] && mkdir -p "$DIR/internal/store"
[ "$WITH_HTTP" = 1 ] && mkdir -p "$DIR/internal/httpapi"
[ "$WITH_REACT" = 1 ] && mkdir -p "$DIR/client/src"
# config/ holds services.yaml when a layer with an address or port is present.
if [ "$WITH_REACT" = 1 ] || [ "$WITH_HTTP" = 1 ]; then
    mkdir -p "$DIR/config" "$DIR/scripts"
fi

# Base layer always runs; the optional layers write their exclusive files and set
# the fragment variables the shared-file assembly below reads.
go_base_layer
[ "$WITH_SQLITE" = 1 ] && go_sqlite_layer
[ "$WITH_REACT" = 1 ] && go_react_layer
# HTTP last: it replaces the base entry point with the server bootstrap.
[ "$WITH_HTTP" = 1 ] && go_http_layer

# Each layer contributes its own .gitignore rules, appended to the base file.
go_gitignore_fragments

# ---------------------------------------------------------------------------
# Makefile: base targets, then the help lines and target blocks each layer added.
# Grouped by area (build, quality, tests, then the layer groups), mirroring the
# TypeScript generator's grouping so the two projects read the same way.
# ---------------------------------------------------------------------------
step "build surface (Makefile)"

CONFIG_MAKE_HELP=""
CONFIG_MAKE_TARGET=""
SERVICES_YAML="${HTTP_YAML:-}${REACT_YAML:-}"
if [ -n "$SERVICES_YAML" ]; then
    CONFIG_MAKE_HELP='	@echo ""
	@echo " config"
	@echo "  config      Regenerate .env from config/services.yaml"'
    CONFIG_MAKE_TARGET='
# --- config --------------------------------------------------------------
.PHONY: config

config: ## Regenerate .env from config/services.yaml
	./scripts/config-env.sh'
fi

write_file "$DIR/Makefile" <<EOF
# help is the default goal so a bare \`make\` documents the project
.DEFAULT_GOAL := help

.PHONY: help
help: ## List available targets
	@echo "${NAME} - available targets:"
	@echo ""
	@echo "  help        Show this list"
	@echo ""
	@echo " build"
	@echo "  build       Compile the binary into bin/${APP}"
	@echo "  tidy        Resolve and prune module dependencies"
${HTTP_MAKE_HELP:-}
${REACT_MAKE_HELP:-}
${SQLITE_MAKE_HELP:-}
	@echo ""
	@echo " tests"
	@echo "  test        Run the unit tier (no external services)"
	@echo ""
	@echo " quality"
	@echo "  fmt         Format with gofmt"
	@echo "  vet         Report suspicious constructs (go vet)"
	@echo "  check       Run all quality gates (fmt-check, vet, build, test)"
${CONFIG_MAKE_HELP:-}

# --- build ---------------------------------------------------------------
.PHONY: build tidy

build: ## Compile the binary into bin/${APP}
	go build -o bin/${APP} ./cmd/${APP}

tidy: ## Resolve and prune module dependencies
	go mod tidy
${HTTP_MAKE_TARGET:-}
${REACT_MAKE_TARGET:-}
${SQLITE_MAKE_TARGET:-}
# --- tests ---------------------------------------------------------------
.PHONY: test

# The unit tier is every untagged test in the module; the integration tier sits
# behind the \`integration\` build tag, so this never selects it.
test: ## Run the unit tier (no external services)
	go test ./...

# --- quality -------------------------------------------------------------
.PHONY: fmt fmt-check vet check

fmt: ## Format with gofmt
	gofmt -w .

fmt-check: ## Check formatting without writing (CI-friendly)
	@unformatted="\$\$(gofmt -l .)"; \\
	if [ -n "\$\$unformatted" ]; then echo "not gofmt-clean:"; echo "\$\$unformatted"; exit 1; fi

vet: ## Report suspicious constructs (go vet)
	go vet ./...

# Aggregate gate for CI and pre-push: fmt-check (not fmt) so unformatted code fails
# rather than being silently rewritten.
check: fmt-check vet build test ## Run all quality gates
${CONFIG_MAKE_TARGET:-}
EOF

# ---------------------------------------------------------------------------
# Service config: ports and addresses in one YAML, assembled from the layer
# fragments. scripts/config-env.sh turns it into .env, which the binary reads
# (SERVER_HOST/SERVER_PORT) and the Vite client reads through loadEnv. Written only
# when a layer with an address contributed a block.
# ---------------------------------------------------------------------------
if [ -n "$SERVICES_YAML" ]; then
    step "service config (config/services.yaml)"

    # %$'\n' strips the fragments' trailing newline so the heredoc's own line break
    # leaves exactly one at end-of-file.
    write_file "$DIR/config/services.yaml" <<EOF
# Service ports and addresses for this project, in one place. Edit here, then run
# \`make config\` (or ./scripts/config-env.sh) to regenerate .env, which the binary
# and the Vite dev server read. Defaults match the code, so a fresh checkout runs
# without regenerating.
${SERVICES_YAML%$'\n'}
EOF

    write_file "$DIR/scripts/config-env.sh" <<'EOF'
#!/usr/bin/env bash
# Generate .env from config/services.yaml so the binary and the Vite dev server read
# their ports and addresses from one place. Re-run after editing the YAML (or via
# `make config`). No YAML dependency: services.yaml is a fixed two-level shape (a
# `section:` line, then two-space `key: value` lines) that this awk reads
# deterministically, emitting SECTION_KEY=value pairs.
#
# Usage:
#   config-env.sh          regenerate .env from config/services.yaml
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

    CONFIG_CLAUDE_MD="
- Service ports and addresses live in config/services.yaml; \`make config\`
  regenerates .env from it, read by the binary and the Vite dev server."
fi

# ---------------------------------------------------------------------------
# CI workflow: layer-aware, assembled from fragments like the Makefile. The base
# gates (build, vet, unit) always run; --sqlite appends the integration job and
# --react the client job. Runs on every PR into main, which the build loop opens one
# of per increment.
# ---------------------------------------------------------------------------
step "CI workflow"

write_file "$DIR/.github/workflows/ci.yml" <<EOF
# Layer-aware CI from init-go-project.sh: jobs scale with the layers added.
# Runs on every PR into main, which the build loop opens one of per increment.
# go-version-file reads go.mod, so the toolchain follows the module, never drifts.
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
      - run: go build ./...
      - run: go vet ./...
      - name: gofmt
        run: |
          unformatted="\$(gofmt -l .)"
          if [ -n "\$unformatted" ]; then echo "not gofmt-clean:"; echo "\$unformatted"; exit 1; fi

  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
      - run: go test ./...${SQLITE_CI_JOB:-}${REACT_CI_JOB:-}
EOF

# ---------------------------------------------------------------------------
# Docs: CLAUDE.md (project identity + runtime facts; conventions live in
# .claude/rules), README.
# ---------------------------------------------------------------------------
step "docs"

write_file "$DIR/CLAUDE.md" <<EOF
# ${NAME}

TODO: one or two lines on what this project is and is not (its scope).

## Layout

- A single binary: cmd/${APP}/main.go is the entry point, everything else is under
  internal/. Build it with \`make build\`, run it with \`./bin/${APP}\`.
- The client is embedded with embed.FS from internal/assets/static, so the shipped
  artefact has no runtime dependency.${REACT_CLAUDE_MD:-}${CONFIG_CLAUDE_MD:-}
- Test tiers split by BUILD TAG, not directory: the unit tier is every untagged
  test (\`go test ./...\`), the integration tier is the files behind
  \`//go:build integration\` (\`go test -tags=integration ./...\`).

## Conventions

- Stack conventions (Go, and any others) are path-scoped rules under
  .claude/rules/, installed by install-project-rules.sh and read automatically.
  Universal conventions (prose, comments) come from the global rules. This file
  carries only what is specific to THIS project: its scope and runtime facts.${SQLITE_CLAUDE_MD:-'

## Integration endpoints

None yet. Declare each integration endpoint this project needs here, and for each:
a readiness check (a command that succeeds only when the endpoint is up), and a
bring-up command (how the human starts it). The build loop'"'"'s judge checks
readiness before running the integration tier and raises an environment block, not
a failure, when an endpoint is down.'}
EOF

write_file "$DIR/README.md" <<EOF
# ${NAME}

A Go project: one binary, no runtime dependencies.

## Quick start

\`\`\`
go mod tidy$([ "$WITH_REACT" = 1 ] && printf '\nmake client-install\nmake client-build')
make test
make build
$([ "$WITH_HTTP" = 1 ] && printf 'make server-start' || printf './bin/%s' "$APP")
\`\`\`

Run \`make help\` to see what each target does.
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
RULE_FLAGS="--go"
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
# Bare commands, one per line, so the block is safe to copy-paste.
echo "Next (run 'make help' to see what each target does):"
echo "  cd $DIR"
echo "  go mod tidy"
[ "$WITH_REACT" = 1 ] && echo "  make client-install"
[ "$WITH_REACT" = 1 ] && echo "  make client-build"
echo "  make test"
echo "  make build"
echo
echo "Then drive it through the pipeline. Two independent prerequisites, in either order:"
echo "  /omero-design-sheet     converges your intent into a feature sheet"
echo "  /omero-review-sheet     reviews the sheet for design soundness before build"
echo "  /omero-setup-project    proves the project environment ready"
echo "Then /omero-build-full builds the sheet (needs both the sheet and the receipt)."
