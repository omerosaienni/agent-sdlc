---
name: omero-create-go-project
description: Scaffold a new Go project (a single-binary module with cmd/<app> plus internal/, an embed.FS client, and a build-tag unit/integration tier split), with optional --sqlite (pure-Go modernc driver), --react (Vite client embedded into the binary) and --http (net/http server) layers. Inits git on main and emits a layer-aware CI workflow. Sits alongside omero-create-ts-project and omero-create-python-project; the pipeline picks the stack from the project the generator produces.
disable-model-invocation: true
argument-hint: "<project-name> [target-dir] [--sqlite] [--react] [--http]"
allowed-tools: Bash({{SDLC_REPO}}/scripts/init-go-project.sh:*), Bash(git:*), Read
---
Create a new Go project by running the generator:
    {{SDLC_REPO}}/scripts/init-go-project.sh $ARGUMENTS

Deterministic. Scaffolds a single-binary Go project:
- go.mod as the stack marker, with cmd/<app>/main.go as the only executable and everything real under internal/.
- internal/assets/ embedding the static client with embed.FS, so the shipped artefact has no runtime dependency.
- A test tier split by BUILD TAG, not directory: the unit tier is every untagged test, the integration tier is the files behind //go:build integration.
- A CLAUDE.md skeleton with an Integration endpoints section, a Go .gitignore, a Makefile, and a layer-aware CI workflow running the build, vet, gofmt and unit gates on PRs into main.

Optional layers, any combination:
- --sqlite: a modernc.org/sqlite store (pure Go, never the CGo mattn/go-sqlite3) with migration, a seed helper, and an in-process integration tier against a temp database file.
- --react: a Vite client under client/, built and synced into the embedded assets. Node is a build dependency only, never a runtime one.
- --http: a net/http server with httptest unit tests, which replaces the base entry point with the server bootstrap.

Inits git on main with an initial commit. It requires a configured global git identity (git config --global user.email ...) and fails before scaffolding if none is set; it never invents an author.

Pass the project name (kebab-case); it becomes both the module path and the binary name. Optionally pass a target directory before the layer flags.

On success the generator prints the created project and the next steps (go mod tidy, make test, make build). Report those next steps to the user as printed; do NOT re-list them inline here. On a non-zero exit, report the error line it printed (a name that is not kebab-case, a target that already exists, or no git identity configured) so the user can correct and re-run.

This is the create step, separate from the pipeline. After the project exists, the user runs /omero-design-sheet (then /omero-review-sheet to review it) and /omero-setup-project in either order (independent prerequisites: design writes and reviews the feature sheet(s), setup proves the project environment ready), then /omero-build-full builds the sheet. Do NOT run those here; this skill only creates the project.
