# Build loop checkpoint: post-PR

<!-- Rendered VERBATIM by contracts/build-judge-loop.md immediately after the loop
     finishes an increment within the same conversation: opening a PR with a remote,
     or integrating into local main in the local-only flow. The loop STOPS here; it
     does not cut the next branch until you choose (and in sequential-attended with a
     remote, not until the PR merges). Fill the angle-bracket slots, change nothing
     else. The decision is the fixed widget in the contract (Checkpoint, the decision
     widget), not prose. The STATE BLOCK is the shared
     file-templates/checkpoint-board.md, inserted verbatim at the marker below; it is
     not copied here, so it cannot drift. -->

<increment-done line: with a remote, "PR opened for increment <id>, <title> (branch <branch>)"; in the local-only flow, "Committed increment <id>, <title> to local main (branch <branch>); no remote, so no PR">. Mode: <mode>. Profile: <profile>. Stopped at the post-PR checkpoint; I have not cut the next branch.
<no-remote notice, or blank (only in the local-only flow): "No GitHub remote: I am building locally and committing each increment to local main; no push or PR until you add a remote.">
<degraded note, or blank: "Subagent dispatch unavailable: I built one increment inline and stopped. To build or resume another, start a fresh conversation and I will reclaim.">
<completion-gate note (lite profile only, keyed on the completion block), or blank: "Completion gate: running the full integration suite." (integration pending), "Completion gate: the integration suite failed; append a fix increment to the sheet and I will build it, then re-run the gate." (integration failed), or "Completion gate: running the documentation sweep." (integration passed, docs pending)>
<OTHER QUEUES (sibling feature queues with open work), one line each: "other queue <feature-name>: <n> in flight, <n> awaiting merge, <n> escalated, <n> blocked", with ", completion gate: <integration|docs state>" appended when a lite sibling is parked at an unfinished completion gate; or blank if none>

<!-- STATE BLOCK: insert file-templates/checkpoint-board.md here verbatim, filling its slots. -->
$\n(Choose below; the decision widget is fixed, see the contract.)\n