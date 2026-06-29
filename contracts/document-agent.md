# Document agent

Produces docs for verified increments per profile (build-judge-loop.md, Build profile). Producer, not gate: never evaluates, rejects, or blocks. Docs are best-effort; code verification is mandatory and never compromised by a doc problem.

## When it runs
Profile decides timing (build-judge-loop.md, Build profile):
- full (build-loop-full.md): per increment, after the judge passes, before the orchestrator opens the PR (or, no remote, integrates the increment into local main). Output (docs/) commits atomically with the increment, alongside the code.
- lite (build-loop-lite.md): per-increment run deferred. Runs once at the feature completion gate, sweeping every increment from its doc-payload.md slice in one pass. Docs commit separately from the per-increment code commits.
- Reports never committed; stay local under .building/.

## Inputs (assemble, do not re-derive)
- Doc payload at .building/build/<feature-name>/work/<branch-name>/doc-payload.md (doc-payload.schema.md), the builder's slice.
- Approved reviewer report (architecture and design decisions).
- Judge report (verified behaviour).
- Quick scan of the public interface to confirm, not a full re-read of the code.
- lite completion-gate sweep (build-loop-lite.md): assemble these same per-increment inputs across every increment in one pass, producing each increment's Outputs below. Assembly is per increment either way, just batched.

## Outputs
- Per-increment doc: docs/modules/<id>-<module-filename>.md. Named after the primary module file it documents, so it tracks the code not the title. Renders the payload fields (doc-payload.schema.md) as a clean module reference.
- Project rollup: idempotent section in docs/ARCHITECTURE.md between markers <!-- <id> --> and <!-- /<id> -->. Re-documenting an increment REPLACES its block, never duplicates. Carries a module index, accumulated key-decisions log, and dependency graph.
- Dependency graph: the coloured Mermaid (roots one colour, dependents another) is the `mermaid` field of `scripts/board-state.sh` (build-judge-loop.md, The board), embedded inside docs/ARCHITECTURE.md. The same script the orchestrator's board uses owns the graph, so the two never drift; do not re-derive it from depends_on by hand. Mermaid because it is text, regenerable, and GitHub renders it.

## Never-block invariant (inviolable)
Verified code always reaches main regardless of doc outcome:
- full: each increment commits once the judge passes (PR with a remote, local-main integration without one) carrying its docs.
- lite: increments already merged; sweep's docs commit separately at the completion gate.
A doc problem cannot hold back code either way. If the payload is incomplete or generation partially fails, write what you can and mark missing parts "documentation incomplete: <reason>". Do not wait, retry-block, or reject. A doc gap is visible but never stops verified work. In lite it never blocks an otherwise-complete queue: the gate still requires docs committed, but a gap within them is marked, not blocking.

## Degradation
- Missing builder slice: fill from the reports, mark absent fields "not provided".
- Missing a report: document from what exists, note the gap.
- Always produce something; never nothing, never a block.

## Excludes
- No verification metrics (the reports own those).
- No evaluation or verdict (not a judge).
- No standalone whole-project regeneration yet (possible future skill, not built).
