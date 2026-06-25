# Judge report: increment <id>, <title>
Date: <YYYY-MM-DD HH:MM:SS>
Verdict: PASS

## Acceptance criteria
- <criterion 1>: PASS, <how verified, the command run>
- <criterion 2>: PASS, <how verified>

## Test result by tier
- Unit: PASS (<n> tests, <ms>)
- Integration: PASS (<n> tests, <ms>), endpoints: <list, e.g. mongo replica set>
<!-- Include the Integration line only when the integration tier ran for this increment: the full profile runs it per increment. In lite and build-quick the per-increment judge is unit-only, so omit the Integration line (lite proves integration once at the completion gate; build-quick never). -->
Order run: unit first, then integration where it runs. Every tier that ran must pass.

## Coverage by tier (measured by tooling, not merged)
### Unit
- Lines <n>% / Branches <n>% / Functions <n>% / Statements <n>%
- Uncovered: <file:lines>
### Integration
<!-- Omit this subsection when the integration tier did not run for this increment (lite, build-quick). -->
- Lines <n>% / Branches <n>% / Functions <n>% / Statements <n>%
- Uncovered: <file:lines>
Note: read with the hollow-test result below; coverage alone does not prove assertions.

## Test inventory by tier (measured by tooling)
### Unit
<n> tests across <n> files, <n> passed, <n> skipped
### Integration
<!-- Omit this subsection when the integration tier did not run for this increment (lite, build-quick). -->
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
