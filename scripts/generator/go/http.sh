#!/usr/bin/env bash
# generator/go/http.sh - the optional net/http server layer (--http). Sourced by
# init-go-project.sh. Writes the server package and its httptest unit tests, and
# REPLACES the base entry point with one that starts the server, the same way the
# TypeScript generator's express layer replaces its base stub. Exports the Makefile,
# CI and services.yaml fragments the orchestrator splices in. Expects DIR, NAME, APP
# and the lib helpers in scope.
#
# The server is the standard library only: net/http's ServeMux has had method and
# path-pattern routing since Go 1.22, so a router dependency buys nothing here and
# would cost the zero-dependency posture.

go_http_layer() {
    step "http server"

    write_file "$DIR/internal/httpapi/server.go" <<EOF
// Package httpapi is the HTTP surface: routing, handlers and the server's
// lifecycle. It serves the embedded client at / so the binary is the whole
// application, with no separate web server to run.
package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"path"
	"strings"
	"time"

	"${NAME}/internal/assets"
)

// Health is the health payload. A struct rather than a map so the response shape
// is a compile-time contract the client can be generated from.
type Health struct {
	OK bool \`json:"ok"\`
}

// Handler builds the routing tree. Returned as an http.Handler rather than
// registered on the package-level DefaultServeMux, so tests can drive it through
// httptest without any global state to reset between cases.
func Handler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(Health{OK: true}); err != nil {
			http.Error(w, "encoding health response", http.StatusInternalServerError)
		}
	})

	// Registered so a WRONG METHOD on an API route is a 405 rather than the client.
	// Go's mux gives the method-qualified pattern precedence, so GET still reaches
	// the handler above; without this the catch-all below matches first and every
	// non-GET request is answered with the application shell and a 200.
	mux.Handle("/healthz", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}))

	// The API area is claimed explicitly so an unmatched path under it 404s instead
	// of falling through to the client fallback below.
	mux.Handle("/"+apiPrefix, http.NotFoundHandler())

	// Everything not matched above is the embedded client.
	mux.Handle("/", clientHandler(assets.FS()))

	return mux
}

// clientHandler serves the embedded client as a single-page application. A bare
// file server is not enough: a client that routes in the browser asks the server
// for paths that have no file behind them, and a 404 there breaks every deep link
// on a refresh.
//
// The fallback is deliberately NOT unconditional. A request naming a concrete file
// still 404s when that file is absent, because answering it with the index turns a
// missing or misnamed bundle into a silent success: the browser is handed HTML
// where it expected JavaScript, and the failure shows up as an unexplained blank
// page instead of a 404 in the network log.
func clientHandler(client fs.FS) http.Handler {
	files := http.FileServerFS(client)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if isClientRoute(client, name) {
			serveIndex(w, client)
			return
		}
		files.ServeHTTP(w, r)
	})
}

// Prefixes the client fallback must never swallow. assetPrefix is where the build
// emits its hashed bundles and apiPrefix is where the server's own routes live:
// both name concrete things, so a miss under either is a real 404 rather than a
// route the client will handle.
const (
	assetPrefix = "assets"
	apiPrefix   = "api"
)

// isClientRoute reports whether a path should fall back to the application shell.
func isClientRoute(client fs.FS, name string) bool {
	if name == "" || name == "." {
		return false
	}
	if underPrefix(name, assetPrefix) || underPrefix(name, apiPrefix) {
		return false
	}
	_, err := fs.Stat(client, name)
	return err != nil
}

// underPrefix matches the prefix itself as well as anything beneath it. path.Clean
// strips the trailing slash, so a bare "/api" arrives as "api" and a check for
// "api/" alone would let it through to the client.
func underPrefix(name, prefix string) bool {
	return name == prefix || strings.HasPrefix(name, prefix+"/")
}

func serveIndex(w http.ResponseWriter, client fs.FS) {
	b, err := fs.ReadFile(client, "index.html")
	if err != nil {
		// Unreachable in a correctly built binary: index.html is embedded at compile
		// time. Reported rather than panicked so a broken build degrades to a 500.
		http.Error(w, "client not built into this binary", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	// A write failure here means the client hung up; the response is already
	// committed, so there is nothing left to report to anyone.
	_, _ = w.Write(b)
}

// ListenAndServe starts the server on host:port and blocks until the server fails
// or ctx is cancelled. Address parts are taken as arguments rather than read from
// the environment here, so the caller (main) stays the single place configuration
// is resolved.
func ListenAndServe(ctx context.Context, host string, port int) error {
	addr := fmt.Sprintf("%s:%d", host, port)
	srv := &http.Server{
		Addr:    addr,
		Handler: Handler(),
		// Set because the zero value is NO timeout at all: one stalled client would
		// otherwise hold a connection open for the life of the process.
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	// Served in the background so this can wait on whichever comes first: the server
	// failing, or the context being cancelled by a signal.
	failed := make(chan error, 1)
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			failed <- fmt.Errorf("http server on %s: %w", addr, err)
			return
		}
		failed <- nil
	}()

	select {
	case err := <-failed:
		return err
	case <-ctx.Done():
		// In-flight requests get a bounded chance to finish. WithoutCancel is load
		// bearing: ctx is already cancelled, so a plain WithTimeout derived from it
		// would expire immediately and Shutdown would drop every connection.
		shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			return fmt.Errorf("shutting down the http server on %s: %w", addr, err)
		}
		return nil
	}
}
EOF

    write_file "$DIR/internal/httpapi/server_test.go" <<'EOF'
package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// The unit tier drives the handler through httptest: in process, no port bound and
// nothing to bring up, so these stay in the run-anywhere tier.
func TestRoutes(t *testing.T) {
	tests := []struct {
		name        string
		path        string
		wantStatus  int
		wantBodyHas string
	}{
		{name: "health reports ok", path: "/healthz", wantStatus: http.StatusOK, wantBodyHas: `"ok":true`},
		{name: "root serves the embedded client", path: "/", wantStatus: http.StatusOK, wantBodyHas: "<html"},
		// The single-page fallback: a client route has no file behind it, and
		// answering 404 there would break every deep link on a refresh.
		{name: "an unknown client route serves the client", path: "/some/route", wantStatus: http.StatusOK, wantBodyHas: "<html"},
		// Not unconditional: a missing concrete file must still 404, or a misnamed
		// bundle is served as HTML and fails as a blank page instead of a 404.
		{name: "a missing asset is a 404", path: "/assets/missing.js", wantStatus: http.StatusNotFound},
		// The API area must not be answered with the shell: a caller expecting JSON
		// would parse HTML and report something unrelated to the real fault.
		{name: "an unmatched API path is a 404", path: "/api/nope", wantStatus: http.StatusNotFound},
		{name: "the bare API prefix is a 404", path: "/api", wantStatus: http.StatusNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, tt.path, nil))

			if rec.Code != tt.wantStatus {
				t.Errorf("GET %s status = %d, want %d", tt.path, rec.Code, tt.wantStatus)
			}
			if tt.wantBodyHas != "" && !strings.Contains(rec.Body.String(), tt.wantBodyHas) {
				t.Errorf("GET %s body = %q, want it to contain %q", tt.path, rec.Body.String(), tt.wantBodyHas)
			}
		})
	}
}

// A wrong method on a real route is a 405, not the client. Without an explicit
// registration the catch-all matches first and answers 200 with HTML.
func TestWrongMethodOnHealthIsNotTheClient(t *testing.T) {
	rec := httptest.NewRecorder()
	Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/healthz", nil))

	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("POST /healthz status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
	if strings.Contains(rec.Body.String(), "<html") {
		t.Error("POST /healthz was answered with the client shell, want a method error")
	}
}

func TestHealthIsValidJSON(t *testing.T) {
	rec := httptest.NewRecorder()
	Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	var got Health
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decoding health response %q: %v", rec.Body.String(), err)
	}
	if !got.OK {
		t.Errorf("health payload OK = false, want true")
	}
}
EOF

    # The server layer owns the entry point: the base stub prints and exits, which is
    # not what a project with a server does. Rewritten, not appended to, so there is
    # one main and no dead branch.
    step "entry point (server)"

    write_file "$DIR/cmd/$APP/main.go" <<EOF
// Command ${APP} is the single binary this project ships. It serves the embedded
// client and the API on one local port; everything the user needs is compiled in.
package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"strconv"
	"syscall"

	"${NAME}/internal/httpapi"
)

// Defaults match config/services.yaml, so a binary run from a fresh checkout works
// with no .env present and \`make config\` only has to be run once the YAML changes.
const (
	defaultHost = "127.0.0.1"
	defaultPort = 8080
)

func main() {
	// main only reports; run owns the work, so its deferred cleanup actually runs.
	// log.Fatal calls os.Exit, which skips every deferred call in the frame, so any
	// close deferred in main would be a promise the code never kept.
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	// Cancelled on an interrupt or a termination signal, which is the only way a
	// long-running binary is ever stopped. Without it the process dies where it
	// stands, dropping in-flight requests and skipping every deferred close.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Default signal handling is restored as soon as the FIRST signal lands, so a
	// second one kills the process immediately. Without this the handler stays
	// installed for the whole shutdown grace period and an operator watching a hung
	// drain cannot interrupt it.
	go func() {
		<-ctx.Done()
		stop()
	}()

	return httpapi.ListenAndServe(ctx, host(), port())
}

// host and port read the .env values \`make config\` generates from
// config/services.yaml, falling back to the defaults above so the binary never
// depends on a file the user has to produce first.
func host() string {
	if v := os.Getenv("SERVER_HOST"); v != "" {
		return v
	}
	return defaultHost
}

func port() int {
	if v := os.Getenv("SERVER_PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
		log.Printf("SERVER_PORT=%q is not a number; using %d", v, defaultPort)
	}
	return defaultPort
}
EOF

    # ---- fragments the orchestrator splices into the shared files ----

    HTTP_YAML="# the Go binary's HTTP server (make server-start)
server:
  host: 127.0.0.1
  port: 8080
"

    HTTP_MAKE_HELP='	@echo ""
	@echo " server"
	@echo "  server-start  Build and run the binary (serves the embedded client)"'

    # .env is sourced by this target rather than read by the binary. The binary takes
    # its configuration from the ENVIRONMENT, which keeps it dependency free and lets
    # a process manager configure it the usual way; this is what turns `make config`
    # output into that environment for a local run. Without it, config/services.yaml
    # reached the Vite dev server and nothing else, so editing a port silently did
    # nothing to the binary.
    HTTP_MAKE_TARGET="
# --- server --------------------------------------------------------------
.PHONY: server-start

server-start: build ## Build and run the binary (serves the embedded client)
	set -a; [ -f .env ] && . ./.env; set +a; ./bin/${APP}"
}
