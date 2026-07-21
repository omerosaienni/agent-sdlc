#!/usr/bin/env bash
# generator/go/react.sh - the optional React client layer (--react). Sourced by
# init-go-project.sh. Writes the Vite client under client/ and exports the Makefile,
# CI and services.yaml fragments the orchestrator splices in. Expects DIR, NAME and
# the lib helpers in scope.
#
# This layer is NOT the TypeScript generator's react layer. There the client lives
# in src/client and Vite (or Express) serves it, so Node is a runtime dependency.
# Here the Go binary serves it: the client is built to client/dist and synced into
# internal/assets/static, which the base layer embeds with embed.FS. Node is a BUILD
# dependency only and is absent from the shipped artefact, which is the whole point
# of the single-binary posture.
#
# Why the sync step rather than embedding client/dist directly: a //go:embed pattern
# cannot contain "..", so the embedding package must sit at or above what it embeds.
# Embedding from client/ would put a Go package inside the Node tree, which then
# drags client/node_modules into every `go build ./...` walk. One embed point under
# internal/ keeps the Go and Node trees disjoint, and `make client-build` is the
# single command that crosses between them.

go_react_layer() {
    step "react client"

    write_file "$DIR/client/package.json" <<EOF
{
  "name": "${NAME}-client",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "test": "vitest run"
  },
  "dependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.6.3",
    "@testing-library/react": "^16.1.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^4.3.4",
    "jsdom": "^25.0.1",
    "typescript": "^5.7.2",
    "vite": "^6.0.7",
    "vitest": "^2.1.8"
  }
}
EOF

    write_file "$DIR/client/vite.config.ts" <<'EOF'
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

// Build output stays inside the client tree (client/dist). `make client-build`
// syncs it into internal/assets/static, the one directory the Go binary embeds.
export default defineConfig(({ mode }) => {
  // Ports come from config/services.yaml via scripts/config-env.sh, which writes
  // .env at the repo root. The empty prefix loads every key, not just VITE_ ones,
  // so the dev server and its API proxy follow the same config the Go binary does.
  const env = loadEnv(mode, '..', '');
  const clientPort = Number(env.CLIENT_PORT) || 5173;
  const serverHost = env.SERVER_HOST || '127.0.0.1';
  const serverPort = env.SERVER_PORT || '8080';
  return {
    plugins: [react()],
    build: { outDir: 'dist', emptyOutDir: true },
    // In development the browser talks to Vite and /api and /healthz are proxied to
    // the Go binary, so there is no CORS to configure. In production neither exists
    // separately: the binary serves both from one origin.
    server: {
      port: clientPort,
      proxy: {
        '/api': `http://${serverHost}:${serverPort}`,
        '/healthz': `http://${serverHost}:${serverPort}`,
      },
    },
    test: {
      environment: 'jsdom',
      globals: true,
      setupFiles: ['./test-setup.ts'],
    },
  };
});
EOF

    write_file "$DIR/client/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noEmit": true,
    "skipLibCheck": true,
    "types": ["vitest/globals"]
  },
  "include": ["src", "vite.config.ts", "test-setup.ts"]
}
EOF

    write_file "$DIR/client/test-setup.ts" <<'EOF'
// Testing Library matchers (toBeInTheDocument etc.) for the jsdom client tier.
import '@testing-library/jest-dom/vitest';
EOF

    write_file "$DIR/client/index.html" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${NAME}</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

    write_file "$DIR/client/src/main.tsx" <<'EOF'
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';

// Mount point. The non-null assertion is safe: index.html always ships #root.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
EOF

    write_file "$DIR/client/src/App.tsx" <<'EOF'
// The root component. Grow this into the real app. Data comes from the Go binary
// over its HTTP API, which serves this bundle from the same origin in production.
export function App() {
  return <h1>app starting</h1>;
}
EOF

    write_file "$DIR/client/src/App.test.tsx" <<'EOF'
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { App } from './App';

// Client unit tier (jsdom). Tests behaviour through the rendered output, not
// implementation details.
describe('App', () => {
  it('renders the startup heading', () => {
    render(<App />);
    expect(screen.getByRole('heading', { name: 'app starting' })).toBeInTheDocument();
  });
});
EOF

    # ---- fragments the orchestrator splices into the shared files ----

    REACT_YAML="# the Vite dev server (make client-start); production is served by the binary
client:
  host: 127.0.0.1
  port: 5173
"

    REACT_MAKE_HELP='	@echo ""
	@echo " client"
	@echo "  client-install    Install the client'"'"'s Node dependencies"
	@echo "  client-start      Start the Vite dev server (proxies to the binary)"
	@echo "  client-test-unit  Run the client unit tier (jsdom)"
	@echo "  client-build      Build the client and sync it into the embedded assets"'

    # client-build is the only target that crosses the Go/Node boundary. The sync is
    # a replace, not a merge: a stale bundle left behind by a previous build would
    # otherwise be embedded alongside the new one.
    REACT_MAKE_TARGET='
# --- client --------------------------------------------------------------
.PHONY: client-install client-start client-test-unit client-build

client-install: ## Install the client'"'"'s Node dependencies
	npm --prefix client install

client-start: ## Start the Vite dev server (proxies /api and /healthz to the binary)
	npm --prefix client run dev

client-test-unit: ## Run the client unit tier (vitest + Testing Library, jsdom)
	npm --prefix client run test

# Node is a BUILD dependency only: the shipped binary embeds the output of this
# target, so nothing Node-related is needed at run time.
client-build: ## Build the client and sync it into the embedded assets
	npm --prefix client run build
	rm -rf internal/assets/static
	cp -r client/dist internal/assets/static'

    REACT_CI_JOB='

  client:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: 22
      - run: npm --prefix client install
      - run: npm --prefix client run build
      - run: npm --prefix client run test'

    # .gitignore fragment: client/dist is the INTERMEDIATE build output. The copy
    # that matters is the one make client-build syncs into internal/assets/static,
    # which is what the binary embeds and what git tracks. Without this the same
    # bundle is committed twice, with the hashed names diverging on every rebuild.
    REACT_GITIGNORE="# the client's intermediate build output; make client-build syncs it into
# internal/assets/static, and THAT copy is the one the binary embeds and git tracks
client/dist/
"

    REACT_CLAUDE_MD='
- The React client lives under client/ and is a BUILD dependency only: `make
  client-build` builds it to client/dist and syncs it into internal/assets/static,
  which the binary embeds with embed.FS. The shipped artefact needs no Node.'
}
