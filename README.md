# agent-sdlc

> Personal AI-agent build system, shared as a working reference. It runs my own
> projects and is opinionated toward my stack (TypeScript, MongoDB, vitest, GitHub).
> Published so the ideas are visible and reusable; offered as-is, with no support
> promised and no commitment to generalise it. Take what is useful. MIT licensed.

Reusable AI agent operating contracts. Each contract is a project-agnostic rulebook for how an agent works; a project consumes a contract by supplying the small project-specific pieces it leaves open. The contracts under [`contracts/`](contracts/) are written dense for an agent to read. The [`docs/`](docs/README.md) folder is the human entry point and explains the whole system.

## How it works, in one breath

Three phases, two gates. **Design** converges intent into a deliverable sheet; **setup** proves the environment buildable; **build** delivers the sheet one verified increment at a time, with four agent roles (builder, reviewer, judge, document) and a human merging every PR. Design and setup are independent prerequisites; the build loop refuses to start without both gate artifacts.

## Using it

The work is driven by four `/omero-*` skills (thin wrappers over the contracts):

1. `omero-create-ts-mongo` scaffolds a TypeScript and MongoDB project (the generator, separate from the pipeline).
2. `omero-design-partner` converges intent into a validated deliverable sheet.
3. `omero-project-setup` proves the project ready and writes the setup receipt.
4. `omero-build-loop` delivers the sheet, one deliverable per branch and PR.

The build loop runs in one of two modes, sequential-attended or parallel-attended, read from `mode` in `state.json`. They share every role, gate and the checkpoint; they differ only in what the loop offers after a PR opens. See [docs/build-loops.md](docs/build-loops.md).

## Documentation

| Page | What it covers |
| --- | --- |
| [docs/](docs/README.md) | Documentation index and contract list |
| [docs/pipeline.md](docs/pipeline.md) | The three phases and two gates, creating a project, tooling, prerequisites |
| [docs/build-loops.md](docs/build-loops.md) | The one build loop, its two modes, the checkpoint, tests, recovery |
| [docs/roles.md](docs/roles.md) | The four agent roles and the ordering invariant |
| [docs/building-folder.md](docs/building-folder.md) | The gitignored `.building/` workspace |
| [docs/scripts.md](docs/scripts.md) | The three shell scripts and how they connect |
| [docs/diagram-spec.md](docs/diagram-spec.md) | The visual set and how to regenerate a diagram |

## Posture

Attended only: the human merges every PR, and the merge is the final gate. Both build modes are attended. Unattended operation (auto-merge on a green pass) is out of scope and not built.
