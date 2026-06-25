#!/usr/bin/env bash
# generator/react.sh - the optional React client layer (--react). Sourced by
# init-ts-project.sh. Writes the React-exclusive files (the src/client tree, the
# src/common types, the Vite and client-vitest configs) and exports fragment
# variables the orchestrator splices into the shared files (package.json, tsconfig,
# Makefile). Also appends its config files to the project's .graphifyignore so they
# stay out of the knowledge graph. Expects DIR, NAME, and the lib helpers in scope.

react_layer() {
    step "react client"

    write_file "$DIR/vite.config.ts" <<'EOF'
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

// Client root is src/client so the app sits beside the server, not at repo root.
// Build output goes to dist/client to keep it clear of any backend build.
export default defineConfig(({ mode }) => {
  // Ports and addresses come from config/services.yaml via scripts/config-env.sh,
  // which writes .env. The empty prefix loads every key, not just VITE_ ones, so
  // the dev server and its API proxy follow one config. Defaults match the yaml.
  const env = loadEnv(mode, process.cwd(), '');
  const clientHost = env.CLIENT_HOST || '127.0.0.1';
  const clientPort = Number(env.CLIENT_PORT) || 5173;
  const serverHost = env.SERVER_HOST || '127.0.0.1';
  const serverPort = env.SERVER_PORT || '3000';
  return {
    root: 'src/client',
    plugins: [react()],
    build: { outDir: '../../dist/client', emptyOutDir: true },
    // Dev server bound per config; /api is proxied to the Express server so the
    // browser talks to the client origin and dodges CORS in development.
    server: {
      host: clientHost,
      port: clientPort,
      proxy: { '/api': `http://${serverHost}:${serverPort}` },
    },
    // A bare `vitest run` (e.g. the coverage gate) resolves this config, not the
    // tier ones, so the client tests need jsdom here too. Paths are relative to
    // root (src/client), mirroring vitest.client.config.ts.
    test: {
      environment: 'jsdom',
      globals: true,
      include: ['**/*.test.tsx'],
      setupFiles: ['./test-setup.ts'],
    },
  };
});
EOF

    # Frontend tests are unit-class (jsdom, no external services), a tier beside the
    # backend tiers. Scoped to *.test.tsx under src/client so it never picks up the
    # backend *.test.ts files (those run under the backend vitest configs).
    write_file "$DIR/vitest.client.config.ts" <<'EOF'
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['src/client/**/*.test.tsx'],
    setupFiles: ['src/client/test-setup.ts'],
  },
});
EOF

    write_file "$DIR/src/client/test-setup.ts" <<'EOF'
// Testing Library matchers (toBeInTheDocument etc.) for the jsdom frontend tier.
import '@testing-library/jest-dom/vitest';
EOF

    write_file "$DIR/src/client/index.html" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${NAME}</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="./main.tsx"></script>
  </body>
</html>
EOF

    write_file "$DIR/src/client/main.tsx" <<'EOF'
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App.js';

// Mount point. The non-null assertion is safe: index.html always ships #root.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
EOF

    write_file "$DIR/src/client/App.tsx" <<'EOF'
// The root component. Grow this into the real app: routes, state and components
// under src/client. Data comes from the backend over its API, never from a
// database directly.
export function App() {
  return <h1>app starting</h1>;
}
EOF

    write_file "$DIR/src/client/App.test.tsx" <<'EOF'
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { App } from './App.js';

// Frontend unit tier (jsdom). Tests behaviour through the rendered output, not
// implementation details.
describe('App', () => {
  it('renders the startup heading', () => {
    render(<App />);
    expect(screen.getByRole('heading', { name: 'app starting' })).toBeInTheDocument();
  });
});
EOF

    # Common types cross the client/server boundary. One definition, imported by
    # both sides, never duplicated.
    write_file "$DIR/src/common/types.ts" <<'EOF'
// Types shared between the client and server. Keep API request/response shapes
// here so both sides agree on one definition.
export interface HealthResponse {
  ok: boolean;
}
EOF

    # The React config files are config, not architecture: keep them out of the
    # knowledge graph like the base configs. Appended so the base .graphifyignore
    # exclusion list stays complete for the full-stack layout.
    cat >> "$DIR/.graphifyignore" <<'EOF'
vite.config.ts
vitest.client.config.ts
EOF
    note "added react config files to .graphifyignore"

    # Client debug configs appended to the base launch.json (base.sh): a browser-side
    # Chrome launch for the Vite app, the client unit tier, and a compound that starts
    # the server and client together. The Chrome URL matches the CLIENT_HOST/PORT
    # defaults in config/services.yaml below; change both if you change the yaml.
    node -e '
      const fs = require("fs");
      const p = process.argv[1] + "/.vscode/launch.json";
      const j = JSON.parse(fs.readFileSync(p, "utf8"));
      j.configurations.push(
        { name: "Open client in Chrome", type: "chrome", request: "launch", url: "http://127.0.0.1:5173", webRoot: "${workspaceFolder}/src/client", presentation: { group: "1-run", order: 3 } },
        { name: "Debug client unit tier (jsdom)", type: "node", request: "launch", program: "${workspaceFolder}/node_modules/vitest/vitest.mjs", args: ["run", "-c", "vitest.client.config.ts", "--no-file-parallelism"], envFile: "${workspaceFolder}/.env", console: "integratedTerminal", autoAttachChildProcesses: true, sourceMaps: true, skipFiles: ["<node_internals>/**"], cwd: "${workspaceFolder}", presentation: { group: "3-client-tests", order: 1 } },
      );
      j.compounds = [
        { name: "Run server + client", configurations: ["Run server", "Open client in Chrome"], stopAll: true, presentation: { group: "1-run", order: 4 } },
      ];
      fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
    ' "$DIR"
    note "added client debug configs (Chrome, client tier, compound)"

    # ---- fragments the orchestrator splices into the shared files ----

    # package.json: React runtime deps and the client scripts; React/Vite/RTL dev
    # deps. Leading commas so they slot in after the base/Mongo entries.
    REACT_DEPS=',
    "react": "^19.0.0",
    "react-dom": "^19.0.0"'
    # Dev-only: the client start and its unit tier. No production build/preview
    # scripts for now (added back when a deploy path is needed).
    REACT_SCRIPTS=',
    "client:start": "vite",
    "client:test:unit": "vitest run -c vitest.client.config.ts"'

    # config/services.yaml fragment: the Vite dev server's address and port.
    # config-env.sh turns this into CLIENT_HOST/CLIENT_PORT, read by vite.config.ts.
    CLIENT_YAML="# the Vite client (make client-start)
client:
  host: 127.0.0.1
  port: 5173
"
    REACT_DEV_DEPS=',
    "@testing-library/jest-dom": "^6.6.3",
    "@testing-library/react": "^16.1.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^4.3.4",
    "jsdom": "^25.0.1",
    "vite": "^6.0.7"'

    # tsconfig: the DOM libs and the react-jsx transform (the client config files
    # join the include set via the orchestrator's tsconfig include assembly).
    REACT_TS_LIB=', "DOM", "DOM.Iterable"'
    REACT_TS_JSX='
    "jsx": "react-jsx",'

    # Makefile fragment: the frontend dev/build/test targets and their help lines.
    # The client help group, and the lone test-all line for the tests group.
    REACT_CLIENT_HELP='	@echo ""
	@echo " client"
	@echo "  client-start      Start the Vite client"
	@echo "  client-test-unit  Run the frontend unit tier (jsdom)"'
    REACT_TESTALL_HELP='	@echo "  test-all    Server tier(s) then the client tier"'

    # The client target group, and the test-all aggregate spliced into the tests group.
    REACT_CLIENT_TARGETS='
# --- client --------------------------------------------------------------
.PHONY: client-start client-test-unit

client-start: ## Start the Vite client
	npm run client:start

client-test-unit: ## Run the frontend unit tier (vitest + Testing Library, jsdom)
	npm run client:test:unit'

    REACT_TESTALL_TARGET='
.PHONY: test-all

# Everything: the server tier(s) (unit, plus integration if Mongo is enabled), then client.
test-all: test client-test-unit ## Run the server tier(s) then the client tier'

    # CI job fragment spliced into .github/workflows/ci.yml after the base (and any
    # Mongo) jobs. The frontend tier runs in jsdom with no external services, so it
    # needs no make db-start. This is where client component tests are gated. Type-checking
    # of the client is already covered by the base typecheck job (tsc spans all of src).
    # Leading blank line keeps it apart from the prior job in the assembled workflow.
    REACT_CI_JOB='

  client:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run client:test:unit'
}
