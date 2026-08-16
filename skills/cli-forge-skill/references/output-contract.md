# Output Contract — machine-readable CLI output

This reference defines the non-negotiable rules for how every command in the
CLI renders output. It is the "optimized for AI models" core of this skill: the
CLI's stdout is a stable API for other programs and AI agents. Anything a
command prints that is not parseable, stable data is a bug.

## 1. `--json` is universal

- Every command that produces data supports `--json`.
- In `--json` mode, **stdout contains exactly one JSON document and nothing
  else** — no preamble, no trailing log lines, no blank lines, no ANSI.
- Add `--no-color`/`--plain` handling by honoring `NO_COLOR` and non-TTY
  detection automatically (see §5); `--json` is always plain.

## 2. JSON shape rules

- **Envelope for collections.** A list result uses:
  ```json
  {"items":[...],"pagination":{"has_more":false}}
  ```
  When pagination exists, include the next cursor:
  `{"items":[...],"pagination":{"has_more":true,"next_cursor":"..."}}`.
  Add `"schema_version":1` inside the envelope when the shape is at risk of
  evolving.
- **Bare object for single results.** A `get` on one resource emits the object
  directly (no wrapper). Document its shape in the command's help.
- **Deterministic key order.** Use Go structs (which marshal in field order)
  for all known shapes. Never emit `map[string]any` for a shape you know — if
  you must, sort the keys before marshaling. Same request must produce
  byte-identical output (no injected random values, no ambient timestamps).
- **Stable types.** Numbers stay numbers; a string ID from the API stays a
  string. Never serialize `12345` as `"12345"` unless the API itself sends a
  string. Dates are `ISO-8601` UTC with `Z`: `2026-08-16T11:22:33Z`.
- **Empty results are empty, not null.** `[]` for lists, `{}` where an object
  is expected; omit absent optional fields rather than emitting `null` when the
  API omits them.
- **Keep the API's meanings.** Field names and enum values come from the API.
  Don't rename status codes, don't localize, don't re-key unless documented.

## 3. Exit codes

| Code | Meaning |
|---|---|
| `0` | Success (including empty results) |
| `1` | Runtime failure: API error, network error, or operation reported failed |
| `2` | Usage error: unknown command/flag, missing or invalid arguments (Cobra default) |
| `130` | Interrupted (SIGINT) |

- A command that fails must exit non-zero; exit `0` only on true success.
- On failure in `--json` mode, stdout is empty and stderr carries the
  structured error (see §4).

## 4. stderr and structured errors

- **Success ⇒ empty stderr.** No "Done!", no stats, no warnings — unless a
  verbosity flag explicitly requested diagnostics.
- **Failure in `--json` mode** ⇒ a single-line JSON document on stderr:
  ```json
  {"ok":false,"error":{"code":"rate_limited","message":"429 Too Many Requests","http_status":429,"details":{"retry_after_seconds":17}}}
  ```
  `message` is human-readable; `code` is a stable machine key from a small
  fixed set:
  `invalid_argument`, `missing_credential`, `auth_failed`, `not_found`,
  `rate_limited`, `api_error`, `network`, `unsupported`, `internal`.
  Add `http_status` when the cause is an API/HTTP response; `details` is an
  optional object, never free text.
- **Failure in human mode** ⇒ one or two readable lines on stderr, same
  information, no JSON requirement.

## 5. TTY hygiene

- When the env var `NO_COLOR` is set (any value), emit zero ANSI escapes.
- When stdout is not a TTY (piped, redirected, captured by an AI agent), emit
  zero ANSI escapes, zero progress indicators, and keep human output
  line-oriented and grep-friendly.
- Progress/spinners, if any, go to stderr and only when stderr is a TTY.
- Human tables are only appropriate when stdout is a TTY; your single source of
  truth for machines is always `--json`.

## 6. What is forbidden on stdout

- HTML, server logs, banner art, version strings on data commands
- Progress bars, spinners, percentages, "N results fetched" chatter
- Multiple JSON documents or JSON mixed with prose
- Empty `null`, `undefined`, or raw HTTP bodies passed through unparsed
  where structured output is expected

## 7. Contract versioning

- `schema_version` appears at the top level of any envelope whose shape may
  evolve; breaking changes bump it.
- Document each command's exact stdout shape in its `--help`, including example
  JSON, so a consuming AI agent never has to guess.
- Mark the contract behavior in the README: "Output is a stable machine API.
  JSON is emitted on stdout only; errors are structured on stderr."

## 8. Verification hooks

- `verify_cli.py` mechanically checks: parseability of `--json` on every probed
  command, stdout/stderr separation, exit-code semantics, and no-ANSI in piped
  mode. Keep those green at all times.
- Manual checks from `references/verification-checklist.md` cover the rest
  (key names, API fidelity, real-API sanity).