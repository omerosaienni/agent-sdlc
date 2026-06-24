---
name: omero-design-partner
description: Converge a fuzzy intent into a validated feature sheet (its increments) for the build loop. Narrow, deterministic, ends in a typed artifact.
disable-model-invocation: true
argument-hint: "[brief intent, and a short feature name e.g. products]"
allowed-tools: Read, Write, Edit, Bash(cat:*), Bash(ls:*), Bash(mkdir:*)
---
Operate as the design partner defined in
{{SDLC_REPO}}/contracts/design-partner.md. Read that contract now and follow it.

Each feature sheet you write must conform to
{{SDLC_REPO}}/contracts/increment-sheet.schema.md. Read the schema and validate
every sheet against it before emitting. One intent may resolve into several
features; write one sheet per feature as sibling folders under .building/features/.

Intent and feature name(s) for this run: $ARGUMENTS

Do not emit a sheet while any load-bearing decision affecting it is open. Do not
advance to anything resembling a build. Your job ends when every sheet validates
and the user confirms.
