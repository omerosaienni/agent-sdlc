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
# .env is generated from config/services.yaml by scripts/config-env.sh; edit the
# YAML, not this. Gitignored because it is derived; code defaults match the YAML.
.env
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

    # launch.json is generated (not a static heredoc) so envFile is conditional and the
    # Mongo/React layers can append their configs to valid JSON (mongo.sh, react.sh). It
    # is gitignored as personal debug config, regenerated on each scaffold.
    #
    # Debugger correctness, why this is not the obvious shim setup: the node debugger
    # must launch the process that runs the code. The .bin/tsx and .bin/vitest shims
    # fork a child and the debugger only attaches to the parent, so breakpoints never
    # bind. So run `node --import tsx <file>` for code (tsx as an in-process loader) and
    # `node node_modules/vitest/vitest.mjs` for tests, with autoAttachChildProcesses to
    # follow vitest's workers. envFile mirrors the start script (present only once a
    # service layer has seeded .env); sourceMaps so stepping lands in the .ts.
    LAUNCH_ENV_FILE=""
    if [ "$WITH_MONGO" = 1 ] || [ "$WITH_REACT" = 1 ] || [ "$WITH_EXPRESS" = 1 ]; then
        LAUNCH_ENV_FILE='${workspaceFolder}/.env'
    fi
    node -e '
      const fs = require("fs");
      const dir = process.argv[1];
      const envFile = process.argv[2];
      const base = {
        type: "node",
        request: "launch",
        console: "integratedTerminal",
        autoAttachChildProcesses: true,
        sourceMaps: true,
        skipFiles: ["<node_internals>/**"],
        cwd: "${workspaceFolder}",
      };
      if (envFile) base.envFile = envFile;
      const tsx = { runtimeExecutable: "node", runtimeArgs: ["--import", "tsx"] };
      const vitest = "${workspaceFolder}/node_modules/vitest/vitest.mjs";
      const j = {
        version: "0.2.0",
        configurations: [
          { name: "Run server", ...base, ...tsx, program: "${workspaceFolder}/src/server/index.ts", presentation: { group: "1-run", order: 1 } },
          { name: "Debug server unit tier", ...base, program: vitest, args: ["run", "-c", "vitest.unit.config.ts", "--no-file-parallelism"], presentation: { group: "2-server-tests", order: 1 } },
          { name: "Debug current test file", ...base, program: vitest, args: ["run", "${relativeFile}", "--no-file-parallelism"], presentation: { group: "4-current-file", order: 1 } },
          { name: "Debug current file (tsx)", ...base, ...tsx, program: "${file}", presentation: { group: "4-current-file", order: 2 } },
        ],
      };
      fs.writeFileSync(dir + "/.vscode/launch.json", JSON.stringify(j, null, 2) + "\n");
    ' "$DIR" "$LAUNCH_ENV_FILE"

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
