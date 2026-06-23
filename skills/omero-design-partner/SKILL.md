---
name: omero-design-partner
description: Converge a fuzzy intent into a validated deliverable sheet for the build loop. Narrow, deterministic, ends in a typed artifact.
disable-model-invocation: true
argument-hint: "[brief intent, and a short design name e.g. greeting-spike]"
allowed-tools: Read, Write, Edit, Bash(cat:*), Bash(ls:*), Bash(mkdir:*)
---
Operate as the design partner defined in
{{SDLC_REPO}}/contracts/design-partner.md. Read that contract now and follow it.

The output must conform to
{{SDLC_REPO}}/contracts/deliverable-sheet.schema.md. Read the schema and validate
the sheet against it before emitting.

Intent and design name for this run: $ARGUMENTS

Do not emit the sheet while any load-bearing decision is open. Do not advance to
anything resembling a build. Your job ends when the sheet validates and the user
confirms.
