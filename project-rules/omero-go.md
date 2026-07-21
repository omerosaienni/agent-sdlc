---
paths:
  - "**/*.go"
---

# Go

Conventions for Go in this project. Terse; loads only for `.go` files.

## Formatting and vet
- `gofmt` clean, always. Imports grouped standard library, third party, local, in
  that order, which is what `goimports` produces. Never hand-align an import block.
- `go vet ./...` clean. A vet finding is a defect, not a style note.

## Errors
- Wrap with `%w` and context naming the operation: `fmt.Errorf("opening %s: %w",
  path, err)`. A caller that loses the chain loses `errors.Is`/`errors.As`.
- Error strings are lowercase and unpunctuated: they are fragments a caller
  concatenates, not sentences.
- Handle every error at the point it is returned. `_ = f()` needs a comment saying
  why the error genuinely does not matter.
- No panics in library code. `panic` is only for a state the compiler guarantees is
  unreachable, and then it says so in a comment.

## Signatures
- `context.Context` is the first parameter, named `ctx`, on anything that does
  I/O, blocks, or calls something that does. Never stored in a struct.
- Interfaces are defined at the CONSUMER, not exported alongside the
  implementation. A package that returns a concrete type and a package that
  accepts a narrow interface compose; the reverse does not.
- Accept interfaces, return structs.

## Tests
- Co-located: `foo_test.go` beside `foo.go`, in the same package unless the test
  genuinely needs the external view (then `package foo_test`).
- Table-driven, with a named `tests` slice and `t.Run(tt.name, ...)`, so a failure
  names the case rather than a line number.
- Failure messages state got and want in that order, with the input:
  `t.Errorf("DSN(%q) = %q, want %q", path, got, want)`.
- `t.TempDir()` and `t.Cleanup()` over manual teardown: they run on failure too.
- Tier split is by BUILD TAG, not directory. The unit tier is every untagged test;
  an integration test carries `//go:build integration` on its first line. A unit
  test never needs a service, a port or a network.

## Concurrency
- The goroutine that starts a thing owns stopping it. Every goroutine has a stated
  exit condition; a goroutine with no way to end is a leak.
- Channels for handing off ownership, mutexes for guarding state. Do not reach for
  a channel where a `sync.Mutex` is the smaller answer.

## This project's hard constraints
These are load bearing, not preferences. They exist so the shipped artefact stays a
single binary with no runtime dependency and cross-compiles without a C toolchain.

- **One binary.** `cmd/<app>/` holds only `main.go`; everything real lives under
  `internal/`. No second executable, no sidecar process, no shelling out to a tool
  the user must install.
- **No CGo.** Every dependency must be pure Go. `CGO_ENABLED=0` builds must work.
- **SQLite is `modernc.org/sqlite`.** NEVER `mattn/go-sqlite3`: it is CGo, which
  breaks both constraints above.
- **The client is embedded** with `embed.FS`, never read from disk at run time.
- **LLM access sits behind a `Provider` interface** defined by the consumer, with a
  stub implementation for tests. No test calls a real API: not deterministic, not
  hermetic, and it needs a secret.

## Dependencies
- Prefer the standard library. `net/http`'s `ServeMux` routes by method and path
  pattern, so a router dependency needs a reason beyond preference.
- Every new module in `go.mod` is a decision: it must be pure Go, maintained, and
  worth its supply-chain surface.
