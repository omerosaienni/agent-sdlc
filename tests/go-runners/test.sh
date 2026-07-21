#!/usr/bin/env bash
# Suite for the Go agent runners (file-templates/runners/go/): agent-tests.sh
# (go test) and agent-typecheck.sh (go build + go vet) must honour the stack-neutral
# exit-code contract (contracts/agent-runner.md) so the shared agent-hollow.sh
# drives them. Sourced and run by tests/run.sh.
#
# This is the most important new suite on this stack, because `go test` CONFLATES
# outcomes: it exits 0 for a package with no test files, and exits 1 for both a
# genuine assertion failure and a build error in a test package. Everything the
# judge concludes rests on the runner disentangling those, so each of the four codes
# is proved against a real Go package rather than asserted from the source.
#
# Structural checks always run. The live matrix scaffolds a BASE project (no
# third-party dependency, so no network is needed) and exercises every code path
# including an end-to-end hollow check through the SHARED runner.

suite_begin "go-runners (go test + go vet/build exit-code contract)" integration

GODIR="$REPO_ROOT/file-templates/runners/go"

# --- the templates drive Go tooling, not pytest/vitest -----------------------
# (existence is not asserted separately: these cat/grep checks and the live matrix
# below consume the files, so a missing template fails them just as loudly.)
expect_match 0 'go test'   "agent-tests.sh drives go test"          cat "$GODIR/agent-tests.sh"
expect_match 0 'go vet'    "agent-typecheck.sh drives go vet"       cat "$GODIR/agent-typecheck.sh"
expect_match 0 'go build'  "agent-typecheck.sh drives go build"     cat "$GODIR/agent-typecheck.sh"
expect_match 0 'tags=integration' "agent-tests.sh splits tiers by build tag" cat "$GODIR/agent-tests.sh"
# usage guards (the spine).
expect_exit 64 "agent-tests.sh no tier -> usage"      bash "$GODIR/agent-tests.sh"
expect_exit 64 "agent-tests.sh bad option -> usage"   bash "$GODIR/agent-tests.sh" unit --bogus
expect_exit 64 "agent-typecheck.sh bad arg -> usage"  bash "$GODIR/agent-typecheck.sh" bogus
expect_exit 64 "agent-tests.sh scope with 'both' -> usage" bash "$GODIR/agent-tests.sh" both internal/app

# --- live exit-code matrix (needs the go toolchain only) ---------------------
GEN="$REPO_ROOT/scripts/init-go-project.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
proj="$work/runtest"

# The SKIP is gated on the toolchain ALONE. A generator regression is a defect, not
# absent tooling, so it must fail the suite rather than quietly skip the matrix and
# leave the run green (tests/README.md sanctions self-skipping only for absent
# tooling).
if ! command -v go >/dev/null 2>&1; then
    printf '  %sSKIP%s live exit-code matrix (go toolchain absent)\n' "${C_NOTE:-}" "${C_RESET:-}"
elif ! bash "$GEN" runtest "$proj" >/dev/null 2>&1; then
    _t_bad "the generator failed to scaffold the runner fixture; the exit-code matrix could not run"
else

    mkdir -p "$proj/.building/scripts"
    cp "$GODIR/agent-tests.sh" "$GODIR/agent-typecheck.sh" \
       "$REPO_ROOT/file-templates/runners/agent-hollow.sh" "$proj/.building/scripts/"
    chmod +x "$proj/.building/scripts/"*.sh

    # rc <cmd...>: run in the project, echo the exit code.
    rc() { ( cd "$proj" && "$@" >/dev/null 2>&1 ); echo $?; }

    expect_exit 0 "live: unit tier passes -> 0"   test "$(rc .building/scripts/agent-tests.sh unit)" = 0
    expect_exit 0 "live: typecheck clean -> 0"    test "$(rc .building/scripts/agent-typecheck.sh)" = 0

    # Scope granularity: Go's unit of compilation is the package DIRECTORY, but the
    # shared agent-hollow.sh's usage contract passes a test FILE. The runner maps a
    # file to its package, which is what makes the two agree; prove both forms work,
    # because a regression here silently breaks every hollow check on this stack.
    expect_exit 0 "live: scope as a package directory -> 0" \
        test "$(rc .building/scripts/agent-tests.sh unit internal/app)" = 0
    expect_exit 0 "live: scope as a test FILE maps to its package -> 0" \
        test "$(rc .building/scripts/agent-tests.sh unit internal/app/app_test.go)" = 0

    # zero selected -> 2. cmd/<app> holds only main.go, so go test exits 0 there
    # while running nothing: exactly the conflation the runner must disentangle.
    expect_exit 0 "live: package with no test files -> 2 (not a pass)" \
        test "$(rc .building/scripts/agent-tests.sh unit cmd/runtest)" = 2

    # real assertion failure -> 1.
    cp "$proj/internal/app/app.go" "$work/app.bak"
    sed -i 's/return "app starting"/return "WRONG"/' "$proj/internal/app/app.go"
    expect_exit 0 "live: failing test -> 1" test "$(rc .building/scripts/agent-tests.sh unit)" = 1
    cp "$work/app.bak" "$proj/internal/app/app.go"

    # build error in a TEST package -> 3, NOT 1. go exits 1 for both, so this is the
    # case that would otherwise bounce an environment problem to the builder as a
    # behaviour failure.
    cat > "$proj/internal/app/broken_test.go" <<'GO'
package app

import "testing"

func TestBroken(t *testing.T) { undefinedSymbolXyz() }
GO
    expect_exit 0 "live: build error in a test package -> 3 (not a test failure)" \
        test "$(rc .building/scripts/agent-tests.sh unit)" = 3
    rm -f "$proj/internal/app/broken_test.go"

    # typecheck: a compile error in SOURCE is a rejection (1), not an environment block.
    cp "$proj/internal/app/app.go" "$work/app.bak2"
    sed -i 's/return "app starting"/return 42/' "$proj/internal/app/app.go"
    expect_exit 0 "live: typecheck build error -> 1" test "$(rc .building/scripts/agent-typecheck.sh)" = 1
    cp "$work/app.bak2" "$proj/internal/app/app.go"

    # typecheck: a vet finding that still COMPILES must also be a rejection (1). This
    # is the half of the gate `go build` alone would miss.
    cat > "$proj/internal/app/vetbad.go" <<'GO'
package app

import "fmt"

// Bad compiles cleanly but is a vet printf diagnostic.
func Bad() string { return fmt.Sprintf("%d", "not a number") }
GO
    expect_exit 0 "live: vet finding that compiles -> 1" \
        test "$(rc .building/scripts/agent-typecheck.sh)" = 1
    rm -f "$proj/internal/app/vetbad.go"

    # runners must report an environment block, never a failure, outside a module.
    expect_exit 0 "live: no go.mod -> tests 3" \
        test "$( ( cd "$work" && bash "$proj/.building/scripts/agent-tests.sh" unit >/dev/null 2>&1 ); echo $? )" = 3
    expect_exit 0 "live: no go.mod -> typecheck 3" \
        test "$( ( cd "$work" && bash "$proj/.building/scripts/agent-typecheck.sh" >/dev/null 2>&1 ); echo $? )" = 3

    # END-TO-END: the SHARED hollow runner drives the Go runner by exit code alone.
    # A real test catching the fault -> ASSERTS (hollow exit 0).
    expect_exit 0 "live: shared hollow ASSERTS on a real test" \
        test "$(rc .building/scripts/agent-hollow.sh unit internal/app/app.go internal/app/app_test.go 'app starting' 'broken')" = 0

    # A non-asserting test -> HOLLOW (hollow exit 1). It must live in its OWN package:
    # Go's scope unit is the package directory, so a hollow test placed beside the
    # real one would be rescued by its neighbour and the case would prove nothing.
    mkdir -p "$proj/internal/hollowdemo"
    cat > "$proj/internal/hollowdemo/hollow_test.go" <<'GO'
package hollowdemo

import (
	"testing"

	"runtest/internal/app"
)

func TestCallsGreeting(t *testing.T) { _ = app.Greeting() }
GO
    expect_exit 0 "live: shared hollow HOLLOW on a non-asserting test" \
        test "$(rc .building/scripts/agent-hollow.sh unit internal/app/app.go internal/hollowdemo/hollow_test.go 'app starting' 'broken')" = 1
    rm -rf "$proj/internal/hollowdemo"

    # A fault that breaks the COMPILE is not behavioural: BAD FAULT (hollow exit 2),
    # never a halt. This is the rc-3 asymmetry in contracts/agent-runner.md.
    expect_exit 0 "live: shared hollow BAD FAULT on a non-behavioural fault" \
        test "$(rc .building/scripts/agent-hollow.sh unit internal/app/app.go internal/app/app_test.go 'return "app starting"' 'return')" = 2

    # The tree must be back to green: every hollow run restores what it faulted.
    expect_exit 0 "live: tree restored to green after the hollow runs" \
        test "$(rc .building/scripts/agent-tests.sh unit)" = 0

    # --- regressions this suite exists to prevent ---------------------------
    # A real failure whose output carries a line starting "# " must stay a failure.
    # go prints that banner above compiler diagnostics, but so does any program
    # under test that emits a shell, SQL or markdown comment; matching it turned
    # genuine failures into environment blocks, which consume no judge attempt and
    # are read as BAD FAULT by the hollow check.
    cat > "$proj/internal/app/noisy_test.go" <<'GO'
package app

import (
	"fmt"
	"testing"
)

func TestNoisyFailure(t *testing.T) {
	fmt.Printf("# diagnostic dump\n# a comment-shaped line\n")
	t.Errorf("deliberate failure")
}
GO
    expect_exit 0 "live: a failure printing '# ' lines is still 1, not 3" \
        test "$(rc .building/scripts/agent-tests.sh unit)" = 1
    rm -f "$proj/internal/app/noisy_test.go"

    # A benchmark-only package reports "[no tests to run]" while passing. Counted
    # across the module rather than per package, it marked a fully green tier hollow.
    mkdir -p "$proj/internal/bench"
    cat > "$proj/internal/bench/bench.go" <<'GO'
package bench

// Noop exists so the package compiles with only a benchmark beside it.
func Noop() {}
GO
    cat > "$proj/internal/bench/bench_test.go" <<'GO'
package bench

import "testing"

func BenchmarkNoop(b *testing.B) {
	for range b.N {
		Noop()
	}
}
GO
    expect_exit 0 "live: a benchmark-only package does not make a green tier hollow" \
        test "$(rc .building/scripts/agent-tests.sh unit)" = 0
    rm -rf "$proj/internal/bench"

    # The integration tier must be able to report a zero selection. `go test -tags`
    # ADDS files rather than selecting only them, so over the whole module the tagged
    # tier is a superset of the unit tier and code 2 would be unreachable.
    expect_exit 0 "live: no tagged test files -> integration reports 2" \
        test "$(rc .building/scripts/agent-tests.sh integration)" = 2
    cat > "$proj/internal/app/tagged_integration_test.go" <<'GO'
//go:build integration

package app

import "testing"

func TestTagged(t *testing.T) {
	if Greeting() == "" {
		t.Error("empty greeting")
	}
}
GO
    expect_exit 0 "live: a tagged test file -> integration reports 0" \
        test "$(rc .building/scripts/agent-tests.sh integration)" = 0
    rm -f "$proj/internal/app/tagged_integration_test.go"

    # --verbose adds detail; it must NOT change the verdict. Returning go's own code
    # inverted the contract (a build error read as a failure, zero selection as a pass).
    expect_exit 0 "live: --verbose keeps the contract code" \
        test "$(rc .building/scripts/agent-tests.sh unit --verbose)" = 0

    # A LIBRARY-ONLY module (no main package anywhere) must type-check clean. The
    # gate discards the linked binary with -o, and `go build -o <dir>/` fails
    # outright when there is nothing to link, which reported a clean library as a
    # build error the builder could not act on.
    lib="$work/libonly"
    mkdir -p "$lib/internal/calc"
    printf 'module libonly\n\ngo 1.23\n' > "$lib/go.mod"
    cat > "$lib/internal/calc/calc.go" <<'GO'
package calc

// Add exists so the module has a package and no main.
func Add(a, b int) int { return a + b }
GO
    cat > "$lib/internal/calc/calc_test.go" <<'GO'
package calc

import "testing"

func TestAdd(t *testing.T) {
	if Add(1, 2) != 3 {
		t.Errorf("Add(1,2) = %d, want 3", Add(1, 2))
	}
}
GO
    expect_exit 0 "live: a module with no main package type-checks clean" \
        test "$( ( cd "$lib" && bash "$GODIR/agent-typecheck.sh" >/dev/null 2>&1 ); echo $? )" = 0
    expect_exit 0 "live: a module with no main package runs its unit tier" \
        test "$( ( cd "$lib" && bash "$GODIR/agent-tests.sh" unit >/dev/null 2>&1 ); echo $? )" = 0

    # A panic in a goroutine fails the tier WITHOUT a "--- FAIL:" line. It is the
    # code under test misbehaving, so it belongs to the builder as a failure, not
    # written off as an environment block the loop can route nowhere.
    cat > "$proj/internal/app/panic_test.go" <<'GO'
package app

import "testing"

func TestPanicsInAGoroutine(t *testing.T) {
	done := make(chan struct{})
	go func() { defer close(done); panic("worker died") }()
	<-done
}
GO
    expect_exit 0 "live: a goroutine panic is a failure (1), not an environment block" \
        test "$(rc .building/scripts/agent-tests.sh unit)" = 1
    rm -f "$proj/internal/app/panic_test.go"

    # The hollow check narrows to the test FUNCTIONS in the file it was pointed at.
    # Scoping only to the package let a real neighbour catch the planted fault, so a
    # non-asserting test graded ASSERTS: a false green on the gate whose whole job is
    # catching hollow tests.
    cat > "$proj/internal/app/hollow_test.go" <<'GO'
package app

import "testing"

func TestCallsGreetingWithoutAsserting(t *testing.T) { _ = Greeting() }
GO
    expect_exit 0 "live: a hollow test BESIDE a real one is still HOLLOW" \
        test "$(rc .building/scripts/agent-hollow.sh unit internal/app/app.go internal/app/hollow_test.go 'app starting' 'broken')" = 1
    expect_exit 0 "live: the real test beside it still ASSERTS" \
        test "$(rc .building/scripts/agent-hollow.sh unit internal/app/app.go internal/app/app_test.go 'app starting' 'broken')" = 0
    rm -f "$proj/internal/app/hollow_test.go"

    # The same, on the tagged tier: an integration test that asserts nothing must not
    # be rescued by the unit tests Go co-locates in the same package.
    cat > "$proj/internal/app/app_integration_test.go" <<'GO'
//go:build integration

package app

import "testing"

func TestAppIntegrationWithoutAsserting(t *testing.T) { _ = Greeting() }
GO
    expect_exit 0 "live: a non-asserting INTEGRATION test is HOLLOW despite unit tests beside it" \
        test "$(rc .building/scripts/agent-hollow.sh integration internal/app/app.go internal/app/app_integration_test.go 'app starting' 'broken')" = 1
    expect_exit 0 "live: the scoped integration tier still runs" \
        test "$(rc .building/scripts/agent-tests.sh integration)" = 0
    rm -f "$proj/internal/app/app_integration_test.go"

    # A comment MENTIONING the build tag must not fabricate an integration tier: the
    # tagged files are resolved by asking the toolchain, not by grepping for the tag.
    cat > "$proj/internal/app/doc_test.go" <<'GO'
package app

// The integration tier is declared with //go:build integration at the top of a file.
GO
    expect_exit 0 "live: prose naming the tag does not fabricate an integration tier" \
        test "$(rc .building/scripts/agent-tests.sh integration)" = 2
    rm -f "$proj/internal/app/doc_test.go"

    # 'both' runs unit then integration, and reports the integration verdict.
    expect_exit 0 "live: 'both' with no tagged tests reports the integration verdict (2)" \
        test "$(rc .building/scripts/agent-tests.sh both)" = 2

    # The env_failure classifier itself was untested, which is why an ordering bug in
    # it survived two review rounds. An unreachable proxy is an ENVIRONMENT block (3),
    # never a type error: go attributes the fetch failure to the importing file's
    # line, so a classifier that looks for a compiler diagnostic first calls a dead
    # proxy a type error and tells the builder to fix their types.
    netproj="$work/netfail"
    mkdir -p "$netproj"
    printf 'module netfail\n\ngo 1.23\n' > "$netproj/go.mod"
    cat > "$netproj/main.go" <<'GO'
package main

import "github.com/definitely/not/a/real/module/anywhere"

func main() { _ = anywhere.Thing }
GO
    expect_exit 0 "live: an unreachable module proxy is an environment block (3), not a type error" \
        test "$( ( cd "$netproj" && GOFLAGS=-mod=mod GOPROXY=off GOMODCACHE="$work/emptycache" \
            bash "$GODIR/agent-typecheck.sh" >/dev/null 2>&1 ); echo $? )" = 3
    # And the two runners must agree on the same input.
    expect_exit 0 "live: the test runner agrees it is an environment block (3)" \
        test "$( ( cd "$netproj" && GOFLAGS=-mod=mod GOPROXY=off GOMODCACHE="$work/emptycache" \
            bash "$GODIR/agent-tests.sh" unit >/dev/null 2>&1 ); echo $? )" = 3

    # An unusable TOOLCHAIN is an environment block, not a rejection. go.mod asking
    # for a newer Go than is installed is not something a builder can fix, and both
    # runners must agree about it: they disagreed on exactly this input while only
    # the proxy case was covered.
    toolproj="$work/toolchain"
    mkdir -p "$toolproj"
    printf 'module toolchain\n\ngo 1.99.0\n' > "$toolproj/go.mod"
    printf 'package toolchain\n\n// F exists so the package compiles.\nfunc F() int { return 1 }\n' > "$toolproj/f.go"
    expect_exit 0 "live: a toolchain the module cannot use is an environment block (typecheck 3)" \
        test "$( ( cd "$toolproj" && GOTOOLCHAIN=local bash "$GODIR/agent-typecheck.sh" >/dev/null 2>&1 ); echo $? )" = 3
    expect_exit 0 "live: the test runner agrees a toolchain block is 3" \
        test "$( ( cd "$toolproj" && GOTOOLCHAIN=local bash "$GODIR/agent-tests.sh" unit >/dev/null 2>&1 ); echo $? )" = 3

    # --- the type gate classifies by go's OWN output structure --------------
    # Three review rounds patched a whitelist of environment error strings here, and
    # each patch introduced the next round's defect. The rule is now structural: go
    # prints a "# <import/path>" banner above every compiler and vet diagnostic and
    # prints none when it never got as far as compiling. These cases are the ones the
    # whitelist got wrong, so they are the ones that must stay covered.
    tcproj="$work/typeclass"
    # tc_rc <file-body> [env...]: the gate's exit code on a module holding that body.
    tc_rc() {
        local body="$1"; shift
        rm -rf "$tcproj"; mkdir -p "$tcproj"
        printf 'module typeclass\n\ngo 1.23\n' > "$tcproj/go.mod"
        printf '%s' "$body" > "$tcproj/a.go"
        ( cd "$tcproj" && env "$@" bash "$GODIR/agent-typecheck.sh" >/dev/null 2>&1 ); echo $?
    }

    # A diagnostic that merely QUOTES an environment phrase is still the builder's to
    # fix. Under the whitelist this exact line was reported as an environment block,
    # so a real type error consumed no attempt and the loop had nowhere to route it.
    expect_exit 0 "live: a type error quoting 'connection refused' is a rejection (1)" \
        test "$(tc_rc 'package a

var x int = "connection refused"
')" = 1
    expect_exit 0 "live: an undefined identifier named 'proxyconnect' is a rejection (1)" \
        test "$(tc_rc 'package a

var x = proxyconnect
')" = 1
    # The mirror of the above: a bare GOTOOLCHAIN term was removed from the whitelist
    # for matching diagnostics like this one, which then left the real toolchain
    # failure below misclassified. The structural rule has to get BOTH right.
    expect_exit 0 "live: an undefined identifier named 'GOTOOLCHAIN' is a rejection (1)" \
        test "$(tc_rc 'package a

var x = GOTOOLCHAIN
')" = 1
    # An unusable toolchain is nobody's code, and no whitelist entry says so now.
    expect_exit 0 "live: an invalid GOTOOLCHAIN value is an environment block (3)" \
        test "$(tc_rc 'package a
' GOTOOLCHAIN=nonsense)" = 3
    # Two more go-level failures that were never on any list, which is the point: the
    # default is now the block, so an unanticipated go failure needs no entry to be
    # classified correctly.
    expect_exit 0 "live: unparseable GOFLAGS is an environment block (3)" \
        test "$(tc_rc 'package a
' GOFLAGS=--bogus)" = 3
    expect_exit 0 "live: an unusable GOCACHE is an environment block (3)" \
        test "$(tc_rc 'package a
' GOCACHE=notabsolute)" = 3
    # Module hygiene has no banner either, but go mod tidy fixes it, so it must stay
    # a rejection: classifying it as environment leaves the loop unable to route the
    # one action that would resolve it.
    expect_exit 0 "live: a malformed go.mod is a rejection (1), not a block" \
        test "$( rm -rf "$tcproj"; mkdir -p "$tcproj"; printf 'module\n' > "$tcproj/go.mod"
                 printf 'package a\n' > "$tcproj/a.go"
                 ( cd "$tcproj" && bash "$GODIR/agent-typecheck.sh" >/dev/null 2>&1 ); echo $? )" = 1
    # Default -mod=readonly, deliberately: go answers "no required module provides
    # package" from go.mod alone and never reaches the network, so this stays a
    # rejection offline. Adding -mod=mod would send it to the proxy, where the same
    # source is correctly an environment block instead.
    expect_exit 0 "live: an import no module provides is a rejection (1), not a block" \
        test "$( rm -rf "$tcproj"; mkdir -p "$tcproj"; printf 'module typeclass\n\ngo 1.23\n' > "$tcproj/go.mod"
                 printf 'package a\n\nimport _ "modernc.org/sqlite"\n' > "$tcproj/a.go"
                 ( cd "$tcproj" && bash "$GODIR/agent-typecheck.sh" >/dev/null 2>&1 ); echo $? )" = 1
    rm -rf "$tcproj"

    # A scoped file that declares no test function selects NOTHING. Falling back to
    # the whole package would let a neighbour's test answer for the file that was
    # asked about, so a helpers-only file would grade ASSERTS off someone else's
    # assertion: a false pass on the gate whose job is catching hollow tests.
    cat > "$proj/internal/app/helpers_test.go" <<'GO'
package app

// helper exists so this file declares no test function at all.
func helper() string { return Greeting() }
GO
    expect_exit 0 "live: a scoped file declaring no test function selects zero (2), not a borrowed pass" \
        test "$(rc .building/scripts/agent-tests.sh unit internal/app/helpers_test.go)" = 2
    # Through the shared hollow runner that surfaces as HALT (3), not a pass: its
    # restore-verify requires a green tier, and a zero selection is not green. The
    # code is heavier than the BAD FAULT the negative run alone would give, but the
    # property that matters holds, and holds loudly: pointing the check at a file
    # with no tests can no longer be answered by a neighbour.
    expect_exit 0 "live: the shared hollow runner refuses a test-free file rather than passing it" \
        test "$(rc .building/scripts/agent-hollow.sh unit internal/app/app.go internal/app/helpers_test.go 'app starting' 'broken')" = 3
    rm -f "$proj/internal/app/helpers_test.go"

    # The type-check gate must leave no artefact: `go build ./...` drops a binary
    # named after the module whenever a main package sits at the root.
    before="$( cd "$proj" && ls | sort )"
    rc .building/scripts/agent-typecheck.sh >/dev/null
    after="$( cd "$proj" && ls | sort )"
    if [ "$before" = "$after" ]; then
        _t_ok "live: the type-check gate leaves no build artefact behind"
    else
        _t_bad "live: the type-check gate changed the working tree; before [$before] after [$after]"
    fi
fi

suite_summary
