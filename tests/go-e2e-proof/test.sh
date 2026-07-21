#!/usr/bin/env bash
# Suite for the Go build path end to end (go-e2e-proof): prove the definition of
# done in one flow. Scaffold a Go project, run the setup gate to a READY receipt
# proved by real go build and go test, add a small typed increment with a unit test,
# then run the judge's own verification sequence on it through the placed runners:
# type-check first, then the unit tier, then the hollow negative run, all by exit
# code. Finally assert the stack-agnostic core contracts still name no stack, so the
# core stayed agnostic. Sourced and run by tests/run.sh.
#
# This is the executable form of the walkthrough in docs/go-build-path.md. It does
# not invoke /omero-build-full (agent-sdlc is not a loop target; the loop builds
# generated projects, not the meta-repo): it exercises the same real pieces the
# loop's setup gate and judge use, which is what the proof needs.
#
# The base scaffold has no third-party dependency, so the whole proof runs offline
# with only the Go toolchain, gh and a git identity present.

suite_begin "go-e2e-proof (Go build path end to end)" integration

GEN="$REPO_ROOT/scripts/init-go-project.sh"
SETUP="$REPO_ROOT/scripts/project-setup.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proj="$work/goapp"

if command -v go >/dev/null 2>&1 && command -v gh >/dev/null 2>&1 \
   && [ -n "$(git config --global user.email 2>/dev/null)" ] \
   && bash "$GEN" goapp "$proj" --http >/dev/null 2>&1; then

    ( cd "$proj" && git config sdlc.identityAllowlist "$(git config user.email)" )

    # 1. setup gate -> READY, proved by real go build and go test. This is also
    #    where the three runners are placed, so everything below runs through the
    #    copies the gate itself put down, not through the templates.
    if ( cd "$proj" && bash "$SETUP" >/dev/null 2>&1 ) && [ -f "$proj/.building/setup-ok" ]; then
        _t_ok "e2e: setup gate reaches READY (receipt written) on the Go project"
    else
        _t_bad "e2e: setup gate did not reach READY on the Go project"
    fi

    # The gate must have detected the stack from go.mod and sourced the Go module.
    expect_match 0 'go present' "e2e: the gate detected the Go stack from go.mod" \
        bash -c "cd '$proj' && bash '$SETUP' --check 2>&1"

    # 2. add a small typed application increment: a value object with behaviour,
    #    table-driven tested, the shape omero-go.md asks for.
    mkdir -p "$proj/internal/tally"
    cat > "$proj/internal/tally/tally.go" <<'GO'
// Package tally counts occurrences, the shape a real increment takes: a small
// exported surface with behaviour worth asserting.
package tally

// Counts returns how many times each value appears, in no particular order.
func Counts(values []string) map[string]int {
	out := make(map[string]int, len(values))
	for _, v := range values {
		out[v]++
	}
	return out
}
GO
    cat > "$proj/internal/tally/tally_test.go" <<'GO'
package tally

import "testing"

func TestCounts(t *testing.T) {
	tests := []struct {
		name   string
		values []string
		want   map[string]int
	}{
		{name: "empty input", values: nil, want: map[string]int{}},
		{name: "counts repeats", values: []string{"a", "b", "a"}, want: map[string]int{"a": 2, "b": 1}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Counts(tt.values)
			if len(got) != len(tt.want) {
				t.Fatalf("Counts(%v) = %v, want %v", tt.values, got, tt.want)
			}
			for k, want := range tt.want {
				if got[k] != want {
					t.Errorf("Counts(%v)[%q] = %d, want %d", tt.values, k, got[k], want)
				}
			}
		})
	}
}
GO

    # 3. the judge sequence on the increment, through the PLACED runners, by exit
    #    code: type-check FIRST, then the unit tier, then the hollow negative run.
    rc() { ( cd "$proj" && "$@" >/dev/null 2>&1 ); echo $?; }

    expect_exit 0 "e2e: judge type-check gate clean on the increment (build + vet, exit 0)" \
        test "$(rc .building/scripts/agent-typecheck.sh)" = 0
    expect_exit 0 "e2e: judge unit tier passes on the increment (go test, exit 0)" \
        test "$(rc .building/scripts/agent-tests.sh unit)" = 0
    # hollow negative run via the SHARED runner: a real test catches a real fault.
    # The fault is behavioural and still compiles (v++ becomes v+=2), which is what
    # the hollow check requires.
    expect_exit 0 "e2e: judge hollow check ASSERTS on the increment (real test catches the fault)" \
        test "$(rc .building/scripts/agent-hollow.sh unit internal/tally/tally.go internal/tally/tally_test.go 'out[v]++' 'out[v] += 2')" = 0

    # 4. a deliberate compile error is caught by the gate (the gate is real, not a
    #    no-op), and the tier that follows it never runs on broken code.
    cp "$proj/internal/tally/tally.go" "$work/tally_bak"
    sed -i 's/out\[v\]++/out[v] = "not an int"/' "$proj/internal/tally/tally.go"
    expect_exit 0 "e2e: judge type-check gate catches a real type error (exit 1)" \
        test "$(rc .building/scripts/agent-typecheck.sh)" = 1
    cp "$work/tally_bak" "$proj/internal/tally/tally.go"

    # 5. the gate is idempotent: a second run is still READY and changes nothing.
    if ( cd "$proj" && bash "$SETUP" >/dev/null 2>&1 ); then
        _t_ok "e2e: setup gate idempotent (second run still READY)"
    else
        _t_bad "e2e: setup gate not idempotent on the Go project"
    fi
else
    printf '  %sSKIP%s live end-to-end proof (go/gh/git-identity absent)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

# --- invariant: the core stayed stack-agnostic -------------------------------
# The whole point of the seam is that adding Go touches the generator and the
# runners and nothing above them. These contracts must name no stack at all.
# "go" alone is too common a word in English prose to grep for, so the pattern
# targets the Go-specific tokens that would actually indicate a leak.
GO_TOKENS='\bgolang\b|go vet|go test|go build|go\.mod|gofmt|//go:build'
expect_exit 1 "design-partner contract names no stack (Go)" \
    grep -qiE "$GO_TOKENS" "$REPO_ROOT/contracts/design-partner.md"
expect_exit 1 "increment schema names no stack (Go)" \
    grep -qiE "$GO_TOKENS" "$REPO_ROOT/contracts/increment-sheet.schema.md"
expect_exit 1 "state schema names no stack (Go)" \
    grep -qiE "$GO_TOKENS" "$REPO_ROOT/contracts/state.schema.md"
# The shared hollow runner is stack-neutral by construction: it reads integers, not
# words, so it must never mention any stack's tooling.
expect_exit 1 "the shared hollow runner names no stack (Go)" \
    grep -qiE "$GO_TOKENS" "$REPO_ROOT/file-templates/runners/agent-hollow.sh"

suite_summary
