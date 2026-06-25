#!/usr/bin/env bash
# generator/express.sh - the optional Express server layer (--express). Sourced by
# init-ts-project.sh. Replaces the base stub entry point with a long-running
# versioned Express HTTP server (src/server/app.ts plus a server bootstrap in
# src/server/index.ts) and its supertest unit tests, and exports the express and
# supertest dependency fragments the orchestrator splices into package.json. With
# the Mongo layer the server's shutdown also closes the shared Mongo client. Expects
# DIR, NAME, WITH_MONGO and the lib helpers in scope.

express_layer() {
    step "express server"

    write_file "$DIR/src/server/app.ts" <<'EOF'
import express, { type Express, type Request, type Response } from 'express';

// The base path so the API is versioned from the start. A breaking change ships
// as /api/v2 alongside, rather than mutating live clients of v1.
export const API_BASE = '/api/v1';

// Liveness response shape, kept local so the server layer stands alone. Grow real
// shared request/response types in src/common when a client needs them.
interface HealthResponse {
  ok: boolean;
}

// Build the app without binding a port, so a unit test can drive routes through
// supertest while the listen and signal wiring stays separate (index.ts).
export function createApp(): Express {
  const app = express();
  app.use(express.json());

  const api = express.Router();

  // Liveness only: verifiable the moment the server boots, before any domain
  // endpoint exists.
  api.get('/health', (_req: Request, res: Response) => {
    const body: HealthResponse = { ok: true };
    res.status(200).json(body);
  });

  app.use(API_BASE, api);

  return app;
}
EOF

    # index.ts replaces the base stub entry point with the server bootstrap. With the
    # Mongo layer, shutdown closes the shared client; without it, the default close is
    # a no-op. Unquoted heredoc: ${NAME} and the close fragments interpolate, while the
    # TypeScript template literals are escaped (\$, \`) so they reach the file intact.
    local close_import="" close_default="async () => {}"
    if [ "$WITH_MONGO" = 1 ]; then
        close_import="
import { closeClient } from './db/index.js';"
        close_default="closeClient"
    fi

    write_file "$DIR/src/server/index.ts" <<EOF
import type { Server } from 'node:http';
import { createApp } from './app.js';${close_import}

// Host and port come from config/services.yaml via scripts/config-env.sh, which
// writes .env (loaded with --env-file-if-exists in the start script). The fixed
// defaults keep a fresh checkout running with no config and MUST match the
// services.yaml defaults; SERVER_HOST and SERVER_PORT override them.
const DEFAULT_HOST = '127.0.0.1';
const DEFAULT_PORT = 3000;

export function resolveHost(env: NodeJS.ProcessEnv = process.env): string {
  const raw = env.SERVER_HOST;
  return raw === undefined || raw === '' ? DEFAULT_HOST : raw;
}

export function resolvePort(env: NodeJS.ProcessEnv = process.env): number {
  const raw = env.SERVER_PORT;
  if (raw === undefined || raw === '') {
    return DEFAULT_PORT;
  }
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(\`SERVER_PORT must be a non-negative integer, got '\${raw}'\`);
  }
  return parsed;
}

// Close the listener then the shared resources so a restart does not leak them.
// closeFn is injected so a unit test can assert it runs exactly once without a real
// signal; exitFn defaults to process.exit but is injectable to keep the test alive.
export async function shutdown(
  server: Server,
  closeFn: () => Promise<void> = ${close_default},
  exitFn: (code: number) => void = process.exit,
): Promise<void> {
  await new Promise<void>((resolve) => server.close(() => resolve()));
  await closeFn();
  exitFn(0);
}

export function main(): Server {
  const app = createApp();
  const host = resolveHost();
  const port = resolvePort();
  const server = app.listen(port, host, () => {
    console.log(\`${NAME} listening on http://\${host}:\${port}\`);
  });

  // Both signals route through one clean shutdown: SIGTERM from an orchestrator
  // stopping the container, SIGINT from Ctrl-C in a terminal.
  for (const signal of ['SIGTERM', 'SIGINT'] as const) {
    process.on(signal, () => {
      void shutdown(server);
    });
  }

  return server;
}

// Runnable directly. The import.meta.url guard keeps main() and the helpers
// importable from tests without starting the server when imported.
if (import.meta.url === \`file://\${process.argv[1]}\`) {
  main();
}
EOF

    write_file "$DIR/src/server/index.test.ts" <<'EOF'
import type { Server } from 'node:http';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp, API_BASE } from './app.js';
import { shutdown, resolvePort, resolveHost } from './index.js';

// Unit tier: no live endpoint. The health route is dependency-free and shutdown
// takes injected close/exit functions, so both run here without a server signal.
describe('health route', () => {
  it('returns 200 with { ok: true }', async () => {
    const res = await request(createApp()).get(`${API_BASE}/health`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });
  });
});

describe('versioning', () => {
  it('mounts routes only under /api/v1', async () => {
    const app = createApp();
    const versioned = await request(app).get('/api/v1/health');
    expect(versioned.status).toBe(200);

    // The unversioned path must not resolve to the versioned handler.
    const unversioned = await request(app).get('/health');
    expect(unversioned.status).toBe(404);
  });
});

describe('shutdown', () => {
  it('runs the close hook exactly once and exits zero', async () => {
    const server = { close: (cb: () => void) => cb() } as unknown as Server;
    const closeFn = vi.fn(async () => {});
    const exitFn = vi.fn<(code: number) => void>();

    await shutdown(server, closeFn, exitFn);

    expect(closeFn).toHaveBeenCalledTimes(1);
    expect(exitFn).toHaveBeenCalledWith(0);
  });
});

describe('resolvePort', () => {
  it('defaults to 3000 when SERVER_PORT is unset', () => {
    expect(resolvePort({})).toBe(3000);
  });

  it('honours SERVER_PORT when set', () => {
    expect(resolvePort({ SERVER_PORT: '4000' })).toBe(4000);
  });
});

describe('resolveHost', () => {
  it('defaults to 127.0.0.1 when SERVER_HOST is unset', () => {
    expect(resolveHost({})).toBe('127.0.0.1');
  });

  it('honours SERVER_HOST when set', () => {
    expect(resolveHost({ SERVER_HOST: '0.0.0.0' })).toBe('0.0.0.0');
  });
});
EOF

    # ---- fragments the orchestrator splices into the shared files ----

    # package.json: the express runtime dep and the supertest + types dev deps.
    # Leading commas so they slot in after the base, Mongo and React entries.
    EXPRESS_DEPS=',
    "express": "^5.2.1"'
    EXPRESS_DEV_DEPS=',
    "@types/express": "^5.0.6",
    "@types/supertest": "^7.2.0",
    "supertest": "^7.2.2"'

    # config/services.yaml fragment: the HTTP server's address and port. The loop's
    # config-env.sh turns this into SERVER_HOST/SERVER_PORT; index.ts reads them.
    SERVER_YAML="# the HTTP server (make server-start)
server:
  host: 127.0.0.1
  port: 3000
"
}
