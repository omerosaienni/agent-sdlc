# TS / React / MongoDB project template

> Roadmap, not shipped. This describes the intended full monorepo template. The
> generator that exists today (`scripts/init-ts-mongo.sh`) is backend only. Treat
> this page as the target shape to grow toward, not a description of the current
> generator output.

The constant skeleton for a TypeScript + React + MongoDB monorepo, plus the
parts that change per project. Start a new project from the constant layer and
grow the template as each project teaches you what else is constant.

This is a v1 extracted from mongo-db-1 (backend) plus the known-wanted React
layer. Treat it as living: when the next project copies a section unchanged, it
is confirmed constant; when it changes a section, that section is domain, move
it out of the constant layer here.

---

## Layout (monorepo)

```
<project>/
  Makefile                 constant (target set below)
  docker-compose.yml       constant (shared-mongo, single-node replica set)
  CLAUDE.md                mostly constant (conventions) + domain (this project's scope)
  .graphifyignore          constant (config exclusions)
  .gitignore               constant base + domain additions
  package.json             root: workspaces + shared scripts (constant shape)
  scripts/
    rs-init.sh             constant (idempotent replica set init)
  packages/
    backend/               Node + Mongo
      src/
        db.ts              constant pattern (one shared client, getDb/closeClient)
        collections.ts     constant pattern (COLLECTIONS registry) + domain (the collections)
        seed.ts            domain (what this project seeds)
        examples/          domain (ex:<feature> modules)
      vitest.unit.config.ts         constant (suffix glob)
      vitest.integration.config.ts  constant (suffix glob)
    frontend/              React + Vite
      src/                 domain (the app)
      vitest.config.ts     constant (RTL + jsdom)
      vite.config.ts       constant base + domain
    shared/               cross-cutting TS types shared front<->back
      src/                 domain (the shared types) + constant (the workspace wiring)
  docs/
    deliverables.md        domain (this project's sheet) — schema is constant (in sdlc repo)
    ARCHITECTURE.md        domain
    modules/               domain (per-deliverable docs)
  graphify-out/            gitignored, generated
  .building/               gitignored, loop working folder
```

---

## Constant vs domain (the inventory)

### Constant (template provides, do not re-derive)

**Infra / tooling**
- docker-compose.yml (shared-mongo, Mongo 8, single-node replica set, shared named volume)
- scripts/rs-init.sh (idempotent, polls for PRIMARY; run by make up, once per server)
- The full Makefile target set (below)
- vitest tier configs and the suffix convention (`*.test.ts` unit, `*.integration.test.ts` integration)
- graphify: the `graphify.mf` Ollama model, `.graphifyignore` config exclusions, and the `make graph`/`graph-viz` targets
- Root package.json workspace wiring (front / back / shared)
- tsconfig base (strict), eslint, prettier config

**Patterns (code shape, not code)**
- db helper: one shared MongoClient per process, `getDb`/`closeClient`, never connect per query
- COLLECTIONS registry: collection names come from a constant, never hardcoded strings
- Example module pattern: `src/examples/<feature>.ts`, runnable via `ex:<feature>`, prints results, `import.meta.url` main-guard so importable from tests
- Test tier rule: a test that touches Mongo is integration tier, never unit; no hollow placeholder tests
- Shared types live in `packages/shared`, imported by both sides, never duplicated

**Conventions (CLAUDE.md, mostly constant)**
- British English, no em dashes, no Oxford commas, no hyphens in compound modifiers
- Strict TypeScript, no `any`, interfaces as driver generics
- async/await throughout, not raw promise chains
- Comments explain WHY not WHAT, brief, only where a non-obvious decision needs one

**Process (from the sdlc repo, already reusable)**
- deliverable-sheet schema, build-judge-loop contract, project-setup gate, identity guard

### Domain (changes per project, the template leaves holes)

- The collections themselves (names + interfaces in collections.ts)
- seed.ts (what this project seeds, the counts, the shapes)
- The `ex:<feature>` example modules and their `ex:*` npm scripts
- The frontend app (components, routes, state)
- The shared types' actual content
- the design sheet at `.building/design/<design-name>/deliverables.md` (this project's sheet), `docs/ARCHITECTURE.md`, module docs
- CLAUDE.md's scope section (what this project is and is not)

---

## Full Makefile target set (monorepo)

mongo-db-1 had the backend half. A monorepo TS/React/Mongo app needs the union:
backend (Mongo + test + graph), frontend (Vite), and combined (ci/lint/typecheck).
Group by side so `make test` runs everything and `make test-backend` scopes.

```make
.DEFAULT_GOAL := help

# ---- meta ----
help            ## List available targets

# ---- infra (backend, shared Mongo) — constant ----
up              ## Start the shared mongod (idempotent) and ensure the replica set
down            ## Stop the shared mongod, keep data (affects every project)
drop            ## Drop this project's database only

# ---- backend dev/build — constant ----
dev-backend     ## Run the backend in watch mode (tsx watch)
build-backend   ## Type-check and compile the backend

# ---- frontend dev/build (React/Vite) — constant ----
dev-frontend    ## Run the Vite dev server
build-frontend  ## Production build (vite build)
preview         ## Preview the production frontend build

# ---- combined dev — constant ----
dev             ## Run backend + frontend together (concurrently)
build           ## Build backend + frontend

# ---- tests, backend — constant ----
test-unit          ## Backend unit tier (no database)
test-integration   ## Backend integration tier (needs Mongo up)
test-backend       ## Backend: unit then integration

# ---- tests, frontend — constant ----
test-frontend      ## Frontend unit tests (vitest + RTL, jsdom)
# test-e2e         ## (optional later) Playwright end-to-end

# ---- tests, combined — constant ----
test            ## Everything: backend (unit+integration) then frontend

# ---- quality gates — constant ----
typecheck       ## tsc --noEmit across all workspaces
lint            ## eslint across all workspaces
format          ## prettier --write
ci              ## typecheck + lint + test (the full gate, what CI runs)

# ---- knowledge graph (graphify) — constant ----
graph           ## Rebuild the knowledge graph (code + docs) and HTML
graph-viz       ## Regenerate graph.html and report from the existing graph

# ---- domain (per project) ----
seed            ## Generate and load seed data        (domain: npm run seed)
# ex:<feature>  ## Example modules                     (domain, one per feature)
```

### Notes on the new (non-mongo-db-1) targets

- **dev / dev-backend / dev-frontend**: mongo-db-1 is backend-only so it never
  needed these. The monorepo runs both sides; `dev` uses `concurrently` (or
  `npm-run-all -p`) to bring up backend watch + Vite together.
- **build / build-backend / build-frontend**: the frontend has a real build step
  (Vite); the backend may compile or run via tsx. `build` does both.
- **test-frontend**: React component tests are a third tier alongside the two
  backend tiers. They use jsdom + Testing Library, run via the frontend's own
  vitest config. They are unit-class (no Mongo), so they never touch the
  integration endpoint.
- **typecheck / lint / format / ci**: cross-workspace quality gates. `ci` is the
  single command a human or pipeline runs to prove the whole repo green. The
  setup gate's checks overlap with `ci`, keep them consistent.
- **graph / graph-viz**: constant, already designed. Code auto-refreshes via the
  post-commit hook; `make graph` refreshes docs (LLM) and rebuilds the HTML.

### Test tiers in a monorepo (three, not two)

1. backend unit (no Mongo) — `*.test.ts` under packages/backend
2. backend integration (needs Mongo) — `*.integration.test.ts` under packages/backend
3. frontend unit (jsdom + RTL) — `*.test.tsx` under packages/frontend

The "Mongo-touching test is integration tier" rule still holds on the backend.
Frontend tests never touch Mongo; if a frontend test needs backend data it mocks
the API boundary, it does not reach into the database.

---

## How this plugs into the existing system

- **Setup gate** (`project-setup.sh`): once the template is proven on a second
  project, the gate can lay down the constant skeleton (Makefile, vitest configs,
  db helper, docker-compose, graphify wiring) for a new repo, the same way it now
  checks identity. Until then, copy the skeleton by hand and note what you change.
- **Build-loop contract**: a graphify orientation rule (query the graph before
  reading files wholesale) is NOT currently in the build-judge-loop contract. If
  you want every project's agents to use the graph, add it there deliberately
  rather than assuming it is already present.
- **graphify.mf model**: machine-level, lives in the ollama repo with the
  interactive-vs-batch-model note. Reused by every project, not per-repo.

---

## Growing the template

This is v1 from one and a half projects (mongo-db-1 backend + known React intent).
The discipline: build the next project by copying this skeleton, and watch the
diff. Sections copied unchanged are confirmed constant. Sections you edit are
domain, move them out of the constant layer here. After two real projects the
template is battle-tested rather than assumed, and that is the point to wire it
into the setup gate as automatic provisioning.
