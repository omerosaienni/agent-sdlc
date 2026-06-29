# Broken fixture: list order inconsistent with depends_on (rule 5)

## Goal
The UI increment is listed BEFORE the API it depends on. The dependency exists and is acyclic, so rules 3 and 4 hold; only rule 5 (an increment never appears before a dep) must fail.

### prod-ui: Products list screen
- depends_on: [prod-api]
- description: A screen listed before prod-api, the increment it depends on.
- done_definition: The screen renders one row per product.
- acceptance_criteria:
  - The component test renders one row per product in the fetched list.
- test_notes: A correct test fails if the screen renders zero rows for a non-empty list.

### prod-api: Products read API
- depends_on: []
- description: The read API the screen above depends on, but listed after it.
- done_definition: The endpoints exist and return seeded products.
- acceptance_criteria:
  - The integration test for list returns at least one seeded product.
- test_notes: A correct test fails if list returns empty when products are seeded.
