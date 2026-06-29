# Broken fixture: missing goal (rejection)

### prod-api: Products read API
- depends_on: []
- description: A valid increment, but the sheet has no `## Goal` paragraph to orient a reader.
- done_definition: The endpoints exist and return seeded products.
- acceptance_criteria:
  - The integration test for list returns at least one seeded product.
- test_notes:
  - A correct test fails if list returns empty when products are seeded.
