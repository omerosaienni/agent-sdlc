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
	"encoding/json"
	"fmt"
	"net/http"

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

	// Everything not matched above is the embedded client, so a page refresh on any
	// path lands on the app rather than a 404 from the API.
	mux.Handle("/", http.FileServerFS(assets.FS()))

	return mux
}

// ListenAndServe starts the server on host:port and blocks. Address parts are taken
// as arguments rather than read from the environment here, so the caller (main)
// stays the single place configuration is resolved.
func ListenAndServe(host string, port int) error {
	addr := fmt.Sprintf("%s:%d", host, port)
	srv := &http.Server{Addr: addr, Handler: Handler()}
	if err := srv.ListenAndServe(); err != nil {
		return fmt.Errorf("http server on %s: %w", addr, err)
	}
	return nil
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
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, tt.path, nil))

			if rec.Code != tt.wantStatus {
				t.Errorf("GET %s status = %d, want %d", tt.path, rec.Code, tt.wantStatus)
			}
			if !strings.Contains(rec.Body.String(), tt.wantBodyHas) {
				t.Errorf("GET %s body = %q, want it to contain %q", tt.path, rec.Body.String(), tt.wantBodyHas)
			}
		})
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
	"log"
	"os"
	"strconv"

	"${NAME}/internal/httpapi"
)

// Defaults match config/services.yaml, so a binary run from a fresh checkout works
// with no .env present and \`make config\` only has to be run once the YAML changes.
const (
	defaultHost = "127.0.0.1"
	defaultPort = 8080
)

func main() {
	if err := httpapi.ListenAndServe(host(), port()); err != nil {
		log.Fatal(err)
	}
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

    HTTP_MAKE_TARGET="
# --- server --------------------------------------------------------------
.PHONY: server-start

server-start: build ## Build and run the binary (serves the embedded client)
	./bin/${APP}"
}
