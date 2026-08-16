---
name: cli-forge-skill
description: "Builds a complete, ship-ready Go CLI for an API using Cobra, engineered for stable machine-readable output that AI models, scripts, and pipelines can consume. Use this whenever the user wants to turn an API, OpenAPI spec, or REST endpoint into a command-line tool — even if they phrase it as \"build a CLI for X\", \"create a Go CLI\", \"wrap this API for the terminal\", or \"a CLI with --json output an AI can read\". Standalone: requires only the Go toolchain, no external generator binary."
version: 1.0.0
license: MIT
compatibility: go
tags: [cli, go, cobra, api, machine-readable, agent]
---

# cli-forge-skill

Turn an API — its OpenAPI spec, its docs, or just its name — into a complete,
professional, ship-ready Go CLI whose output is engineered for machines: stable
JSON, clean exit codes, and zero decorative text. The CLI must be usable by a
human in a terminal **and** by another AI model reading its stdout.

## Rules

Caveman mode is ON for this whole conversation, until I say "stop caveman". Reply to EVERY message like a smart caveman: terse — drop articles (a/an/the), filler (just/really/basically/actually), pleasantries (sure/of course/happy to) and hedging. Fragments fine. Short synonyms (fix, not "implement a solution for"). Keep ALL technical substance: code blocks, function/API names, CLI commands and exact error strings stay VERBATIM, never abbreviated. No emoji, no decorative tables, no narrating what you do. Never announce or name this mode. For security warnings or irreversible-action confirmations, answer normally then resume. Intensity FULL: drop articles, fragments OK, short synonyms. Classic caveman terseness.

## When to use this skill

Use this whenever the user wants any of the following, even when they don't use
these exact words:

- "make/build/create a CLI for <API>", "a tool to call <API>"
- "wrap this API", "turn this REST endpoint into a command-line tool"
- "a CLI with --json output", "output an AI/agent can read", "machine-readable
  CLI", "agent-friendly CLI"
- "a Go CLI", "a cobra CLI", "an installable command-line tool"
- They hand you an OpenAPI/Swagger spec, a Postman/HAR capture, or API docs and
  want commands generated from them

For CLIs whose primary job is wrapping a specific API, this skill replaces
`printing-press` when the printing-press binary is unavailable or unwanted. It
works standalone with nothing but the Go toolchain. Not for building MCP
servers, web services, or libraries — only command-line tools.

## Environment assumptions

- Go 1.21+ on `PATH` (`go`, and network for `go mod download` unless you work
  from a vendored/offline copy).
- Cobra is pulled in as a normal module dependency — nothing installed globally.
- No reliance on `printing-press`, `cli-printing-press`, or any other CLI
  generator binary. This skill is self-contained.
- For live smoke-testing, an API key or other credentials may be needed; ask the
  user, never invent one, and never embed a value in code.

## Core workflow

Follow this loop. Report where you are in it when the user asks for progress.

1. **Capture requirements.** Derive from the request: the API name, its base
   URL or spec path, the auth model (API key, bearer, OAuth, none), and whether
   the user cares about humans, machines, or both. Write a short run manifest
   (a few lines) recording these so later steps and the user can refer to it.

2. **Research the API surface.** Read `references/research.md`. Resolve the
   spec (OpenAPI/Swagger JSON or YAML, a docs site, or a HAR capture), then
   derive base URL, auth details, rate limits, and a resource→command map.
   Keep this lean: one research brief, no research theater.

3. **Design the CLI surface.** Map resources (nouns) to commands, actions
   (verbs) to subcommands/flags. Decide which commands produce data (these all
   get `--json`) vs. which are actions (confirm, still structured errors).
   Print the planned command tree for the user to sanity-check before coding.

4. **Scaffold the Go project.** In the target directory, run:

   ```bash
   bash scripts/scaffold_cli.sh --module <module-path> --name <cli-name> \
     --description "<one-line purpose>"
   ```

   This produces a compiling Cobra skeleton (root, version, completion,
   config-from-env, JSON output helpers, retrying HTTP client). Confirm it
   builds before writing a single command: `cd <cli-name> && go build ./...`.

5. **Implement the commands.** Follow `references/stack-guide.md`. Wire real
   endpoints through `internal/client`, resolve configuration via
   `internal/config` (env var → flag → default), and keep output rendering
   solely inside `internal/output`.

6. **Enforce the output contract.** Apply `references/output-contract.md` to
   every command you ship. This is the "optimized for AI models" core: stable
   `--json`, deterministic field order, nothing on stderr except problems,
   semantic exit codes, NO_COLOR and non-TTY hygiene. Compare against
   `assets/example-json.md` while editing.

7. **Verify.** Run the mechanical matrix:

   ```bash
   python3 scripts/verify_cli.py <path-to-binary> [command...] [--module <dir>]
   ```

   Fix every failure before proceeding. Then walk
   `references/verification-checklist.md` by hand — prompt phrasing, environment
   cleanliness, real-API sanity, and no secrets.

8. **Ship.** Finalize a README (install, usage, env vars, examples), confirm
   `go vet ./...` and `go test ./...` pass, and hand the CLI to the user at the
   location they asked for. Offer the Makefile release/cross-compile targets
   (`make build`, `make test`, `make cross`) as the packaging path.

## Cardinal rules

- **Machine-readable output is mandatory, not optional**, on every
  data-producing command. `--json` is always available; output is stable and
  parseable.
- **stdout carries data; stderr carries problems.** No partial JSON, no
  progress bars, no ANSI noise in piped/non-TTY output.
- **Exit codes are semantic**: 0 success, 1 runtime/API failure, 2 usage error.
- **Never embed secrets.** Auth comes from environment variables. Names are
  fine in docs; values never touch code or git.
- **Optimize for time-to-ship.** Reuse prior research, avoid over-documenting,
  and don't invent endpoints that don't exist.

## Reference files

| File | When to read it |
|---|---|
| `references/research.md` | Step 2: resolving a spec, mapping resources to commands |
| `references/stack-guide.md` | Steps 5: Cobra/Go conventions, client, config, auth, build |
| `references/output-contract.md` | Step 6 and whenever touching output rendering |
| `references/verification-checklist.md` | Step 7: manual pass alongside `scripts/verify_cli.py` |

## Scripts

- `scripts/scaffold_cli.sh` — deterministic Go+Cobra skeleton generator (Step 4).
- `scripts/verify_cli.py` — mechanical verification matrix (Step 7): help/version/
  completions, `--json` parseability, stdout/stderr separation, exit codes,
  NO_COLOR and non-TTY hygiene, and optional `go vet`/`go test` via `--module`.

## Assets

- `assets/example-json.md` — concrete good-vs-bad `--json` examples; use as the
  north star in Step 6.