# Design review: <feature-name>
Date: <YYYY-MM-DD>
Review pass: <N>

## Sheet under review
- <path to increments.md>
- Increments: <id, id, id, ...>

## Checks
- Inter-increment consistency: <holds | finding below>
- No dead-code-inducing cut: <holds | finding below>
- No hidden multi-increment: <holds | finding below>
- Claimed-but-untested behaviour: <holds | finding below>

## Blocking findings
- [critical|major] <check>: increments <id> and <id>, object `<name>`. <what conflicts, and why it is unbuildable or unsound>. Fix direction: <re-slice | decouple | split | add a criterion>.
- (or: none)

## Surfaced to human (judgement the reviewer cannot settle)
- <the fork, why it needs the human, a recommendation>
- (or: none)

## Verdict
- Approved | Sent back to designer (blocking findings above)
