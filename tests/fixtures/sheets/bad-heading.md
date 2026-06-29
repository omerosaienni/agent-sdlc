# Broken fixture: non-canonical heading (rule 8)

## Goal
The increment heading is a bare `### <id>` with no `: <title>`, and the id/title carried in a separate bullet. Everything else looks plausible; rule 8 (canonical `### <id>: <title>` heading, no separate id/title bullet) must fail.

### prod-api
- id: prod-api
- title: Products read API
- depends_on: []
- description: A read API whose heading omits the title and adds a forbidden separate id bullet.
- done_definition: The endpoints exist and return seeded products.
- acceptance_criteria:
  - The integration test for list returns at least one seeded product.
- test_notes:
  - A correct test fails if list returns empty when products are seeded.
