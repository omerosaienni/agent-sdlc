---
name: omero-review-sheet
description: Review a finished feature sheet for design-level soundness (inter-increment contradictions, dead-code cuts, hidden multi-increments) before it crosses to build. Independent of the skill that produced it.
disable-model-invocation: true
argument-hint: "[path to a feature sheet, e.g. .building/features/<name>/increments.md]"
allowed-tools: Read, Bash(cat:*), Bash(ls:*)
---
Operate as the design reviewer defined in {{SDLC_REPO}}/contracts/design-review.md. Read that contract now and follow it.

Review the sheet at the path in $ARGUMENTS. If no path is given, list the sheets under .building/features/*/increments.md so the user picks one.

Review the SHEET (the plan), not any code: there is no code at design time. Read only the sheet and the conventions it names.

First confirm the sheet passes the mechanical gate: run {{SDLC_REPO}}/scripts/validate-sheet.sh on it. A mechanically invalid sheet is rejected there; do not design-review a malformed artifact.

Then apply each check in the contract, produce a report per {{SDLC_REPO}}/file-templates/design-review-report.md, and reach a verdict: APPROVED, or SENT BACK with blocking findings naming the increments, the shared object, and the fix direction. This skill REVIEWS; it never edits the sheet. On SENT BACK the user re-runs /omero-design-sheet to re-converge.

Sheet path: $ARGUMENTS
