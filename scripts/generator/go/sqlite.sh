#!/usr/bin/env bash
# generator/go/sqlite.sh - the optional SQLite store layer (--sqlite). Sourced by
# init-go-project.sh. Writes the store package (pure-Go driver, migration, seed
# helper), its unit test and its integration-tagged test, and exports the fragments
# the orchestrator splices into the Makefile, the CI workflow and CLAUDE.md.
# Expects DIR, NAME and the lib helpers in scope.
#
# The driver is modernc.org/sqlite, a pure-Go translation of SQLite. This is load
# bearing, not a preference: the CGo driver (mattn/go-sqlite3) reintroduces a C
# toolchain, which breaks cross-compilation and the single-binary promise. The
# project rule omero-go.md carries the same constraint so the reviewer enforces it.

go_sqlite_layer() {
    step "sqlite store"

    write_file "$DIR/internal/store/store.go" <<'EOF'
// Package store owns the embedded SQLite database: opening it, migrating the
// schema, and the queries above it. The database is a single file the binary
// creates next to itself, so there is no server to install or run.
package store

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"

	// Pure-Go SQLite driver, registered as "sqlite". Never mattn/go-sqlite3: that
	// one needs CGo, which costs cross-compilation and the single-binary promise.
	_ "modernc.org/sqlite"
)

// DSN builds the connection string for a database file. Foreign keys are off by
// default in SQLite and must be enabled per connection, so the pragma travels with
// the DSN rather than being a call every caller has to remember.
func DSN(path string) string {
	return "file:" + url.PathEscape(path) + "?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)"
}

// Open opens (creating if absent) the database at path and verifies the connection
// is usable before returning it, so a caller never receives a handle that fails on
// first use.
func Open(ctx context.Context, path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", DSN(path))
	if err != nil {
		return nil, fmt.Errorf("opening sqlite database %s: %w", path, err)
	}
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("connecting to sqlite database %s: %w", path, err)
	}
	return db, nil
}

// schema is the full schema, applied on every start. Each statement is written to
// be safe to re-run, so migration is idempotent and needs no version table until
// the first destructive change.
const schema = `
CREATE TABLE IF NOT EXISTS item (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    created_at TEXT NOT NULL
);
`

// Migrate applies the schema. Safe to call on every start.
func Migrate(ctx context.Context, db *sql.DB) error {
	if _, err := db.ExecContext(ctx, schema); err != nil {
		return fmt.Errorf("migrating schema: %w", err)
	}
	return nil
}

// TableNames lists the user tables present, so a caller (or a test) can assert the
// migration actually landed rather than trusting that it returned no error.
func TableNames(ctx context.Context, db *sql.DB) ([]string, error) {
	rows, err := db.QueryContext(ctx,
		`SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name`)
	if err != nil {
		return nil, fmt.Errorf("listing tables: %w", err)
	}
	defer rows.Close()

	var names []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, fmt.Errorf("scanning table name: %w", err)
		}
		names = append(names, name)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("reading table names: %w", err)
	}
	return names, nil
}
EOF

    write_file "$DIR/internal/store/seed.go" <<'EOF'
package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// Seed inserts sample rows so a fresh database has something to look at during
// development. Separate from Migrate: schema is required, sample data never is.
func Seed(ctx context.Context, db *sql.DB, names []string) error {
	stmt, err := db.PrepareContext(ctx, `INSERT INTO item (name, created_at) VALUES (?, ?)`)
	if err != nil {
		return fmt.Errorf("preparing seed insert: %w", err)
	}
	defer stmt.Close()

	now := time.Now().UTC().Format(time.RFC3339)
	for _, name := range names {
		if _, err := stmt.ExecContext(ctx, name, now); err != nil {
			return fmt.Errorf("seeding item %q: %w", name, err)
		}
	}
	return nil
}
EOF

    # Unit tier: the pure helpers, run-anywhere, no file system and no driver work.
    write_file "$DIR/internal/store/store_test.go" <<'EOF'
package store

import (
	"strings"
	"testing"
)

func TestDSN(t *testing.T) {
	tests := []struct {
		name string
		path string
		want string
	}{
		{name: "enables foreign keys", path: "app.db", want: "_pragma=foreign_keys(1)"},
		{name: "sets a busy timeout", path: "app.db", want: "_pragma=busy_timeout(5000)"},
		{name: "carries the file path", path: "app.db", want: "file:app.db"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := DSN(tt.path); !strings.Contains(got, tt.want) {
				t.Errorf("DSN(%q) = %q, want it to contain %q", tt.path, got, tt.want)
			}
		})
	}
}
EOF

    # Integration tier: behind the build tag, so `go test ./...` (the unit tier)
    # never selects it. In process against a temp database file: no server, no
    # container, nothing to bring up, which is why this stack declares no external
    # endpoint and the setup gate never sits in a BLOCKED state for it.
    write_file "$DIR/internal/store/store_integration_test.go" <<'EOF'
//go:build integration

package store

import (
	"context"
	"path/filepath"
	"testing"
)

func TestMigrateCreatesSchema(t *testing.T) {
	ctx := context.Background()
	// t.TempDir is removed when the test ends, so the tier leaves nothing behind.
	db, err := Open(ctx, filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("opening a temp database: %v", err)
	}
	defer db.Close()

	if err := Migrate(ctx, db); err != nil {
		t.Fatalf("migrating: %v", err)
	}

	names, err := TableNames(ctx, db)
	if err != nil {
		t.Fatalf("listing tables: %v", err)
	}
	want := "item"
	found := false
	for _, n := range names {
		if n == want {
			found = true
		}
	}
	if !found {
		t.Errorf("after migration tables are %v, want them to include %q", names, want)
	}
}

func TestMigrateIsIdempotent(t *testing.T) {
	ctx := context.Background()
	db, err := Open(ctx, filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("opening a temp database: %v", err)
	}
	defer db.Close()

	for i := range 2 {
		if err := Migrate(ctx, db); err != nil {
			t.Fatalf("migrate run %d: %v", i+1, err)
		}
	}
}
EOF

    # ---- fragments the orchestrator splices into the shared files ----

    SQLITE_MAKE_HELP='	@echo ""
	@echo " db"
	@echo "  db-test-integration  Run the integration tier (temp SQLite, in process)"'

    SQLITE_MAKE_TARGET='
# --- db ------------------------------------------------------------------
.PHONY: db-test-integration

# No bring-up target: the integration tier opens a temp database file in process,
# so there is nothing to start and nothing to tear down.
db-test-integration: ## Run the integration tier (temp SQLite, in process)
	go test -tags=integration ./...'

    # CLAUDE.md: the setup gate greps for this heading, and the answer for this
    # stack is that there is no external endpoint at all.
    SQLITE_CLAUDE_MD='

## Integration endpoints

None. The integration tier is in process: it opens a temporary SQLite file that
`t.TempDir()` removes when the test ends. There is no server to bring up, so the
build loop never raises an environment block for this project. Run the tier with
`make db-test-integration`.'

    SQLITE_CI_JOB='

  integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
      - run: go test -tags=integration ./...'
}
