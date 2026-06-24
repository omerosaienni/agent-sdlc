---
version: 1.1.0
status: active
---

# Script layout

The canonical internal structure every shell script in this repo follows, so any
script reads in the same order and you always know where to look: helpers are
always in one place, arguments are parsed in one place, the real work is in
clearly banner'd sections. The output *idiom* may differ by job (see below), but
the *skeleton* is fixed.

## Versioning

This contract carries semantic version frontmatter. The meaning of a bump:

- major: a breaking change. Existing scripts now violate the layout and must be
  reorganised to comply.
- minor: an additive change. A new allowed section or option that does not break
  scripts already compliant.
- patch: a clarification or wording fix with no structural meaning.

Frontmatter is kept minimal on purpose (version and status only). The title is
the H1 below; dates live in git history. Do not add fields that duplicate what is
already available elsewhere.

## The skeleton (top to bottom)

1. **Shebang and header comment.** `#!/usr/bin/env bash`, then a comment block
   stating in one line what the script does, the usage, every flag, and the exit
   codes. The `--help` handler may print this block back.

2. **`set` options.** `set -euo pipefail` by default. A script may use
   `set -uo pipefail` without `-e` only if it manages its own failure
   accumulation (e.g. a `fail` counter that decides the exit code), and a comment
   must say so. Naming the exception is required; a silent missing `-e` is a
   defect.

3. **Constants.** Any fixed values near the top, overridable by env where that is
   genuinely a dial (e.g. an allowlist a different machine overrides). Per the
   project rule, only make a value configurable when it is actually a dial.

4. **Helpers.** All functions in one block, before any are called. Colour setup,
   output helpers, and logic helpers live here together. This is the single place
   to find every function the script defines.

5. **Argument parsing.** One loop. Flags, never environment variables, for
   behaviour the caller chooses. `--help` handled. Unknown options error via the
   usage helper.

6. **Resolve and validate inputs.** Everything the script needs is computed and
   checked here, before any side effect. Derive values, probe the environment,
   fail early on bad input. Nothing destructive happens before this passes.

7. **The work, in banner'd ordered sections.** Each unit of work is a labelled
   block. Use a consistent banner:

   ```
   # ---------------------------------------------------------------------------
   # Area name: one line on what this section does.
   # ---------------------------------------------------------------------------
   ```

   Announce the area to the user with the script's output idiom (see below).

8. **Finish.** The terminal outcome: a producer prints next steps; a verifier
   prints a verdict and writes its receipt.

## Output idiom (differs by job, deliberately)

The skeleton is fixed; the *shape of the output* is not, because produce and
verify are different jobs and a forced-identical output would make each worse.

- **Producer** (writes things, e.g. the generator): a step flow. One `==>` line
  per area, optional per-item detail under `--verbose`.
- **Verifier** (checks things, e.g. the setup gate): a check list. One
  `OK`/`FAIL`/`BLOCK`/`NEED` line per check, with a final verdict.

Both share the same colour handling, flag conventions, and helper-block
structure. Only the per-line idiom differs.

## Colour and verbosity (shared conventions)

- Colour is enabled only when stdout is a real terminal, `TERM` is not `dumb`,
  and the user has not opted out (`NO_COLOR`, or a `--no-color` flag). This keeps
  escape codes out of piped or redirected output.
- Behaviour the caller chooses is a flag, never an environment variable.
  `--verbose` for detail, `--debug` for a `set -x` trace, `--no-color` to force
  plain output.

## Multi-file scripts (orchestrator and layers)

A script that grows large or composes optional parts may split into an
orchestrator plus sourced component files, rather than one monolith. The skeleton
above still governs the orchestrator; the components follow these rules:

- **One orchestrator.** The entry-point script (in `scripts/`) owns the skeleton:
  header, `set` options, argument parsing, input validation, and the ordered work.
  It sources the components and calls them; it is the only file the user runs.
- **Components are sourced, not executed.** They live together in a sibling
  directory (e.g. `scripts/generator/`), each `#!/usr/bin/env bash` with a header comment
  saying it is sourced and what it provides. They define functions and set
  variables in the orchestrator's scope; they do not `set -e` or parse args.
- **One shared-helpers file.** The output helpers, colour setup, and file
  primitives live in a single sourced lib the orchestrator and every component
  use, so there is one definition of each helper (the "single place" rule above,
  across files).
- **Layers own their exclusive files; the orchestrator assembles shared ones.**
  When several layers contribute to one output file (e.g. a `package.json` the
  base, Mongo, and React layers all add to), the layer exports a named fragment
  and the orchestrator splices it in. A layer never hard-codes another layer's
  content, and never edits a file another layer owns.

## Reference example

`scripts/init-ts-project.sh` is the reference implementation: an orchestrator that
sources `scripts/generator/lib.sh` (helpers) and the `scripts/generator/base.sh`,
`mongo.sh`, `react.sh` layers, assembling the shared files from their fragments. A
single-file script should mirror the skeleton; a composed one should mirror this
orchestrator-and-layers structure.
