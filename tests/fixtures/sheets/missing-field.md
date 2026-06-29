# Broken fixture: missing field (rule 1)

## Goal
An increment omits the test_notes bullet. Everything else is valid; only rule 1 (all five bullet fields present, non-empty) must fail.

### prod-api: Products read API
- depends_on: []
- description: A read API for products that is missing its test_notes field below.
- done_definition: The endpoints exist and return seeded products.
- acceptance_criteria:
  - The integration test for list returns at least one seeded product.
