# The build pipeline

Three phases, two gates. Design and setup are independent prerequisites; both must be done before build, in either order. Each produces a gate artifact, and the build loop refuses to start without both.

![The three phases and two gates](diagrams/pipeline-overview.svg)

## The three phases

1. **Design** (`/omero-design-partner`) converges a fuzzy intent into a deliverable sheet, written to `.building/design/<design-name>/deliverables.md` where `<design-name>` is a short kebab-case name you give the design. Gate: the sheet, validated against [`../contracts/deliverable-sheet.schema.md`](../contracts/deliverable-sheet.schema.md).
2. **Setup** (`/omero-project-setup`) proves the environment is buildable by running things: tooling matches, the test tiers select non-zero tests, the agent test runner is placed and works, configs are valid, git is ready. It runs `scripts/project-setup.sh`. Gate: the receipt at `.building/build/setup-ok`. Idempotent, so it doubles as a re-runnable health check.
3. **Build** (`/omero-build-loop`) delivers the sheet one increment at a time. It checks the receipt on entry, then for each deliverable runs builder, reviewer, tiered judge, document, PR, human merge. The loop runs in one of two modes, sequential-attended or parallel-attended, read from `mode` in `state.json`. See [`build-loops.md`](build-loops.md).

The two gates are independent: re-running design (a new sheet) does not invalidate the setup receipt, and a tooling change invalidates the receipt, not the sheet.

## Creating a project

A project is created by a stack-specific generator, separate from the pipeline. The generator decides the stack; the pipeline runs on whatever project exists and passes setup. This keeps the pipeline stack-agnostic: the same design, setup and build work on any project a generator produces.

`scripts/init-ts-mongo.sh` scaffolds a backend TypeScript and MongoDB project from the constant template (tooling, infra, the db helper, an entry point, a faker seed helper, conventions, then git init). It makes no domain assumptions; you grow `src/index.ts` and add your own modules. Generators are named for the stack they create, so each is honest about what it produces and more can be added without renaming.

## Pipeline tooling

Two scripts back the pipeline itself, stack-agnostic:

- `scripts/project-setup.sh` is the setup gate: it proves a project ready by execution and writes the receipt.
- `scripts/ensure-report-tooling.sh` installs and verifies the coverage tooling the judge needs.

All three scripts (the generator plus these two) follow a shared layout ([`../contracts/script-layout.md`](../contracts/script-layout.md)) and share pure-constant content through `templates/` so nothing drifts. See [`scripts.md`](scripts.md) for what each does and how they connect.

## Prerequisites for an attended run

Some prerequisites you provide; the rest the setup gate proves by execution.

You provide (the gate does not install these): the integration endpoints up (e.g. Docker and Compose running the shared Mongo, brought up with `make up`), `gh` authenticated, and a GitHub remote with main present (the gate never creates a remote).

The gate proves, by running things, and scaffolds boilerplate on consent:

- git is a repo, the remote and main are reachable, `gh` is authenticated, and the commit identity is on the allowlist.
- report tooling matches (the coverage provider is derived from the installed test runner).
- the project's declared test-tier commands select non-zero tests and pass.
- the declared integration endpoint is reachable (it runs the integration tier; a downed endpoint is reported as BLOCKED, not a failure).
- `.building` is gitignored.

## External tooling

Most tooling is project-level, not installed by hand: a generated project lists vitest, typescript, eslint, prettier, tsx and the MongoDB driver in its package.json, and `npm install` plus the setup gate bring and prove them.

One optional external tool is referenced by generated projects but is not required by the pipeline. The scaffolded Makefile carries `graph` and `graph-viz` targets that call [graphify](https://github.com/safishamsi/graphify), a local-first codebase knowledge-graph tool pinned to a local Ollama backend. The build loop never invokes it; the targets are a convenience for exploring a project as a graph. Without graphify those two Make targets are the only thing that will not run. Install is `uv tool install graphifyy` (note the double y in the package name; the CLI command is still `graphify`).
