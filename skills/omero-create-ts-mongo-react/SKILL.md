---
name: omero-create-ts-mongo-react
description: Scaffold a new full-stack TypeScript + MongoDB + React project. Backend under src/server (db helper at src/server/db), React + Vite client under src/client, shared types under src/shared. Single package, not a monorepo. Inits git and installs the TypeScript, Mongo, and React stack rules. Every project shares one mongod (shared-mongo, port 27017) as its own database.
disable-model-invocation: true
argument-hint: "<project-name> [target-dir] [--verbose]"
allowed-tools: Bash({{SDLC_REPO}}/scripts/init-ts-mongo-react.sh:*), Bash(git:*), Read
---
Create a new full-stack TypeScript + MongoDB + React project by running the generator:
    {{SDLC_REPO}}/scripts/init-ts-mongo-react.sh $ARGUMENTS
This is the full-stack counterpart to /omero-create-ts-mongo. It is a thin wrapper
over the backend generator with the React layer added, so the backend half has one
source of truth and never drifts. It scaffolds the backend (src/server, db helper at
src/server/db), a React + Vite client (src/client) with a jsdom test tier, a shared
types tree (src/shared), then inits git and installs the TypeScript, Mongo, and React
stack rules into the project's .claude/rules/. Single package, not a monorepo, so the
stack rules' directory globs bind cleanly.
Pass the project name (kebab-case) and optionally a target directory and flags.
On success it prints the created project and the next steps (npm install, make up,
make test-all, make dev-client). Report those to the user. On a non-zero exit, report
the error line it printed (a name that is not kebab-case, a target that already exists,
or a missing template) so the user can correct and re-run.
This is the create step, separate from the pipeline. After the project exists, the
user runs /omero-project-setup to prove it ready, then /omero-design-partner and
/omero-build-loop. Do not run those here; this skill only creates the project.
