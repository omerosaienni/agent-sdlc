# agent-sdlc

> An AI-agent build system, shared as a working reference. It is opinionated toward
> one stack (TypeScript, MongoDB, vitest, GitHub) and published so the ideas are
> visible and reusable. Offered as-is, with no support promised and no commitment to
> generalise it. Take what is useful. MIT licensed.

Reusable AI agent operating contracts. Each contract is a project-agnostic rulebook for how an agent works; a project consumes a contract by supplying the small project-specific pieces it leaves open. The contracts under [`contracts/`](contracts/) are the source of truth for behaviour, dense reference. The [`docs/`](docs/README.md) folder explains the whole system; start there.

## How it works, in one breath

Three phases, two gates. **Design** converges intent into feature sheet(s); **setup** proves the environment buildable; **build** delivers the sheet one verified increment at a time, with four agent roles (builder, reviewer, judge, document) and a human in control at every increment (merging each PR with a remote, or reviewing each local commit without one). Design and setup are independent prerequisites; the build loop refuses to start without both gate artifacts.

## Quick start

Install the skills once (idempotent; the repo is the source of truth, the installed copies are generated):

```sh
./skills/install-skills.sh
```

Then drive a project through these four `/omero-*` skills, in order:

```text
/omero-create-ts-project <project-name> [--mongo] [--react] [--express]  # 1. scaffold a TypeScript project (optional Mongo/React/Express layers)
/omero-design-partner "<intent>" <feature-name>  # 2. converge intent into feature sheet(s)
/omero-project-setup                            # 3. prove the project ready (writes the setup receipt)
/omero-build-loop <path-to-sheet>               # 4. deliver the sheet, one PR per increment (a local commit if no remote)
```

Steps 2 and 3 are independent prerequisites and can run in either order; step 4 refuses to start without both the receipt and a schema-valid sheet. The feature name is a short kebab-case label you choose, for example `gym-tracker`. To exercise the loop itself before a real build, run it against [`examples/smoke-test-sheet.md`](examples/smoke-test-sheet.md), a one-increment sheet that runs the whole orchestration on a trivial case.

## Using it

The work is driven by these four `/omero-*` skills (thin wrappers over the contracts; two more are setup helpers, `omero-install-project-rules`, which installs stack rules into a repo and is normally run for you by the generator, and `omero-install-global-rules`, which runs the once-per-machine global setup (the global rules and git guards), see [`skills/README.md`](skills/README.md)):

1. `omero-create-ts-project` scaffolds a TypeScript project, with optional Mongo, React and Express layers and a layer-aware GitHub Actions CI workflow (the generator, separate from the pipeline).
2. `omero-design-partner` converges intent into validated feature sheet(s).
3. `omero-project-setup` proves the project ready and writes the setup receipt.
4. `omero-build-loop` delivers the sheet, one increment per branch (one PR per increment with a GitHub remote, otherwise a local commit to main).

The build loop runs in one of two modes, sequential-attended or parallel-attended, read from `mode` in `state.json`. They share every role, gate and the checkpoint; they differ only in what the loop offers after a PR opens. Orthogonally it runs in one of two profiles, full (the default) or lite, read from `profile` in `state.json`: lite defers the integration tier and the documentation to a completion gate for fast iteration, while full verifies and documents every increment before it ships. See [docs/build-loops.md](docs/build-loops.md).

## Documentation

| Page | What it covers |
| --- | --- |
| [docs/](docs/README.md) | Documentation index and contract list |
| [docs/pipeline.md](docs/pipeline.md) | The three phases and two gates, creating a project, tooling, prerequisites |
| [docs/build-loops.md](docs/build-loops.md) | The one build loop, its two modes and two profiles, the checkpoint, tests, recovery |
| [docs/roles.md](docs/roles.md) | The four agent roles and the ordering invariant |
| [docs/building-folder.md](docs/building-folder.md) | The gitignored `.building/` workspace |
| [docs/scripts.md](docs/scripts.md) | The pipeline shell scripts and how they connect |

## Repository layout

| Path | What lives here |
| --- | --- |
| [`contracts/`](contracts/) | The operating contracts. The source of truth for behaviour, dense reference. |
| [`docs/`](docs/README.md) | The documentation pages and the diagrams. |
| [`skills/`](skills/README.md) | The thin `/omero-*` skill wrappers and the installer that points them at this repo. |
| [`scripts/`](scripts/) | The shell scripts: the layered project generator (and its `scripts/generator/` layers), the setup gate, the report-tooling helper, the sheet validator, the per-project rules installer and the global hooks and rules installers. |
| [`tests/`](tests/) | The repo's own test suites (one folder per script under test) and their fixtures, run by `tests/run.sh` and the tests workflow on every PR into main. |
| [`file-templates/`](file-templates/) | The shared constant files (agent runners, report and checkpoint templates, vitest configs) the scripts copy from so nothing drifts. |
| [`claude-rules/`](claude-rules/README.md) | The global Claude rules (conventions, branch naming), symlinked into `~/.claude/rules`. |
| [`project-rules/`](project-rules/README.md) | The per-project stack rule templates (TypeScript, Mongo, React), copied into a repo's `.claude/rules`. |
| [`hooks/`](hooks/README.md) | The global git guards: commit identity and branch naming. |
| [`examples/`](examples/) | The smoke-test sheet for validating the loop itself. |
| [`.github/`](.github/) | GitHub repo config: the `CODEOWNERS` file routing every change to the repo owner for review, and the `workflows/` (the tests workflow run on every PR into main). |

## Posture

Attended only: with a GitHub remote the human merges every PR, and the merge is the final gate; with no remote the build loop commits each increment to local main and the judge's pass is the gate, the human still deciding at every checkpoint. GitHub is optional: a missing remote warns and the loop continues locally, it never blocks. Both build modes are attended. Unattended operation (auto-merge on a green pass) is out of scope and not built.

## License

MIT. See [`LICENSE`](LICENSE). Offered as-is, with no support promised.
