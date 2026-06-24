# Scripts

Three pipeline scripts stand a project up and prove it ready for the build loop:
the generator, the setup gate, and a small dependency helper. This documents what
each does and how they connect. (The repo also has scripts outside the pipeline:
the per-project rules installer, documented in [`project-rules.md`](project-rules.md),
and the global git-hooks and Claude-rules installers, documented in
[`../hooks/`](../hooks/README.md) and [`project-rules.md`](project-rules.md). Those
are not part of the create-verify-build flow described here.)

They follow the layout in `contracts/script-layout.md`. The diagrams here are
inline Mermaid (rendered by GitHub) rather than the SVGs catalogued in
`diagram-spec.md`, because a script's documentation is easier to keep in sync
when the diagram lives as text beside the prose.

## How they connect

Three pipeline scripts, three jobs: one creates a project, one proves it ready, one
is a small dependency helper the gate also uses. The relationship is create, then
verify, then the loop consumes the receipt.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#e4edf4','primaryTextColor':'#1d2733','primaryBorderColor':'#5b6b7a','lineColor':'#5b6b7a','fontSize':'14px'}}}%%
flowchart LR
    init["init-ts-project.sh<br/>(create)"] -->|writes a project| proj["project on disk"]
    proj --> gate["project-setup.sh<br/>(verify)"]
    ensure["ensure-report-tooling.sh<br/>(dependency helper)"] -.->|coverage tooling| gate
    gate -->|on READY writes| receipt["setup-ok receipt"]
    receipt --> loop["build loop<br/>(consumes)"]

    classDef script fill:#dbe7f0,stroke:#5b6b7a,color:#1d2733;
    classDef artifact fill:#dceadf,stroke:#5a8a66,color:#1d2733;
    class init,gate,ensure script;
    class proj,receipt artifact;
```

- **init-ts-project.sh** scaffolds a new project: a TypeScript base, plus optional Mongo and React layers.
- **project-setup.sh** proves a project is ready by execution, and on success
  writes the `setup-ok` receipt the build loop refuses to start without.
- **ensure-report-tooling.sh** is a focused helper that installs and verifies the
  coverage tooling the judge needs. The gate folds the same check into step 1, so
  this script is the standalone version of that one concern.

The receipt is the bridge: the generator creates, the gate verifies and stamps,
the loop consumes the stamp.

---

## init-ts-project.sh (the generator)

Scaffolds a TypeScript project with optional Mongo and React layers. The base is
always TypeScript (tooling, an entry point, a unit tier under `src/server`); `--mongo`
adds the db helper, docker infra, the integration tier and a faker seed; `--react`
adds the React + Vite client under `src/client`. It inits git and installs the
matching stack rules. It makes no domain assumptions; you grow `src/server/index.ts`
and add your own modules.

It is a small multi-file script (per `contracts/script-layout.md`): an orchestrator
that sources the shared helpers (`scripts/generator/lib.sh`) and the
`scripts/generator/base.sh`, `mongo.sh`, `react.sh` layers, assembling the shared files
(package.json, tsconfig, Makefile) from the fragments each enabled layer contributes.

```
init-ts-project.sh <project-name> [target-dir] [--mongo] [--react] [--verbose] [--no-color] [--debug]
```

- `--mongo` adds the MongoDB layer; `--react` adds the React client layer; any combination is valid.

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
    tooling --> db["database helper<br/>src/server/db/index.ts (db name baked in, shared 27017)"]
    db --> infra["docker infra<br/>compose, rs-init"]
    infra --> build["build surface<br/>Makefile, package.json"]
    build --> entry["entry + seed<br/>src/server/index.ts + test + smoke test<br/>src/server/seed.ts (faker seed helper)"]
    entry --> editor["editor<br/>.vscode debug configs"]
    editor --> docs["docs<br/>CLAUDE.md (identity + runtime), README"]
    docs --> git["git init + initial commit<br/>(idempotent)"]
    git --> rules["stack rules<br/>install-project-rules.sh --typescript --mongo"]
    rules --> done["print next steps"]

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

    subgraph source["Source (src/server/)"]
        dbts["src/server/db/index.ts"]
        index["src/server/index.ts (entry point)"]
        indextest["src/server/index.test.ts (unit)"]
        smoke["src/server/smoke.integration.test.ts"]
        seed["src/server/seed.ts (faker seed helper)"]
    end

    subgraph build["Build surface"]
        makefile["Makefile"]
        pkg["package.json"]
    end

    subgraph docs["Docs + editor"]
        claude["CLAUDE.md (identity + runtime)"]
        rules[".claude/rules/ (TS + Mongo stack rules)"]
        readme["README.md"]
        vscode[".vscode/launch.json (gitignored)"]
    end

    dbts --> index
    dbts --> smoke
    dbts --> seed

    classDef param fill:#dceadf,stroke:#5a8a66,color:#1d2733;
    class name,dbname param;
```

The entry point, the seed helper and the smoke test all use `src/server/db/index.ts`,
so the database helper is exercised from birth: the unit tier tests the entry point, and
the integration tier runs a replica-set smoke test through the real helper (it
asserts the set reports a PRIMARY, so it fails if mongod is down or the replica
set was never initiated). The seed helper (`make seed`, faker-backed) proves the
faker to Mongo path end to end and is a domain-free starting point you grow.

### What it does not do

Deliberately separate, so create and verify stay distinct: it does not run
`npm install`, bring up Docker, provision graphify, or run the setup gate. After
generating, the project still needs install, bring-up, and the gate.

---

## project-setup.sh (the gate)

Proves a project is ready to build, by execution not assertion. Idempotent, acts
only on the gap. On READY it writes `.building/setup-ok`, the receipt the
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
    s2["2. testing convention<br/>tier configs + npm scripts<br/>+ agent runners (test, hollow)"]
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
The allowlist is read from git config `sdlc.identityAllowlist` (space-separated),
so no email is baked into the repo; set it once globally, or via
`setup-global-git-hooks.sh install`. Unset is a FAIL.

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

The type-check runner (`.building/scripts/agent-typecheck.sh`, from the shared
template) is the judge's gate, run first before the tiers because nothing else
type-checks: the tiers run through esbuild and tsx, which strip types. A clean
type-check (exit 0) is required to pass; a type error (exit 1) is a hard fail like a
failing test, and a type-check that cannot run at all (exit 3, no tsconfig or tsc
absent) is an environment block. The build loop's judge places and runs it; the
setup gate (today) places and proves only the test and hollow-check runners.

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
