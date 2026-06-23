# agent-sdlc documentation

Explains the whole system, and the place to start. The contracts under [`../contracts/`](../contracts/) are the source of truth for behaviour.

## Start here

- [`pipeline.md`](pipeline.md): the three phases and two gates, creating a project, the pipeline tooling and prerequisites.
- [`build-loops.md`](build-loops.md): the one build loop, its two modes (sequential and parallel), the per-deliverable cycle, the checkpoint, tests, recovery.
- [`roles.md`](roles.md): the four agent roles and the ordering invariant.

## Reference

- [`building-folder.md`](building-folder.md): the gitignored `.building/` workspace, what each file is.
- [`scripts.md`](scripts.md): the three shell scripts and how they connect.
- [`diagram-spec.md`](diagram-spec.md): the canonical definition of the visual set, and how to regenerate a diagram.
- [`diagrams/`](diagrams/): the SVGs.

## Templates and examples

- [`templates/ts-react-mongo.md`](templates/ts-react-mongo.md): a forward-looking roadmap for a full TypeScript / React / MongoDB monorepo template. The current generator is backend only; this page is the intended shape, not what ships today.
- [`../examples/smoke-test-sheet.md`](../examples/smoke-test-sheet.md): a one-deliverable sheet that exercises the whole build loop on a trivial case. Run it first to validate the orchestration itself.
- [`../hooks/`](../hooks/README.md): the per-commit git identity guard, the runtime half of the commit-attribution defence the setup gate also enforces.

## Contracts

The operating contracts, each a project-agnostic rulebook a project consumes by supplying its small project-specific pieces:

- [`../contracts/deliverable-sheet.schema.md`](../contracts/deliverable-sheet.schema.md): the typed design-to-build interface.
- [`../contracts/design-partner.md`](../contracts/design-partner.md): phase 1, design.
- [`../contracts/project-setup.md`](../contracts/project-setup.md): phase 2, the idempotent readiness gate.
- [`../contracts/build-judge-loop.md`](../contracts/build-judge-loop.md): phase 3, the build loop (both modes).
- [`../contracts/document-agent.md`](../contracts/document-agent.md): the document stage, a producer that never gates.
- [`../contracts/doc-payload.schema.md`](../contracts/doc-payload.schema.md): the typed payload the agents fill for the document stage.
- [`../contracts/state.schema.md`](../contracts/state.schema.md): the typed per-design state file the loop, the cross-queue scan and the reconstruction path read and write.
- [`../contracts/script-layout.md`](../contracts/script-layout.md): the canonical layout every script follows.

## Skills

The thin `/omero-*` wrappers, in [`../skills/`](../skills/). The create skill (`omero-create-ts-mongo`) runs the project generator; the pipeline skills (`omero-design-partner`, `omero-project-setup`, `omero-build-loop`) each reference a contract by path. All carry `disable-model-invocation: true`; invoke with `/omero-*`.
