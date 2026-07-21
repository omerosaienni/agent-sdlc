#!/usr/bin/env bash
# generator/go/base.sh - the Go base layer. Sourced by init-go-project.sh, never
# run. Writes the files every Go project gets: the module, the single-binary layout
# (cmd/<app>/main.go plus internal/), a trivial exported function with a co-located
# unit test so the setup gate's unit tier selects a non-zero count, and the embed.FS
# placeholder the client assets are served from. Expects DIR, NAME, APP, GO_VERSION
# and the lib helpers (step/note/write_file) in scope.
#
# Tier split: by BUILD TAG (unit = untagged, integration = //go:build integration),
# not by directory. Go co-locates _test.go files with the package they test, so a
# directory split would fight the language; the tag split is the idiomatic
# equivalent of the Python generator's tests/unit and tests/integration.
#
# go.mod is written here rather than by `go mod init`, so the generator needs no Go
# toolchain to scaffold (the same posture as the Python generator, which writes
# pyproject.toml without needing uv). Dependencies are resolved by `go mod tidy` in
# the setup gate, which is the step that proves the environment by execution.

go_base_layer() {
    step "module (go.mod)"

    # No require block: the layers' dependencies are resolved by `go mod tidy` in the
    # setup gate, so no version is pinned here to rot. The go directive names the
    # language version the code targets, not the toolchain that must build it.
    write_file "$DIR/go.mod" <<EOF
module ${NAME}

go ${GO_VERSION}
EOF

    step "entry point"

    write_file "$DIR/cmd/$APP/main.go" <<EOF
// Command ${APP} is the single binary this project ships. Everything the user
// needs is compiled in: no runtime dependency, no separate server, no interpreter.
package main

import (
	"fmt"

	"${NAME}/internal/app"
)

func main() {
	fmt.Println(app.Greeting())
}
EOF

    write_file "$DIR/internal/app/app.go" <<EOF
// Package app holds the program's own logic, kept out of main so it is importable
// and therefore testable. Grow this into the real application.
package app

// Greeting returns the startup message. Replace with the real bootstrap.
func Greeting() string {
	return "app starting"
}
EOF

    # Co-located and table-driven, the two Go testing conventions omero-go.md
    # enforces. Present from the first commit so the unit tier never selects zero,
    # which the setup gate treats as a hollow suite and hard-fails.
    write_file "$DIR/internal/app/app_test.go" <<EOF
package app

import "testing"

func TestGreeting(t *testing.T) {
	tests := []struct {
		name string
		want string
	}{
		{name: "startup message", want: "app starting"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Greeting(); got != tt.want {
				t.Errorf("Greeting() = %q, want %q", got, tt.want)
			}
		})
	}
}
EOF

    step "embedded client assets"

    # The single embed point for everything the binary serves. It lives here, above
    # the client, because a //go:embed pattern cannot contain "..": the embedding
    # package must sit at or above the files it embeds. The React layer builds the
    # Vite client to client/dist and syncs it into static/, so adding that layer
    # changes what is embedded, never where the Go code reads it from.
    #
    # static/index.html is committed rather than generated because //go:embed fails
    # at COMPILE time on an empty match. Without a committed placeholder a fresh
    # clone would not build until someone ran a Node build, which would put a Node
    # toolchain on the path of every Go-only gate.
    write_file "$DIR/internal/assets/assets.go" <<'EOF'
// Package assets holds the static client the binary serves, compiled in via
// embed.FS so the shipped artefact is one file with no runtime dependency.
package assets

import (
	"embed"
	"io/fs"
)

// all: is deliberate: a Vite build emits dotted entries (.vite/) that a bare
// embed pattern would silently skip, producing a client that is subtly incomplete.
//
//go:embed all:static
var embedded embed.FS

// FS returns the embedded client rooted at the directory the server should serve,
// so callers never encode the "static" prefix.
func FS() fs.FS {
	sub, err := fs.Sub(embedded, "static")
	if err != nil {
		// Unreachable: the directory is embedded at compile time, so a failure here
		// would mean the binary was built without its assets.
		panic("assets: embedded static directory missing: " + err.Error())
	}
	return sub
}
EOF

    write_file "$DIR/internal/assets/static/index.html" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${NAME}</title>
  </head>
  <body>
    <div id="root">app starting</div>
  </body>
</html>
EOF

    write_file "$DIR/internal/assets/assets_test.go" <<'EOF'
package assets

import (
	"io/fs"
	"strings"
	"testing"
)

func TestFSServesIndex(t *testing.T) {
	b, err := fs.ReadFile(FS(), "index.html")
	if err != nil {
		t.Fatalf("reading index.html from the embedded assets: %v", err)
	}
	if !strings.Contains(string(b), "<html") {
		t.Errorf("embedded index.html does not look like HTML: %q", string(b))
	}
}
EOF

    step "tooling configs"

    write_file "$DIR/.gitignore" <<'EOF'
# Go build output
/bin/
*.exe
*.test
*.out
# the SQLite database the binary creates next to itself
*.db
*.db-journal
*.db-wal
*.db-shm
# Node, only present with the client layer
client/node_modules/
# derived from config/services.yaml by `make config`
.env
# loop output stays local
.building/
graphify-out/
.claude/
EOF
}
