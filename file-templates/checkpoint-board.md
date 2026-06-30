<!-- The STATE BLOCK: the single source of the checkpoint board, shared by
     checkpoint-entry, checkpoint-post-pr and checkpoint-reclaim. Each of those
     templates inserts this block VERBATIM at its STATE BLOCK marker, filling the
     angle-bracket slots and changing nothing else. Editing the board edits this one
     file; the three templates never carry their own copy. Rendered from
     scripts/board-state.sh output (build-judge-loop.md, The board). -->

this queue: <M> of <T> merged to main (<merged id list>).

POSSIBLY STALLED (state is not pending, merged or pr-open):
- <id> <title> <★ or blank> -- increment <id> is in state <status>, this may be stalled.
<!-- one row per increment whose status is not pending/merged/pr-open, lowest id first. If none, write exactly: None. -->

AWAITING MERGE (PR open, you merge):
- <id> <title> <★ or blank> -- branch <branch>. Merge to unblock <dependent ids, or "no dependents">.
<!-- one row per pr-open increment, lowest id first; in the lite profile, also one row for the completion docs PR when completion.docs is pr-open (id completion-docs, title "documentation sweep", no star, branch docs/<feature-name>-completion, "no dependents"), placed last. If none, write exactly: None. -->

READY (all deps merged):
- <id> <title> <★ or blank> -- deps <satisfied dep ids> merged.
<!-- one row per ready increment, lowest id first. If none, write exactly: None. -->

BLOCKED (waiting on an unmerged dep):
- <id> <title> <★ or blank> -- needs <unmerged dep ids, each with its status>.
<!-- one row per blocked increment, lowest id first. If none, write exactly: None. -->

Legend. ★ = on a longest dependency chain through the sheet, from a root to a terminal (an increment nothing depends on; there may be several terminals, and chains may tie). It marks the longest path to done, not importance or priority. Starred rows appear in every section so the whole critical path is visible.
