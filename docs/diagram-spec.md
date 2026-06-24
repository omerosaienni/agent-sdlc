# Diagram spec

Diagrams live in `docs/diagrams/`.

Canonical definition of the SDLC visual set. The SVGs in docs/ are hand-authored artifacts; this spec is their source of truth. The SVGs are small, plain markup, so a diagram is edited or added directly in the repo. When a diagram changes, update the affected SVG AND its catalogue entry here, so the spec never drifts from the diagrams.

## Shared conventions (every diagram follows these)

### Colour palette (hex, hardcoded for light and dark)
- Builder / actor-blue: fill #E6F1FB, stroke #185FA5, title #0C447C, text #185FA5
- Reviewer / purple: fill #EEEDFE, stroke #534AB7, title #3C3489, text #534AB7
- Judge / teal: fill #E1F5EE, stroke #0F6E56, title #085041, text #0F6E56
- Orchestrator, process, file / grey: fill #F1EFE8, stroke #5F5E5A, title #444441, text #5F5E5A
- Input, output, artifact, gate / amber: fill #FAEEDA, stroke #854F0B, title #633806, text #854F0B
- Neutral arrow / line: #73726c
- Body secondary text: #5F5E5A

### Shape vocabulary (shape carries category, colour carries role)
- Rounded rectangle (rx 8 to 10): an actor (agent) or a process step.
- Folded-corner rectangle: a file on disk. Draw as a path with the top-right corner folded in by 24px: M x y, L (x+w-24) y, L (x+w) (y+24), L (x+w) (y+h), L x (y+h), Z, plus a fold line M (x+w-24) y, L (x+w-24) (y+24), L (x+w) (y+24). This is the standard document marker, like a cylinder means database.
- Plain rectangle (no rounding): a phase.

### Canvas
- viewBox width 680 (desktop). Height to fit. Fonts sans-serif. Title text ~14 to 16px weight 500, body ~12px.
- Arrow marker: a path M2 1 L8 5 L2 9, stroke-width 1.5, orient auto, refX 8.
- Standalone SVGs use the hardcoded hex above so they render the same in light and dark and embed in markdown.

## Catalogue (each diagram: file, what it shows, nodes, relationships)

### pipeline-overview.svg
Three-phase pipeline. Design (purple) produces the feature sheet (amber file); setup gate (teal) produces the receipt (amber file); the two are independent parallel prerequisites that both feed the build loop (blue), which repeats per increment and ends at queue complete (grey). Label: design and setup are independent, either order. The two gates are independent.

### build-judge-loop.svg
Per-increment loop drawn as a supervisor pattern. Left: the orchestrator lane (grey), labelled as your /omero-build-loop session, the conductor; it spawns each subagent (dashed spawn arrows from the lane), sequences them, owns state.json, and commits and opens the PR itself (dashed tie from the lane to the Open PR box). Centre column, the subagents the orchestrator spawns with fresh context each: Builder (blue) -> Reviewer (purple, approved) -> Judge (teal, unit then integration, passed) -> Document (amber, producer never blocks) -> Open PR into main (grey, an orchestrator action) -> Human merges the PR (outlined, not filled: you, the final gate, not an agent) -> advance. Right side: reviewer bounce <=3 (purple) and judge reject <=3 (teal) arcs back to the builder. Three actor treatments: orchestrator lane (spawns and does git), subagents (filled colour boxes), human (outlined).

### endpoint-block.svg
Four-step sequence: Judge checks endpoint readiness (teal) -> down -> Environment block, tells you in the session, names the endpoint and bring-up, no judge attempt spent (amber) -> You bring it up and confirm (grey, make up) -> Judge re-checks and continues (teal).

### role-orchestrator.svg, role-builder.svg, role-reviewer.svg, role-judge.svg, role-document.svg
Role cards, one per agent role plus the orchestrator. Coloured header (role colour) with name and tagline, then four rows: Owns, Produces, Cannot, Context. The Cannot row is the role boundary. The document card is amber and its Cannot row is "block, reject, or evaluate an increment" (it is the only role that never gates). Content per role is in build-judge-loop.md.

### roles-comparison.svg
The orchestrator and all four agent roles side by side as small coloured boxes (orchestrator grey, builder blue, reviewer purple, judge teal, document amber), with rows: owns (sequence+state / the increment / the code / the behaviour / the docs), context (passive / building / informed / fresh / producer), can block (no / no / bounce <=3 / reject <=3 / no). Caption: reviewer and judge split on code-vs-behaviour and informed-vs-fresh, which is why neither is redundant; the document agent is the only agent that never gates.

### loop-data-flow.svg
Vertical data flow. Shared inputs (amber file: feature sheet + CLAUDE.md, available to all) -> Builder (blue) -> code + tests + builder.md + doc-payload.md (grey FILE) -> Reviewer (purple) -> review report: record + bounce (grey FILE) -> Judge (teal, runs the suite itself) -> judge report: verdict + per-tier coverage (grey FILE) -> on pass the Document agent (amber, producer, never blocks) -> docs/modules + ARCHITECTURE.md (grey FILE) -> the orchestrator commits code and docs/ only (reports stay local under .building/) and opens the PR (amber file); human merges. All on-disk artifacts use the folded-corner file shape.

### io-orchestrator.svg, io-builder.svg, io-reviewer.svg, io-judge.svg, io-document.svg
Input/output cards, one per agent role plus the orchestrator. Coloured header, then Inputs (left) and Outputs (right) lists with an arrow between. The builder lists its doc-payload.md slice as an output; the document card takes the doc-payload slice plus the reviewer and judge reports as inputs and produces docs only, never a verdict. Contents per agent match the role and data-flow definitions.

### file-layout.svg
Two boxes: committed versus gitignored. Committed (green): the increment, code plus docs/ (modules and ARCHITECTURE.md). Gitignored (grey): the whole .building/ folder, all loop output, never committed. Inside .building/: project-level setup-ok and scripts/ (the three runners) at the top, then build/ with one folder per feature (feature queue); each build/<feature-name>/ holds its own state.json (carrying that queue's mode), a work/<branch-name>/ tree per unit (builder.md, review-pass-N.md, judge.md, doc-payload.md; an escalations/ subfolder if escalated), and that queue's escalations/ index of relative symlinks into its own work folders. One gitignore rule: .building/. Shows the file-based, no-memory architecture and the per-feature state layout.

### sequence-spawn.svg
Sequence diagram, dynamics over time. Lifelines for the orchestrator (grey) and the four subagents (builder blue, reviewer purple, judge teal, document amber). The orchestrator spawns each subagent in turn (solid arrow), the subagent does work (activation bar on its lifeline) and writes a file then ends (dashed return). Notes mark the bounce respawn (max 3) and the reject respawn (max 3). The judge spawn is labelled fresh context, the property to verify on a real run. The orchestrator then commits, opens the PR, and writes state itself (self activation). The human merges (outlined). Shows the spawn-work-end rhythm the static diagrams cannot.

### increment-states.svg
State machine for one increment as tracked in state.json. The state set is the canonical enum from build-judge-loop.md and must match it exactly: pending, building, in-review, in-judgement, documented, pr-open, merged, escalated, blocked (the diagram may render readable labels like "in review" but the set is the same). Happy path along the top: pending (grey) -> building (blue) -> in review (purple) -> in judgement (teal) -> documented (amber) -> PR open (grey) -> merged (outlined, the only success terminal). Coloured loops back to building: bounce (purple) and reject (teal). Two interruption states below, reached by dashed amber arrows: escalated (after 3 fails, waits for you) and blocked (endpoint down, pauses then resumes). A dashed purple recovery edge runs from escalated back to in-review: you fix on the branch and continue, and the work re-enters verification from the reviewer. The orchestrator records each transition.

### error-paths.svg
Error path map. Each interruption as a row: Reviewer bounce (purple) and Judge reject (teal) both respawn from the builder, budget 3, then escalate (amber). A type error (the type-check gate the judge runs first) and a hollow suite (teal) are both hard fails counting as a reject; a type-check that cannot run is an environment block, like endpoint down. Endpoint down (amber) pauses with no attempt spent, not a failure. Missing doc slice (amber) degrades, marks the gap, never blocks. Caption: two kinds of interruption, those that cost an attempt and can escalate, and those that never fail verified work; the line between them is the design.

### git-topology.svg
Branch topology of sequential-attended mode. One horizontal main line (grey). Each increment cuts a branch (blue) from a freshly-fetched origin/main, named after the work (<id>-<kebab-title>, e.g. d3-connection-helper, for audit), does the work, and opens a PR back into main (dark arrow) which the human merges. The next increment cuts fresh from the updated origin/main only after the previous PR merged. There is no integration branch and no second hop. main is green after every merge; each PR is one increment's audit record. Caption explains the per-increment cut, build, review, judge, document, PR, merge, and that this is the sequential mode; the parallel counterpart is parallel-topology.svg.

### parallel-topology.svg
Branch topology of parallel-attended mode, the counterpart to git-topology.svg. One horizontal main line (grey) with a single dashed vertical guide marking the current origin/main where every eligible increment is cut. Several sibling branches (blue) start from that one guide, never stacked on each other, each opening a PR (dark arrow) back to a distinct merge point on main. A dashed sibling marks more. Caption: each branch is built and verified against main as it stood at its own cut, in isolation; the human merges the siblings in any order and resolves conflicts; green is per-branch not per-main, so re-run the suite after combining; the loop never merges or stacks. Shows the structural difference from the sequential topology: one cut point, a fan of independent siblings, the human combines.

### checkpoint.svg
The checkpoint cycle, shared by both modes, drawn as a flowchart. A board node (grey) sorts each increment by its state into four sections (POSSIBLY STALLED and AWAITING MERGE in amber as the human-action categories, READY in blue, BLOCKED in grey) and the star legend (longest chain to done). An arrow leads to the decision node (amber), ask_user_input with up to five fixed chips, only the applicable ones and Wait always: Carry on, Build a specific one, Merge the PR, Resume the stalled one, Wait. Carry on and Build a specific one and the build-like Resume funnel to one outcome (blue, produce a PR and return); Merge the PR to a human-merge outcome (amber, the loop reconciles state); Wait is an outlined terminal. Dashed grey loop-back arrows return the non-wait outcomes to the board, showing the stop-after-every-PR cycle. A side note states the only mode difference: Carry on and Build a specific one appear whenever READY is non-empty in parallel-attended, but only when nothing else is in flight in sequential-attended. Caption notes the degraded one-per-conversation behaviour and that the labels never reword.

## Regeneration instructions
- "Regenerate all": rebuild every catalogue entry as an SVG using the conventions above.
- "Update <name>": change one diagram; then update its catalogue entry here.
- "Add a diagram of <X>": create it to the conventions, append a catalogue entry.
- Generated (not hand-built) diagrams, such as the document agent's dependency graph, are Mermaid with classDef colours from the palette, not SVG.
