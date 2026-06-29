# Broken fixture: depends_on references a non-existent id (rule 3)

## Goal
An increment depends on an id that no increment defines. Everything else is valid; only rule 3 (every depends_on id exists) must fail.

### prod-ui: Products list screen
- depends_on: [prod-api]
- description: A screen that depends on prod-api, but no prod-api increment exists in this sheet.
- done_definition: The screen renders one row per product.
- acceptance_criteria:
  - The component test renders one row per product in the fetched list.
- test_notes:
  - A correct test fails if the screen renders zero rows for a non-empty list.
