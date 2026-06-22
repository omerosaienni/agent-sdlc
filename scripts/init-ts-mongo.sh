#!/usr/bin/env bash
# init-ts-mongo.sh - scaffold a backend TypeScript + MongoDB project from the
# constant template. Writes the stack files (tooling, infra, db helper, entry
# point, conventions), parameterising the name-bearing ones, then inits git.
# Makes no domain assumptions: you grow src/index.ts and add your own modules.
#
# This is the GENERATOR half of project provisioning. After it runs, the project
# still needs: npm install, docker bring-up, and the setup gate (project-setup.sh)
# to prove it ready for the build loop.
#
# Usage:
#   init-ts-mongo.sh <project-name> [target-dir] [--port N] [--verbose] [--debug]
#
#   project-name : kebab-case, used for the npm package, the compose project,
#                  the container, the volume, and the Mongo database name.
#   target-dir   : where to create it (default: ./<project-name>)
#   --port N     : host port for this project's Mongo. Default: auto-pick the
#                  first free port from 27017 up, so a second project never
#                  collides with a first that is already running. Baked into the
#                  project's files (instance per repo, deterministic once made).
#   --verbose    : print each file as it is written (default prints one line per
#                  area).
#   --debug      : trace every shell command (set -x); shows exactly which step
#                  ran last if the script stops early.
#
# Scope: backend only (first generator pass). Frontend/monorepo is a later
# expansion. See docs/templates/ts-react-mongo.md for the full intended template.
set -euo pipefail

# ============================================================================
# Helpers
# ============================================================================

VERBOSE=0
USE_COLOR=auto   # auto | always | never (set by --no-color or detection below)

# Colour is enabled only when stdout is a real terminal, TERM is not dumb, and
# the user has not opted out (NO_COLOR convention or --no-color). This keeps
# escape codes out of piped or redirected output.
setup_color() {
    if [ "$USE_COLOR" = never ] || [ -n "${NO_COLOR:-}" ] \
       || [ ! -t 1 ] || [ "${TERM:-dumb}" = dumb ]; then
        C_RESET= ; C_STEP= ; C_NOTE= ; C_OK= ; C_ERR=
    else
        C_RESET=$'\033[0m'
        C_STEP=$'\033[1;36m'   # bold cyan, area headers
        C_NOTE=$'\033[2m'      # dim, detail lines
        C_OK=$'\033[32m'       # green, success
        C_ERR=$'\033[31m'      # red, errors
    fi
}

# step announces an area of work: one clean line by default.
step() { printf '%s==>%s %s\n' "$C_STEP" "$C_RESET" "$1"; }

# note prints a detail line only under --verbose.
note() { [ "$VERBOSE" = "1" ] && printf '%s    %s%s\n' "$C_NOTE" "$1" "$C_RESET"; return 0; }

# err prints to stderr in red.
err() { printf '%s%s%s\n' "$C_ERR" "$1" "$C_RESET" >&2; }

# writes the heredoc on stdin to a file, announcing it only under --verbose. Use
# instead of a bare `cat >` so every write is consistently reported.
write_file() {
    local path="$1"
    cat > "$path"
    note "wrote ${path#"$DIR"/}"
}

# Templates: pure constant files live in the repo's templates/ directory so they
# are defined once and shared by every script that emits them. Resolve relative
# to this script's own location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"

# copy_template <template-name> <dest-path>: copy a shared template into the
# project, failing loudly if it is missing rather than emitting a broken project.
copy_template() {
    local src="$TEMPLATES_DIR/$1" dest="$2"
    if [ ! -f "$src" ]; then
        echo "missing template: $src (is the templates/ directory present?)" >&2
        exit 1
    fi
    cp "$src" "$dest"
    note "wrote ${dest#"$DIR"/} (from template)"
}

# port_in_use: true if something is already listening on the host port. A
# project's mongod binds the host port, so probing for a listener is the right
# test. Prefer ss, fall back to bash's /dev/tcp probe if ss is absent.
port_in_use() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltn "( sport = :$1 )" 2>/dev/null | grep -q ":$1 "
    else
        (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&- 3<&-; return 0; } || return 1
    fi
}

usage() {
    echo "usage: init-ts-mongo.sh <project-name> [target-dir] [--port N] [--verbose] [--no-color] [--debug]" >&2
    exit 2
}

# ============================================================================
# Parse arguments (flags, never environment variables)
# ============================================================================

NAME=""
DIR=""
PORT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --port)    PORT="${2:-}"; shift 2 ;;
        --port=*)  PORT="${1#*=}"; shift ;;
        --verbose) VERBOSE=1; shift ;;
        --no-color|--no-colour) USE_COLOR=never; shift ;;
        --debug)   set -x; shift ;;
        -h|--help) usage ;;
        -*)        echo "unknown option: $1" >&2; usage ;;
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

# kebab-case: the name flows into a Mongo db name and a docker volume, both of
# which dislike spaces and uppercase. Fail early rather than emit a broken repo.
case "$NAME" in
    *[!a-z0-9-]*) echo "project-name must be kebab-case (lowercase, digits, hyphens): '$NAME'" >&2; exit 2 ;;
esac

DIR="${DIR:-./$NAME}"
if [ -e "$DIR" ]; then
    echo "target '$DIR' already exists; refusing to overwrite" >&2
    exit 1
fi

# Derived names. DB_NAME drops hyphens (cleaner as a Mongo database name); the
# compose project and volume keep the hyphenated form.
DB_NAME="$(echo "$NAME" | tr -d '-')"
VOLUME="${NAME}-data"

# Port: explicit and validated, or auto-picked as the first free one from 27017.
if [ -n "$PORT" ]; then
    case "$PORT" in
        ''|*[!0-9]*) echo "--port must be a number: '$PORT'" >&2; exit 2 ;;
    esac
    if port_in_use "$PORT"; then
        echo "requested port $PORT is already in use; pick another or omit --port to auto-pick" >&2
        exit 1
    fi
else
    PORT=27017
    while port_in_use "$PORT"; do
        note "port $PORT in use, trying next"
        PORT=$((PORT + 1))
        if [ "$PORT" -gt 27117 ]; then
            echo "no free port found in 27017-27117; pass --port explicitly" >&2
            exit 1
        fi
    done
fi

# ============================================================================
# Scaffold
# ============================================================================

step "Scaffolding '$NAME' into '$DIR' (db: $DB_NAME, port: $PORT)"
mkdir -p "$DIR"/{src,scripts,docs,docs/modules}


# ---------------------------------------------------------------------------
# Tooling: test tiers, TypeScript, lint, format, ignores. All constant.
# ---------------------------------------------------------------------------
step "tooling configs"

# Vitest tier configs come from shared templates (also used by the setup gate),
# so the two scripts can never drift.
copy_template vitest.unit.config.ts "$DIR/vitest.unit.config.ts"
copy_template vitest.integration.config.ts "$DIR/vitest.integration.config.ts"

write_file "$DIR/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "types": ["node"]
  },
  "include": ["src", "vitest.unit.config.ts", "vitest.integration.config.ts", "eslint.config.js"]
}
EOF

write_file "$DIR/eslint.config.js" <<'EOF'
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  { ignores: ['dist', 'node_modules'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  // prettier last so it switches off rules that would fight the formatter
  prettier,
);
EOF

write_file "$DIR/.prettierrc.json" <<'EOF'
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100
}
EOF

write_file "$DIR/.gitignore" <<'EOF'
node_modules/
dist/
.claude/
.vscode/
coverage/
.building/
graphify-out/
EOF

write_file "$DIR/.graphifyignore" <<'EOF'
# loop + build output
.building/
graphify-out/
node_modules/
dist/
coverage/

# config files: not architecture, just noise in the graph
tsconfig.json
package.json
package-lock.json
.prettierrc.json
eslint.config.js
vitest.unit.config.ts
vitest.integration.config.ts
EOF

# ---------------------------------------------------------------------------
# Database helper: the one shared client. Constant in shape; URI port and
# DB_NAME are parameterised.
# ---------------------------------------------------------------------------
step "database helper"

write_file "$DIR/src/db.ts" <<EOF
import { MongoClient, type Db } from 'mongodb';

// directConnection=true is required: a single node replica set advertises its
// internal container hostname (port 27017), which the host cannot follow, so the
// driver must be told not to chase that advertisement and to stay on the host
// port this project mapped.
const URI = 'mongodb://127.0.0.1:${PORT}/?directConnection=true';

// Database the whole project uses. One place so all modules agree.
export const DB_NAME = '${DB_NAME}';

// One shared MongoClient per process. MongoClient construction is lazy in the
// driver: it does not touch the network until connect(), so building the
// instance here needs no live server and the getter can be unit tested for reuse.
let client: MongoClient | undefined;

// serverSelectionTimeoutMS keeps failures fast when the endpoint is down rather
// than hanging on the driver default of 30s.
export function getClient(): MongoClient {
  if (client === undefined) {
    client = new MongoClient(URI, { serverSelectionTimeoutMS: 5000 });
  }
  return client;
}

// Typed db handle off the one shared client. connect() is idempotent on the
// driver so callers need not coordinate who connects first.
export async function getDb(): Promise<Db> {
  const c = getClient();
  await c.connect();
  return c.db(DB_NAME);
}

// Close the shared client and clear it so a later getClient() rebuilds. Scripts
// and tests must call this or the process will not exit.
export async function closeClient(): Promise<void> {
  if (client !== undefined) {
    await client.close();
    client = undefined;
  }
}
EOF

# ---------------------------------------------------------------------------
# Infra: Docker Mongo (single node replica set) and its init script. The host
# port, compose project, container and volume names are parameterised.
# ---------------------------------------------------------------------------
step "docker infra"

write_file "$DIR/docker-compose.yml" <<EOF
# name pins the compose project so the container and volume names are stable
# regardless of the working directory (a git worktree is named after a number,
# which would otherwise leak into the volume name and break \`make nuke\`).
name: ${NAME}
services:
  mongo:
    image: mongo:8.0
    container_name: ${NAME}
    # --replSet is mandatory: the project models a single node replica set so
    # change streams and transactions work. bind_ip_all lets the host reach it.
    command: ["mongod", "--replSet", "rs0", "--bind_ip_all"]
    ports:
      # host port is this project's own (instance per repo); container is always 27017
      - "${PORT}:27017"
    volumes:
      - data:/data/db
volumes:
  # fixed name so \`make nuke\` can verify the volume is gone deterministically
  data:
    name: ${VOLUME}
EOF

# rs-init.sh is constant (no project name inside; it targets the 'mongo' service).
write_file "$DIR/scripts/rs-init.sh" <<'EOF'
#!/usr/bin/env bash
# Initialise the single node replica set, idempotently, then wait for a PRIMARY.
#
# Run inside the container via `docker compose exec` so mongosh talks to mongod
# over loopback. The member host is 127.0.0.1:27017, which is also what the host
# reaches with directConnection=true, so no internal container hostname leaks out.
set -euo pipefail

# compose exec addresses the service, not the container_name
SERVICE=mongo

# rs.initiate on an already-initialised set throws AlreadyInitialized (code 23).
# Catching it makes a second run a no-op instead of a failure.
docker compose exec -T "${SERVICE}" mongosh --quiet --eval '
  try {
    rs.initiate({
      _id: "rs0",
      members: [{ _id: 0, host: "127.0.0.1:27017" }],
    });
    print("replica set initiated");
  } catch (e) {
    if (e.codeName === "AlreadyInitialized" || e.code === 23) {
      print("replica set already initialised");
    } else {
      throw e;
    }
  }
'

# Poll rather than trust rs.initiate returning: election is asynchronous, so the
# smoke test could connect before a PRIMARY exists. Block here to keep bootstrap
# race-free.
echo "waiting for a PRIMARY to be elected..."
for _ in $(seq 1 30); do
    state=$(docker compose exec -T "${SERVICE}" mongosh --quiet --eval 'db.hello().isWritablePrimary' 2>/dev/null || true)
    case "${state}" in
        true)
            echo "PRIMARY elected"
            exit 0
            ;;
        *)
            sleep 1
            ;;
    esac
done
echo "timed out waiting for PRIMARY" >&2
exit 1
EOF
chmod +x "$DIR/scripts/rs-init.sh"

# ---------------------------------------------------------------------------
# Build surface: Makefile targets and package.json scripts. The nuke volume
# name and help banner are parameterised; only constant scripts are carried.
# ---------------------------------------------------------------------------
step "build surface (Makefile, package.json)"

write_file "$DIR/Makefile" <<EOF
# help is the default goal so a bare \`make\` documents the project
.DEFAULT_GOAL := help

.PHONY: help up rs-init start seed down nuke bootstrap test test-unit test-integration lint typecheck graph graph-viz

help: ## List available targets
	@echo "${NAME} - available targets:"
	@echo ""
	@echo "  help        Show this list"
	@echo "  up          Start MongoDB in Docker"
	@echo "  rs-init     Initialise the single node replica set (idempotent)"
	@echo "  start       Run the entry point (src/index.ts)"
	@echo "  seed        Generate and load faker seed data"
	@echo "  down        Stop the container, keep data"
	@echo "  nuke        Stop the container and delete the named volume"
	@echo "  bootstrap   up + rs-init in one go"
	@echo "  test-unit   Run the unit tier (no database needed)"
	@echo "  test-integration  Run the integration tier (needs Mongo up)"
	@echo "  test        Run unit then integration, in that order"
	@echo "  lint        Run eslint over src"
	@echo "  typecheck   Type-check without emitting (tsc --noEmit)"
	@echo "  graph       Rebuild the knowledge graph (code + docs) and HTML"
	@echo "  graph-viz   Regenerate graph.html and report from the existing graph"

up: ## Start MongoDB in Docker
	docker compose up -d
	@echo "waiting for mongod to accept connections..."
	@# poll the server rather than a fixed sleep: the image runs initdb on first
	@# boot, so readiness time is not constant. ping needs no auth and no RS.
	@for i in \$\$(seq 1 30); do \\
		if docker compose exec -T mongo mongosh --quiet --eval 'db.runCommand({ ping: 1 }).ok' 2>/dev/null | grep -q 1; then \\
			echo "mongod is up"; \\
			exit 0; \\
		fi; \\
		sleep 1; \\
	done; \\
	echo "mongod did not become ready" >&2; \\
	exit 1

rs-init: ## Initialise the single node replica set (idempotent)
	./scripts/rs-init.sh

start: ## Run the entry point (src/index.ts)
	npm start

seed: ## Generate and load faker seed data
	npm run seed

down: ## Stop the container, keep data
	docker compose down

nuke: ## Stop the container and delete the named volume
	docker compose down -v
	@# confirm the volume is actually gone: a deterministic name lets us assert it
	@if docker volume ls --format '{{.Name}}' | grep -qx ${VOLUME}; then \\
		echo "volume ${VOLUME} still present" >&2; \\
		exit 1; \\
	fi
	@echo "container and volume removed"

bootstrap: up rs-init ## up + rs-init, no manual steps

test-unit: ## Run the unit tier (no database needed)
	npm run test:unit

test-integration: ## Run the integration tier (needs Mongo up)
	npm run test:integration

# unit before integration so a logic break fails fast without needing the database
test: test-unit test-integration ## Run unit then integration, in that order

lint: ## Run eslint over src
	npm run lint

typecheck: ## Type-check without emitting (tsc --noEmit)
	npm run typecheck

# Knowledge graph (graphify). Model/env pinned so the target is self-contained.
# Code is auto-refreshed by the post-commit hook (AST, no LLM); this target is
# for refreshing docs (needs the LLM) and rebuilding the HTML view.
GRAPHIFY_ENV := OLLAMA_MODEL=graphify OLLAMA_API_KEY=x

graph: ## Rebuild the knowledge graph: code (AST) + docs (LLM) + HTML
	\$(GRAPHIFY_ENV) graphify . --backend ollama --token-budget 8000 --max-concurrency 1

graph-viz: ## Regenerate graph.html and the report from the existing graph
	\$(GRAPHIFY_ENV) graphify cluster-only . --backend ollama
EOF

write_file "$DIR/package.json" <<EOF
{
  "name": "${NAME}",
  "version": "0.1.0",
  "description": "A TypeScript MongoDB project using the native driver",
  "type": "module",
  "private": true,
  "scripts": {
    "start": "tsx src/index.ts",
    "seed": "tsx src/seed.ts",
    "test:unit": "vitest run -c vitest.unit.config.ts",
    "test:integration": "vitest run -c vitest.integration.config.ts",
    "lint": "eslint src",
    "typecheck": "tsc --noEmit",
    "format:check": "prettier --check ."
  },
  "dependencies": {
    "mongodb": "^6.12.0"
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
    "tsx": "^4.22.4",
    "typescript": "^5.7.2",
    "typescript-eslint": "^8.18.1",
    "vitest": "^4.1.9"
  }
}
EOF

# ---------------------------------------------------------------------------
# Source: the entry point. Every project has at least one main; this is it. No
# domain assumptions, it is the front door you grow into the real program. The
# matching test keeps the unit tier non-empty (the setup gate needs a non-zero
# count).
# ---------------------------------------------------------------------------
step "entry point"

write_file "$DIR/src/index.ts" <<'EOF'
// The program entry point. Grow this into the real bootstrap: for a backend that
// usually means connecting to Mongo via getDb() and starting the server.
export function main(): string {
  return 'app starting';
}

// Runnable directly. The import.meta.url guard keeps main() importable from tests
// without running when imported.
if (import.meta.url === `file://${process.argv[1]}`) {
  console.log(main());
}
EOF

write_file "$DIR/src/seed.ts" <<'EOF'
import { faker } from '@faker-js/faker';
import { getDb, closeClient } from './db.js';

// Generate and load development seed data. A domain-free starting point that
// proves the faker to Mongo path works end to end; grow it into the collections
// and shapes your project needs.
export async function seed(count = 10): Promise<number> {
  const db = await getDb();
  const examples = db.collection('examples');
  const docs = Array.from({ length: count }, () => ({
    name: faker.person.fullName(),
    email: faker.internet.email(),
    createdAt: new Date(),
  }));
  await examples.deleteMany({});
  const result = await examples.insertMany(docs);
  return result.insertedCount;
}

// Runnable directly. The import.meta.url guard keeps seed() importable from tests
// without running on import.
if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    const count = await seed();
    console.log(`seeded ${count} documents into 'examples'`);
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  } finally {
    await closeClient();
  }
}
EOF

write_file "$DIR/src/index.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest';
import { main } from './index.js';

// Unit tier (no Mongo). Grows alongside the entry point.
describe('main', () => {
  it('returns the startup message', () => {
    expect(main()).toBe('app starting');
  });
});
EOF

# Generic Mongo smoke test (integration tier). Not tied to any domain or to the
# entry point's logic, it verifies the infrastructure: the app's own connection
# path reaches a healthy single node replica set with a PRIMARY. It stays true
# for the life of the project, run `make bootstrap` first. This also exercises
# the db helper from birth.
write_file "$DIR/src/smoke.integration.test.ts" <<'EOF'
import { afterAll, describe, expect, it } from 'vitest';
import { getDb, closeClient } from './db.js';

// replSetGetStatus returns a typed members array. We only care about state.
interface ReplSetMember {
  stateStr: string;
}
interface ReplSetStatus {
  set: string;
  members: ReplSetMember[];
}

afterAll(async () => {
  await closeClient();
});

describe('replica set smoke test', () => {
  it(
    'reports a PRIMARY member',
    async () => {
      // Connect exactly as the rest of the app will, through the shared helper,
      // so this fails if mongod is down OR the replica set was never initiated.
      const db = await getDb();
      const status = (await db
        .admin()
        .command({ replSetGetStatus: 1 })) as ReplSetStatus;
      expect(status.set).toBe('rs0');
      const states = status.members.map((m) => m.stateStr);
      expect(states).toContain('PRIMARY');
    },
    15000,
  );
});
EOF


# ---------------------------------------------------------------------------
# Editor: generic VSCode debug configs (gitignored, personal). They follow the
# open file rather than naming modules, so they work in any project.
# ---------------------------------------------------------------------------
step "editor debug configs"
mkdir -p "$DIR/.vscode"
write_file "$DIR/.vscode/launch.json" <<'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug current file",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "npx",
      "runtimeArgs": ["tsx", "${relativeFile}"],
      "console": "integratedTerminal",
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    },
    {
      "name": "Debug current test file",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "npx",
      "runtimeArgs": [
        "vitest",
        "run",
        "${relativeFile}",
        "--no-file-parallelism"
      ],
      "console": "integratedTerminal",
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    },
    {
      "name": "Debug unit tier",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "npx",
      "runtimeArgs": [
        "vitest",
        "run",
        "-c",
        "vitest.unit.config.ts",
        "--no-file-parallelism"
      ],
      "console": "integratedTerminal",
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    },
    {
      "name": "Debug integration tier (Mongo must be up)",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "npx",
      "runtimeArgs": [
        "vitest",
        "run",
        "-c",
        "vitest.integration.config.ts",
        "--no-file-parallelism"
      ],
      "console": "integratedTerminal",
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    }
  ]
}
EOF

# ---------------------------------------------------------------------------
# Docs: conventions (CLAUDE.md) and README. Conventions are constant; the scope
# line is a stub for you to fill.
# ---------------------------------------------------------------------------
step "docs and conventions"

write_file "$DIR/CLAUDE.md" <<EOF
# ${NAME}

TODO: one or two lines on what this project is and is not (its scope).

## Layout and entry point
- Entry point: src/index.ts. Every program has at least one main; this is it.
  Runnable via \`npm start\`. Grow it into the real bootstrap (for a backend that
  usually means connecting to Mongo via getDb() and starting the server).
- All source under src/. One module per file, named after what it does, lower
  case. A module's test sits beside it (see Test tiers).
- TypeScript, strict. Node, native MongoDB driver. vitest two tier (unit and
  integration).

## Database access (the pattern)
- One shared MongoClient per process via the db helper at src/db.ts. Never connect
  per query. Import getDb/closeClient from './db.js'.
- When the project needs named collections, put the names in one place (a
  COLLECTIONS constant, conventionally src/collections.ts) and import them. Never
  hardcode collection name strings. Pass document interfaces as driver generics,
  e.g. db.collection<Item>(COLLECTIONS.items).

## Runnable modules (the pattern)
- A module meant to be run on its own (a seed, an example, a script) is runnable
  via an npm script and an \`import.meta.url\` main-guard so it runs when invoked
  directly but stays importable from tests. Name an example script ex:<feature>
  and have it print its results.

## Conventions
- Strict TypeScript. Supply interfaces and pass them as driver generics. Do NOT use \`any\`.
- async/await throughout, not raw promise chains.
- British English in comments and output. No em dashes (restructure instead). No
  Oxford commas. No hyphens in compound modifiers.
- Comments explain WHY not WHAT. Be brief. A why only where a non-obvious decision
  needs one. Do not restate the code.

## Test tiers
- A test that touches Mongo MUST be in the integration tier (*.integration.test.ts),
  never the unit tier. One file per module per tier, named after the module,
  co-located, tier by suffix (foo.ts -> foo.test.ts and/or foo.integration.test.ts).
- Shared test helpers, if any, in one support module under src/test-support/.

## Integration endpoints
- Mongo at mongodb://127.0.0.1:${PORT} with directConnection=true. Readiness: a
  connect succeeds, or \`docker compose ps\` shows the mongo service up. Bring up
  with \`make bootstrap\`.
EOF

# Stub README.
write_file "$DIR/README.md" <<EOF
# ${NAME}

A TypeScript MongoDB project.

## Quick start
\`\`\`
npm install
make bootstrap     # start Mongo, init the replica set
make test          # unit then integration
\`\`\`
EOF

# ---------------------------------------------------------------------------
# Git: init the repo and make the first commit. Idempotent: git init on an
# existing repo is a no-op, and the commit is skipped if history already exists,
# so re-running does not error or duplicate.
# ---------------------------------------------------------------------------
step "git repository"
(
    cd "$DIR"
    if [ ! -d .git ]; then
        git init -q
    fi
    git add -A
    # Only commit if there is no HEAD yet, so a repo with history is left as is.
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        git commit -q -m "Initial scaffold"
        note "initialised and committed initial scaffold"
    else
        note "repo already has history, left as is"
    fi
)

printf '\n%sScaffolded %s%s\n' "$C_OK" "$NAME" "$C_RESET"
echo "Next:"
echo "  cd $DIR"
echo "  npm install"
echo "  make bootstrap          # start Mongo on port $PORT and init the replica set"
echo "  make test               # unit (entry point) + integration (Mongo smoke test)"
echo
echo "Then build the project: grow src/index.ts into the real entry point, add your"
echo "modules and their tests, write docs/deliverables.md, and run the setup gate"
echo "(project-setup.sh) to prove it loop-ready."
