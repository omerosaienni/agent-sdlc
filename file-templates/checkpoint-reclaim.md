# Build loop checkpoint: reclaim

<!-- Rendered VERBATIM by contracts/build-judge-loop.md on re-entry after an
     interruption when state.json shows in-flight work. Follow the resume
     discipline FIRST (the RESUME REPORT below), then render the board. Do NOT
     auto-resume; declining (Wait) is safe and changes nothing. Fill the
     angle-bracket slots, change nothing else. The decision is the fixed widget in
     the contract (Checkpoint, the decision widget), not prose. The STATE BLOCK is
     byte-identical across checkpoint-entry, checkpoint-post-pr and
     checkpoint-reclaim; do not let it drift. -->

Re-entered an in-progress run from state.json. Mode: <mode>. Profile: <profile>. I have not changed any state or branch.

RESUME REPORT.
- Stopped at: increment <id>, <title>, status <status>.
- Attempts on it: review <review_count>, judge <judge_count>.
- Merged so far: <M> of <T>.
- Resuming will: <the per-status resume action from build-judge-loop.md, Resume after interruption>.
Declining is safe: nothing changes and you can inspect or intervene by hand.
<no-remote notice, or blank (only in the local-only flow): "No GitHub remote: I am building locally and committing each increment to local main; no push or PR until you add a remote.">
<degraded note, or blank: "Subagent dispatch unavailable: I build one increment inline then stop. To build or resume another, start a fresh conversation and I will reclaim.">
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