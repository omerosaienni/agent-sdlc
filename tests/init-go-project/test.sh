#!/usr/bin/env bash
# Suite for scripts/init-go-project.sh: the Go generator scaffolds a single-binary
# module with an embed.FS client and a non-hollow unit tier, each layer flag adds
# exactly its own files, and the result really builds and tests. Sourced and run by
# tests/run.sh, which sets REPO_ROOT, the colour vars, and sources tests/lib.sh.
#
# Structural checks always run (no toolchain, no network). The base live proof needs
# only the Go toolchain: the base layer has no third-party dependency, so it builds
# and tests offline. The --sqlite live proof additionally needs the module proxy
# (modernc.org/sqlite) and self-skips without it, never silently passing.

suite_begin "init-go-project.sh (Go generator)" integration

GEN="$REPO_ROOT/scripts/init-go-project.sh"

# --- input guards (the spine) ------------------------------------------------
expect_exit 2  "no name -> usage"                bash "$GEN"
expect_exit 2  "non-kebab name -> usage"         bash "$GEN" Bad_Name
expect_exit 2  "unknown option -> usage"         bash "$GEN" demo-app --bogus

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- base scaffold (structural, no toolchain) --------------------------------
base="$work/demo-app"
if bash "$GEN" demo-app "$base" >/dev/null 2>&1; then
    _t_ok "generator exits 0 scaffolding demo-app"
else
    _t_bad "generator failed to scaffold demo-app"
fi

# The module marker names the project, and it is the marker the setup gate detects.
expect_match 0 '^module demo-app$' "go.mod declares the module" cat "$base/go.mod"
# One binary: the entry point is under cmd/<app>, everything else under internal/.
expect_match 0 'package main' "cmd/<app>/main.go is the entry point" cat "$base/cmd/demo-app/main.go"
# The embed point exists and is the single place the client is served from.
expect_match 0 'go:embed all:static' "assets embed the static client" cat "$base/internal/assets/assets.go"
# The committed placeholder is what makes //go:embed resolve on a fresh clone; without
# it the module would not compile until someone ran a Node build.
expect_match 0 '<html' "a placeholder index.html is committed for the embed to match" cat "$base/internal/assets/static/index.html"
# CLAUDE.md declares the Integration endpoints section the setup gate greps for.
expect_match 0 'Integration endpoints' "CLAUDE.md declares integration endpoints" cat "$base/CLAUDE.md"
# git initialised on main with the scaffold commit: assert the behaviour, not just
# that a .git directory is present.
expect_match 0 '^main$' "git on main with the scaffold commit" git -C "$base" branch --show-current
# The Go stack rule is installed for the base (no react rule without the layer).
expect_exit 0 "go stack rule installed"          test -f "$base/.claude/rules/omero-go.md"
expect_exit 1 "no react rule without --react"    test -f "$base/.claude/rules/omero-react.md"
# --help honours the header-block convention (also covered by tests/script-help).
expect_exit 0 "--help exits clean" bash "$GEN" --help

# --- each layer flag adds exactly its own files ------------------------------
# The base must NOT carry any layer's files, or the flags are not really optional.
expect_exit 1 "base has no sqlite store"   test -d "$base/internal/store"
expect_exit 1 "base has no http server"    test -d "$base/internal/httpapi"
expect_exit 1 "base has no react client"   test -d "$base/client"
expect_exit 1 "base writes no services.yaml (no layer has an address)" test -f "$base/config/services.yaml"

sq="$work/sq-app"
bash "$GEN" sq-app "$sq" --sqlite >/dev/null 2>&1
expect_match 0 'modernc.org/sqlite' "--sqlite uses the pure-Go driver" cat "$sq/internal/store/store.go"
# The constraint is that the CGo driver is never DEPENDED ON, which is a quoted
# import path in Go source and a require line in go.mod. A bare name match would
# instead fail on the store's own comment and the project rule, both of which name
# the driver precisely to say never to use it.
expect_exit 1 "--sqlite never imports the CGo driver" \
    grep -rq --include='*.go' '"github.com/mattn/go-sqlite3"' "$sq"
expect_exit 1 "--sqlite never requires the CGo driver in go.mod" \
    grep -q 'mattn/go-sqlite3' "$sq/go.mod"
expect_match 0 '//go:build integration' "--sqlite declares the integration tier by build tag" cat "$sq/internal/store/store_integration_test.go"
expect_match 0 'integration:' "--sqlite adds the CI integration job" cat "$sq/.github/workflows/ci.yml"
expect_exit 1 "--sqlite adds no http server" test -d "$sq/internal/httpapi"

ht="$work/ht-app"
bash "$GEN" ht-app "$ht" --http >/dev/null 2>&1
expect_match 0 'httptest' "--http unit-tests the handler through httptest" cat "$ht/internal/httpapi/server_test.go"
expect_match 0 'httpapi.ListenAndServe' "--http replaces the entry point with the server bootstrap" cat "$ht/cmd/ht-app/main.go"
expect_match 0 '^server:' "--http contributes its services.yaml block" cat "$ht/config/services.yaml"
# config-env.sh ran during scaffold, so .env is seeded and the binary runs as built.
expect_match 0 '^SERVER_PORT=' ".env seeded from services.yaml at scaffold time" cat "$ht/.env"
# The generated server must be production-shaped, not a toy. Each of these was
# added to the reference project by hand first, which is exactly how a template and
# the project it is supposed to produce drift apart.
for want in ReadHeaderTimeout ReadTimeout WriteTimeout IdleTimeout; do
    expect_match 0 "$want" "--http sets $want (the zero value is no timeout at all)" \
        cat "$ht/internal/httpapi/server.go"
done
expect_match 0 'srv.Shutdown' "--http shuts the server down rather than dying where it stands" \
    cat "$ht/internal/httpapi/server.go"
expect_match 0 'signal.NotifyContext' "--http listens for a termination signal" \
    cat "$ht/cmd/ht-app/main.go"
# log.Fatal skips every deferred call in the frame, so a main that holds one is
# making a promise it does not keep. The work belongs in a function returning error.
expect_match 0 'func run\(\) error' "--http puts the work in run() so deferred cleanup is reachable" \
    cat "$ht/cmd/ht-app/main.go"
# The config file has to reach the binary. It reached only the Vite dev server, so
# editing a port changed the client and left the server on its compiled default.
expect_match 0 'set -a; \[ -f .env \]' "--http sources .env in server-start so services.yaml reaches the binary" \
    cat "$ht/Makefile"

rt="$work/rt-app"
bash "$GEN" rt-app "$rt" --react >/dev/null 2>&1
expect_match 0 'outDir' "--react builds the Vite client to its own dist" cat "$rt/client/vite.config.ts"
expect_match 0 'cp -r client/dist internal/assets/static' "--react syncs the built client into the one embed point" cat "$rt/Makefile"
expect_exit 0 "--react installs the react stack rule" test -f "$rt/.claude/rules/omero-react.md"
# The Go tree must stay free of Node: no Go package inside client/, or every
# `go build ./...` would walk client/node_modules. find exits 0 whether or not it
# matched, so the assertion is on its OUTPUT being empty, not on its exit code.
stray_go="$(find "$rt/client" -name '*.go' 2>/dev/null)"
if [ -z "$stray_go" ]; then
    _t_ok "--react puts no Go package inside the client tree"
else
    _t_bad "--react put Go files inside the client tree: $stray_go"
fi

# --- live proof: the base scaffold really builds, vets and tests --------------
# Needs only the toolchain: the base layer has no third-party dependency, so this
# runs offline. Reported skipped (never passed) when go is absent.
if command -v go >/dev/null 2>&1; then
    inb() { ( cd "$base" && "$@" >/dev/null 2>&1 ); }
    if inb go build ./...; then _t_ok "live: go build ./... compiles the fresh scaffold"
    else _t_bad "live: go build ./... failed on the fresh scaffold"; fi
    if inb go vet ./...; then _t_ok "live: go vet ./... clean on the fresh scaffold"
    else _t_bad "live: go vet ./... reported findings on the fresh scaffold"; fi
    if inb go test ./...; then _t_ok "live: go test ./... passes (the unit tier selects a test)"
    else _t_bad "live: go test ./... failed on the fresh scaffold"; fi
    # gofmt-clean matters because the generated files are the reviewer's baseline: a
    # scaffold that is not gofmt-clean fails the project's own `make check` on day one.
    if [ -z "$( cd "$base" && gofmt -l . 2>/dev/null )" ]; then
        _t_ok "live: the fresh scaffold is gofmt-clean"
    else
        _t_bad "live: the fresh scaffold is not gofmt-clean: $( cd "$base" && gofmt -l . )"
    fi
else
    printf '  %sSKIP%s live base build/vet/test proof (go toolchain absent)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

# --- live proof: the --sqlite layer resolves and both tiers pass --------------
# Needs the module proxy to fetch modernc.org/sqlite, so this is the one part that
# wants network. Skipped, never silently passed, when tidy cannot resolve.
if command -v go >/dev/null 2>&1 && ( cd "$sq" && go mod tidy >/dev/null 2>&1 ); then
    insq() { ( cd "$sq" && "$@" >/dev/null 2>&1 ); }
    if insq go test ./...; then _t_ok "live: --sqlite unit tier passes"
    else _t_bad "live: --sqlite unit tier failed"; fi
    if insq go test -tags=integration ./...; then _t_ok "live: --sqlite integration tier passes (temp DB, in process)"
    else _t_bad "live: --sqlite integration tier failed"; fi
    # The tag split is the tier split: the migration test must be invisible to the
    # unit tier, or the two tiers are the same tier wearing different names.
    if ( cd "$sq" && go test -run TestMigrateCreatesSchema ./internal/store 2>&1 | grep -q 'no tests to run' ); then
        _t_ok "live: the integration test is invisible to the unit tier (build-tag split holds)"
    else
        _t_bad "live: the integration test was selectable without the integration tag"
    fi
else
    printf '  %sSKIP%s live --sqlite proof (go absent or no network for the module proxy)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

# --- live proof: the --react layer really installs, builds and tests -----------
# Needs Node and the npm registry, so it self-skips rather than silently passing.
# Without it the whole client layer was asserted by grep alone, and a broken
# package.json, tsconfig or client test would have shipped with the suite green.
if command -v npm >/dev/null 2>&1 && ( cd "$rt" && npm --prefix client install --no-audit --no-fund >/dev/null 2>&1 ); then
    inrt() { ( cd "$rt" && "$@" >/dev/null 2>&1 ); }
    if inrt npm --prefix client run build; then _t_ok "live: --react client type-checks and builds"
    else _t_bad "live: --react client failed to build"; fi
    if inrt npm --prefix client run test; then _t_ok "live: --react client unit tier passes"
    else _t_bad "live: --react client unit tier failed"; fi
    # The sync is what puts the build where the binary embeds it. Without it the
    # binary serves the placeholder for ever while every gate stays green.
    if inrt make client-build && [ -f "$rt/internal/assets/static/index.html" ] \
       && grep -q 'assets/' "$rt/internal/assets/static/index.html"; then
        _t_ok "live: make client-build syncs the built client into the embedded assets"
    else
        _t_bad "live: make client-build did not put the built client where the binary embeds it"
    fi
    # And the intermediate output must stay untracked, or the same bundle is
    # committed twice with diverging hashed names on every rebuild.
    if ( cd "$rt" && git check-ignore -q client/dist ); then
        _t_ok "live: the client's intermediate build output is gitignored"
    else
        _t_bad "live: client/dist is tracked; the bundle would be committed twice"
    fi
else
    printf '  %sSKIP%s live --react client proof (npm absent or no registry access)\n' "${C_NOTE:-}" "${C_RESET:-}"
fi

suite_summary
