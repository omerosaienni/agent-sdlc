#!/usr/bin/env bash
# generator/base.sh - the always-present TypeScript base layer. Sourced by
# init-ts-project.sh. Writes the exclusive base files (tooling, the entry point and
# its unit test, editor configs, the CLAUDE.md skeleton, README). The shared files
# assembled from layer fragments (package.json, tsconfig.json, Makefile) are owned
# by the orchestrator, not here. Expects DIR, NAME and the lib helpers in scope.

base_layer() {
    step "tooling configs"

    # Vitest unit tier config from the shared template (also used by the setup gate),
    # so the two never drift. The integration tier config is the Mongo layer's job.
    copy_template vitest.unit.config.ts "$DIR/vitest.unit.config.ts"

    write_file "$DIR/eslint.config.js" <<'EOF'
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  { ignores: ['dist', 'node_modules'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  // prettier last so it switches off rules that would fight the formatter
  prettier,
);
EOF

    write_file "$DIR/.prettierrc.json" <<'EOF'
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100
}
EOF

    write_file "$DIR/.gitignore" <<'EOF'
node_modules/
dist/
.claude/
# Share format-on-save and the recommended extensions; keep personal debug configs local.
.vscode/*
!.vscode/settings.json
!.vscode/extensions.json
coverage/
.building/
graphify-out/
EOF

    # Base .graphifyignore: loop output plus the config files that are noise in the
    # graph. The React layer appends its own config files (vite, vitest.client) to
    # this file so the exclusion list stays complete for the full-stack layout.
    write_file "$DIR/.graphifyignore" <<'EOF'
# loop + build output
.building/
graphify-out/
node_modules/
dist/
coverage/

# config files: not architecture, just noise in the graph
tsconfig.json
package.json
package-lock.json
.prettierrc.json
eslint.config.js
vitest.unit.config.ts
.github/
EOF

    step "entry point"

    write_file "$DIR/src/server/index.ts" <<'EOF'
// The program entry point. Grow this into the real bootstrap: for a backend that
// reaches a database, that usually means connecting and starting the server.
export function main(): string {
  return 'app starting';
}

// Runnable directly. The import.meta.url guard keeps main() importable from tests
// without running when imported.
if (import.meta.url === `file://${process.argv[1]}`) {
  console.log(main());
}
EOF

    write_file "$DIR/src/server/index.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest';
import { main } from './index.js';

// Unit tier (no external dependencies). Grows alongside the entry point.
describe('main', () => {
  it('returns the startup message', () => {
    expect(main()).toBe('app starting');
  });
});
EOF

    step "editor configs"
    mkdir -p "$DIR/.vscode"
    write_file "$DIR/.vscode/launch.json" <<'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug current file",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "${workspaceFolder}/node_modules/.bin/tsx",
      "runtimeArgs": ["${relativeFile}"],
      "console": "integratedTerminal",
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    },
    {
      "name": "Debug current test file",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "${workspaceFolder}/node_modules/.bin/vitest",
      "runtimeArgs": [
        "run",
        "${relativeFile}",
        "--no-file-parallelism"
      ],
      "console": "integratedTerminal",
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    },
    {
      "name": "Debug unit tier",
      "type": "node",
      "request": "launch",
      "runtimeExecutable": "${workspaceFolder}/node_modules/.bin/vitest",
      "runtimeArgs": [
        "run",
        "-c",
        "vitest.unit.config.ts",
        "--no-file-parallelism"
      ],
      "console": "integratedTerminal",
      "skipFiles": ["<node_internals>/**"],
      "cwd": "${workspaceFolder}"
    }
  ]
}
EOF

    # Format on save with Prettier, and recommend the extension so the formatter is
    # present. Committed (the .gitignore keeps these two while ignoring launch.json),
    # so every clone gets the same on-save formatting the setup gate also enforces.
    write_file "$DIR/.vscode/settings.json" <<'EOF'
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode"
}
EOF

    write_file "$DIR/.vscode/extensions.json" <<'EOF'
{
  "recommendations": ["esbenp.prettier-vscode", "dbaeumer.vscode-eslint"]
}
EOF
}
