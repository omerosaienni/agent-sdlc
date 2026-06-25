---
version: 1.1.0
status: active
---

# Script layout

Canonical internal structure every shell script in this repo follows. Same read
order everywhere: helpers in one place, args parsed in one place, real work in
banner'd sections. Output *idiom* may differ by job (see below); the *skeleton*
is fixed.

## Versioning

Semantic version frontmatter. Bump meaning:

- major: breaking. Existing scripts now violate the layout and must be reorganised to comply.
- minor: additive. New allowed section or option that does not break compliant scripts.
- patch: clarification or wording fix, no structural meaning.

Frontmatter minimal on purpose (version and status only). Title is the H1 below;
dates live in git history. Do not add fields that duplicate what is available
elsewhere.

## The skeleton (top to bottom)

1. **Shebang and header comment.** `#!/usr/bin/env bash`, then a comment block
   stating in one line: what the script does, usage, every flag, exit codes.
   `--help` handler may print this block back.

2. **`set` options.** `set -euo pipefail` by default. May use `set -uo pipefail`
   without `-e` only if it manages its own failure accumulation (e.g. a `fail`
   counter that decides the exit code), and a comment must say so. Naming the
   exception is required; a silent missing `-e` is a defect.

3. **Constants.** Fixed values near the top, overridable by env only where that
   is genuinely a dial (e.g. an allowlist a different machine overrides). Per the
   project rule, only make a value configurable when it is actually a dial.

4. **Helpers.** All functions in one block, before any are called. Colour setup,
   output helpers, logic helpers together. Single place to find every function
   the script defines.

5. **Argument parsing.** One loop. Flags, never environment variables, for
   behaviour the caller chooses. `--help` handled. Unknown options error via the
   usage helper.

6. **Resolve and validate inputs.** Everything needed is computed and checked
   here, before any side effect. Derive values, probe the environment, fail early
   on bad input. Nothing destructive happens before this passes.

7. **The work, in banner'd ordered sections.** Each unit of work is a labelled
   block. Use a consistent banner:

   ```
   # ---------------------------------------------------------------------------
   # Area name: one line on what this section does.
   # ---------------------------------------------------------------------------
   ```

   Announce the area to the user with the script's output idiom (see below).

8. **Finish.** Terminal outcome: a producer prints next steps; a verifier prints
   a verdict and writes its receipt.

## Output idiom (differs by job, deliberately)

Skeleton fixed; output *shape* is not. Produce and verify are different jobs; a
forced-identical output would make each worse.

- **Producer** (writes things, e.g. the generator): a step flow. One `==>` line
  per area, optional per-item detail under `--verbose`.
- **Verifier** (checks things, e.g. the setup gate): a check list. One
  `OK`/`FAIL`/`BLOCK`/`NEED` line per check, with a final verdict.

Both share colour handling, flag conventions, and helper-block structure. Only
the per-line idiom differs.

## Colour and verbosity (shared conventions)

- Colour enabled only when: stdout is a real terminal, `TERM` is not `dumb`, and
  user has not opted out (`NO_COLOR`, or a `--no-color` flag). Keeps escape codes
  out of piped or redirected output.
- Behaviour the caller chooses is a flag, never an environment variable.
  `--verbose` for detail, `--debug` for a `set -x` trace, `--no-color` to force
  plain output.

## Multi-file scripts (orchestrator and layers)

A script that grows large or composes optional parts may split into an
orchestrator plus sourced component files, rather than one monolith. The skeleton
above still governs the orchestrator; components follow these rules:

- **One orchestrator.** Entry-point script (in `scripts/`) owns the skeleton:
  header, `set` options, argument parsing, input validation, ordered work. It
  sources the components and calls them; it is the only file the user runs.
- **Components are sourced, not executed.** They live together in a sibling
  directory (e.g. `scripts/generator/`), each `#!/usr/bin/env bash` with a header
  comment saying it is sourced and what it provides. They define functions and
  set variables in the orchestrator's scope; they do not `set -e` or parse args.
- **One shared-helpers file.** Output helpers, colour setup, and file primitives
  live in a single sourced lib the orchestrator and every component use, so there
  is one definition of each helper (the "single place" rule above, across files).
- **Layers own their exclusive files; the orchestrator assembles shared ones.**
  When several layers contribute to one output file (e.g. a `package.json` the
  base, Mongo, React and Express layers all add to), the layer exports a named
  fragment and the orchestrator splices it in. A layer never hard-codes another
  layer's content, and never edits a file another layer owns.

## Reference example

`scripts/init-ts-project.sh` is the reference implementation: an orchestrator
that sources `scripts/generator/lib.sh` (helpers) and the
`scripts/generator/base.sh`, `mongo.sh`, `react.sh`, `express.sh` layers,
assembling the shared files from their fragments. A single-file script should
mirror the skeleton; a composed one should mirror this orchestrator-and-layers
structure.
