# Stack guide — Cobra + Go conventions

Step 5 of the workflow. All conventions here assume the skeleton produced by
`scripts/scaffold_cli.sh`. Deviate only when the API demands it, and document
the deviation.

## Project layout

```
<name>/
├── main.go                         # entry; calls cmd.Execute()
├── go.mod
├── internal/
│   ├── version/version.go          # Version, Commit, Date vars (ldflags)
│   ├── config/config.go            # resolution: flag > env > default
│   ├── client/client.go            # retrying, rate-aware HTTP client
│   └── output/output.go            # JSON emitters + exit-code helpers
├── cmd/
│   ├── root.go                     # root command, persistent flags, initConfig
│   ├── version.go                  # version command
│   ├── completion.go               # cobra completion (bash/zsh/fish/powershell)
│   └── <resource>.go               # one file per resource command
├── Makefile
├── LICENSE
└── README.md
```

Only `cmd/` should grow as commands are added. Output rendering lives only in
`internal/output`; network only in `internal/client`.

## Cobra usage patterns

- **Persistent flags on root** (inherited everywhere you need them):
  `--api-url` (env `X_API_URL`), `--api-key` (env `X_API_KEY`), `--timeout`.
  Keep the flag set small; resource-specific flags go on the resource commands.
- **Kebab-case long flags** (`--per-page`), short single letters only for the
  most common (`-o` for output is acceptable; keep the set minimal).
- **stderr contract support**:
  ```go
  rootCmd.SilenceUsage = true
  rootCmd.SilenceErrors = true
  rootCmd.SetFlagErrorFunc(...) // print usage error to stderr, exit 2
  ```
  You print errors yourself via `internal/output` so error shape matches
  `references/output-contract.md`.
- **One constructor per command**: `func NewProjectsCmd() *cobra.Command`.
  Register subcommands in its `AddCommand` list. Keep `RunE` thin: parse flags,
  call client, pass the typed result to the output writer; never print from the
  client layer.
- **Config initialized once** via `cobra.OnInitialize(initConfig)` reading env
  vars (and an optional config file if the API has a lot of defaults).

## Config resolution order

Explicit flag → environment variable → config-file value (optional) → default.
Expose the env var name in each flag's help text: `--api-key (env: EXAMPLE_API_KEY)`.
Implement once in `internal/config`, not per command.

## HTTP client

- Wrap `http.Client` with a sane `Timeout` (default 30s, overridable by
  `--timeout`), a `User-Agent` of `<name>/<version>`.
- **Retry on**: `429` (honor `Retry-After` if present, else back off),
  transient 5xx (`502/503/504`), timeouts, connection resets. Exponential
  backoff with jitter (base ~250ms, max ~5s). Only retry idempotent methods
  (GET, PUT, DELETE, HEAD) automatically; retry POST/PATCH only for endpoints
  the API documents as idempotent or when explicitly requested.
- **Convert HTTP-level failures into typed errors** the output layer can map to
  the contract's `code`/`http_status` fields (`rate_limited`, `api_error`,
  `auth_failed`, `network`...).

## Auth

- API key/bearer comes from config only (env/flag). **Never** embed, log, or
  echo the value. Redact it from any debug transport before output.
- If the API wants a specific header name, set it in `internal/client`.
- OAuth: if the user already has a token, treat it as a bearer token via the
  same config path. Do not implement a full OAuth flow unless the user asks.

## Versioning and discovery

- `internal/version` variables are stamped at build time:
  `-ldflags "-X <module>/internal/version.Version=v0.1.0 -X .../Commit=<sha> ..."`.
  Makefile target `version`/`build` does this; never hardcode versions in code
  beyond the default `0.1.0`.
- Ship `version` and `completion` commands; root supports `--version`.
- `--help` for every command must include: purpose, example usage, the exact
  `--json` stdout shape (with a sample), env vars honored, and exit codes.

## Testing

- Unit-test the client against `httptest.Server`: happy path, 429/retry, error
  mapping. Assert URL, method, headers, body.
- Command-level tests: invoke `cmd.Execute()` on the command or use
  `cobra`'s args directly against a fake server; assert `--json` stdout is
  valid JSON and matches a golden string (this pins the output contract).
- Run `go vet ./...` and `go test ./...` locally before shipping.

## Build and packaging

Makefile targets (already scaffolded) to keep consistent:

- `build` → `bin/<name>` — `CGO_ENABLED=0 go build -trimpath -ldflags "-s -w <version stamps>"`
- `test`, `vet` — `go test ./...`, `go vet ./...`
- `cross` — build matrix for linux/darwin/windows × amd64/arm64 into `dist/`
- `install` — `go install` with the same ldflags
- `deploy`/release notes are out of scope unless the user asks; a single static
  binary plus `make cross` is the professional floor for distribution.