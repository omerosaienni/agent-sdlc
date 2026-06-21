---
name: omero-create-ts-mongo
description: Scaffold a new backend TypeScript and MongoDB project from the constant template. Writes tooling, infra, the db helper, an entry point, conventions, then inits git. Makes no domain assumptions; you grow src/index.ts. Picks a free Mongo port so projects never collide.
disable-model-invocation: true
argument-hint: "<project-name> [target-dir] [--port N] [--verbose]"
allowed-tools: Bash(./scripts/*:*), Bash(git:*), Read
---
Create a new TypeScript and MongoDB project by running the generator:
    {{SDLC_REPO}}/scripts/init-ts-mongo.sh $ARGUMENTS
The generator is deterministic, there is no contract to interpret: it scaffolds
the constant template, parameterises the name-bearing values, picks a free Mongo
port, and inits git. Pass the project name (kebab-case) and optionally a target
directory and flags.
On success it prints the created project and the next steps (npm install, make
bootstrap, make test). Report those to the user. On a non-zero exit, report the
error line it printed (for example a name that is not kebab-case, a target that
already exists, or a missing template) so the user can correct and re-run.
This is the create step, separate from the pipeline. After the project exists,
the user runs /omero-project-setup to prove it ready, then /omero-design-partner
and /omero-build-loop. Do not run those here; this skill only creates the project.
