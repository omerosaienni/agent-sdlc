#!/usr/bin/env bash
# generator/mongo.sh - the optional MongoDB layer (--mongo). Sourced by
# init-ts-project.sh. Writes the Mongo-exclusive files (db helper, docker infra, the
# integration tier and its config, the seed helper) and exports fragment variables
# the orchestrator splices into the shared files (package.json, tsconfig include,
# Makefile, CLAUDE.md). Expects DIR, NAME, DB_NAME and the lib helpers in scope.
#
# Mongo model: every project shares one mongod container (shared-mongo, fixed port
# 27017, replica set rs0). A project lives in its own database inside it, named
# after the project. The compose is identical in every project, so the first to run
# `make up` creates the container and later projects reuse it.

mongo_layer() {
    step "database helper"

    # At src/server/db/index.ts so the db layer is a folder (importable as
    # './db/index.js' from src/server, and the directory the Mongo stack rule scopes to).
    write_file "$DIR/src/server/db/index.ts" <<EOF
import { MongoClient, type Db } from 'mongodb';

// Host and port come from config/services.yaml via scripts/config-env.sh (which
// writes .env). The defaults are the shared-mongo container on loopback and MUST
// match services.yaml; MONGO_HOST and MONGO_PORT override them (a non-default port
// points at a dedicated mongod rather than the shared one).
const HOST = process.env.MONGO_HOST ?? '127.0.0.1';
const PORT = process.env.MONGO_PORT ?? '27017';
// directConnection=true is required: a single node replica set advertises its
// internal container hostname, which the host cannot follow, so the driver must be
// told not to chase that advertisement and to stay on the configured host.
const URI = \`mongodb://\${HOST}:\${PORT}/?directConnection=true\`;

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
    command: ['mongod', '--replSet', 'rs0', '--bind_ip_all']
    # Host port from config/services.yaml (compose reads MONGO_PORT from the .env
    # that config-env.sh writes; defaults to 27017, the shared port). The container
    # side stays 27017. A non-default host port is a dedicated mongod, not shared.
    ports:
      - '${MONGO_PORT:-27017}:27017'
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

    step "integration tier and seed"

    # Integration tier config from the shared template, like the unit config, so the
    # generator and the setup gate never drift.
    copy_template vitest.integration.config.ts "$DIR/vitest.integration.config.ts"

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

    # Generic Mongo smoke test (integration tier). Not tied to any domain or to the
    # entry point's logic, it verifies the infrastructure: the app's own connection
    # path reaches a healthy single node replica set with a PRIMARY. Run `make up`
    # first. This also exercises the db helper from birth.
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
  it('reports a PRIMARY member', async () => {
    // Connect exactly as the rest of the app will, through the shared helper,
    // so this fails if mongod is down OR the replica set was never initiated.
    const db = await getDb();
    const status = (await db.admin().command({ replSetGetStatus: 1 })) as ReplSetStatus;
    expect(status.set).toBe('rs0');
    const states = status.members.map((m) => m.stateStr);
    expect(states).toContain('PRIMARY');
  }, 15000);
});
EOF

    # An extra VS Code debug config for the integration tier (Mongo must be up).
    # Appended to the base launch.json via a node one-liner so the JSON stays valid.
    node -e '
      const fs = require("fs");
      const p = process.argv[1] + "/.vscode/launch.json";
      const j = JSON.parse(fs.readFileSync(p, "utf8"));
      j.configurations.push({
        name: "Debug integration tier (Mongo must be up)",
        type: "node",
        request: "launch",
        runtimeExecutable: "${workspaceFolder}/node_modules/.bin/vitest",
        runtimeArgs: ["run", "-c", "vitest.integration.config.ts", "--no-file-parallelism"],
        console: "integratedTerminal",
        skipFiles: ["<node_internals>/**"],
        cwd: "${workspaceFolder}",
      });
      fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
    ' "$DIR"
    note "added integration-tier debug config"

    # ---- fragments the orchestrator splices into the shared files ----

    # package.json: the mongodb runtime dep and the seed + integration-tier scripts.
    # Leading commas so they slot in after the base entries.
    MONGO_DEPS=',
    "mongodb": "^6.12.0"'
    MONGO_SCRIPTS=',
    "seed": "tsx --env-file-if-exists=.env src/server/seed.ts",
    "test:integration": "vitest run -c vitest.integration.config.ts"'

    # config/services.yaml fragment: the Mongo address and port. config-env.sh turns
    # this into MONGO_HOST/MONGO_PORT, read by the db layer and the compose mapping.
    MONGO_YAML="# the shared mongod (db layer + docker compose)
mongo:
  host: 127.0.0.1
  port: 27017
"

    # CLAUDE.md section documenting the runtime endpoint (this project's DB facts).
    MONGO_CLAUDE_MD="

## Integration endpoints

- Mongo at mongodb://127.0.0.1:27017 with directConnection=true, the shared
  container shared-mongo. The host and port come from the mongo block of
  config/services.yaml (defaults to 127.0.0.1:27017). This project uses database
  ${DB_NAME}. Readiness: a connect succeeds, or \`docker compose ps\`
  shows the mongo service up. Bring up with \`make up\`. The shared server is an
  attended prerequisite; the loop does not start it."

    # Makefile fragment: the infra and integration targets, plus the help lines for
    # them. The orchestrator appends MONGO_MAKE_TARGETS after the base targets and
    # weaves MONGO_MAKE_HELP into the help block.
    MONGO_MAKE_HELP='	@echo "  up          Start the shared mongod (idempotent) and ensure the replica set"
	@echo "  seed        Generate and load faker seed data"
	@echo "  down        Stop the shared mongod, keep data (affects every project)"
	@echo "  drop        Drop this project'"'"'s database ('"${DB_NAME}"') only"
	@echo "  test-integration  Run the integration tier (needs Mongo up)"'

    MONGO_MAKE_TARGETS="
.PHONY: up down drop seed test-integration

up: ## Start the shared mongod (idempotent) and ensure the replica set
	docker compose up -d
	@echo \"waiting for mongod to accept connections...\"
	@for i in \$\$(seq 1 30); do \\
		if docker compose exec -T mongo mongosh --quiet --eval 'db.runCommand({ ping: 1 }).ok' 2>/dev/null | grep -q 1; then \\
			echo \"mongod is up\"; \\
			exit 0; \\
		fi; \\
		sleep 1; \\
	done; \\
	echo \"mongod did not become ready\" >&2; \\
	exit 1
	./scripts/rs-init.sh

seed: ## Generate and load faker seed data
	npm run seed

down: ## Stop the shared mongod, keep data
	docker compose down

drop: ## Drop this project's database (${DB_NAME}) only
	docker compose exec -T mongo mongosh --quiet --eval 'db.getSiblingDB(\"${DB_NAME}\").dropDatabase()'
	@echo \"database ${DB_NAME} dropped\"

test-integration: ## Run the integration tier (needs Mongo up)
	npm run test:integration"

    # CI job fragment spliced into .github/workflows/ci.yml after the base jobs. The
    # integration tier on a real mongod: make up brings up the shared container and
    # initialises the replica set, seed proves the faker-to-Mongo path, then the
    # tier runs. Leading blank line keeps it apart from the base jobs.
    MONGO_CI_JOB='

  integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      # reuse make up (compose + rs-init to a PRIMARY) rather than re-encoding the
      # replica set in YAML; seed then proves the faker-to-Mongo path before the tier
      - run: make up
      - run: npm run seed
      - run: npm run test:integration'
}
