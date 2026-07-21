# Epic manifest schema (epic.json)

The epic's build order manifest: one JSON file per epic at `.building/epics/<epic-name>/epic.json`. Records the order in which a run's features are built, and the cross feature dependencies that fix that order. Written by the design partner (design-partner.md), one manifest per epic, emitted even for a single feature epic. A human facing, human driven document: the builder does NOT read it and the ATTENDED build loop (build-judge-loop.md) is not gated on it. The one exception is the STACKED build loop (build-stacked.md), which reads it read-only to resolve its stack base (which feature a stack chains onto); even there it is a base-resolution reference, not a gate, and the loop never writes it and depends on nothing beyond the cross feature `depends_on`. Single source of truth for the epic level build order that was previously only prose in each feature's goal.

## Why this exists
Cross feature order (Orders needs Customers merged first) was recorded only in prose in the dependent feature's goal (increment-sheet.schema.md, Vocabulary). There was no single machine-readable place stating the whole epic's build sequence, so a human driving the build had nowhere to read the order off. This manifest is that place: the epic's features, in build order, with the dependency edges that justify the order.

## Naming strategy (all `.building` artifacts)
Every `.building` artifact is `.building/<kind>/<identity>/<generic-file>`: the DIRECTORY carries identity, the FILENAME names the kind. So a sheet is `features/<feature>/increments.md`, a state file is `build/<feature>/state.json`, and an epic manifest is `epics/<epic-name>/epic.json`. The epic gets its own `epics/<epic-name>/` namespace like the others; the flat alternative (`.building/epics.json`) is a drift, it bakes identity into the filename and assumes one epic.

## Structure
- epic: string, non-empty. One line naming the whole program or product (the Epic of the vocabulary, increment-sheet.schema.md). Context only.
- features: ordered list. The build order, read top to bottom. Each element:
  - name: string, non-empty, kebab-case. The feature's short name, its key elsewhere in `.building` (`features/<name>/`, `build/<name>/`). Unique within the manifest.
  - sheet: string, non-empty. Path to that feature's increment sheet, `.building/features/<name>/increments.md`. The manifest REFERENCES features by their existing path; it does not own their folders (a feature is not nested under an epic).
  - depends_on: list of feature names that must be merged to main before this feature starts. Empty if none. The edges that justify the list order. Cross feature only; within feature order is the sheet's depends_on (increment-sheet.schema.md), not repeated here.

No status field. Build progress lives in each feature's state.json (state.schema.md); tracking it here too would duplicate and drift, and nothing here consumes it.

## Example
```
{
  "epic": "A small CRM: customers, products and their orders.",
  "features": [
    { "name": "foundation", "sheet": ".building/features/foundation/increments.md", "depends_on": [] },
    { "name": "customers",  "sheet": ".building/features/customers/increments.md",  "depends_on": ["foundation"] },
    { "name": "products",   "sheet": ".building/features/products/increments.md",   "depends_on": ["foundation"] },
    { "name": "orders",     "sheet": ".building/features/orders/increments.md",     "depends_on": ["customers", "products"] }
  ]
}
```

A single feature epic is a one element list with `depends_on: []`.

## Validation (all must hold)
1. epic is a present, non-empty string.
2. features is a non-empty list; each element has name, sheet (present, non-empty strings) and depends_on (a list).
3. name unique across features.
4. Every depends_on entry is the name of a feature in the manifest.
5. No cycle across the feature depends_on edges.
6. List order consistent with depends_on: a feature never appears before one it depends on.
7. Every feature's sheet path is `.building/features/<name>/increments.md` (the path agrees with the name and the naming strategy).

## Validation tooling
- Enforced mechanically by `scripts/validate-epics.sh <epic.json>`: all seven rules.
- The script is the source of truth for these checks; on disagreement with this prose, the script is what runs, fix the prose (the rules are the spec, the script is the gate, mirrors claude-rules/omero-git-authorship.md).
- Sheet EXISTENCE on disk is NOT checked: `.building` is gitignored and a manifest is validated for internal shape, which holds whether or not the sheets are present in a given checkout. Rule 7 checks the path is well-formed, not that the file exists.
- Exits: 0 valid, 1 rejection (fixable), 3 node absent, 4 structural defect, 64 usage. A defect outranks a rejection when both are present.
- Defect vs rejection: the DAG is the law, mirroring the sheet validator. A cycle (rule 5), an empty/absent features list, or non-JSON is a non-DAG/non-manifest = structural DEFECT (exit 4, regenerate upstream). Every other failure is a locatable REJECTION (exit 1); a dangling depends_on (rule 4) is a typo in an edge, still a DAG, so a rejection.
- Fixtures: tests/fixtures/epics/ (valid + one per failing rule), run by tests/run.sh and the tests workflow on every PR into main.

## Who writes it
- The design partner, when it resolves an intent into features: sole writer. It writes one manifest per epic alongside the per feature sheets, and re-emits the whole manifest on a modifying run (latest wins, like a sheet).
- Nothing else writes it. The attended build loop never reads or writes it; it is not a build input there. The stacked build loop (build-stacked.md) reads it read-only to resolve its stack base and never writes it (see this file's intro); no loop writes it.

## Excludes
No status, no counts, no branches, no build state (those are state.schema.md's, per feature). No within feature ordering (that is the sheet's depends_on). Epic level grouping is the human's; this manifest records one epic's feature order, not a hierarchy of epics.
