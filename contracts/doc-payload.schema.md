# Documentation payload schema

Typed seam between the working agents and the document agent. Each increment accumulates a payload the document agent assembles into docs. Each agent contributes only what it uniquely knows; no agent restates another's slice.

## Location
`.building/build/<feature-name>/work/<branch-name>/doc-payload.md`, gitignored working file, written as the agents work.

## Fields (the durable essence, distinct from the verification record in the reports)
- id, title: from the sheet.
- purpose: one line, what this module is for. [builder]
- public interface: the exported surface other code uses this through. [builder]
- key decisions: each a decision plus why, the non-obvious ones only. [builder, plus reviewer report's architecture section]
- verified behaviour: one line on what the judge confirmed works. [judge]
- gotchas: constraints, surprises, things a future reader would trip on. [builder, plus reviewer suggestions]
- dependencies: what this builds on. [depends_on, from the sheet]

## Sources the document agent reads
1. This payload file (the builder's slice).
2. The approved reviewer report (architecture and design decisions).
3. The judge report (verified behaviour).
Does NOT re-read all the code; reads these plus a quick scan of the public interface to confirm.

## Degradation
If the builder slice is absent or partial, fill what you can from the reports and mark missing fields "not provided". Never blocks. The reviewer separately notes a missing slice as a non-blocking suggestion, so quality is visible without compromising the never-block guarantee.

## Excludes
No coverage tables, test inventories, or verification metrics. Those are the reports' job. The payload is what a reader needs to understand the module, not proof it works.
