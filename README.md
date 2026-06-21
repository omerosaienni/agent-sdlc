# agent-sdlc

> Personal AI-agent build system, shared as a working reference. It runs my own
> projects and is opinionated toward my stack (TypeScript, MongoDB, vitest, GitHub).
> Published so the ideas are visible and reusable; offered as-is, with no support
> promised and no commitment to generalise it. Take what is useful. MIT licensed.


Reusable AI agent operating contracts. Each contract is a project-agnostic rulebook for how an agent works. Projects consume a contract by supplying the small project-specific pieces it leaves open. Contracts are written dense for the agent to read; this README is the human entry point.

## The build pipeline (three phases, two gates)

The pipeline has three phases. Design and setup are independent prerequisites; both must be done before build, in either order. Each produces a gate artifact, and the build loop refuses to start without both.

1. **Design** (`/omero-design-partner`) converges a fuzzy intent into a deliverable sheet. Gate: the sheet, validated against the schema.
2. **Setup** (`/omero-project-setup`) proves the environment is buildable by running things (tooling matches, test tiers select non-zero tests, the agent test runner is placed and works, configs valid, git ready). It runs `scripts/project-setup.sh`. Gate: the receipt at `.building/build/setup-ok`. Idempotent, also a re-runnable health check.
3. **Build** (`/omero-build-loop`) delivers the sheet one increment at a time. Checks the receipt on entry, then for each deliverable: builder, reviewer, tiered judge, PR, human merge.

See [`docs/diagrams/pipeline-overview.svg`](docs/diagrams/pipeline-overview.svg) for the phase shape and [`docs/diagrams/build-judge-loop.svg`](docs/diagrams/build-judge-loop.svg) for the per-deliverable loop.

The two gates are independent: re-running design (a new sheet) does not invalidate the setup receipt, and a tooling change invalidates the receipt, not the sheet.

## Creating a project

A project is created by a stack-specific generator, separate from the pipeline below. The generator decides the stack; the pipeline runs on whatever project exists and passes setup. This keeps the pipeline stack-agnostic: the same design, setup, and build work on any project a generator produces.

- `scripts/init-ts-mongo.sh` scaffolds a backend TypeScript and MongoDB project from the constant template (tooling, infra, the db helper, an entry point, conventions, then git init). It makes no domain assumptions; you grow `src/index.ts` and add your own modules.

Generators are named for the stack they create, so each is honest about what it produces and more can be added without renaming.

## Pipeline tooling

Two scripts back the pipeline itself, stack-agnostic:

- `scripts/project-setup.sh` is the setup gate (phase 2): it proves a project ready by execution and writes the receipt.
- `scripts/ensure-report-tooling.sh` is a focused helper that installs and verifies the coverage tooling the judge needs.

All three scripts follow a shared layout ([`contracts/script-layout.md`](contracts/script-layout.md)) and share pure-constant content through `templates/` so nothing drifts. See [`docs/scripts.md`](docs/scripts.md) for what each does, how they connect, and diagrams of the generation flow and the scaffold components.

## The four roles in the build loop

- Orchestrator: passive, sequences deliverables, owns state, opens PRs.
- Builder: implements one deliverable.
- Reviewer: owns the code (conventions, architecture, scope, defects, test-tier classification). Informed context. Bounces to the builder.
- Judge: owns behaviour. Fresh context. Runs the tests itself: unit tier first, then integration tier; both must pass.

Flow: builder, then review loop (budget 3), then judge loop (budget 3, delta-review inside each cycle). No code reaches the judge without a reviewer pass (the ordering invariant). Either loop exhausting three attempts escalates. A downed integration endpoint pauses (environment block), it does not fail the deliverable.

## Where the loop keeps its work

Everything the loop generates while building (state, the agents' working files, escalation records) lives under a single gitignored folder, `.building/`. None of it is committed; your commits and PRs carry only code and docs. The structure is `.building/build/` for loop state, `.building/work/<branch-name>/` for each unit's agent files, and a `.building/escalations/` index. See [`docs/building-folder.md`](docs/building-folder.md) for the full layout and what each file is.

## Tests

Two tiers. Unit tests have no external dependencies and run anywhere; integration tests need live endpoints. One test file per module under test, co-located, tier by suffix (`<module>.test.ts`, `<module>.integration.test.ts`). Shared helpers in one support module. The judge runs unit first (cheap, fail fast), then integration. A tier that should have tests but selects zero is a hollow suite and fails.

## Contracts

- [`contracts/deliverable-sheet.schema.md`](contracts/deliverable-sheet.schema.md): the typed design-to-build interface.
- [`contracts/design-partner.md`](contracts/design-partner.md): phase 1.
- [`contracts/project-setup.md`](contracts/project-setup.md): phase 2, idempotent readiness gate.
- [`contracts/build-judge-loop.md`](contracts/build-judge-loop.md): phase 3, the main loop.
- [`contracts/document-agent.md`](contracts/document-agent.md): the document stage (producer, never gates).
- [`contracts/doc-payload.schema.md`](contracts/doc-payload.schema.md): the typed payload the agents fill for the document stage.
- [`contracts/script-layout.md`](contracts/script-layout.md): the canonical layout every script follows.
- [`contracts/parallel-build-loop.md`](contracts/parallel-build-loop.md): parallel version, parked, not deployed.

## Skills

Create skill (makes a project, separate from the pipeline): `omero-create-ts-mongo` runs the generator.
Pipeline skills (the three phases): `omero-design-partner`, `omero-project-setup`, `omero-build-loop`.
All carry `disable-model-invocation: true`; invoke with `/omero-*`. They are thin wrappers: the pipeline skills reference a contract by path; the create skill just runs its generator (deterministic, no contract). One source of truth, no drift.

## Posture

Sequential and attended only. The human merges every PR; the merge is the final gate. Parallel and unattended are designed and parked, gated on hoisting installs out of the loop and making consequential dialogs suppressible.

## Validating the loop itself

Before running a real build, exercise the orchestration on a trivial deliverable. `examples/smoke-test-sheet.md` is a one-deliverable sheet (a function returning 42 with a unit test) that runs through the whole loop quickly: branch cut, builder, reviewer, judge, document, PR, merge. If the smoke test passes cleanly, the orchestration works and you can trust it on a real sheet; if it breaks, you have found the problem on a trivial case.

## Recovery

The loop is robust to interruption and failure, and keeps the human in control at both recovery points. After an interruption (crash, closed terminal), re-running reads `state.json`, finds where it stopped, and asks before resuming; declining is safe and changes nothing. When a deliverable escalates after three failed attempts, the loop waits: you fix it on its existing branch and tell it to continue, and the fix re-enters verification from the reviewer (it is reviewed and judged, never waved through). See [`contracts/build-judge-loop.md`](contracts/build-judge-loop.md) for the full resume and escalation-recovery behaviour.

## Prerequisites for an attended run

Proven by the setup gate, which checks and reports, scaffolding boilerplate on consent and never creating remotes:
- git, a GitHub remote with main present, gh authenticated.
- Docker and Compose for container deliverables.
- Matching report tooling (coverage provider derived from the installed test runner).
- The project's declared test-tier commands and integration endpoints.

## External tooling

Most tooling is project-level, not something you install by hand: a generated project lists vitest, typescript, eslint, prettier, tsx and the MongoDB driver in its package.json, and `npm install` plus the setup gate bring and prove them. You do not pre-install those.

What your environment is expected to provide for an attended run is short: git and a GitHub remote, the gh CLI authenticated, Node and npm, and Docker with Compose for container deliverables. The setup gate checks and reports these.

One optional external tool is referenced by generated projects but is not required by the pipeline. The scaffolded Makefile carries `graph` and `graph-viz` targets that call [graphify](https://github.com/safishamsi/graphify), a local-first codebase knowledge-graph tool, pinned to a local Ollama backend. The build loop never invokes it; the targets are a convenience for exploring a project as a graph. If you do not have graphify, those two Make targets are the only thing that will not run, everything else works without it. Install is `uv tool install graphifyy` (note the double y in the package name; the CLI command is still `graphify`).

## Conventions

Conventions are defined where they are used, not restated here, so there is one source of truth:
- A generated project's coding conventions (strict TypeScript, the db-helper and COLLECTIONS patterns, the runnable-module pattern, test-tier rules) live in that project's `CLAUDE.md`, written by `init-ts-mongo.sh`.
- Script conventions (layout, colour, flags) live in [`contracts/script-layout.md`](contracts/script-layout.md).

The cross-cutting writing rules, applied everywhere: British English, no em dashes, no Oxford commas, no hyphens in compound modifiers.

## Where things live

- `contracts/` the operating contracts (above), the agent-facing source of truth.
- `scripts/` the project generator and the pipeline tooling; see [`docs/scripts.md`](docs/scripts.md).
- `templates/` pure-constant files the scripts copy, defined once.
- `docs/` human documentation: [`scripts.md`](docs/scripts.md), [`building-folder.md`](docs/building-folder.md), [`diagram-spec.md`](docs/diagram-spec.md) (the diagram catalogue), and `diagrams/` (the SVGs).
- `examples/` the smoke-test sheet for validating the loop.
- `skills/` the thin `/omero-*` skill wrappers.
