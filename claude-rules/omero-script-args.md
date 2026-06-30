# Script arguments

Caller-chosen behaviour is a positional argument or a flag, never an environment variable.

- A caller changes a script's behaviour or its output location through `--flag` or a positional arg, parsed in one loop, with `--help` and an unknown-option error. Never by exporting a variable the script reads.
- Exempt (these are fine): a `.env` file (config a generated project reads, not script behaviour); standard, widely-honoured env vars where they are the convention (`NO_COLOR`, `TERM`, `XDG_CONFIG_HOME`, `HOME`); a script's own internal variables and the values a sourced component sets in its orchestrator's scope.
- A script may set an env var for a child process it spawns (e.g. `PYTHONDONTWRITEBYTECODE=1 pytest ...`); that is configuring the child, not reading caller-chosen behaviour from the environment.

Full spec: contracts/script-layout.md (Skeleton step 5, and Colour and verbosity). This rule is the always-loaded reminder; the contract is the spec; the script is the gate.
