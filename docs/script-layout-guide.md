# Script layout, explained

This page is the human rationale behind [`../contracts/script-layout.md`](../contracts/script-layout.md), the terse rule set every shell script in this repo follows. The contract is what an agent applies; this page explains why the shape is the way it is and walks the reference implementation.

## Why one fixed skeleton

Every script reads in the same order: helpers in one place, arguments parsed in one place, the real work in labelled sections. The point is that you never hunt. Open any script and you know the header states what it does and its exit codes, the helpers are grouped before they are called, inputs are validated before anything destructive runs, and the work is a sequence of banner'd blocks. A consistent skeleton means a script you have never seen reads like one you wrote.

The input-validation step (resolve and validate before any side effect) is the load-bearing one: it is what lets a script fail early and cleanly on bad input rather than half-doing its work and leaving a mess. Nothing destructive happens until that step passes.

## Why the output idiom differs by job

The skeleton is fixed but the output is not, and that is deliberate. A script that *produces* something and a script that *verifies* something are doing different jobs, and forcing them to print the same way would make each worse.

- A **producer** (the generator is the example) is telling you a story of what it is building: one step line per area, with detail under `--verbose`. You read it top to bottom as a flow.
- A **verifier** (the setup gate is the example) is answering a question, ready or not: one pass/fail line per check and a verdict at the end. You scan it for the failures.

A producer's step flow would bury a verifier's verdict, and a verifier's check list would make a producer's narrative read like an audit. So they share everything structural (colour, flags, the helper block) and differ only in the per-line shape.

## The reference implementation

`scripts/init-ts-project.sh` is the worked example of the multi-file form. It is an orchestrator that sources `scripts/generator/lib.sh` for the shared helpers and the `scripts/generator/base.sh`, `mongo.sh`, `react.sh` and `express.sh` layers, then assembles the shared files (`package.json`, `tsconfig`, `Makefile`) from the fragments each enabled layer contributes.

It shows the two multi-file rules in practice. Each layer owns its exclusive files outright, but where several layers contribute to one shared file, the layer exports a named fragment and the orchestrator splices it in, so no layer ever hard-codes or edits another's content. And every layer uses the one shared-helpers lib, so there is a single definition of each helper across all the files.

A single-file script should mirror the plain skeleton; a script that grows large or composes optional parts should mirror this orchestrator-and-layers structure rather than becoming one monolith.
