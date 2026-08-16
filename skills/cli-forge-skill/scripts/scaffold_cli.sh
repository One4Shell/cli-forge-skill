#!/usr/bin/env bash
# scaffold_cli.sh -- generate a deterministic professional Go+Cobra CLI skeleton.
#
# Produces a compiling project with stable JSON output helpers (the
# cli-forge-skill output contract), config-from-env resolution, a retrying HTTP
# client, version/completion commands, a Makefile, LICENSE and README, so the
# agent only has to implement the API's real commands -- never re-derive
# boilerplate from prose.
#
# Usage:
#   scaffold_cli.sh --module <module-path> --name <cli-name> \
#       [--description "<one-line purpose>"] [--out <dir>]
set -euo pipefail

MODULE=""
NAME=""
DESC="A command-line client for an API."
OUT=""
YEAR="$(date +%Y)"

usage() {
  cat <<'EOF'
Usage: scaffold_cli.sh --module <module-path> --name <cli-name> [options]

Options:
  --module <path>        Go module path, e.g. github.com/acme/myapi-cli (required)
  --name <name>          Binary/command name, e.g. myapi (required)
  --description "<text>" One-line purpose for the root command help
  --out <dir>            Directory to create the project in (default: ./<name>)
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --module) MODULE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --description) DESC="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$MODULE" || -z "$NAME" ]]; then
  echo "Error: --module and --name are required" >&2
  usage
  exit 1
fi

OUT="${OUT:-$NAME}"
if [[ -e "$OUT" ]]; then
  echo "Error: $OUT already exists" >&2
  exit 1
fi

ENVP="$(printf '%s' "$NAME" | tr '[:lower:]-' '[:upper:]_')"
mkdir -p "$OUT/cmd" "$OUT/internal/version" "$OUT/internal/config" \
  "$OUT/internal/client" "$OUT/internal/output"

# --- File writer with token substitution ---------------------------------
# Tokens (__MODULE__, __NAME__, __DESC__, __ENVP__, __YEAR__, __BIN__) are
# replaced by sed below; heredocs stay quoted so nothing interpolates early.
write_file() { cat > "$1"; }

write_file "$OUT/go.mod" <<EOF
module __MODULE__

go 1.21
EOF

write_file "$OUT/main.go" <<'EOF'
package main

import "MODULETOK/cmd"

func main() {
	cmd.Execute()
}
EOF

write_file "$OUT/internal/version/version.go" <<'EOF'
package version

// Build information. The Makefile stamps these via -ldflags; the scaffold
// defaults are the un-stamped fallback.
var (
	Version = "0.1.0"
	Commit  = "none"
	Date    = "unknown"
)
EOF

write_file "$OUT/internal/config/config.go" <<'EOF'
package config

import (
	"os"
	"time"
)

// Config holds the resolved runtime settings. Resolution order is
// flag > environment variable > default; cmd/ applies flag values after
// calling Defaults().
type Config struct {
	APIURL  string
	APIKey  string
	Timeout time.Duration
}

// Env returns env[name] if set and non-empty, otherwise def.
func Env(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

// Defaults returns the baseline configuration read from environment variables
// prefixed with the CLI name (e.g. APP_CLI_API_URL) plus sane defaults.
func Defaults(envPrefix string) Config {
	return Config{
		APIURL:  Env(envPrefix+"_API_URL", "https://api.example.com"),
		APIKey:  Env(envPrefix+"_API_KEY", ""),
		Timeout: 30 * time.Second,
	}
}
EOF

write_file "$OUT/internal/output/output.go" <<'EOF'
package output

import (
	"encoding/json"
	"fmt"
	"os"
)

// Pagination carries cursor state for collection envelopes.
type Pagination struct {
	HasMore    bool   `json:"has_more"`
	NextCursor string `json:"next_cursor,omitempty"`
}

// Envelope wraps a collection result so machine consumers can rely on a
// stable, self-describing shape (see the cli-forge-skill output contract).
type Envelope struct {
	Items         any         `json:"items"`
	SchemaVersion int         `json:"schema_version,omitempty"`
	Pagination    *Pagination `json:"pagination,omitempty"`
}

// Err is the structured error payload emitted on stderr on failure.
type Err struct {
	Code       string `json:"code"`
	Message    string `json:"message"`
	HTTPStatus int    `json:"http_status,omitempty"`
	Details    any    `json:"details,omitempty"`
}

type failure struct {
	OK    bool `json:"ok"`
	Error Err  `json:"error"`
}

// WriteJSON emits v to stdout as exactly one JSON document followed by a
// newline. It is the only way data leaves a command.
func WriteJSON(v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(os.Stdout, string(b))
	return err
}

// Fail writes the machine-readable failure to stderr (used in --json mode)
// and exits with status 1. stdout is left untouched.
func Fail(err Err) {
	if err.Code == "" {
		err.Code = "internal"
	}
	_ = json.NewEncoder(os.Stderr).Encode(failure{OK: false, Error: err})
	os.Exit(1)
}

// FailText exits 1 after printing a human-readable error line to stderr.
func FailText(code, message string) {
	if code == "" {
		code = "internal"
	}
	fmt.Fprintf(os.Stderr, "error[%s]: %s\n", code, message)
	os.Exit(1)
}
EOF

write_file "$OUT/internal/client/client.go" <<'EOF'
package client

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Config configures the HTTP client.
type Config struct {
	APIURL     string
	APIKey     string
	Timeout    time.Duration
	UserAgent  string
	MaxRetries int
}

// Client is a small rate-aware, retrying HTTP client for an API.
type Client struct {
	cfg    Config
	client *http.Client
}

// New returns a Client with sane defaults applied. It performs no network I/O.
func New(cfg Config) *Client {
	if cfg.Timeout <= 0 {
		cfg.Timeout = 30 * time.Second
	}
	if cfg.MaxRetries <= 0 {
		cfg.MaxRetries = 3
	}
	return &Client{cfg: cfg, client: &http.Client{Timeout: cfg.Timeout}}
}

// Do performs one request. Idempotent methods retry on 429/5xx; the JSON
// response is unmarshaled into out when out is non-nil. Body is JSON-encoded
// when non-nil. Returns the HTTP status and the last error.
func (c *Client) Do(method, path string, query map[string]string, body, out any) (int, error) {
	u := c.cfg.APIURL + path
	if parsed, err := url.Parse(u); err == nil {
		q := parsed.Query()
		for k, v := range query {
			q.Set(k, v)
		}
		parsed.RawQuery = q.Encode()
		u = parsed.String()
	}

	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return 0, err
		}
		reader = bytes.NewReader(b)
	}

	req, err := http.NewRequest(method, u, reader)
	if err != nil {
		return 0, err
	}
	if c.cfg.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.cfg.APIKey)
	}
	req.Header.Set("Accept", "application/json")
	if c.cfg.UserAgent != "" {
		req.Header.Set("User-Agent", c.cfg.UserAgent)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	idempotent := method == http.MethodGet || method == http.MethodPut ||
		method == http.MethodDelete || method == http.MethodHead

	for attempt := 1; ; attempt++ {
		resp, err := c.client.Do(req)
		if err != nil {
			return 0, fmt.Errorf("network error: %w", err)
		}
		respBody, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			return resp.StatusCode, readErr
		}

		retryable := resp.StatusCode == http.StatusTooManyRequests ||
			(resp.StatusCode >= 500 && resp.StatusCode < 600)
		if retryable && idempotent && attempt < c.cfg.MaxRetries {
			wait(c.respAfter(resp.Header), attempt)
			continue
		}

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return resp.StatusCode, fmt.Errorf("error %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
		}
		if out != nil && len(respBody) > 0 {
			if err := json.Unmarshal(respBody, out); err != nil {
				return resp.StatusCode, fmt.Errorf("decode response: %w", err)
			}
		}
		return resp.StatusCode, nil
	}
}

func (c *Client) respAfter(h http.Header) time.Duration {
	raw := h.Get("Retry-After")
	if raw == "" {
		return 0
	}
	if secs, err := strconv.Atoi(raw); err == nil {
		return time.Duration(secs) * time.Second
	}
	if t, err := http.ParseTime(raw); err == nil {
		return time.Until(t)
	}
	return 0
}

func wait(after time.Duration, attempt int) {
	if after > 0 {
		time.Sleep(after)
		return
	}
	d := time.Duration(attempt) * 250 * time.Millisecond
	if d > 5*time.Second {
		d = 5 * time.Second
	}
	time.Sleep(d)
}
EOF

write_file "$OUT/cmd/root.go" <<'EOF'
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"MODULETOK/internal/config"
	"MODULETOK/internal/version"
)

var (
	cfg     config.Config
	apiURL  string
	apiKey  string
	jsonOut bool
)

var rootCmd = &cobra.Command{
	Use:           "BINTOK",
	Short:         "DESCTOK",
	Long:          "DESCTOK\n\nStable JSON output is available on every data command with --json.",
	SilenceUsage:  true,
	SilenceErrors: true,
	Version:       version.Version,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

func init() {
	rootCmd.PersistentFlags().StringVar(&apiURL, "api-url", "", "API base URL (env: ENVPTOK_API_URL)")
	rootCmd.PersistentFlags().StringVar(&apiKey, "api-key", "", "API key (env: ENVPTOK_API_KEY)")
	rootCmd.PersistentFlags().BoolVar(&jsonOut, "json", false, "emit machine-readable JSON on stdout")
}

// initConfig runs once before any command, applying flag > env > default.
func initConfig() {
	cfg = config.Defaults("ENVPTOK")
	if apiURL != "" {
		cfg.APIURL = apiURL
	}
	if apiKey != "" {
		cfg.APIKey = apiKey
	}
}

// Execute runs the root command. Errors that reach this far are usage errors
// (exit 2); runtime/API failures exit 1 via internal/output.
func Execute() {
	cobra.OnInitialize(initConfig)
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}
EOF

write_file "$OUT/cmd/version.go" <<'EOF'
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"MODULETOK/internal/version"
)

func init() {
	rootCmd.AddCommand(newVersionCmd())
}

func newVersionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print the CLI version",
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			_, err := fmt.Fprintf(os.Stdout, "%s version %s (commit %s, built %s)\n",
				rootCmd.Name(), version.Version, version.Commit, version.Date)
			return err
		},
	}
}
EOF

write_file "$OUT/.gitignore" <<'EOF'
/bin/
/dist/
*.exe
__debug_bin*
EOF

write_file "$OUT/LICENSE" <<EOF
MIT License

Copyright (c) __YEAR__ __NAME__ contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

write_file "$OUT/README.md" <<EOF
# __NAME__

__DESC__

## Install

Build from source:

\`\`\`sh
make build
./bin/__NAME__ --help
\`\`\`

## Configuration

| Env var | Flag | Default |
|---------|------|---------|
| __ENVP___API_URL | \`--api-url\` | https://api.example.com |
| __ENVP___API_KEY | \`--api-key\` | (none) |

Resolution order: flag > environment variable > default.

## Output contract

Every data command supports \`--json\`. JSON is emitted on stdout only; errors
are structured on stderr; exit codes are 0 success, 1 runtime failure,
2 usage error. See \`--help\` per command for its exact JSON shape.

## License

MIT
EOF

write_file "$OUT/Makefile" <<EOF
BIN ?= __NAME__
MODULE ?= __MODULE__
VERSION ?= v0.1.0
COMMIT ?= \$(shell git rev-parse --short HEAD 2>/dev/null || echo none)
DATE ?= \$(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS := -s -w -X '\$(MODULE)/internal/version.Version=\$(VERSION)' -X '\$(MODULE)/internal/version.Commit=\$(COMMIT)' -X '\$(MODULE)/internal/version.Date=\$(DATE)'
PLATFORMS ?= linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64

.PHONY: build test vet cross install clean

build:
	CGO_ENABLED=0 go build -trimpath -ldflags "\$(LDFLAGS)" -o bin/\$(BIN) .

test:
	go test ./...

vet:
	go vet ./...

cross:
	@mkdir -p dist
	@for p in \$(PLATFORMS); do \\
		os=$$$${p%/*}; arch=$$$${p#*/}; \\
		out=dist/\$(BIN)-\$\$\{os\}-\$\$\{arch\}; \\
		if [ "\$\$\{os\}" = "windows" ]; then out=\$\$\{out\}.exe; fi; \\
		GOOS=\$\$\{os\} GOARCH=\$\$\{arch\} CGO_ENABLED=0 go build -trimpath -ldflags "\$(LDFLAGS)" -o \$\$\{out\} .; \\
		echo "built \$\$\{out\}"; \\
	done

install:
	go install -ldflags "\$(LDFLAGS)" .

clean:
	rm -rf bin dist
EOF

# --- Substitute tokens -----------------------------------------------------
find "$OUT" -type f \( -name '*.go' -o -name 'Makefile' -o -name 'README.md' \
  -o -name 'LICENSE' -o -name 'go.mod' \) -print0 | while IFS= read -r -d '' f; do
  sed -i \
    -e "s|MODULETOK|${MODULE}|g" \
    -e "s|BINTOK|${NAME}|g" \
    -e "s|DESCTOK|${DESC}|g" \
    -e "s|ENVPTOK|${ENVP}|g" \
    -e "s|__MODULE__|${MODULE}|g" \
    -e "s|__NAME__|${NAME}|g" \
    -e "s|__DESC__|${DESC}|g" \
    -e "s|__ENVP__|${ENVP}|g" \
    -e "s|__YEAR__|${YEAR}|g" \
    "$f"
done

# --- Resolve dependencies (best effort; offline copies can vendor instead) ---
if command -v go >/dev/null 2>&1 && (cd "$OUT" && go get github.com/spf13/cobra@latest >/dev/null 2>&1 && go mod tidy >/dev/null 2>&1); then
  echo "dependencies resolved: github.com/spf13/cobra"
else
  echo "warning: could not resolve modules (go unavailable or offline)."
  echo "         run 'go mod tidy' inside $OUT when online."
fi

echo ""
echo "Created CLI project at: $OUT"
echo "Next steps:"
echo "  1. cd $OUT && go build ./...   (verify it compiles)"
echo "  2. Implement your API commands under cmd/ (see references/stack-guide.md)"
echo "  3. Render output only via internal/output (see references/output-contract.md)"
echo "  4. make test  /  make build"