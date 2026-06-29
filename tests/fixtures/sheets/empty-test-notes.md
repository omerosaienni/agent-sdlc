# Broken fixture: test_notes label with no list items (rule 1)

## Goal
An increment whose test_notes label is present but carries no nested bullet items. test_notes is a list field, so an empty list is an empty field: rule 1 (all fields non-empty) must fail.

### prod-api: Products read API
- depends_on: []
- description: A read API whose test_notes has a label but no items below it.
- done_definition: The endpoints exist and return seeded products.
- acceptance_criteria:
  - The list integration test returns at least one seeded product.
- test_notes:
