#!/usr/bin/env bash
# Ship the current branch's PR, deterministically. Merging after the PR's checks pass is
# not a judgement call, so it is a script that gates itself rather than a rule an agent
# might skip. This is the gate; contracts/merge-pr.md is its spec. Order: on a feature
# branch, tooling present, no plaintext token in git config, gh authenticated, an open PR
# exists, its remote required checks all pass, an optional local CI run, then git town ship.
#
# Stack-agnostic on purpose: it never runs pyright, pytest or tsc. CI is the check
# authority and the script trusts `gh pr checks --required`, so one gate serves this repo's
# TypeScript and Python paths alike. The one local step is optional-by-presence: if the
# project ships scripts/ci-local.sh it is run at merge time, otherwise the step is skipped
# with a warning.
#
# git town ship is the one merge path: it merges a direct child of main into main via the
# GitHub API (respecting a squash-only policy), deletes the branch, syncs main and
# reparents any stacked children. It ships only DIRECT children of main; a deeper stack
# branch it refuses, and this script surfaces that refusal rather than forcing --to-parent.
#
# Auth: git town ships via the GitHub API and needs a token to do it. It does NOT read the
# gh keyring on its own, but it DOES honour a GITHUB_TOKEN env var, so this script supplies
# `gh auth token` to the ship child process only. The token stays in the gh keyring and is
# never written to git config or disk. A plaintext git-town.github-token in .git/config is a
# different thing, the exposure being prevented, so finding one is still a hard block.
#
# Usage:
#   merge-pr.sh                 ship the current branch's PR (message defaults to the PR title)
#   merge-pr.sh "squash msg"    ship with an explicit squash message
#   merge-pr.sh --dry-run       show git town ship --dry-run, merge nothing
#   merge-pr.sh --help          print this header and exit 0
#
# Exit codes:
#   0  shipped (or, under --dry-run, the plan printed)
#   1  BLOCKED: a gate failed; the reason is on stderr
#   2  bad usage: unknown option or extra positional
set -uo pipefail   # no -e: gates print their own BLOCKED reason and exit with an explicit code

# ============================================================================
# Helpers
# ============================================================================

usage() { awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; }

# A gate failure: one BLOCKED reason to stderr, exit 1. Callers pass extra guidance lines.
block() {
    echo "BLOCKED: $1" >&2
    shift
    for line in "$@"; do echo "  $line" >&2; done
    exit 1
}

# ============================================================================
# Parse arguments
# ============================================================================

message=""
message_set=0
dry_run=0

# One loop owns every caller-chosen behaviour: the MESSAGE positional, --dry-run, --help
# and the unknown-option and extra-argument errors. Nothing is read from the environment.
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --dry-run) dry_run=1; shift ;;
        --*) echo "merge-pr.sh: unknown option '$1'" >&2; usage >&2; exit 2 ;;
        *)
            if [ "$message_set" -eq 1 ]; then
                echo "merge-pr.sh: unexpected extra argument '$1'" >&2; usage >&2; exit 2
            fi
            message="$1"; message_set=1; shift ;;
    esac
done

# ============================================================================
# Resolve and validate: repo, branch, tooling. Nothing merges before these pass.
# ============================================================================

# Resolve the repo from git, never trust CWD.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$repo_root" ] || block "not inside a git repository." "Run this from within the project's git repo."
cd "$repo_root" || block "cannot cd into repo root '$repo_root'."

# Ship only from a work branch: main, master and a detached HEAD are refused.
branch="$(git symbolic-ref --short HEAD 2>/dev/null)"
case "$branch" in
    ""|main|master)
        block "refusing to ship from '${branch:-detached HEAD}'." "Switch to the feature branch whose PR you want to ship." ;;
esac

# Tooling: a missing tool is a loud block, never a silent skip.
for tool in git gh; do
    command -v "$tool" >/dev/null 2>&1 || block "'$tool' not found on PATH." "Install $tool and retry."
done
git town --version >/dev/null 2>&1 || block "git-town not installed." "Install git-town (it is the one merge path) and retry."

# ============================================================================
# Token guard: a plaintext token in git config is the exposure being prevented.
# ============================================================================

# If a git-town.github-token sits in git config it is a real plaintext exposure (it has
# happened once). Refuse, and tell the operator to remove it and rotate it. git town gets
# its credential from the gh keyring, so removing the config token loses nothing.
if git config --get git-town.github-token >/dev/null 2>&1; then
    block "a plaintext git-town.github-token is set in git config." \
        "Remove it and rely on gh keyring auth, then rotate the exposed token:" \
        "git config --unset git-town.github-token   (add --global if it is set globally)" \
        "gh auth status                             (confirm the keyring login)"
fi

# ============================================================================
# Auth: a keyring token git town can ship with. Supplied to the ship child, not git config.
# ============================================================================

# gh auth status is not enough: git town ships via the GitHub API and needs an actual token,
# which `gh auth token` returns from the keyring. An empty token means shipping would fail
# with the driver-does-not-support-API-shipping error, so block now with the real remedy.
gh auth status >/dev/null 2>&1 || block "gh is not authenticated." \
    "Run 'gh auth login' (keyring). Do not set a token in git config."
github_token="$(gh auth token 2>/dev/null)"
[ -n "$github_token" ] || block "gh has no token to ship with ('gh auth token' is empty)." \
    "Run 'gh auth login' so git town can ship via the GitHub API. Do not set a token in git config."

# ============================================================================
# PR: an OPEN PR must exist for this branch. Resolve number, state and title.
# ============================================================================

# One call fetches all three: number for the checks gate, state to refuse a non-open PR,
# title for the default squash message. gh --jq parses the JSON so neither jq nor python
# is required; a tab-joined line keeps it a single read.
pr_line="$(gh pr view --json number,state,title --jq '[.number,.state,.title]|@tsv' 2>/dev/null)"
[ -n "$pr_line" ] || block "no PR found for branch '$branch'." "Open a PR for this branch first."
IFS=$'\t' read -r pr_number pr_state pr_title <<<"$pr_line"
[ "$pr_state" = "OPEN" ] || block "PR #$pr_number is $pr_state, not OPEN. Nothing to ship."

# ============================================================================
# Remote checks gate: every required check must pass. GitHub cannot enforce this on a
# free-plan private repo, so the script does.
# ============================================================================

# `gh pr checks --required` lists only the required checks and exits non-zero if any is
# pending or failing. GOTCHA: with zero required checks it exits 0 with EMPTY output, which
# would silently pass an unverifiable PR. Capture the output and treat the empty case as a
# block: we cannot confirm safety, so we do not merge.
echo "merge-pr.sh: verifying required remote checks on PR #$pr_number..." >&2
checks_out="$(gh pr checks "$pr_number" --required 2>/dev/null)"
checks_rc=$?
if [ "$checks_rc" -ne 0 ]; then
    block "PR #$pr_number has required checks that are pending or failing." \
        "Wait for CI, or fix the failing checks, then retry. See: gh pr checks $pr_number --required"
fi
if [ -z "$(printf '%s' "$checks_out" | tr -d '[:space:]')" ]; then
    block "PR #$pr_number reports no required checks, so safety cannot be confirmed." \
        "Configure required checks on the PR, or verify CI by hand, before shipping."
fi

# ============================================================================
# Optional local CI, by presence. The merge-time home for the heavy full-CI run.
# ============================================================================

# The pre-push hook runs only fast per-commit gates, so a full local CI run belongs here,
# not there. It is optional-by-presence to keep this script stack-agnostic: a project that
# ships scripts/ci-local.sh gets a verbatim local CI run at merge time; one that does not
# simply skips it. This script never creates ci-local.sh, it only runs an existing one.
if [ -x scripts/ci-local.sh ]; then
    echo "merge-pr.sh: running local CI (scripts/ci-local.sh)..." >&2
    ./scripts/ci-local.sh || block "local CI (scripts/ci-local.sh) failed." "Fix the failure and retry."
elif [ -f scripts/ci-local.sh ]; then
    block "scripts/ci-local.sh exists but is not executable." "Run: chmod +x scripts/ci-local.sh"
else
    echo "merge-pr.sh: WARNING no scripts/ci-local.sh; skipping the local CI run." >&2
fi

# ============================================================================
# Ship. git town handles the merge, branch delete, main sync and stack reparenting.
# ============================================================================

# Message defaults to the PR title (the natural squash subject) unless a positional
# overrode it.
[ "$message_set" -eq 0 ] && message="$pr_title"

# --dry-run passes straight through. If this branch is not a direct child of main, git town
# refuses; that refusal is surfaced verbatim so the operator ships or deletes ancestors
# first, rather than this script forcing --to-parent blindly.
#
# GITHUB_TOKEN is set on the git town child only (the omero-script-args exempt case: a script
# configuring a child process it spawns). git town reads it to ship via the API; it never
# lands in git config or on disk.
ship_args=(ship -m "$message")
[ "$dry_run" -eq 1 ] && ship_args+=(--dry-run)
echo "merge-pr.sh: git town ${ship_args[*]}" >&2
GITHUB_TOKEN="$github_token" git town "${ship_args[@]}"
