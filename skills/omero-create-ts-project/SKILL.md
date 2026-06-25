---
name: omero-create-ts-project
description: Scaffold a new TypeScript project, with optional Mongo, React and Express layers. Base is always TypeScript under src/server. Add --mongo for the MongoDB layer (db helper at src/server/db, docker infra, integration tier), --react for the React + Vite client (src/client, frontend tier) and --express for a versioned Express HTTP server (src/server/app.ts, supertest unit tests). Any combination works. Inits git and installs the matching stack rules.
disable-model-invocation: true
argument-hint: "<project-name> [target-dir] [--mongo] [--react] [--express]"
allowed-tools: Bash({{SDLC_REPO}}/scripts/init-ts-project.sh:*), Bash(git:*), Read
---
Create a new TypeScript project by running the generator:
    {{SDLC_REPO}}/scripts/init-ts-project.sh $ARGUMENTS
The generator is deterministic and layered: a TypeScript base (src/server, unit
tier, tooling) is always scaffolded, and the optional layers are added by flag.
Pass --mongo to add the MongoDB layer (the db helper at src/server/db, docker
infra, the integration tier, a faker seed), --react to add the React + Vite
client (src/client, a shared types tree, a jsdom frontend tier), and --express to
replace the stub entry point with a versioned Express HTTP server (src/server/app.ts
and its supertest unit tests; with --mongo its shutdown closes the shared client).
Any combination is valid, from TypeScript alone to all the layers together.
It inits git and installs the matching stack rules (--typescript always, plus
--mongo and/or --react) into the project's .claude/rules/, so conventions are
path-scoped rules read automatically rather than inlined in CLAUDE.md.
Pass the project name (kebab-case) and optionally a target directory and the layer
flags.
On success it prints the created project and the next steps (npm install; with
Mongo, make up; make test or make test-all). Report those to the user. On a non-zero
exit, report the error line it printed (a name that is not kebab-case, a target that
already exists, or a missing template) so the user can correct and re-run.
This is the create step, separate from the pipeline. After the project exists, the
user runs /omero-design-partner and /omero-project-setup in either order (they are
independent prerequisites: design writes the feature sheet(s), setup proves the
project environment ready), then /omero-build-loop builds the sheet. Do not run those
here; this skill only creates the project.
