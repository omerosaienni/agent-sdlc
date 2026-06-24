# Judge report: increment <id>, <title>
Date: <YYYY-MM-DD HH:MM:SS>
Verdict: PASS

## Acceptance criteria
- <criterion 1>: PASS, <how verified, the command run>
- <criterion 2>: PASS, <how verified>

## Test result by tier
- Unit: PASS (<n> tests, <ms>)
- Integration: PASS (<n> tests, <ms>), endpoints: <list, e.g. mongo replica set>
Order run: unit first, then integration. Both required to pass.

## Coverage by tier (measured by tooling, not merged)
### Unit
- Lines <n>% / Branches <n>% / Functions <n>% / Statements <n>%
- Uncovered: <file:lines>
### Integration
- Lines <n>% / Branches <n>% / Functions <n>% / Statements <n>%
- Uncovered: <file:lines>
Note: read with the hollow-test result below; coverage alone does not prove assertions. Unit coverage is naturally low on data-layer code; the integration tier carries that coverage.

## Test inventory by tier (measured by tooling)
### Unit
<n> tests across <n> files, <n> passed, <n> skipped
### Integration
<n> tests across <n> files, <n> passed, <n> skipped

### <functionName> (mapping below is asserted by the judge, not tool-measured)
- <test name> [unit|integration]
   - <one-line description>
- <test name> [unit|integration]
   - <one-line description>

## Quality signals (measured by tooling)
- Type errors (tsc): <n>
- Lint errors: <n>, warnings: <n>
- Hollow-test check: PASS, tests fail when the code is broken (negative run)
- Slowest test: <name>, <ms>

## Notes
- <anything the human should know>
