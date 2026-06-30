# agent-sdlc documentation

Explains the whole system, and the place to start. The contracts under [`../contracts/`](../contracts/) are the source of truth for behaviour.

## Start here

- [`pipeline.md`](pipeline.md): the three phases and two gates, creating a project, the pipeline tooling and prerequisites.
- [`build-loops.md`](build-loops.md): the one build loop, its two modes (sequential and parallel) and two profiles (full and lite), the per-increment cycle, the checkpoint, tests, recovery.
- [`roles.md`](roles.md): the four agent roles and the ordering invariant.

## Reference

- [`building-folder.md`](building-folder.md): the gitignored `.building/` workspace, what each file is.
- [`scripts.md`](scripts.md): the pipeline shell scripts (the generator, the setup gate, the report helper, the sheet validator) and how they connect.
- [`script-layout-guide.md`](script-layout-guide.md): the human rationale behind the script-layout contract, with the worked reference example.
- [`project-rules.md`](project-rules.md): the two rule layers (global conventions and per-project stack rules), the installers and the path-scoping.
- [`diagrams/`](diagrams/): the SVGs, embedded in the pages above.

## Templates and examples

- [`templates/ts-react-mongo.md`](templates/ts-react-mongo.md): the full TypeScript / React / MongoDB project `init-ts-project.sh --mongo --react` produces (a single-package layout, not a monorepo), and what is constant versus domain.
- [`../examples/smoke-test-sheet.md`](../examples/smoke-test-sheet.md): a one-increment sheet that exercises the whole build loop on a trivial case. Run it first to validate the orchestration itself.
- [`../hooks/`](../hooks/README.md): the global git guards (commit identity and branch naming), installed via `setup-global-git-hooks.sh`.

## Contracts

The operating contracts, each a project-agnostic rulebook a project consumes by supplying its small project-specific pieces:

- [`../contracts/increment-sheet.schema.md`](../contracts/increment-sheet.schema.md): the typed design-to-build interface.
- [`../contracts/design-partner.md`](../contracts/design-partner.md): phase 1, design.
- [`../contracts/project-setup.md`](../contracts/project-setup.md): phase 2, the idempotent readiness gate.
- [`../contracts/build-judge-loop.md`](../contracts/build-judge-loop.md): phase 3, the build loop's profile-agnostic orchestration core (both modes).
- [`../contracts/judge.md`](../contracts/judge.md): phase 3, the judge's verification spec (test tiers, integration endpoints, the type-check and hollow-test gates), read alongside build-judge-loop.md.
- [`../contracts/agent-runner.md`](../contracts/agent-runner.md): the exit-code contract every stack's agent runners honour, so one shared hollow-check runner serves all stacks.
- [`../contracts/build-loop-full.md`](../contracts/build-loop-full.md): the full profile (default), integration-tested and documented per increment.
- [`../contracts/build-loop-lite.md`](../contracts/build-loop-lite.md): the lite profile, integration and documentation deferred to a completion gate.
- [`../contracts/document-agent.md`](../contracts/document-agent.md): the document stage, a producer that never gates.
- [`../contracts/doc-payload.schema.md`](../contracts/doc-payload.schema.md): the typed payload the agents fill for the document stage.
- [`../contracts/state.schema.md`](../contracts/state.schema.md): the typed per-feature state file the loop, the cross-queue scan and the reconstruction path read and write.
- [`../contracts/script-layout.md`](../contracts/script-layout.md): the canonical layout every script follows (rationale in [`script-layout-guide.md`](script-layout-guide.md)).

## Skills

The thin `/omero-*` wrappers, in [`../skills/`](../skills/). `omero-create-ts-project` runs the TypeScript project generator (TypeScript base, optional `--mongo`, `--react` and `--express` layers) and `omero-create-python-project` runs the Python generator (src-layout, uv, pytest, strict pyright); `omero-install-project-rules` installs stack rules into a repo and `omero-install-global-rules` runs the once-per-machine global setup (symlinks the global rules and installs the git guards); the pipeline skills (`omero-design-partner`, `omero-setup-project`, `omero-build-full`) each reference a contract by path. All carry `disable-model-invocation: true`; invoke with `/omero-*`.
