#!/usr/bin/env bash
# generator/lib.sh - shared helpers for the project generator and its stack layers.
# Sourced by init-ts-project.sh and the layer scripts (base.sh, mongo.sh, react.sh),
# so every layer uses the same output idiom, colour handling, and file primitives.
# Not executed directly. Expects DIR, VERBOSE, USE_COLOR, and TEMPLATES_DIR to be
# set by the orchestrator before use.

# Colour is enabled only when stdout is a real terminal, TERM is not dumb, and the
# user has not opted out (NO_COLOR convention or --no-color). Keeps escape codes out
# of piped or redirected output.
setup_color() {
    if [ "$USE_COLOR" = never ] || [ -n "${NO_COLOR:-}" ] \
       || [ ! -t 1 ] || [ "${TERM:-dumb}" = dumb ]; then
        C_RESET= ; C_STEP= ; C_NOTE= ; C_OK= ; C_ERR=
    else
        C_RESET=$'\033[0m'
        C_STEP=$'\033[1;36m'   # bold cyan, area headers
        C_NOTE=$'\033[2m'      # dim, detail lines
        C_OK=$'\033[32m'       # green, success
        C_ERR=$'\033[31m'      # red, errors
    fi
}

# step announces an area of work: one clean line by default.
step() { printf '%s==>%s %s\n' "$C_STEP" "$C_RESET" "$1"; }

# note prints a detail line only under --verbose.
note() { [ "$VERBOSE" = "1" ] && printf '%s    %s%s\n' "$C_NOTE" "$1" "$C_RESET"; return 0; }

# err prints to stderr in red.
err() { printf '%s%s%s\n' "$C_ERR" "$1" "$C_RESET" >&2; }

# write_file <path>: write the heredoc on stdin to a file, announcing it under
# --verbose. Use instead of a bare `cat >` so every write is consistently reported.
write_file() {
    local path="$1"
    cat > "$path"
    note "wrote ${path#"$DIR"/}"
}

# copy_template <template-name> <dest-path>: copy a shared template into the
# project, failing loudly if it is missing rather than emitting a broken project.
copy_template() {
    local src="$TEMPLATES_DIR/$1" dest="$2"
    if [ ! -f "$src" ]; then
        echo "missing template: $src (is the file-templates/ directory present?)" >&2
        exit 1
    fi
    cp "$src" "$dest"
    note "wrote ${dest#"$DIR"/} (from template)"
}
