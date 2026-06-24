---
paths:
  - "src/server/db/**"
---

# MongoDB

Conventions for MongoDB access. Scoped to the db layer (`src/server/db/`), so it is
language-neutral by location, not by file type. Stated to stand alone, it does not
assume any particular language rule is also installed.

## Connection
- One shared client per process via the db helper. Never connect per query.
- Get the database through the helper (e.g. `getDb()`); close the client once, on
  shutdown, not per operation.

## Collections
- Centralise collection names in one place (a `COLLECTIONS` constant), never
  hardcode name strings at call sites.
- Type your documents: pass the document shape to the driver so reads and writes
  are checked, not `any`.

## Tests
- A test that touches Mongo belongs in the integration tier, never the unit tier.
  The unit tier must run without a database; anything needing a live Mongo is
  integration.
- Integration tests assume the shared Mongo is up (an attended prerequisite); they
  do not start it.
