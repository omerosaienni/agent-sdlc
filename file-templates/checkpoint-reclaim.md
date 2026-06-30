# Build loop checkpoint: reclaim

<!-- Rendered VERBATIM by contracts/build-judge-loop.md on re-entry after an
     interruption when state.json shows in-flight work. Follow the resume
     discipline FIRST (the RESUME REPORT below), then render the board. Do NOT
     auto-resume; declining (Wait) is safe and changes nothing. Fill the
     angle-bracket slots, change nothing else. The decision is the fixed widget in
     the contract (Checkpoint, the decision widget), not prose. The STATE BLOCK is
     the shared file-templates/checkpoint-board.md, inserted verbatim at the marker
     below; it is not copied here, so it cannot drift. -->

Re-entered an in-progress run from state.json. Mode: <mode>. Profile: <profile>. I have not changed any state or branch.

RESUME REPORT.
- Stopped at: increment <id>, <title>, status <status>.
- Attempts on it: review <review_count>, judge <judge_count>.
- Merged so far: <M> of <T>.
- Resuming will: <the per-status resume action from build-judge-loop.md, Resume after interruption>.
Declining is safe: nothing changes and you can inspect or intervene by hand.
<no-remote notice, or blank (only in the local-only flow): "No GitHub remote: I am building locally and committing each increment to local main; no push or PR until you add a remote.">
<degraded note, or blank: "Subagent dispatch unavailable: I build one increment inline then stop. To build or resume another, start a fresh conversation and I will reclaim.">
<completion-gate note (lite profile only, keyed on the completion block), or blank: "Completion gate: running the full integration suite." (integration pending), "Completion gate: the integration suite failed; append a fix increment to the sheet and I will build it, then re-run the gate." (integration failed), or "Completion gate: running the documentation sweep." (integration passed, docs pending)>
<OTHER QUEUES (sibling feature queues with open work), one line each: "other queue <feature-name>: <n> in flight, <n> awaiting merge, <n> escalated, <n> blocked", with ", completion gate: <integration|docs state>" appended when a lite sibling is parked at an unfinished completion gate; or blank if none>

<!-- STATE BLOCK: insert file-templates/checkpoint-board.md here verbatim, filling its slots. -->
$\n(Choose below; the decision widget is fixed, see the contract.)\n