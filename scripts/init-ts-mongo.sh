#!/usr/bin/env bash
# init-ts-mongo.sh - scaffold a backend TypeScript + MongoDB project from the
# constant template. Writes the stack files (tooling, infra, db helper, entry
# point, conventions), parameterising the name-bearing ones, then inits git.
# Makes no domain assumptions: you grow src/server/index.ts and add your own modules.
#
# This is the GENERATOR half of project provisioning. After it runs, the project
# still needs: npm install, docker bring-up, and the setup gate (project-setup.sh)
# to prove it ready for the build loop.
#
# Mongo model: every project shares one mongod container (shared-mongo, fixed
# port 27017, replica set rs0). A project lives in its own database inside it,
# named after the project. The compose that defines the shared container is
# identical in every project, so the first project to run `make up` creates it
# and later projects reuse it. Nobody owns the container, so deleting it is a
# manual docker rm, never a make target; a project's own destructive verb (drop)
# removes only its database.
#
# Usage:
#   init-ts-mongo.sh <project-name> [target-dir] [--verbose] [--debug]
#
#   project-name : kebab-case, used for the npm package and the Mongo database
#                  name. The shared container and volume are constant, not named
#                  after the project.
#   target-dir   : where to create it (default: ./<project-name>)
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

usage() {
    echo "usage: init-ts-mongo.sh <project-name> [target-dir] [--verbose] [--no-color] [--debug]" >&2
    exit 2
}

# ============================================================================
# Parse arguments (flags, never environment variables)
# ============================================================================

NAME=""
DIR=""
WITH_REACT=0   # --with-react adds the src/client React+Vite layer (set by init-ts-mongo-react.sh)
while [ $# -gt 0 ]; do
    case "$1" in
        --verbose) VERBOSE=1; shift ;;
        --no-color|--no-colour) USE_COLOR=never; shift ;;
        --with-react) WITH_REACT=1; shift ;;
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

# kebab-case: the name becomes the Mongo db name and the npm package name, both
# of which dislike spaces and uppercase. Fail early rather than emit a broken repo.
case "$NAME" in
    *[!a-z0-9-]*) echo "project-name must be kebab-case (lowercase, digits, hyphens): '$NAME'" >&2; exit 2 ;;
esac

DIR="${DIR:-./$NAME}"
if [ -e "$DIR" ]; then
    echo "target '$DIR' already exists; refusing to overwrite" >&2
    exit 1
fi

# Derived names. The kebab-case name is already a valid Mongo database name
# (lowercase, digits, hyphens, none of which Mongo forbids and well under the
# 63 byte limit), so it is used verbatim, no transform. The shared container and
# volume are constant (shared-mongo, shared-mongo-data), not derived from the
# project, because every project shares the one mongod.
DB_NAME="$NAME"

# ============================================================================
# Scaffold
# ============================================================================

# Layout: source lives under src/server/ (with the db helper at src/server/db/),
# not a flat src/. This is the canonical layout the stack rules scope to
# (omero-mongo.md -> src/server/db/**) and the shape a project grows a src/client/
# into when it adds a frontend. The db helper sits in its own folder so the Mongo
# rule's directory glob has a real target.
step "Scaffolding '$NAME' into '$DIR' (db: $DB_NAME)"
mkdir -p "$DIR"/{src/server/db,scripts,docs,docs/modules}
# React adds the client tree (omero-react.md scopes to src/client/**) and a shared
# tree for types crossing the client/server boundary.
[ "$WITH_REACT" = 1 ] && mkdir -p "$DIR"/{src/client,src/shared}


# ---------------------------------------------------------------------------
# Tooling: test tiers, TypeScript, lint, format, ignores. All constant.
# ---------------------------------------------------------------------------
step "tooling configs"

# Vitest tier configs come from shared templates (also used by the setup gate),
# so the two scripts can never drift.
copy_template vitest.unit.config.ts "$DIR/vitest.unit.config.ts"
copy_template vitest.integration.config.ts "$DIR/vitest.integration.config.ts"

# React needs DOM libs and the react-jsx transform; the client also imports Vite
# config files, so those join the include set. Interpolated so the backend-only
# tsconfig stays unchanged.
TS_LIB='"ES2022"'
TS_JSX=""
TS_INCLUDE='"src", "vitest.unit.config.ts", "vitest.integration.config.ts", "eslint.config.js"'
if [ "$WITH_REACT" = 1 ]; then
    TS_LIB='"ES2022", "DOM", "DOM.Iterable"'
    TS_JSX='
    "jsx": "react-jsx",'
    TS_INCLUDE='"src", "vitest.unit.config.ts", "vitest.integration.config.ts", "vitest.client.config.ts", "vite.config.ts", "eslint.config.js"'
fi

write_file "$DIR/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": [${TS_LIB}],${TS_JSX}
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "types": ["node"]
  },
  "include": [${TS_INCLUDE}]
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

# At src/server/db/index.ts so the db layer is a folder (importable as
# './db/index.js' from src/server, and the directory the Mongo stack rule scopes to).
write_file "$DIR/src/server/db/index.ts" <<EOF
import { MongoClient, type Db } from 'mongodb';

// directConnection=true is required: a single node replica set advertises its
// internal container hostname (port 27017), which the host cannot follow, so the
// driver must be told not to chase that advertisement and to stay on 127.0.0.1.
// The port is fixed because every project shares one mongod (the shared-mongo
// container), each in its own database.
const URI = 'mongodb://127.0.0.1:27017/?directConnection=true';

// Database this project uses inside the shared server. One place so all modules
// agree. Named after the project, so the shared server lists one database per
// project.
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
# Infra: the shared Docker Mongo (single node replica set) and its init script.
# The compose is constant and identical in every project: it defines the one
# shared mongod that all projects use. The first project to run `make up`
# creates it; later projects reuse it.
# ---------------------------------------------------------------------------
step "docker infra"

write_file "$DIR/docker-compose.yml" <<'EOF'
# This compose is identical in every project. It defines the one shared mongod
# that all projects share, each as its own database. The first project to run
# `make up` creates the container; later projects reuse it. Nobody owns it, so
# deleting it is a manual docker rm of shared-mongo, never a make target.
name: shared-mongo
services:
  mongo:
    image: mongo:8.0
    container_name: shared-mongo
    # --replSet is mandatory: a single node replica set so change streams and
    # transactions work. bind_ip_all lets the host reach it.
    command: ["mongod", "--replSet", "rs0", "--bind_ip_all"]
    ports:
      - "27017:27017"
    volumes:
      - data:/data/db
volumes:
  # fixed shared name; deterministic so a manual teardown can target it exactly
  data:
    name: shared-mongo-data
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
# smoke test could connect before a PRIMARY exists. Block here to keep `make up`
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
# Build surface: Makefile targets and package.json scripts. The drop database
# name and help banner are parameterised; only constant scripts are carried.
# ---------------------------------------------------------------------------
step "build surface (Makefile, package.json)"

write_file "$DIR/Makefile" <<EOF
# help is the default goal so a bare \`make\` documents the project
.DEFAULT_GOAL := help

.PHONY: help up start seed down drop test test-unit test-integration lint typecheck graph graph-viz

help: ## List available targets
	@echo "${NAME} - available targets:"
	@echo ""
	@echo "  help        Show this list"
	@echo "  up          Start the shared mongod (idempotent) and ensure the replica set"
	@echo "  start       Run the entry point (src/server/index.ts)"
	@echo "  seed        Generate and load faker seed data"
	@echo "  down        Stop the shared mongod, keep data (affects every project)"
	@echo "  drop        Drop this project's database (${DB_NAME}) only"
	@echo "  test-unit   Run the unit tier (no database needed)"
	@echo "  test-integration  Run the integration tier (needs Mongo up)"
	@echo "  test        Run unit then integration, in that order"
	@echo "  lint        Run eslint over src"
	@echo "  typecheck   Type-check without emitting (tsc --noEmit)"
	@echo "  graph       Rebuild the knowledge graph (code + docs) and HTML"
	@echo "  graph-viz   Regenerate graph.html and report from the existing graph"

up: ## Start the shared mongod (idempotent) and ensure the replica set
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
	@# rs-init is a step inside up, not a separate verb: once per server, idempotent
	./scripts/rs-init.sh

start: ## Run the entry point (src/server/index.ts)
	npm start

seed: ## Generate and load faker seed data
	npm run seed

down: ## Stop the shared mongod, keep data
	@# this stops the shared container for every project, not just this one; the
	@# data survives. Deleting the shared server is a manual docker rm, never here.
	docker compose down

drop: ## Drop this project's database (${DB_NAME}) only
	@# scoped to this project's database, so the shared server and every other
	@# project's data are untouched. Same in-container path as rs-init, no host mongosh.
	docker compose exec -T mongo mongosh --quiet --eval 'db.getSiblingDB("${DB_NAME}").dropDatabase()'
	@echo "database ${DB_NAME} dropped"

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

# Frontend Makefile targets, appended only with React. A separate append (not part
# of the heredoc above) keeps the backend Makefile byte-identical when React is off.
# test-all chains everything; the base `test` stays backend-only so a backend-only
# habit still works, and test-client is the frontend tier (jsdom, no Mongo).
if [ "$WITH_REACT" = 1 ]; then
    cat >> "$DIR/Makefile" <<'EOF'

.PHONY: dev-client build-client preview test-client test-all

dev-client: ## Run the Vite dev server
	npm run dev:client

build-client: ## Production build of the client (vite build)
	npm run build:client

preview: ## Preview the production client build
	npm run preview

test-client: ## Frontend unit tier (vitest + Testing Library, jsdom; no Mongo)
	npm run test:client

# Everything: backend unit + integration, then the frontend tier.
test-all: test test-client ## Run the backend tiers then the frontend tier
EOF
fi

# React adds frontend scripts, runtime deps (react, react-dom) and dev deps (vite,
# the react plugin, RTL, jsdom). Built as JSON fragments here so the package.json
# heredoc stays valid whether or not React is on. The fragments carry their own
# leading comma so they slot in after the constant entries.
REACT_SCRIPTS=""
REACT_DEPS=""
REACT_DEV_DEPS=""
if [ "$WITH_REACT" = 1 ]; then
    REACT_SCRIPTS=',
    "dev:client": "vite",
    "build:client": "vite build",
    "preview": "vite preview",
    "test:client": "vitest run -c vitest.client.config.ts"'
    REACT_DEPS=',
    "react": "^19.0.0",
    "react-dom": "^19.0.0"'
    REACT_DEV_DEPS=',
    "@testing-library/jest-dom": "^6.6.3",
    "@testing-library/react": "^16.1.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^4.3.4",
    "jsdom": "^25.0.1",
    "vite": "^6.0.7"'
fi

write_file "$DIR/package.json" <<EOF
{
  "name": "${NAME}",
  "version": "0.1.0",
  "description": "A TypeScript MongoDB project using the native driver",
  "type": "module",
  "private": true,
  "scripts": {
    "start": "tsx src/server/index.ts",
    "seed": "tsx src/server/seed.ts",
    "test:unit": "vitest run -c vitest.unit.config.ts",
    "test:integration": "vitest run -c vitest.integration.config.ts",
    "lint": "eslint src",
    "typecheck": "tsc --noEmit",
    "format:check": "prettier --check ."${REACT_SCRIPTS}
  },
  "dependencies": {
    "mongodb": "^6.12.0"${REACT_DEPS}
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
    "vitest": "^4.1.9"${REACT_DEV_DEPS}
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

write_file "$DIR/src/server/index.ts" <<'EOF'
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

write_file "$DIR/src/server/seed.ts" <<'EOF'
import { faker } from '@faker-js/faker';
import { getDb, closeClient } from './db/index.js';

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

write_file "$DIR/src/server/index.test.ts" <<'EOF'
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
# for the life of the project, run `make up` first. This also exercises
# the db helper from birth.
write_file "$DIR/src/server/smoke.integration.test.ts" <<'EOF'
import { afterAll, describe, expect, it } from 'vitest';
import { getDb, closeClient } from './db/index.js';

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
# React client layer (only with --with-react). Vite + React under src/client/,
# a shared types tree under src/shared/, and a jsdom vitest config for the
# frontend unit tier (*.test.tsx). The client never touches Mongo: a frontend
# test that needs data mocks the API boundary, it does not reach the database.
# ---------------------------------------------------------------------------
if [ "$WITH_REACT" = 1 ]; then
    step "react client"

    write_file "$DIR/vite.config.ts" <<'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Client root is src/client so the app sits beside the server, not at repo root.
// Build output goes to dist/client to keep it clear of any backend build.
export default defineConfig({
  root: 'src/client',
  plugins: [react()],
  build: { outDir: '../../dist/client', emptyOutDir: true },
});
EOF

    # Frontend tests are unit-class (jsdom, no Mongo), a third tier beside the two
    # backend tiers. Scoped to *.test.tsx under src/client so it never picks up the
    # backend *.test.ts files (those run under the backend vitest configs).
    write_file "$DIR/vitest.client.config.ts" <<'EOF'
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['src/client/**/*.test.tsx'],
    setupFiles: ['src/client/test-setup.ts'],
  },
});
EOF

    write_file "$DIR/src/client/test-setup.ts" <<'EOF'
// Testing Library matchers (toBeInTheDocument etc.) for the jsdom frontend tier.
import '@testing-library/jest-dom/vitest';
EOF

    write_file "$DIR/src/client/index.html" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${NAME}</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="./main.tsx"></script>
  </body>
</html>
EOF

    write_file "$DIR/src/client/main.tsx" <<'EOF'
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App.js';

// Mount point. The non-null assertion is safe: index.html always ships #root.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
EOF

    write_file "$DIR/src/client/App.tsx" <<'EOF'
// The root component. Grow this into the real app: routes, state, and components
// under src/client. Data comes from the backend over its API, never from Mongo
// directly.
export function App() {
  return <h1>app starting</h1>;
}
EOF

    write_file "$DIR/src/client/App.test.tsx" <<'EOF'
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { App } from './App.js';

// Frontend unit tier (jsdom, no Mongo). Tests behaviour through the rendered
// output, not implementation details.
describe('App', () => {
  it('renders the startup heading', () => {
    render(<App />);
    expect(screen.getByRole('heading', { name: 'app starting' })).toBeInTheDocument();
  });
});
EOF

    # Shared types cross the client/server boundary. One definition, imported by
    # both sides, never duplicated.
    write_file "$DIR/src/shared/types.ts" <<'EOF'
// Types shared between the client and server. Keep API request/response shapes
// here so both sides agree on one definition.
export interface HealthResponse {
  ok: boolean;
}
EOF
fi


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
      "runtimeExecutable": "${workspaceFolder}/node_modules/.bin/tsx",
      "runtimeArgs": ["${relativeFile}"],
      "console": "integratedTerminal",
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    },
    {
      "name": "Debug current test file",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "${workspaceFolder}/node_modules/.bin/vitest",
      "runtimeArgs": [
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
      "runtimeExecutable": "${workspaceFolder}/node_modules/.bin/vitest",
      "runtimeArgs": [
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
      "runtimeExecutable": "${workspaceFolder}/node_modules/.bin/vitest",
      "runtimeArgs": [
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

## Layout
- Backend source under src/server/, the db helper at src/server/db/. A frontend, if
  added, lives under src/client/. Entry point: src/server/index.ts, run via
  \`npm start\`. Grow it into the real bootstrap (usually: connect to Mongo via
  getDb() and start the server).

## Conventions
- Stack conventions (TypeScript, Mongo, and any others) are path-scoped rules under
  .claude/rules/, installed by install-project-rules.sh and read automatically.
  Universal conventions (prose, comments) come from the global rules. This file
  carries only what is specific to THIS project: its scope and runtime facts.

## Integration endpoints
- Mongo at mongodb://127.0.0.1:27017 with directConnection=true, the shared
  container shared-mongo. This project uses database ${DB_NAME}. Readiness: a
  connect succeeds, or \`docker compose ps\` shows the mongo service up. Bring up
  with \`make up\`. The shared server is an attended prerequisite; the loop does
  not start it.
EOF

# Stub README.
write_file "$DIR/README.md" <<EOF
# ${NAME}

A TypeScript MongoDB project.

## Quick start
\`\`\`
npm install
make up            # start the shared Mongo and init the replica set
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
        # default the unborn branch to main, the branch the pipeline builds into
        # (setup proves main on the remote, the build loop PRs into main). Done via
        # symbolic-ref so it is set before the first commit and works on any git
        # version, regardless of the user's init.defaultBranch.
        git symbolic-ref HEAD refs/heads/main
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

# Stack convention rules: delegate to the installer rather than inline them, so
# there is one source of truth for the conventions and the generator never carries
# its own copy. TS + Mongo always; React too with --with-react. Runs after git init
# (the installer requires a .git). Non-fatal: a rules hiccup must not fail an
# otherwise good scaffold, so warn and continue rather than abort under set -e.
step "stack rules"
RULE_FLAGS="--typescript --mongo"
[ "$WITH_REACT" = 1 ] && RULE_FLAGS="$RULE_FLAGS --react"
rules_rc=0
# shellcheck disable=SC2086 # RULE_FLAGS is a deliberate list of flags, word-split on purpose
"$SCRIPT_DIR/install-project-rules.sh" "$DIR" $RULE_FLAGS || rules_rc=$?
if [ "$rules_rc" -ne 0 ]; then
    err "stack-rule install failed (exit $rules_rc); scaffold is fine, run install-project-rules.sh manually"
fi

# The git guards (identity + branch-name) are global via core.hooksPath, not
# seeded per project: a per-repo copy would be ignored while the global path is
# set and would drift. So we install nothing here, only nudge if it is unset.
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
echo "  make up                 # start the shared Mongo and init the replica set"
if [ "$WITH_REACT" = 1 ]; then
    echo "  make test-all           # backend unit + integration, then the frontend tier"
    echo "  make dev-client         # run the Vite dev server"
else
    echo "  make test               # unit (entry point) + integration (Mongo smoke test)"
fi
echo
echo "Then build the project: grow src/server/index.ts into the real entry point, add your"
echo "modules and their tests, write docs/deliverables.md, and run the setup gate"
echo "(project-setup.sh) to prove it loop-ready."
