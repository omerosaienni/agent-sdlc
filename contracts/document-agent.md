# Document agent

Produce documentation for verified increments, when the profile says (build-judge-loop.md, Build profile): per increment after the judge passes in full, once at the completion gate in lite (see When it runs). A producer, not a gate: it never evaluates, rejects, or blocks. Documentation is best-effort; code verification is mandatory and is never compromised by a documentation problem.

## When it runs
The profile decides the timing (build-judge-loop.md, Build profile). In full (build-loop-full.md) it runs per increment, after the judge passes and before the orchestrator opens the PR (or, with no remote, integrates the increment into local main); its output (docs/) commits atomically with the increment, alongside the code. In lite (build-loop-lite.md) the per-increment run is deferred: the agent runs once at the feature completion gate, sweeping every increment from its doc-payload.md slice in one pass, and its docs commit separately from the per-increment code commits. Reports are not committed; they stay local under .building/.

## Inputs (assemble, do not re-derive)
- The doc payload at .building/build/<feature-name>/work/<branch-name>/doc-payload.md (doc-payload.schema.md), the builder's slice.
- The approved reviewer report (architecture and design decisions).
- The judge report (verified behaviour).
A quick scan of the public interface to confirm, not a full re-read of the code. In the lite completion-gate sweep (build-loop-lite.md) the agent assembles these same per-increment inputs across every increment in the feature in one pass, producing each increment's outputs below; the assembly is per increment either way, just batched.

## Outputs
- Per-increment doc: docs/modules/<id>-<module-filename>.md. Named after the primary module file it documents, so it tracks the code, not the title. Renders the seven payload fields as a clean module reference.
- Project rollup: an idempotent section in docs/ARCHITECTURE.md between markers <!-- <id> --> and <!-- /<id> -->. Re-documenting an increment REPLACES its block, never duplicates. The doc carries a module index, an accumulated key-decisions log, and a dependency graph.
- Dependency graph: regenerated as coloured Mermaid from the sheet's depends_on (roots one colour, dependents another, matching the palette), inside docs/ARCHITECTURE.md. Mermaid because it is text, regenerable, and GitHub renders it.

## Never-block invariant (inviolable)
Verified code always reaches main regardless of documentation outcome: in full each increment commits once the judge has passed (a PR with a remote, a local-main integration without one) carrying its docs; in lite the increments are already merged and the sweep's docs commit separately at the completion gate, so a documentation problem cannot hold back code either way. If the payload is incomplete or generation partially fails, the document agent writes what it can and marks missing parts "documentation incomplete: <reason>". It does not wait, retry-block, or reject. A documentation gap is visible but never stops verified work, and in lite it never blocks a queue that is otherwise complete (the gate still requires the docs to be committed, but a gap within them is marked, not blocking).

## Degradation
Missing builder slice: fill from the reports, mark absent fields "not provided". Missing a report: document from what exists, note the gap. Always produce something; never nothing, never a block.

## Excludes
No verification metrics (the reports own those). No evaluation or verdict (it is not a judge). No standalone whole-project regeneration yet (a possible future skill, not built).
