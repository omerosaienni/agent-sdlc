#!/usr/bin/env bash
# generator/react.sh - the optional React client layer (--react). Sourced by
# init-ts-project.sh. Writes the React-exclusive files (the src/client tree, the
# src/shared types, the Vite and client-vitest configs) and exports fragment
# variables the orchestrator splices into the shared files (package.json, tsconfig,
# Makefile). Also appends its config files to the project's .graphifyignore so they
# stay out of the knowledge graph. Expects DIR, NAME, and the lib helpers in scope.

react_layer() {
    step "react client"

    write_file "$DIR/vite.config.ts" <<'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Client root is src/client so the app sits beside the server, not at repo root.
// Build output goes to dist/client to keep it clear of any backend build.
export default defineConfig({
  root: 'src/client',
  plugins: [react()],
  build: { outDir: '../../dist/client', emptyOutDir: true },
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
// The root component. Grow this into the real app: routes, state, and components
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

    # Shared types cross the client/server boundary. One definition, imported by
    # both sides, never duplicated.
    write_file "$DIR/src/shared/types.ts" <<'EOF'
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

    # ---- fragments the orchestrator splices into the shared files ----

    # package.json: React runtime deps and the client scripts; React/Vite/RTL dev
    # deps. Leading commas so they slot in after the base/Mongo entries.
    REACT_DEPS=',
    "react": "^19.0.0",
    "react-dom": "^19.0.0"'
    REACT_SCRIPTS=',
    "dev:client": "vite",
    "build:client": "vite build",
    "preview": "vite preview",
    "test:client": "vitest run -c vitest.client.config.ts"'
    REACT_DEV_DEPS=',
    "@testing-library/jest-dom": "^6.6.3",
    "@testing-library/react": "^16.1.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^4.3.4",
    "jsdom": "^25.0.1",
    "vite": "^6.0.7"'

    # tsconfig: the DOM libs and the react-jsx transform, plus the client config
    # files joining the include set.
    REACT_TS_LIB=', "DOM", "DOM.Iterable"'
    REACT_TS_JSX='
    "jsx": "react-jsx",'
    REACT_TS_INCLUDE=', "vitest.client.config.ts", "vite.config.ts"'

    # Makefile fragment: the frontend dev/build/test targets and their help lines.
    REACT_MAKE_HELP='	@echo "  dev-client  Run the Vite dev server"
	@echo "  build-client  Production build of the client"
	@echo "  test-client  Frontend unit tier (jsdom)"
	@echo "  test-all    Backend tiers then the frontend tier"'

    REACT_MAKE_TARGETS='
.PHONY: dev-client build-client preview test-client test-all

dev-client: ## Run the Vite dev server
	npm run dev:client

build-client: ## Production build of the client (vite build)
	npm run build:client

preview: ## Preview the production client build
	npm run preview

test-client: ## Frontend unit tier (vitest + Testing Library, jsdom)
	npm run test:client

# Everything: backend tiers (unit, plus integration if Mongo is enabled), then frontend.
test-all: test test-client ## Run the backend tiers then the frontend tier'
}
