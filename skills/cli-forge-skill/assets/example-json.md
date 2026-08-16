# Example `--json` output — good vs bad

Concrete north-star for Step 6 of the workflow. When in doubt about what a
`--json` result should look like, match the GOOD column exactly.

## A collection (list command)

**BAD — noise on stdout, mixed key order, non-ISO time, int-as-string drift:**

```
Fetching projects... 52% |██████████░░| 
projects smoke test passed
[{"id": 12345, "created_at": "Mon, 16 Aug 2026 11:22:33 GMT", "name": "API", "Status": "active"}]
```

Problems in order: progress bar and log chatter on stdout before the JSON;
`Status` capitalised and out of struct order; locale-formatted date without
`Z`; `id` forced to string; the array has no envelope so pagination metadata
has nowhere to live.

**GOOD:**

```json
{"items":[{"id":12345,"name":"api","status":"active","created_at":"2026-08-16T11:22:33Z"}],"pagination":{"has_more":false}}
```

- One JSON document, nothing else, on stdout.
- Struct field order: `id, name, status, created_at` — deterministic.
- Types match the API: `id` is the API's own int, `created_at` is ISO-8601 UTC
  with `Z`.
- Collection lives in the stable envelope with pagination metadata.

## A single object (get command)

```json
{"id":12345,"name":"api","status":"active","created_at":"2026-08-16T11:22:33Z"}
```

Bare object, no wrapper, same deterministic ordering and types.

## Empty results

```json
{"items":[],"pagination":{"has_more":false}}
```

`[]`, not `null`, and exit code `0` — empty is a valid success.

## Failure in `--json` mode (stderr only)

stdout stays empty; stderr carries:

```json
{"ok":false,"error":{"code":"rate_limited","message":"429 Too Many Requests","http_status":429,"details":{"retry_after_seconds":17}}}
```

- `code` is a stable machine key from the small fixed set (see
  `references/output-contract.md`).
- `message` is human-readable (may also be duplicated as plain text in human
  mode).
- `http_status` and `details` present only when meaningful.

## Exit codes

| Scenario | Code |
|---|---|
| Success (incl. empty results) | `0` |
| API/network/runtime failure | `1` |
| Unknown flag, bad arguments | `2` |

## Tests worth pinning

The `verify_cli.py` matrix checks parseability and channel separation
mechanically. Add one `go test` golden assertion per data command that pins the
exact JSON string, so the contract cannot regress silently while editing
structs or field tags.