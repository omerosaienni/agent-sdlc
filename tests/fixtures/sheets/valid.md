# Valid fixture sheet

## Goal
A two-increment feature (read API then its UI) proving validate-sheet.sh passes a conforming sheet: it exercises depends_on, ordering and the canonical serialisation on a clean input.

### prod-api: Products read API
- depends_on: []
- description: A read-only Products API exposing list and get-by-id over the existing db helper.
- done_definition: list and get-by-id exist, are typed, and return seeded products.
- acceptance_criteria:
  - The list integration test returns at least one seeded product.
  - get-by-id returns the matching product for a known id, and a 404-shaped result for an unknown one.
- test_notes:
  - A wrong implementation returns an empty list when products are seeded.
  - A wrong implementation returns the wrong product for a known id.

### prod-ui: Products list screen
- depends_on: [prod-api]
- description: A React screen that fetches the Products list API and renders one row per product.
- done_definition: The screen renders the fetched list, with an empty state for none.
- acceptance_criteria:
  - The component test renders one row per product in the fetched list.
  - An empty list renders the empty-state element.
- test_notes:
  - A wrong implementation renders zero rows for a non-empty list.
  - A wrong implementation omits the empty state for an empty list.
