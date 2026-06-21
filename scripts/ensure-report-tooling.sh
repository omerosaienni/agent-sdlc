#!/usr/bin/env bash
# Ensure this repo has the tooling the judge report needs: coverage and json
# reporters. Idempotent. Run from the project root.
#
# Usage:
#   ensure-report-tooling.sh            ask before installing (if at a terminal)
#   ensure-report-tooling.sh --yes      install without asking
#   ensure-report-tooling.sh --check    report only, never install (exit 2 if missing)
#
# Exit: 0 present or installed, 1 coverage run failed, 2 missing and not installed
set -euo pipefail

# ============================================================================
# Helpers
# ============================================================================

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# consent: true if the script may install, given the mode and whether we are at a
# terminal. Keeps the install decision in one place.
consent() {
    case "$mode" in
        yes)   return 0 ;;
        check) return 1 ;;
        ask)
            if [ -t 0 ]; then
                read -r -p "install now? [y/N] " reply
                case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
            fi
            return 1 ;;
    esac
}

# ============================================================================
# Parse arguments
# ============================================================================

mode="ask"
for arg in "$@"; do
    case "$arg" in
        -y|--yes)  mode="yes" ;;
        --check)   mode="check" ;;
        -h|--help) usage ;;
        *)
            echo "unknown argument: $arg" >&2
            echo "use --yes, --check, or no argument" >&2
            exit 64 ;;
    esac
done

# ============================================================================
# Resolve inputs: what is missing
# ============================================================================

need=()
node -e "require.resolve('@vitest/coverage-v8')" 2>/dev/null || need+=("@vitest/coverage-v8")

# ============================================================================
# Install the gap (only with consent)
# ============================================================================

if [ ${#need[@]} -eq 0 ]; then
    echo "report tooling already present"
else
    echo "missing report tooling: ${need[*]}"
    if [ "$mode" = check ]; then
        exit 2
    fi
    echo "this installs npm dev dependencies (network + package.json change)"
    if consent; then
        echo "installing: ${need[*]}"
        npm install -D "${need[@]}"
    else
        # ask-mode at a non-terminal, or declined: refuse rather than guess.
        echo "skipped install; coverage tooling missing" >&2
        exit 2
    fi
fi

# ============================================================================
# Verify coverage actually runs
# ============================================================================

if npx vitest run --coverage --reporter=dot >/dev/null 2>&1; then
    echo "coverage runs"
else
    echo "coverage configured but a run failed; check vitest.config.ts" >&2
    exit 1
fi
