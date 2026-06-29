# Valid fixture sheet

## Goal
A schema-valid two-increment sheet used to prove validate-sheet.sh passes a conforming sheet. An API increment followed by a UI increment that depends on it, so the validator exercises depends_on, ordering and the canonical serialisation on a clean input.

### prod-api: Products read API
- depends_on: []
- description: Add a read-only Products API exposing list and get-by-id over the existing db helper. No write paths in this increment.
- done_definition: The list and get-by-id endpoints exist, are typed, and return seeded products.
- acceptance_criteria:
  - The integration test for list returns at least one seeded product.
  - get-by-id returns the matching product for a known id.
  - get-by-id returns a 404-shaped result for an unknown id.
- test_notes: A correct test fails if list returns an empty array when products are seeded, or if get-by-id returns the wrong product.

### prod-ui: Products list screen
- depends_on: [prod-api]
- description: Add a React screen that fetches the Products list API and renders each product. Read-only, no mutation.
- done_definition: The screen fetches the list endpoint and renders one row per product.
- acceptance_criteria:
  - The component test renders one row per product in the fetched list.
  - An empty list renders the empty-state element.
- test_notes: A correct test fails if the screen renders zero rows for a non-empty list, or omits the empty state for an empty list.
