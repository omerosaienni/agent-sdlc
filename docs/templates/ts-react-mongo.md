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
  package.json                   constant shape (React adds client scripts + deps)
  tsconfig.json                  constant (React adds jsx + DOM libs)
  vite.config.ts                 constant, React only (client root src/client)
  vitest.unit.config.ts          constant (backend unit, *.test.ts)
  vitest.integration.config.ts   constant (backend integration, *.integration.test.ts)
  vitest.client.config.ts        constant, React only (frontend jsdom, *.test.tsx)
  scripts/
    rs-init.sh                   constant (idempotent replica set init)
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
    modules/                     domain (per-deliverable docs)
  graphify-out/                  gitignored, generated
  .building/                     gitignored, loop working folder
```

---

## Constant vs domain (the inventory)

### Constant (the generator provides, do not re-derive)

**Infra / tooling**
- docker-compose.yml (shared-mongo, single-node replica set, shared named volume)
- scripts/rs-init.sh (idempotent, polls for PRIMARY; run by `make up`, once per server)
- The Makefile target set (backend always; frontend targets with React)
- The three vitest configs and the suffix convention (`*.test.ts` backend unit,
  `*.integration.test.ts` backend integration, `*.test.tsx` frontend)
- graphify: the `.graphifyignore` exclusions and the `make graph`/`graph-viz` targets
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
- The design sheet at `.building/design/<design-name>/deliverables.md`,
  `docs/ARCHITECTURE.md`, module docs
- CLAUDE.md's scope section (what this project is and is not)

---

## Makefile targets

The backend targets are always present; the frontend targets are appended only with
React.

```make
# ---- infra (shared Mongo) ----
up                 ## Start the shared mongod (idempotent) and ensure the replica set
down               ## Stop the shared mongod, keep data (affects every project)
drop               ## Drop this project's database only

# ---- backend ----
start              ## Run the entry point (src/server/index.ts)
seed               ## Generate and load faker seed data
test-unit          ## Backend unit tier (no database)
test-integration   ## Backend integration tier (needs Mongo up)
test               ## Backend: unit then integration

# ---- quality + graph ----
lint               ## eslint over src
typecheck          ## tsc --noEmit (covers server, client, common under one tsconfig)
graph / graph-viz  ## Knowledge graph (graphify)

# ---- frontend (React only) ----
dev-client         ## Run the Vite dev server
build-client       ## Production build (vite build)
preview            ## Preview the production client build
test-client        ## Frontend unit tier (vitest + Testing Library, jsdom)
test-all           ## Backend tiers then the frontend tier
```

`typecheck` runs one `tsc --noEmit` over the whole `src` tree (server, client, and
common), so a strict-mode type error anywhere is caught even though the test tiers
run through esbuild/tsx (which strip types). This is the project-level form of the
judge's type-check gate.

---

## Test tiers (three with React, two without)

1. backend unit (no Mongo) — `*.test.ts` under `src/server`
2. backend integration (needs Mongo) — `*.integration.test.ts` under `src/server`
3. frontend unit (jsdom + Testing Library) — `*.test.tsx` under `src/client`

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
- **Build-loop contract**: unchanged. The frontend tier is an extra unit-class tier;
  it does not change the loop's gates.

---

## Relationship to the other stack combinations

This full-stack project is `init-ts-project.sh --mongo --react`. It is not a separate
generator: the base, Mongo, and React layers are the same ones every other
combination uses (`scripts/generator/base.sh`, `scripts/generator/mongo.sh`, `scripts/generator/react.sh`),
so there is no separate full-stack definition to drift. React is purely additive on
top of the base (and Mongo, if enabled): the `src/client` and `src/common` trees, the
Vite and client-vitest configs, the frontend package.json entries and tsconfig
jsx/DOM additions, the frontend Makefile targets, and the `--react` stack rule.
