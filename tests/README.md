# Tests

agent-sdlc's own test suites. `tests/run.sh` discovers every `tests/<name>/test.sh`, runs each (sourced, sharing `tests/lib.sh`'s assertions), and reports the suites grouped by kind with a per-kind tally. Add a suite by adding a folder; no change to `run.sh`.

## Kinds

Every suite declares its kind as the second argument to `suite_begin` (an argument, never an env var). A suite that omits the kind or passes an unknown one fails the run. The judge's unit/integration tiers describe a target project the pipeline builds; this meta-repo's tests are a different thing, so `structural` is added for conformance tests with no behavioural analogue.

- **unit**: a pure script or stub, run-anywhere, no external tooling. (`validate-sheet`, `validate-state`, `board-state`, `agent-runner`.)
- **integration**: runs real external tooling (uv, pytest, pyright, npm) and self-skips when the tooling or network is absent. (`init-python-project`, `project-setup`, `py-runners`, `py-e2e-proof`.)
- **structural**: reads files and asserts conformance (frontmatter, naming, no stale strings), executes nothing under test. (`skills`.)

```
suite_begin "validate-sheet.sh" unit
suite_begin "project-setup.sh (stack seam)" integration
suite_begin "skills (create-project contracts)" structural
```

## Writing a suite

- Call `suite_begin "<name>" <kind>` first, `suite_summary` last.
- Assert with `expect_exit <want> <name> <cmd...>`, `expect_match <want> <regex> <name> <cmd...>`, or `expect_json <name> <node-assert> <cmd...>` (see `lib.sh`).
- Assert behaviour or content, not a file's location: a bare `test -f X` is a snapshot, redundant if another assertion already runs or reads X, and weak where existence is only a proxy for correctness. A behavioural outcome check that happens to use `test -f` (e.g. a receipt the gate just wrote) is fine.
- An `integration` suite must self-skip (report SKIP, not fail) when its tooling or network is unavailable, so the run stays green where the tooling is absent (e.g. in `act`'s container).
