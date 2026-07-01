# Design review

Independent review of a finished increment sheet for design-level soundness, before it crosses to build. The sheet validator (increment-sheet.schema.md) gates the sheet mechanically (fields, DAG, ordering); this gates it for judgement the script cannot see. Mirrors the build reviewer (build-judge-loop.md, Reviewer rules) one layer up: that role owns the code, this one owns the plan.

## Why this exists
A sheet whose every increment validates and reads well alone can still be unbuildable or unsound as a whole, because the defect lives BETWEEN increments. The designer writing the sheet is inside the work, the same blind spot a builder reviewing its own code has. So an independent role reads the assembled sheet fresh and pushes back before build starts.

## Role
- Owns the plan (the sheet), not the code. Reads the whole sheet fresh, no other context than the sheet and the conventions it names.
- Checks the design-soundness questions below. Can BOUNCE to the designer with findings; does not edit the sheet itself.
- Writes a report each pass (file-templates/design-review-report.md).
- Runs only after the sheet passes `scripts/validate-sheet.sh` (a mechanically invalid sheet is rejected before review; no point reviewing the design of a malformed artifact).

## Checks (design-level; the script cannot see these)
Each finding cites the specific increments and the object or behaviour at issue. A check that holds is stated as holding; silence is not a pass.

1. Inter-increment consistency. No two increments make incompatible claims on a shared object (a file, function, graph, endpoint, config shape). The sharpest case: under the build's monotonic-green invariant the judge re-runs every merged increment's tests when judging a later one, so if increment A's tests pin a behaviour of an object and a later increment B replaces or mutates that object, A's tests go red under B's judge and B cannot pass. A sheet with this conflict is UNBUILDABLE however well each increment reads alone.

2. No dead-code-inducing cut. An increment must not be satisfiable only by adding a production object that nothing in the runtime uses. Watch for the escape from check 1: keeping a now-obsolete object alive solely so an earlier increment's test stays green leaves an unused production class kept alive by a test, a code smell, NOT a resolution. The fix is at the cut, not in the code: re-slice so the increments touch disjoint objects (the earlier increment acts on its OWN object, decoupled from the one a later increment transforms), so neither a contradiction nor a dead object arises.

3. No hidden multi-increment. An increment with many independent failure modes (its test_notes span unrelated behaviours) is likely two increments wearing one heading. Flag for a split.

4. Claimed-but-untested behaviour. Every behaviour a done_definition names must be pinned by an acceptance criterion. A done bar with no runnable check behind it is a claim the build cannot verify.

This list is grown from real defects, not enumerated up front. A new design defect class found in the wild is added here; do not pad it with hypotheticals.

## Verdict
- APPROVED: no blocking findings. The sheet may cross to build.
- SENT BACK: one or more blocking findings. The designer re-converges (re-runs the design loop seeded by the findings) and the sheet is reviewed again. Findings name the increments, the object, and the fix direction (re-slice / decouple / split / add a criterion), not the literal new wording (that is the designer's craft).

A blocking finding is critical or major. A check that is a judgement call the reviewer cannot settle (it depends on intent only the human holds) is surfaced to the human, not silently resolved, consistent with the design partner's own surface-don't-decide discipline.

## Boundaries
- Does NOT re-check the mechanical rules (the validator owns those) nor whether the goal is USEFUL (the designer and human own that).
- Does NOT design. It reviews and bounces; the designer produces. The producer/reviewer separation is the point.
- Reads only the sheet and named conventions. It does not read or run code (there is none yet at design time).

## Workflow placement
Logically: designer emits sheet -> validate-sheet.sh (mechanical gate) -> design review (this) -> build. WIRING this into the design skill or the build entry is a separate decision, made once the review is proven against real sheets. Until then it runs standalone against a given sheet.
