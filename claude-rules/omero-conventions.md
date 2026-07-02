# Conventions

Universal conventions that apply to every project. Terse on purpose: this loads every session.

## Prose (comments, docs, output)
- British English.
- No em dashes. Restructure the sentence instead.
- No Oxford commas.
- No hyphens in compound modifiers.

## Names carry meaning; comments are the residue
Understanding comes first from names and structure, then from comments for what names can't carry. Optimise for a reader skimming top to bottom, not for comment coverage.

- A "what" comment is a naming failure first. Before writing one, rename the variable or extract a named function so the code states it. `days_until_expiry` not `d`; `poll_until_ready()` not `helper2()`. A good name lets a reader skip the body.
- If a block needs a comment to say what it does, that block wants to be a function whose name says it.

## Comments: why, and invisible contracts
A comment earns its place only if an oriented reader (fluent in the language and this codebase) would stumble without it, in a way a better name can't fix.

- Keep: the *why* behind a non-obvious choice (a version pin, a loopback bind, a file drop-in instead of a flag, polling instead of a readiness probe); an invisible external contract the file can't show (an API that 429s without a sleep, VS Code injecting the test target for a `debug-test` config); a non-local consequence ("changing this breaks X elsewhere").
- Delete: restating the code. Not `// stop the container` above `docker rm -f`; yes `// archive.conf is a conf.d drop-in, not -c, so ALTER SYSTEM can override it`.
- Reasoning you just worked out goes in the commit message, not the file. A comment serves the future reader, not the author's just-finished debugging.
- Be brief: one line where one line does. Multi-sentence only when the why genuinely needs it (a race, an ordering constraint, a non-obvious gotcha).
- Config and infra files (launch.json, CI yaml, shell) carry more comments than app code: they hold the most invisible contracts and offer the fewest good names.
- Never trust an existing comment: read the code before believing it. Comments rot, so check paths, flags, names, and cross-references against the real code, and fix a stale one when you touch its file.
