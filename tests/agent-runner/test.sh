#!/usr/bin/env bash
# Suite for the agent-runner seam (contracts/agent-runner.md): the shared
# hollow-check runner classifies a negative run by the test runner's EXIT CODE
# alone, never its output text, so one file serves every stack. Sourced and run by
# tests/run.sh, which sets REPO_ROOT, the colour vars, and sources tests/lib.sh.
#
# The proof is a STUB agent-tests.sh that returns a chosen exit code regardless of
# its arguments and prints stack-arbitrary words. Driving the real shared
# agent-hollow.sh against it proves the verdict comes from the code, not the words.
# The same proof, with a Python-flavoured stub, is reused by the Python runners.

suite_begin "agent-runner seam (shared hollow + per-stack layout)"

HOLLOW="$REPO_ROOT/file-templates/runners/agent-hollow.sh"

# --- the hollow verdict reads the exit code, not the words ----------------------
# Build a throwaway project dir with .building/scripts/ holding the shared hollow
# runner and a STUB agent-tests.sh whose exit code we control. RC_FILE carries the
# code the stub returns; the stub prints deliberately NON-vitest words so a verdict
# that depended on output strings would misclassify.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/.building/scripts" "$work/src"
cp "$HOLLOW" "$work/.building/scripts/agent-hollow.sh"; chmod +x "$work/.building/scripts/agent-hollow.sh"

cat > "$work/.building/scripts/agent-tests.sh" <<'STUB'
#!/usr/bin/env bash
# Stub test runner: return the code in .building/rc, print stack-arbitrary words.
# Models any stack's agent-tests.sh: only the exit code is the contract.
echo "pytest-ish: some words that are NOT vitest output"
exit "$(cat .building/rc 2>/dev/null || echo 0)"
STUB
chmod +x "$work/.building/scripts/agent-tests.sh"

# A source file with a unique fault target, and a (dummy) test file: the hollow
# runner only needs them to exist and the fault string to occur exactly once.
echo 'export const answer = 42;' > "$work/src/a.ts"
echo '// test' > "$work/src/a.test.ts"

# run_hollow <rc>: set the stub's return code, run the shared hollow runner once,
# echo its own exit code. The restore-verify run uses the SAME rc, so a non-green
# rc on the negative run also fails the restore (HALT) unless we reset rc to 0
# first. To isolate the NEGATIVE-run classification we reset rc to 0 right after
# the negative run by having the stub read rc fresh each call: see per-case setup.
hollow_verdict() {
    local neg_rc="$1" restore_rc="${2:-0}" ec
    # The negative run and the restore-verify run both call the stub. We want the
    # negative run to return neg_rc and the restore run to return restore_rc. The
    # stub reads .building/rc each call, so a single value cannot differ between the
    # two calls. Encode a two-shot sequence: first call pops the first line.
    printf '%s\n%s\n' "$neg_rc" "$restore_rc" > "$work/.building/rc.seq"
    cat > "$work/.building/scripts/agent-tests.sh" <<'STUB'
#!/usr/bin/env bash
echo "stack-arbitrary words, not vitest"
seq=".building/rc.seq"
code="$(head -1 "$seq" 2>/dev/null || echo 0)"
tail -n +2 "$seq" > "$seq.tmp" 2>/dev/null && mv "$seq.tmp" "$seq"
exit "$code"
STUB
    chmod +x "$work/.building/scripts/agent-tests.sh"
    ( cd "$work" && bash .building/scripts/agent-hollow.sh unit src/a.ts src/a.test.ts '42' '43' >/dev/null 2>&1 ); ec=$?
    echo "$ec"
}

# Each case asserts the hollow runner's OWN exit code (captured by hollow_verdict)
# equals the expected value. expect_exit asserts the exit CODE of the command, so
# the command is `test <verdict> = <want>` and we expect it to SUCCEED (exit 0).
# negative run rc 0 -> HOLLOW (hollow's own exit 1); restore run green (rc 0).
expect_exit 0  "rc0 negative run -> HOLLOW (exit 1)"     test "$(hollow_verdict 0 0)" = 1
# negative run rc 1 -> ASSERTS (hollow's own exit 0).
expect_exit 0  "rc1 negative run -> ASSERTS (exit 0)"    test "$(hollow_verdict 1 0)" = 0
# negative run rc 2 -> BAD FAULT (hollow's own exit 2).
expect_exit 0  "rc2 negative run -> BAD FAULT (exit 2)"  test "$(hollow_verdict 2 0)" = 2
# negative run rc 3 -> BAD FAULT, not HALT (fault broke the build, re-pick).
expect_exit 0  "rc3 negative run -> BAD FAULT (exit 2)"  test "$(hollow_verdict 3 0)" = 2
# restore-verify run non-green (rc 1) -> HALT (hollow's own exit 3), even though
# the negative run asserted. This is the rc-3-asymmetry's partner: a failed
# restore halts regardless of the negative verdict.
expect_exit 0  "non-green restore -> HALT (exit 3)"      test "$(hollow_verdict 1 1)" = 3

suite_summary
