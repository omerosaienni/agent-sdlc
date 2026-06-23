# Document agent

Produce documentation for a verified deliverable, after the judge passes and before the PR. A producer, not a gate: it never evaluates, rejects, or blocks. Documentation is best-effort; code verification is mandatory and is never compromised by a documentation problem.

## When it runs
After the judge passes a deliverable, before the orchestrator opens the PR. Its output (docs/) commits atomically with the deliverable, alongside the code. Reports are not committed; they stay local under .building/.

## Inputs (assemble, do not re-derive)
- The doc payload at .building/build/<design-name>/work/<branch-name>/doc-payload.md (doc-payload.schema.md), the builder's slice.
- The approved reviewer report (architecture and design decisions).
- The judge report (verified behaviour).
A quick scan of the public interface to confirm, not a full re-read of the code.

## Outputs
- Per-deliverable doc: docs/modules/<id>-<module-filename>.md. Named after the primary module file it documents, so it tracks the code, not the title. Renders the seven payload fields as a clean module reference.
- Project rollup: an idempotent section in docs/ARCHITECTURE.md between markers <!-- <id> --> and <!-- /<id> -->. Re-documenting a deliverable REPLACES its block, never duplicates. The doc carries a module index, an accumulated key-decisions log, and a dependency graph.
- Dependency graph: regenerated as coloured Mermaid from the sheet's depends_on (roots one colour, dependents another, matching the palette), inside docs/ARCHITECTURE.md. Mermaid because it is text, regenerable, and GitHub renders it.

## Never-block invariant (inviolable)
The deliverable always commits and opens its PR once the judge has passed, regardless of documentation outcome. If the payload is incomplete or generation partially fails, the document agent writes what it can and marks missing parts "documentation incomplete: <reason>". It does not wait, retry-block, or reject. A documentation gap is visible but never stops verified work.

## Degradation
Missing builder slice: fill from the reports, mark absent fields "not provided". Missing a report: document from what exists, note the gap. Always produce something; never nothing, never a block.

## Excludes
No verification metrics (the reports own those). No evaluation or verdict (it is not a judge). No standalone whole-project regeneration yet (a possible future skill, not built).
