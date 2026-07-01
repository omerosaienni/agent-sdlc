# TS / React / MongoDB project template

> Shipped. `scripts/init-ts-project.sh --mongo --react` generates this. The
> generator is layered (a TypeScript base plus optional Mongo and React layers), so
> the full-stack project is just all three layers enabled and there is one source of
> truth per layer. Single package, NOT a monorepo: one package.json, one tsconfig,
> source split by directory under `src/`.

The constant skeleton for a TypeScript + React + MongoDB project, plus the parts
that change per project. The base and Mongo layers are exactly what
`init-ts-project.sh --mongo` produces; the React layer adds the client and common
trees, a Vite config, a jsdom test tier, and the frontend dependencies.

Single package, not a monorepo, on purpose: the stack convention rules are
path-scoped by directory (`omero-mongo.md` -> `src/server/db/**`, `omero-react.md`
-> `src/client/**`). A directory glob binds cleanly on one source tree, with no
workspace tooling to maintain.

---

## Layout (single package)

```
<project>/
  Makefile                       constant (backend targets; React adds frontend targets)
  docker-compose.yml             constant (shared-mongo, single-node replica set)
  CLAUDE.md                      domain scope + runtime facts (conventions live in .claude/rules)
  .graphifyignore                constant (config exclusions)
  .gitignore                     constant (includes .claude/, dist/)
  .github/workflows/ci.yml       constant shape (layer-aware: +integration with Mongo, +client with React)
  package.json                   constant shape (React adds client scripts + deps)
  tsconfig.json                  constant (React adds jsx + DOM libs)
  vite.config.ts                 constant, React only (client root src/client)
  vitest.unit.config.ts          constant (backend unit, *.test.ts)
  vitest.integration.config.ts   constant (backend integration, *.integration.test.ts)
  vitest.client.config.ts        constant, React only (frontend jsdom, *.test.tsx)
  config/
    services.yaml                constant shape (mongo and client ports + addresses, one block per layer)
  .env                           gitignored, generated from config/services.yaml by make config
  scripts/
    rs-init.sh                   constant (idempotent replica set init)
    config-env.sh                constant (turns config/services.yaml into .env)
  src/
    server/                      Node + Mongo backend
      db/index.ts                constant pattern (one shared client, getDb/closeClient)
      index.ts                   entry point (grow into the real bootstrap)
      seed.ts                    domain (what this project seeds)
      index.test.ts              backend unit tier
      smoke.integration.test.ts  backend integration tier
    client/                      React + Vite (React only)
      index.html                 constant (the mount page)
      main.tsx                   constant (mounts App into #root)
      App.tsx                    domain (grow into the real app)
      App.test.tsx               frontend tier (jsdom + Testing Library)
      test-setup.ts              constant (RTL matchers)
    common/                      types crossing the client/server boundary (React only)
      types.ts                   domain (the common types)
  .claude/rules/                 stack rules (TypeScript, Mongo, React); gitignored
  docs/
    ARCHITECTURE.md              domain
    modules/                     domain (per-increment docs)
  graphify-out/                  gitignored, generated
  .building/                     gitignored, loop working folder
```

---

## Constant vs domain (the inventory)

### Constant (the generator provides, do not re-derive)

**Infra / tooling**
- docker-compose.yml (shared-mongo, single-node replica set, shared named volume)
- scripts/rs-init.sh (idempotent, polls for PRIMARY; run by `make db-start`, once per server)
- config/services.yaml + scripts/config-env.sh: the ports and addresses (one block per
  layer), turned by `make config` into a gitignored `.env` the Vite client and docker
  compose read, so ports live in one file (the code defaults match the YAML)
- The Makefile target set (backend always; frontend targets with React)
- The three vitest configs and the suffix convention (`*.test.ts` backend unit,
  `*.integration.test.ts` backend integration, `*.test.tsx` frontend)
- graphify: the `.graphifyignore` exclusions and the `make graph`/`graph-viz` targets
- The CI workflow `.github/workflows/ci.yml` (layer-aware: lint, format, typecheck and
  unit always; an integration job with Mongo; a client job with React)
- package.json (one package; React adds client scripts and the react/vite/RTL deps)
- tsconfig base (strict; React adds `jsx: react-jsx` and the DOM libs), eslint, prettier
- vite.config.ts (client root `src/client`, build to `dist/client`)

**Patterns (code shape, not code)**
- db helper: one shared MongoClient per process, `getDb`/`closeClient`, never connect
  per query. Lives at `src/server/db/index.ts`.
- A runnable module (a seed, an example, a script) uses an npm script and an
  `import.meta.url` main-guard so it runs when invoked directly but stays importable
  from tests.
- Test tier rule: a backend test that touches Mongo is the integration tier, never
  the unit tier. Frontend tests never touch Mongo; if one needs backend data it mocks
  the API boundary, it does not reach the database.
- Common types live in `src/common`, imported by both sides, never duplicated.

**Conventions (path-scoped rules in `.claude/rules/`, not CLAUDE.md)**
- These are installed by `install-project-rules.sh` (`--typescript --mongo --react`),
  not inlined. See [docs/project-rules.md](../project-rules.md). CLAUDE.md carries only
  this project's scope and runtime facts.

### Domain (changes per project, the template leaves holes)

- The collections (names + interfaces; introduce a COLLECTIONS registry as the
  project grows, so names come from a constant rather than hardcoded strings)
- seed.ts (what this project seeds, the counts, the shapes)
- Example modules and their npm scripts
- The frontend app (components, routes, state) under src/client
- The common types' actual content under src/common
- The feature sheet at `.building/features/<feature-name>/increments.md`,
  `docs/ARCHITECTURE.md`, module docs
- CLAUDE.md's scope section (what this project is and is not)

---

## Makefile targets

The backend targets are always present; the frontend targets are appended only with
React.

Targets are grouped by service (`db`, `server`, `client`), each named
`<service>-<action>`, mirroring the package.json `<service>:<action>` scripts.

```make
# ---- db (shared Mongo) ----
db-start           ## Start the shared mongod (idempotent) and ensure the replica set
db-stop            ## Stop the shared mongod, keep data (affects every project)
db-drop            ## Drop this project's database only
db-seed            ## Generate and load faker seed data

# ---- server ----
server-start             ## Start the entry point (src/server/index.ts)
server-test-unit         ## Server unit tier (no external services)
server-test-integration  ## Server integration tier (needs db up)

# ---- client (React only) ----
client-start       ## Start the Vite client
client-test-unit   ## Frontend unit tier (vitest + Testing Library, jsdom)

# ---- tests (cross-service) ----
test               ## Server tier(s): unit then integration
test-all           ## Server tier(s) then the client tier

# ---- quality + graph ----
lint               ## eslint over src
typecheck          ## tsc --noEmit (covers server, client, common under one tsconfig)
format             ## prettier --write (format the repo)
format-check       ## prettier --check (CI-friendly, no writes)
check              ## All quality gates: format-check, lint, typecheck, test
graph / graph-viz  ## Knowledge graph (graphify)

# ---- config ----
config             ## Regenerate .env from config/services.yaml
```

`typecheck` runs one `tsc --noEmit` over the whole `src` tree (server, client, and
common), so a strict-mode type error anywhere is caught even though the test tiers
run through esbuild/tsx (which strip types). This is the project-level form of the
judge's type-check gate.

---

## Test tiers (three with React, two without)

1. backend unit (no Mongo): `*.test.ts` under `src/server`
2. backend integration (needs Mongo): `*.integration.test.ts` under `src/server`
3. frontend unit (jsdom + Testing Library): `*.test.tsx` under `src/client`

The "Mongo-touching test is the integration tier" rule holds on the backend.
Frontend tests never touch Mongo; if a frontend test needs backend data it mocks the
API boundary.

---

## How this plugs into the existing system

- **Stack rules**: the generator installs `omero-typescript.md`, `omero-mongo.md`, and
  `omero-react.md` into `.claude/rules/` via `install-project-rules.sh`. See
  [docs/project-rules.md](../project-rules.md).
- **Setup gate** (`project-setup.sh`): proves the project loop-ready the same way it
  does for a backend project. The monorepo provisioning idea (the gate laying down the
  skeleton) is not built; the generator is how a project gets the skeleton.
- **Build-loop contract**: unchanged. The judge gates the backend unit and integration
  tiers; the frontend tier is an extra unit-class tier the judge does not run, gated
  instead by the generated CI workflow's `client` job on every PR into main.

---

## Relationship to the other stack combinations

This full-stack project is `init-ts-project.sh --mongo --react`. It is not a separate
generator: the base, Mongo, and React layers are the same ones every other
combination uses (`scripts/generator/base.sh`, `scripts/generator/mongo.sh`, `scripts/generator/react.sh`),
so there is no separate full-stack definition to drift. React is purely additive on
top of the base (and Mongo, if enabled): the `src/client` and `src/common` trees, the
Vite and client-vitest configs, the frontend package.json entries and tsconfig
jsx/DOM additions, the frontend Makefile targets, and the `--react` stack rule.
