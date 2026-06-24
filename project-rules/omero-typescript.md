---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript

Conventions for TypeScript in this project. Terse; loads only for `.ts`/`.tsx` files.

## Types
- Strict mode. Never `any` — supply interfaces and pass them as generics.
- Prefer `unknown` over `any` at boundaries, then narrow.

## Modules and files
- One module per file, named after what it does, lowercase.
- A module's test sits beside it (see Tests).
- A runnable module (a seed, an example, a script) is run via an npm script and an
  `import.meta.url` main-guard, so it runs when invoked directly but stays
  importable from tests. Name an example script `ex:<feature>` and have it print
  its results.

## Async
- async/await throughout, not raw promise chains.

## Tests
- vitest, two tiers: unit (`*.test.ts`) and integration (`*.integration.test.ts`).
- One file per module per tier, co-located, tier by suffix
  (`foo.ts` -> `foo.test.ts` and/or `foo.integration.test.ts`).
- Shared test helpers, if any, in one support module under `src/test-support/`.
