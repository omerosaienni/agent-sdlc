# Build loop checkpoint: post-PR

<!-- Rendered VERBATIM by contracts/build-judge-loop.md immediately after the loop
     opens a PR. The loop STOPS here; it does not cut the next branch until you
     choose (and in sequential-attended, not until the PR merges). Fill the
     angle-bracket slots, change nothing else. The decision is the fixed widget in
     the contract (Checkpoint, the decision widget), not prose. The STATE BLOCK is
     byte-identical across checkpoint-entry, checkpoint-post-pr and
     checkpoint-reclaim; do not let it drift. -->

PR opened for increment <id>, <title> (branch <branch>). Mode: <mode>. Stopped at the post-PR checkpoint; I have not cut the next branch.
<degraded note, or blank: "Subagent dispatch unavailable: I built one increment inline and stopped. To build or resume another, start a fresh conversation and I will reclaim.">
<OTHER QUEUES (sibling feature queues with open work), one line each: "other queue <feature-name>: <n> in flight, <n> awaiting merge, <n> escalated, <n> blocked"; or blank if none>

<!-- STATE BLOCK START (byte-identical across the three checkpoint templates) -->
this queue: <M> of <T> merged to main (<merged id list>).

POSSIBLY STALLED (state is not pending, merged or pr-open):
- <id> <title> <★ or blank> -- increment <id> is in state <status>, this may be stalled.
<!-- one row per increment whose status is not pending/merged/pr-open, lowest id first. If none, write exactly: None. -->

AWAITING MERGE (PR open, you merge):
- <id> <title> <★ or blank> -- branch <branch>. Merge to unblock <dependent ids, or "no dependents">.
<!-- one row per pr-open increment, lowest id first. If none, write exactly: None. -->

READY (all deps merged):
- <id> <title> <★ or blank> -- deps <satisfied dep ids> merged.
<!-- one row per ready increment, lowest id first. If none, write exactly: None. -->

BLOCKED (waiting on an unmerged dep):
- <id> <title> <★ or blank> -- needs <unmerged dep ids, each with its status>.
<!-- one row per blocked increment, lowest id first. If none, write exactly: None. -->

Legend. ★ = on a longest dependency chain through the sheet, from a root to a terminal (an increment nothing depends on; there may be several terminals, and chains may tie). It marks the longest path to done, not importance or priority. Starred rows appear in every section so the whole critical path is visible.
<!-- STATE BLOCK END -->
$\n(Choose below; the decision widget is fixed, see the contract.)\n