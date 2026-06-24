---
paths:
  - "src/client/**"
---

# React

Conventions for the React client. Scoped to `src/client/`, so it applies to the UI
tree and not to server `.tsx`. Drafted from sensible defaults — refine to taste.

## Components
- Function components only, with hooks. No class components.
- One component per file, named in PascalCase after the component; the file matches
  the export.
- Keep components small and presentational where possible; lift data fetching and
  side effects to hooks or a container.

## State and effects
- Local state with `useState`/`useReducer`; do not reach for a global store until a
  value is genuinely shared across distant components.
- Every `useEffect` has a correct dependency array. An effect with no cleanup that
  subscribes or sets up anything is a bug — return the teardown.
- Derive, don't duplicate: compute from props/state during render rather than
  mirroring into more state.

## Types
- Props are typed with an explicit interface. No `any`.
- Prefer discriminated unions over optional-flag soup for variant components.

## Tests
- Component tests use the unit tier (no Mongo, no network). Test behaviour through
  the rendered output and user interaction, not implementation details.
