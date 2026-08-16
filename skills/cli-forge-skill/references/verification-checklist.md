# Verification checklist — manual pass

Run `scripts/verify_cli.py` first (the mechanical matrix). Then walk this list
by hand — these are judgment calls a script cannot make. Fix anything that
fails before shipping.

## Trigger and scope sanity

- [ ] The builds/research match what the user asked for (right API, right
      resources) — Step 3's command tree is reflected in `--help`.
- [ ] No scope creep: every command actually calls a real, verified endpoint;
      no invented paths survived from research.md's "speculative" column.

## Contract compliance, by hand

- [ ] Run one real command against the real API with `--json` (or with a mock
      if no credentials): keys and values match the API's own shapes; the sample
      in `--help` matches actual output.
- [ ] Success path: stderr is empty; stdout is exactly one JSON document.
- [ ] Forced failure (bad id, missing key): exit code is `1`, stdout is empty,
      stderr is the structured error JSON (in `--json` mode).
- [ ] Bad usage (`--json` on a non-existent flag / missing required arg):
      exit code is `2`.
- [ ] Piped output (non-TTY): no ANSI escapes, no spinners; `NO_COLOR=1` gives
      the same cleanliness.
- [ ] A `list` command with empty results emits `[]`/empty envelope, exit 0.

## Environment and portability

- [ ] No hardcoded absolute paths or author-machine specifics in code, README,
      Makefile, or scripts.
- [ ] No secrets: grep the tree for the literal API key / bearer value you
      tested with — it must not appear in code, git, or docs.
- [ ] Config resolution is flag > env > default, and env var names are spelled
      out in `--help`.
- [ ] `go vet ./...` and `go test ./...` pass in a clean clone (not just in the
      working tree).

## Docs and delivery

- [ ] README install steps were actually executed once (down to first successful
      run), not just written.
- [ ] `--help` for `list`/`get` shows the JSON shape and an example; `version`
      and `completion` commands work.
- [ ] Edge cases from research.md (§6) are handled or explicitly declined with
      the user — not silently dropped.

## Smoke prompts for the skill itself

Use these to confirm the *skill* triggers correctly before publishing it (they
should be recognized on re-runs):

- "Let's make a CLI for the GitHub API"
- "Wrap this OpenAPI spec: ./swagger.json — I want --json output"
- "Build a Go tool that queries Stripe from the terminal"
- "I need a machine-readable CLI for our internal REST API"

If one of these would not fire this skill, tighten the frontmatter
`description` and re-validate.