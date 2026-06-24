# Conventions

Universal conventions that apply to every project. Terse on purpose: this loads every session.

## Prose (comments, docs, output)
- British English.
- No em dashes — restructure the sentence instead.
- No Oxford commas.
- No hyphens in compound modifiers.

## Comments — why, not what
- A comment must add what the code can't. If it only restates the code, delete it.
  Not `// stop the container` above `docker rm -f`; yes `// archive.conf is a conf.d drop-in, not -c, so ALTER SYSTEM can override it`.
- Be brief: one line where one line does. Go multi-sentence only when the why genuinely needs it (a race, an ordering constraint, a non-obvious gotcha).
- Add a why where a non-obvious choice has none — a version pin, a loopback bind, a file drop-in instead of a flag, polling instead of a readiness probe.
- Never trust an existing comment: read the code before believing it. Comments rot — check paths, flags, names, and cross-references against the real code, and fix a stale one when you touch its file.
