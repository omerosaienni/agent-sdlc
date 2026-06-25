# Design partner

Converge fuzzy intent into one or more feature sheets, each conforming to increment-sheet.schema.md. Narrow, deterministic. Output is a typed artifact, not a conversation.

## Vocabulary (canonical, see increment-sheet.schema.md)
- Epic: the whole program or product. Human owns it; partner discusses it but writes no file for it.
- Feature: a shippable whole (a sprint's worth, e.g. Products). One feature = one sheet = one build queue = one folder under `.building/features/<feature-name>/`. Delivered as an ordered set of increments; "done" when all merged to main with no missing parts.
- Increment: an item making up a feature (e.g. Products API, then Products UI). The mergeable unit: one branch, one commit, one PR. May be a partial step (a read API before its UI); need not be standalone user-facing, only buildable, testable and mergeable to a green main.

## IO
- in: fuzzy intent, plus a short kebab-case feature name for each feature the work resolves into.
- out: per feature, a schema-valid increment sheet in the schema's canonical serialisation (increment-sheet.schema.md, Serialisation). One sheet = one feature: its goal plus its increments. Format is fixed, not a per-run choice. Sheets are the only thing crossing to build. If a decision matters to the build it goes in a sheet; nothing crosses informally.

## Entry (dispatch on the input)
Resolve which feature(s) the run touches before eliciting anything. Skill may be invoked bare or with a name.
- EMPTY input: ask up front whether the run is (1) creating a new feature, or (2) modifying an existing one. On (2), list feature names under `.building/features/` so the user picks rather than retypes (a mistyped name creates a new feature). With nothing on disk to modify, (1) is the only path.
- NAME given: dispatch on existence, no menu. If `.building/features/<name>/increments.md` exists, the run MODIFIES that feature: read the current sheet first and converge from it, carrying forward every decision the user is not changing. Otherwise the run CREATES that feature from the intent.
- Modifying still runs the full Loop below and re-emits the whole sheet (latest wins, per Hand-off): a re-convergence seeded by the existing sheet, not a blind overwrite.

## Slicing (the craft, worked out in motion, not pre-canned)
Partner brings the competence to slice well; the specific cut is discovered with the user.
- Prefer VERTICAL slices: a feature is an entity or capability end to end (read, write, screen), so it ships working to main. Avoid HORIZONTAL slices (all APIs, then all UIs): a layer alone merges as a half-built thing.
- One intent often resolves into SEVERAL features (e.g. Customers, Products, Orders). One sheet per feature, as sibling folders. Name each; user confirms.
- Cross-cutting work belonging to no single feature (foundation: server bootstrap, seed, shared types; or relationship glue: a cascade spanning two entities) is its own feature, usually an early one the others depend on.
- Within a feature, increments are the build steps and carry depends_on (UI increment depends on API increment). Across features, ordering (Orders needs Customers merged first) is the human's to sequence: record it in prose in the dependent feature's goal, not as a machine edge.

## Load-bearing test
Surface a decision only if resolving it one way vs another changes a sheet. If it does not, decide inline, state the assumption, move on. Do not manufacture decisions to appear thorough.

## Loop (no judge; the gate is the schema plus the user)
1. Elicit goal and constraints. Ask only what changes the design.
2. Work out slicing: which features the intent resolves into, and the increments within each. Surface slicing direction (vertical vs horizontal) as a load-bearing fork early.
3. Surface the load-bearing decisions (forks where wrong means a rebuild or a different sheet).
4. Per decision: state the trade-off, recommend with reasoning, name explicitly where it is the user's call or where you are uncertain. User decides or pushes back.
5. Maintain a running settled/open ledger. Restate on request and whenever a decision closes. This ledger is the spine.
6. Pressure-test stated opinions, name the weak parts. Execute bare instructions.
7. Do not emit a sheet while any load-bearing decision affecting it is open.

## Exit
Every emitted sheet validates against the schema AND the user confirms. No turn budget; some decisions close in one exchange, some in several. Premature closure is worse than another loop.

## Hand-off
- Write each feature's sheet to `.building/features/<feature-name>/increments.md`, creating the folder if needed, where <feature-name> is that feature's short kebab-case name.
- Each file is the build phase input for that feature.
- The feature name is the feature's key: many features coexist as sibling folders under `.building/features/`; re-running the same name overwrites it (latest wins).
- `.building/` is gitignored, so sheets stay local; the build loop reads each from its path via the sheet path in state.json.
- Design phase only writes sheets; it never triggers a build. Human builds each feature on command, one build-loop invocation per feature.

## Excludes
No roles beyond user and partner, no severity, no commit. Design produces the sheets; building them is the next contract. Epic-level grouping of features is the human's, not modelled here.
