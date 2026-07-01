#!/usr/bin/env bash
# Project setup gate. Prove a project is ready to build, by execution not
# assertion. Idempotent: safe to run any number of times. Acts only on the gap.
# On READY it writes a receipt (.building/setup-ok) the build loop checks.
#
# This is the stack-neutral ORCHESTRATOR. It owns the spine every stack shares
# (argument parsing, the verdict helpers, git/remote/gh/commit-identity, the
# .building gitignore, the receipt and the exit codes), detects the project's
# stack, and sources the matching per-stack module under scripts/setup/ for the
# stack-specific checks (tooling, test tiers, coverage, placing the agent runners).
# Detection: package.json -> TypeScript (setup/ts.sh), pyproject.toml -> Python
# (setup/python.sh). A further stack adds its own module and one detection line;
# no check body branches on stack inline.
#
# Usage:
#   project-setup.sh            set up: install and scaffold gaps as needed (default)
#   project-setup.sh --check    verify only; never install, scaffold or push
#
# Exit: 0 READY, 1 NOT READY (fix FAILs), 2 NOT READY (--check found setup to
#       apply; re-run without --check), 3 BLOCKED (endpoint down)
#
# No -e: this gate accumulates failures in `fail` and decides its own exit code,
# so a single failing check must not abort the run.
set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

# Git commit-identity allowlist: the loop's commits must be authored by one of
# these emails, so they attribute to the right GitHub account. Read from your own
# git config (sdlc.identityAllowlist, space-separated) so no personal email is
# baked into this repo. Set it once: git config --global sdlc.identityAllowlist '<email>'
# (the hooks installer, setup-global-git-hooks.sh, does this for you).
IDENTITY_ALLOWLIST="$(git config --get sdlc.identityAllowlist 2>/dev/null || true)"

# ============================================================================
# Helpers
# ============================================================================

fail=0
note(){ printf 'WARN  %s\n' "$1"; }
ok(){ printf 'OK    %s\n' "$1"; }
bad(){ printf 'FAIL  %s\n' "$1"; fail=1; }
block(){ printf 'BLOCK %s\n' "$1"; [ "$fail" -lt 3 ] && fail=3; }
need(){ printf 'NEED  %s\n' "$1"; [ "$fail" -lt 2 ] && fail=2; }

# consent: true if the gate may install/scaffold/push. Acting is the default, since
# invoking the gate is the consent; --check is the read-only preview that refuses.
consent(){ [ "$mode" = check ] && return 1; return 0; }

# Templates: the per-stack modules and the runner/config templates they place
# come from shared template dirs. Resolve relative to this script's own location
# so the orchestrator and the modules it sources agree on where templates live.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$SCRIPT_DIR/setup"
TEMPLATES_DIR="$SCRIPT_DIR/../file-templates"
# copy_template stays in the spine because every stack module uses it to place its
# templates; one definition shared, like the generator's one lib for every layer.
copy_template(){ local src="$TEMPLATES_DIR/$1" dest="$2"
    if [ ! -f "$src" ]; then echo "missing template: $src" >&2; return 1; fi
    cp "$src" "$dest"; }

# detect_stack: name the project's stack from a marker file, so the orchestrator
# sources one per-stack module instead of branching on stack at each check. A new
# stack adds a marker and a case here, and its own scripts/setup/<stack>.sh.
detect_stack(){
    # Marker files name the stack. Both present is ambiguous (which stack is the
    # project?), so report it rather than guess; the dispatch turns "" into a hard
    # fail.
    local ts=0 py=0
    [ -f package.json ] && ts=1
    [ -f pyproject.toml ] && py=1
    if [ "$ts" = 1 ] && [ "$py" = 1 ]; then echo "ambiguous"; return; fi
    [ "$ts" = 1 ] && { echo ts; return; }
    [ "$py" = 1 ] && { echo python; return; }
    echo ""   # unrecognised: the orchestrator reports it as a hard fail below
}

# ============================================================================
# Parse arguments
# ============================================================================

mode="act"
for a in "$@"; do case "$a" in
    --check) mode="check" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 64 ;;
esac; done

echo "== Project setup gate =="

# ---------------------------------------------------------------------------
# Stack-specific checks: detect the stack and run its module. The module owns the
# tooling, test tiers, coverage and runner placement; it accumulates into `fail`
# through the shared helpers exactly as the inline checks did, so a TypeScript
# project's output and receipt are unchanged by the seam. An unrecognised stack is
# a hard fail: nothing downstream can prove an environment it does not understand.
# ---------------------------------------------------------------------------
stack="$(detect_stack)"
case "$stack" in
    ts)
        # shellcheck source=setup/ts.sh
        . "$SETUP_DIR/ts.sh"
        ts_setup
        ;;
    python)
        # shellcheck source=setup/python.sh
        . "$SETUP_DIR/python.sh"
        python_setup
        ;;
    ambiguous)
        bad "both package.json and pyproject.toml present; cannot tell which stack this is. Keep one marker, or split the stacks into separate projects"
        ;;
    *)
        bad "could not detect a supported stack (expected package.json for TypeScript or pyproject.toml for Python); add the project's marker file"
        ;;
esac

# ---------------------------------------------------------------------------
# 5. Git, remote, gh, identity, main on remote.
# ---------------------------------------------------------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then ok "git repository"
    # A remote is not required to build locally (commit and iterate work offline);
    # it is only needed to push branches and open PRs. So a missing remote is a
    # warning, never a hard FAIL: setup still reports READY, and adding the remote
    # stays the user's action before the loop's PRs can flow.
    # One warning covers the whole missing-remote story: no remote means main
    # cannot be pushed either, so the two are reported together here rather than
    # split across this section and the main-branch check below.
    has_remote=0
    if git remote get-url origin >/dev/null 2>&1; then ok "origin remote"; has_remote=1
    else note "no origin remote; local building works, but push/PR (and pushing main) need one (add a GitHub remote, your action)"; fi
    gh auth status >/dev/null 2>&1 && ok "gh authenticated" || bad "gh not authenticated; run gh auth login"
    # commit identity must be on the allowlist, so the loop's commits attribute to the right account
    commit_email="$(git config user.email 2>/dev/null)"
    if [ -z "$IDENTITY_ALLOWLIST" ]; then
        bad "sdlc.identityAllowlist not set; run: git config --global sdlc.identityAllowlist '<your-commit-email>'"
    else
        case " $IDENTITY_ALLOWLIST " in
            *" $commit_email "*) ok "commit identity ($commit_email)";;
            *) bad "commit email '$commit_email' not on the allowlist; set git config user.email to one of: $IDENTITY_ALLOWLIST";;
        esac
    fi
    if git show-ref --verify --quiet refs/heads/main; then ok "local main branch"
        # Pushing main only makes sense with a remote. Without one, the missing-remote
        # warning above already covers it, so stay silent here rather than emit a
        # second warning for the same cause.
        if [ "$has_remote" -ne 1 ]; then :
        elif git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then ok "main on remote"
        elif consent; then git push -u origin main >/dev/null 2>&1 && ok "pushed main" || bad "push failed"
        else need "main not on remote; re-run without --check to push"; fi
    else bad "no local main branch; the build loop cuts each increment branch from main"; fi
else bad "not a git repository; init and add a GitHub remote"; fi

# ---------------------------------------------------------------------------
# 6. Loop output stays local: .building must be gitignored.
# ---------------------------------------------------------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
    if git check-ignore -q .building 2>/dev/null; then
        ok ".building is gitignored (loop output stays local)"
    else
        note ".building is not gitignored; loop output could be committed and travel to machines that never ran setup"
        if consent; then
            printf '\n.building/\n' >> .gitignore
            git check-ignore -q .building 2>/dev/null && ok "added .building to .gitignore" || bad "added to .gitignore but still not ignored; check .gitignore"
        else
            need ".building not gitignored; re-run without --check to add it"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Verdict and receipt.
# ---------------------------------------------------------------------------
echo "========================"
mkdir -p .building
if [ "$fail" -eq 0 ]; then
    head=$(git rev-parse HEAD 2>/dev/null || echo unknown)
    printf '{ "ready": true, "head": "%s", "at": "%s" }\n' "$head" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .building/setup-ok
    echo "READY (receipt written to .building/setup-ok)"; exit 0
else
    rm -f .building/setup-ok   # stale receipt must not survive a non-ready result
    case "$fail" in
        2) echo "NOT READY: --check found install/scaffold/push to do; re-run without --check to apply"; exit 2 ;;
        3) echo "BLOCKED: endpoint down, bring it up and re-run"; exit 3 ;;
        *) echo "NOT READY: fix the FAIL lines and re-run"; exit 1 ;;
    esac
fi
