# Broken fixture: dependency cycle (rule 4)

## Goal
Two increments that depend on each other, forming a cycle. Everything else is valid; only rule 4 (no cycle) must fail.

### prod-api: Products read API
- depends_on: [prod-ui]
- description: A read API that wrongly declares a dependency on the UI, closing a cycle with prod-ui.
- done_definition: The endpoints exist and return seeded products.
- acceptance_criteria:
  - The integration test for list returns at least one seeded product.
- test_notes:
  - A correct test fails if list returns empty when products are seeded.

### prod-ui: Products list screen
- depends_on: [prod-api]
- description: A screen that depends on the API, which in turn depends back on this screen.
- done_definition: The screen renders one row per product.
- acceptance_criteria:
  - The component test renders one row per product in the fetched list.
- test_notes:
  - A correct test fails if the screen renders zero rows for a non-empty list.
