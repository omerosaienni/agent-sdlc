---
version: 1.0.0
status: active
---

# Agent runner output contract

The seam that lets one shared hollow-check runner serve every stack. The judge runs tests and type-checks through per-stack runners the setup gate places under `.building/scripts/`; this contract pins what those runners must return so the stack-neutral machinery above them (the judge, the single shared `agent-hollow.sh`) reads the result the same way regardless of stack. Referenced by build-judge-loop.md and by each stack's runner templates under `file-templates/runners/<stack>/`.

## The principle (why exit codes, not output strings)
The exit code is the contract; the terse line is advisory. Machines read the code, humans read the line. The judge already follows this everywhere else (build-judge-loop.md: "relies on its terse line and exit code; it never appends shell"); this contract makes the hollow check follow it too, so nothing parses one stack's wording. A runner MAY print any terse summary it likes on pass and full output on failure; no other script depends on those words. Two stacks differ only in the commands underneath, never in the codes they return.

## `agent-tests.sh <tier> [path]...` exit codes (load-bearing, identical across stacks)
- 0: the tier ran and every selected test passed.
- 1: the tier ran and at least one test failed (a behaviour failure).
- 2: the tier selected zero tests (a hollow suite: nothing ran, not a pass).
- 3: the tier could not run at all (environment: tooling or config absent or broken; no suite executed).

A stack's `agent-tests.sh` MUST map its native runner onto exactly these codes. TypeScript (vitest) and Python (pytest) both already produce them; the mapping is the runner's job, not the caller's.

## `agent-typecheck.sh` exit codes (load-bearing, identical across stacks)
- 0: clean, no type errors (proceed to the tiers).
- 1: type errors (a rejection: returned to the builder, consumes a judge attempt).
- 3: the check could not run (no config, the type-checker not installed, a config error): an environment block, not a rejection, consumes no attempt.

There is no code 2 for type-check: a type-checker either checks, errors, or cannot run.

## How `agent-hollow.sh` classifies, by `agent-tests.sh`'s exit code ALONE
The hollow check plants a behavioural fault, runs the scoped tier once (the negative run), then restores and runs it again (the restore-verify run). It reads only the exit code of `agent-tests.sh`, never its output text, so it is stack-neutral. The negative run's verdict:
- rc 0 -> HOLLOW: the tier stayed green with the code broken, so the test never asserted the broken behaviour. The hollow failure (the check's own exit 1).
- rc 1 -> ASSERTS: a test failed on the fault, so the test is real. The pass (the check's own exit 0).
- rc 2 -> BAD FAULT: the fault made the tier select no tests, so it was not behavioural; re-pick (the check's own exit 2).
- rc 3 -> BAD FAULT: the fault stopped the tier from running at all (it broke compilation or import), so it was not a behavioural fault; re-pick (the check's own exit 2).

The rc-3 asymmetry (the careful part): a could-not-run during the NEGATIVE run is BAD FAULT (our planted fault broke the build, re-pick a behavioural one), but a could-not-run during the RESTORE-VERIFY run is HALT (the check's own exit 3: the tree did not return to green). Same on both stacks: a TypeScript fault that breaks the compile and a Python fault that breaks the import are both non-behavioural faults to re-pick, and a failed restore is a halt either way.

## Why this holds the core stack-agnostic
Adding a stack means writing its `agent-tests.sh` and `agent-typecheck.sh` to return these codes and placing them from `file-templates/runners/<stack>/`. The shared `agent-hollow.sh` (`file-templates/runners/agent-hollow.sh`) is never copied per stack and never changes: it parses integers, not words. The judge, the orchestrator and the schemas never learn the stack. The stack lives in the generator and in these placed runners, exactly where the pipeline says stack lives.
