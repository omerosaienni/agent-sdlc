# Scripts

The repo has three shell scripts that stand a project up and prove it ready for
the build loop. This documents what each does and how they connect.

They follow the layout in `contracts/script-layout.md`. The diagrams here are
inline Mermaid (rendered by GitHub) rather than the SVGs catalogued in
`diagram-spec.md`, because a script's documentation is easier to keep in sync
when the diagram lives as text beside the prose.

## How they connect

Three scripts, three jobs: one creates a project, one proves it ready, one is a
small dependency helper the gate also uses. The relationship is create, then
verify, then the loop consumes the receipt.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#e4edf4','primaryTextColor':'#1d2733','primaryBorderColor':'#5b6b7a','lineColor':'#5b6b7a','fontSize':'14px'}}}%%
flowchart LR
    init["init-ts-mongo.sh<br/>(create)"] -->|writes a project| proj["project on disk"]
    proj --> gate["project-setup.sh<br/>(verify)"]
    ensure["ensure-report-tooling.sh<br/>(dependency helper)"] -.->|coverage tooling| gate
    gate -->|on READY writes| receipt["setup-ok receipt"]
    receipt --> loop["build loop<br/>(consumes)"]

    classDef script fill:#dbe7f0,stroke:#5b6b7a,color:#1d2733;
    classDef artifact fill:#dceadf,stroke:#5a8a66,color:#1d2733;
    class init,gate,ensure script;
    class proj,receipt artifact;
```

- **init-ts-mongo.sh** scaffolds a new project from the constant template.
- **project-setup.sh** proves a project is ready by execution, and on success
  writes the `setup-ok` receipt the build loop refuses to start without.
- **ensure-report-tooling.sh** is a focused helper that installs and verifies the
  coverage tooling the judge needs. The gate folds the same check into step 1, so
  this script is the standalone version of that one concern.

The receipt is the bridge: the generator creates, the gate verifies and stamps,
the loop consumes the stamp.

---

## init-ts-mongo.sh (the generator)

Scaffolds a backend TypeScript + MongoDB project: tooling, infra, the db helper,
an entry point, conventions, then inits git. It makes no domain assumptions; you
grow `src/index.ts` and add your own modules.

```
init-ts-mongo.sh <project-name> [target-dir] [--verbose] [--no-color] [--debug]
```

- `--verbose` prints each file as it is written.
- `--no-color` forces plain output (colour is auto-detected and on only at a
  terminal).
- `--debug` traces every shell command.

### Generation flow

What the script does, in order. It resolves and validates every input before it
writes anything, then writes each area, then inits git.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#e4edf4','primaryTextColor':'#1d2733','primaryBorderColor':'#5b6b7a','lineColor':'#5b6b7a','fontSize':'14px'}}}%%
flowchart TD
    args["parse args<br/>name, dir, flags"] --> resolve["resolve + validate<br/>kebab-case name, derive db name,<br/>refuse if dir exists"]
    resolve --> tooling["tooling configs<br/>vitest tiers, tsconfig, eslint,<br/>prettier, ignores"]
    tooling --> db["database helper<br/>src/db.ts (db name baked in, shared 27017)"]
    db --> infra["docker infra<br/>compose, rs-init"]
    infra --> build["build surface<br/>Makefile, package.json"]
    build --> entry["entry point<br/>src/index.ts + test + smoke test"]
    entry --> editor["editor<br/>.vscode debug configs"]
    editor --> docs["docs<br/>CLAUDE.md, README"]
    docs --> git["git init + initial commit<br/>(idempotent)"]
    git --> done["print next steps"]

    classDef io fill:#fdeccd,stroke:#b8743d,color:#1d2733;
    classDef work fill:#e4edf4,stroke:#5b6b7a,color:#1d2733;
    class args,resolve io;
    class tooling,db,infra,build,entry,editor,docs,git work;
```

### Scaffold components

What lands in a generated project, grouped, with the parameters that flow into
each. The project name is the only varying input; everything else, including the
shared compose and the fixed port, is constant.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#e4edf4','primaryTextColor':'#1d2733','primaryBorderColor':'#5b6b7a','lineColor':'#5b6b7a','fontSize':'14px'}}}%%
flowchart TD
    name(["project name"]) --> dbname(["db name (verbatim)"])
    dbname --> dbts
    dbname --> makefile
    name --> makefile

    subgraph tooling["Tooling (constant)"]
        vitest["vitest.unit/integration.config.ts"]
        tsconfig["tsconfig.json"]
        lint["eslint + prettier"]
        ignores[".gitignore, .graphifyignore"]
    end

    subgraph infra["Infra (constant, shared-mongo)"]
        compose["docker-compose.yml"]
        rsinit["scripts/rs-init.sh"]
    end

    subgraph source["Source"]
        dbts["src/db.ts"]
        index["src/index.ts (entry point)"]
        indextest["src/index.test.ts (unit)"]
        smoke["src/smoke.integration.test.ts"]
    end

    subgraph build["Build surface"]
        makefile["Makefile"]
        pkg["package.json"]
    end

    subgraph docs["Docs + editor"]
        claude["CLAUDE.md (conventions)"]
        readme["README.md"]
        vscode[".vscode/launch.json (gitignored)"]
    end

    dbts --> index
    dbts --> smoke

    classDef param fill:#dceadf,stroke:#5a8a66,color:#1d2733;
    class name,dbname param;
```

The entry point and the smoke test both use `src/db.ts`, so the database helper
is exercised from birth: the unit tier tests the entry point, the integration
tier runs a generic Mongo connectivity smoke test through the real helper.

### What it does not do

Deliberately separate, so create and verify stay distinct: it does not run
`npm install`, bring up Docker, provision graphify, or run the setup gate. After
generating, the project still needs install, bring-up, and the gate.

---

## project-setup.sh (the gate)

Proves a project is ready to build, by execution not assertion. Idempotent, acts
only on the gap. On READY it writes `.building/build/setup-ok`, the receipt the
build loop checks.

```
project-setup.sh            check; ask before installing or scaffolding
project-setup.sh --yes      install and scaffold gaps without asking
project-setup.sh --check    verify only; never install or scaffold
```

Exit codes: 0 READY, 1 NOT READY (fix the FAIL lines), 2 needs `--yes`, 3 BLOCKED
(endpoint down).

### What it checks

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#e4edf4','primaryTextColor':'#1d2733','primaryBorderColor':'#5b6b7a','lineColor':'#5b6b7a','fontSize':'14px'}}}%%
flowchart TD
    s1["1. report tooling<br/>coverage matches vitest major"]
    s2["2. testing convention<br/>tier configs + npm scripts<br/>+ agent runners (test + hollow)"]
    s3["3. run each tier<br/>non-zero selection + pass<br/>+ agent runners work"]
    s4["4. coverage runs"]
    s5["5. git, remote, gh, identity, main"]
    s6["6. .building is gitignored"]
    verdict{"any FAIL?"}
    ready["READY<br/>write setup-ok receipt, exit 0"]
    notready["NOT READY / NEED / BLOCKED<br/>remove stale receipt, exit 1/2/3"]

    s1 --> s2 --> s3 --> s4 --> s5 --> s6 --> verdict
    verdict -->|no| ready
    verdict -->|yes| notready

    classDef check fill:#e4edf4,stroke:#5b6b7a,color:#1d2733;
    classDef good fill:#dceadf,stroke:#5a8a66,color:#1d2733;
    classDef bad fill:#f7ddd7,stroke:#c0533b,color:#1d2733;
    class s1,s2,s3,s4,s5,s6 check;
    class ready good;
    class notready bad;
```

Each check is one of OK (pass), FAIL (must fix, exit 1), NEED (needs `--yes` to
install or scaffold, exit 2), or BLOCK (endpoint down, exit 3). The gate
accumulates failures and decides the exit code at the end, which is why it runs
without `set -e`.

The identity check is load-bearing for attribution: the loop's commits must be
authored by an email on the allowlist so they map to the right GitHub account.
Override the allowlist per machine with `GIT_IDENTITY_ALLOWLIST`.

The agent test runner (`.building/scripts/agent-tests.sh`) is part of the testing
convention the gate scaffolds and proves. It is the path the build loop's judge
uses to run tests: terse one-line output on pass, full output on failure, so the
judge's repeated verification runs cost a few tokens of context rather than the
whole vitest dump each time. Humans keep the verbose path (`npm run test:unit`,
`make test`); both drive the same tier configs, so they never disagree on what
they test. The gate places the runner from the shared template if absent or out of
date (step 2) and runs it to prove the agent path works before stamping ready
(step 3). A project whose human tests pass but whose agent runner is broken is
not loop-ready, because the judge depends on that path.

The hollow-check runner (`.building/scripts/agent-hollow.sh`) is placed and proven the same
way. It is the single command the judge uses for the hollow-test negative run: it
backs up the file, applies the judge's behavioural fault, runs the scoped tier,
restores the file from an exit trap, then re-verifies green, returning a verdict
by exit code. Setup writes it from the template if absent or out of date (step 2) and
proves it is runnable (step 3) on the same loop-ready footing as the test runner.

### Modes

- default (ask): reports gaps and, at a terminal, asks before installing or
  scaffolding.
- `--yes`: installs and scaffolds gaps without asking.
- `--check`: reports only, never changes anything. Use this to verify without
  side effects.

---

## ensure-report-tooling.sh (dependency helper)

A focused helper that ensures the repo has the coverage tooling the judge report
needs (`@vitest/coverage-v8`) and verifies a coverage run works. Idempotent.

```
ensure-report-tooling.sh            ask before installing (at a terminal)
ensure-report-tooling.sh --yes      install without asking
ensure-report-tooling.sh --check    report only, never install (exit 2 if missing)
```

The gate's step 1 covers the same ground (it derives the required coverage major
from the installed vitest). This script is the standalone, single-concern version
for when you want to fix just the report tooling without running the whole gate.
