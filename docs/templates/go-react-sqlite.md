# Go / React / SQLite project template

> Shipped. `scripts/init-go-project.sh --sqlite --react --http` generates this. The
> generator is layered (a Go base plus optional SQLite, React and HTTP layers), so
> the full-stack project is just all four enabled and there is one source of truth
> per layer. One Go module, NOT a monorepo: one `go.mod`, source split by directory
> under `internal/`, with the client a separate Node package under `client/` that is
> a BUILD dependency only.

The constant skeleton for a Go + React + SQLite project, plus the parts that change
per project. This is the shrink-wrap shape: the shipped artefact is a single binary
with the client compiled into it, no Docker, no Node runtime, no database server and
no C toolchain.

---

## Layout (one module)

```
<project>/
  Makefile                       constant (build/quality/test; layers add their groups)
  CLAUDE.md                      domain scope + runtime facts (conventions live in .claude/rules)
  .gitignore                     constant (bin/, *.db, client/node_modules, .env, .claude/)
  .github/workflows/ci.yml       constant shape (layer-aware: +integration with SQLite, +client with React)
  go.mod                         the stack MARKER the setup gate detects
  config/
    services.yaml                constant shape (server and client ports, one block per layer)
  .env                           gitignored, generated from config/services.yaml by make config
  scripts/
    config-env.sh                constant (turns config/services.yaml into .env)
  cmd/<app>/
    main.go                      entry point; the ONLY package main in the module
  internal/
    app/
      app.go                     domain (grow into the real application)
      app_test.go                unit tier, table-driven
    assets/
      assets.go                  constant (embed.FS over static/, the one embed point)
      assets_test.go             unit tier (the embedded client is readable)
      static/index.html          committed placeholder; make client-build overwrites it
    store/                       SQLite only
      store.go                   constant pattern (DSN, Open, Migrate, TableNames)
      seed.go                    domain (what this project seeds)
      store_test.go              unit tier (pure helpers, no file system)
      store_integration_test.go  integration tier, behind //go:build integration
    httpapi/                     HTTP only
      server.go                  constant pattern (Handler() returns http.Handler)
      server_test.go             unit tier via httptest
  client/                        React + Vite (React only); a BUILD dependency, not a runtime one
    package.json                 constant (its own Node package, not a workspace)
    vite.config.ts               constant (builds to client/dist, proxies to the binary in dev)
    tsconfig.json                constant (strict, jsx: react-jsx)
    index.html                   constant (the mount page)
    src/main.tsx                 constant (mounts App into #root)
    src/App.tsx                  domain (grow into the real app)
    src/App.test.tsx             client tier (jsdom + Testing Library)
    test-setup.ts                constant (RTL matchers)
  .claude/rules/                 stack rules (Go, React); gitignored
  .building/                     loop output; gitignored
```

## What is constant and why

**One `package main`.** `cmd/<app>/main.go` resolves configuration and starts
things; it holds no logic. Everything real is under `internal/`, which the compiler
enforces as private to this module. A second executable would be a second artefact
to ship, which the shrink-wrap constraint does not allow.

**One embed point.** `internal/assets/static/` is the only directory the binary
embeds. `make client-build` runs the Vite build to `client/dist` and syncs it in.
The Go side never changes when the client does, and the Node tree never contains a
Go package, so `go build ./...` never walks `client/node_modules`.

**The placeholder `index.html` is committed on purpose.** `//go:embed` fails at
compile time on an empty match, so without it a fresh clone would not build until
someone ran a Node build. Committing it keeps every Go-only gate (CI, the setup
gate, the judge) free of a Node dependency.

**Tiers split by build tag.** The unit tier is every untagged test; the integration
tier is the files carrying `//go:build integration`. Go co-locates tests with the
code they test, so a directory split would fight the language. See
`docs/go-build-path.md`.

**The integration tier needs nothing brought up.** It opens a temp SQLite file that
`t.TempDir()` removes, and drives handlers through `httptest`. No Docker, no
compose file, no readiness check, so the setup gate never sits in a BLOCKED state.

## The load-bearing dependency rules

These are in `project-rules/omero-go.md` so the reviewer enforces them on every
increment, not just at scaffold time:

- **No CGo.** `CGO_ENABLED=0` builds must work, or cross-compilation to Windows,
  macOS and Linux needs a C toolchain per target and the single-binary promise dies.
- **SQLite is `modernc.org/sqlite`**, the pure-Go translation. Never
  `mattn/go-sqlite3`, which is CGo and breaks the rule above. This is the single
  most consequential dependency choice in the template.
- **Prefer the standard library.** `net/http`'s `ServeMux` routes by method and path
  pattern, so a router dependency needs a reason beyond preference.

## What changes per project

- `CLAUDE.md`: the project's scope, and its integration endpoints (for this template,
  the honest answer is "none, the tier is in process").
- `internal/app/` and the packages that grow beside it: the actual domain.
- `internal/store/`: the real schema in `store.go`'s `schema` constant, and what
  `seed.go` seeds. The template ships a single `item` table as a placeholder.
- `client/src/`: the real UI. `App.tsx` is a mount point, not a design.
- `config/services.yaml`: the ports, if the defaults (binary on 8080, Vite on 5173)
  clash with something else on the machine.

## Toolchain version

`go.mod` is written with a `go` directive naming the language version the generated
code targets, not a toolchain pin. `go mod tidy` will RAISE it when a dependency
requires a newer language version (`modernc.org/sqlite` currently forces it well
above the generator's floor), and with the default `GOTOOLCHAIN=auto` the newer
toolchain is fetched transparently. That is Go's designed behaviour, so the raised
directive in a scaffolded project is expected, not drift to correct.
