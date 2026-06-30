---
version: 2.1.0
status: active
---

# Script layout

Canonical structure every shell script in this repo follows. The skeleton is fixed; the output idiom differs by job. Human rationale and the worked example are in docs/script-layout-guide.md; this contract is the terse rule set.

## Versioning
Semver frontmatter. major: breaking, existing scripts now violate the layout. minor: additive section/option, compliant scripts unaffected. patch: wording. Frontmatter is version and status only; the title is the H1, dates are in git.

## Skeleton (top to bottom)
1. Shebang + header comment: `#!/usr/bin/env bash`, then one block stating what it does, usage, every flag, exit codes. A terminal-callable script MUST answer `--help` (and `-h`) by printing this block to stdout and exiting 0 (the convention: `grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'`). Sourced components (a lib or layer with no shebang-run path, defining functions in an orchestrator's scope) are exempt: they are never called directly.
2. `set` options: `set -euo pipefail` by default. `set -uo pipefail` (no `-e`) only if the script accumulates its own failures (e.g. a fail counter deciding the exit), and a comment MUST name the exception. A silent missing `-e` is a defect.
3. Constants: fixed values near the top, env-overridable only where the value is genuinely a dial.
4. Helpers: all functions in one block before any call. Colour, output, logic helpers together.
5. Argument parsing: one loop. Flags, never env vars, for caller-chosen behaviour. `--help`/`-h` prints the header and exits 0 (success, to stdout, distinct from the error path); unknown options error via the usage helper (stderr, non-zero). Do not route `--help` through a usage helper that exits non-zero: asking for help is success, not an error.
6. Resolve and validate inputs: compute and check everything before any side effect. Nothing destructive runs before this passes.
7. The work, in banner'd ordered sections. Each unit of work is a labelled block:
   ```
   # ---------------------------------------------------------------------------
   # Area name: one line on what this section does.
   # ---------------------------------------------------------------------------
   ```
8. Finish: a producer prints next steps; a verifier prints a verdict and writes its receipt.

## Output idiom (by job)
Skeleton fixed, output shape not. Producer and verifier are different jobs.
- Producer (writes things, e.g. the generator): a step flow, one `==>` line per area, per-item detail under `--verbose`.
- Verifier (checks things, e.g. the setup gate): a check list, one `OK`/`FAIL`/`BLOCK`/`NEED` line per check, final verdict.
Both share colour handling, flag conventions and helper-block structure; only the per-line idiom differs.

## Colour and verbosity (shared)
- Colour only when stdout is a real terminal, `TERM` is not `dumb`, and not opted out (`NO_COLOR` or `--no-color`).
- Caller-chosen behaviour is a flag, never an env var: `--verbose` detail, `--debug` `set -x` trace, `--no-color` plain.

## Multi-file scripts (orchestrator and layers)
A large or composed script may split into an orchestrator plus sourced components. The skeleton still governs the orchestrator.
- One orchestrator: the entry-point script in `scripts/` owns the skeleton (header, `set`, args, validation, work), sources the components, and is the only file the user runs.
- Components are sourced, not executed: in a sibling dir (e.g. `scripts/generator/`), each with a header saying it is sourced and what it provides. They define functions and set variables in the orchestrator's scope; they do not `set -e` or parse args.
- One shared-helpers file: output, colour and file primitives in a single sourced lib used by the orchestrator and every component, so each helper has one definition.
- Layers own their exclusive files; the orchestrator assembles shared ones. When several layers contribute to one output file, the layer exports a named fragment and the orchestrator splices it in. A layer never hard-codes or edits another layer's content.

Reference implementation: `scripts/init-ts-project.sh` (see docs/script-layout-guide.md for the walkthrough).
