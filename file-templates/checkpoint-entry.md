# Build loop checkpoint: entry

<!-- Rendered VERBATIM by contracts/build-judge-loop.md on first entry, or when a
     fresh conversation continues a run with no interruption to recover. Fill the
     angle-bracket slots, change nothing else. The decision is the fixed widget in
     the contract (Checkpoint, the decision widget), not prose. The STATE BLOCK is
     the shared file-templates/checkpoint-board.md, inserted verbatim at the marker
     below; it is not copied here, so it cannot drift. -->

Build loop. Mode: <mode>. Profile: <profile>. Sheet: <sheet path>.
<no-remote notice, or blank (only in the local-only flow): "No GitHub remote: I will build locally and commit each increment to local main; no push or PR until you add a remote.">
<degraded note, or blank: "Subagent dispatch unavailable: I build one increment inline then stop. To build or resume another, start a fresh conversation and I will reclaim.">
<completion-gate note (lite profile only, keyed on the completion block), or blank: "Completion gate: running the full integration suite." (integration pending), "Completion gate: the integration suite failed; append a fix increment to the sheet and I will build it, then re-run the gate." (integration failed), or "Completion gate: running the documentation sweep." (integration passed, docs pending)>
<OTHER QUEUES (sibling feature queues with open work), one line each: "other queue <feature-name>: <n> in flight, <n> awaiting merge, <n> escalated, <n> blocked", with ", completion gate: <integration|docs state>" appended when a lite sibling is parked at an unfinished completion gate; or blank if none>

<!-- STATE BLOCK: insert file-templates/checkpoint-board.md here verbatim, filling its slots. -->
$\n(Choose below; the decision widget is fixed, see the contract.)\n