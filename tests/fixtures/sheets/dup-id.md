# Broken fixture: duplicate id (rule 2)

## Goal
Two increments share the same id. Everything else is valid; only rule 2 (ids unique) must fail.

### prod-api: Products read API
- depends_on: []
- description: A read API for products.
- done_definition: The endpoints exist and return seeded products.
- acceptance_criteria:
  - The integration test for list returns at least one seeded product.
- test_notes:
  - A correct test fails if list returns empty when products are seeded.

### prod-api: Products write API
- depends_on: []
- description: A write API that reuses the prod-api id already taken above.
- done_definition: The create endpoint persists a product.
- acceptance_criteria:
  - The integration test creates a product and reads it back.
- test_notes:
  - A correct test fails if a created product cannot be read back.
