#!/usr/bin/env bash
# init-ts-mongo-react.sh - scaffold a full-stack TypeScript + MongoDB + React
# project. A thin wrapper over init-ts-mongo.sh --with-react, so the backend half
# has exactly one source of truth and never drifts from the backend generator.
#
# Layout: src/server/ (backend, db helper at src/server/db/), src/client/ (React +
# Vite), src/shared/ (types crossing the boundary). Single package, not a monorepo,
# so the stack rules' directory globs (src/server/db/**, src/client/**) bind cleanly.
# Installs the TypeScript, Mongo, and React stack rules.
#
# Usage: same as init-ts-mongo.sh.
#   init-ts-mongo-react.sh <project-name> [target-dir] [--verbose] [--no-color] [--debug]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/init-ts-mongo.sh" --with-react "$@"
