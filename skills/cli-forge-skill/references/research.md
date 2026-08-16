# Research: mapping an API to a CLI surface

Step 2 of the workflow. Goal: one concise brief that tells you (and the user)
exactly what commands the CLI will have and what each one does against the
real API. Keep it lean — research feeds design, it does not replace it.

## 1. Resolve the spec source

Try these in order until you have enough to work from, stopping early when a
source is "good enough":

1. **Official OpenAPI/Swagger spec.** Look for: a file the user handed you,
   `/<api>/openapi.json`, `/openapi.yaml`, `/swagger.json`, `/api-docs` paths,
   or entries on apis.guru. This is the ideal source: endpoint list, schemas,
   auth, and pagination all in one.
2. **Official API docs.** The developer site's reference pages. Slower to parse
   but authoritative. Use a raw fetch (curl, not a browser renderer) when
   field-level details matter.
3. **Postman collection / HAR capture.** Convert to a working endpoint list;
   treat captured examples as ground truth for request/response shapes.
4. **Ask the user.** If the API is undocumented, private, or ambiguous, ask
   before inventing — a fabricated endpoint that 404s is worse than a smaller CLI.

Probe any URL to confirm it is what you think: check status and content type,
read the first lines of the document. Record what you used as the source in the
brief.

## 2. Extract the API facts

For each candidate source, extract into your brief:

- **Base URL** and any version prefix (`/v2`, `/api`).
- **Auth scheme**: API key (header name), bearer token, OAuth token, or none.
  Which endpoints need auth, which don't.
- **Rate limits**: whether the API documents them, and any `Retry-After` /
  `X-RateLimit-*` behavior to shape client defaults.
- **Error shape**: what a non-200 response body looks like (so you can map it
  into the CLI's structured errors).
- **Pagination style**: page-based (`?page=&per_page=`), cursor-based
  (`?cursor=`), header-based (`Link:`), or none.
- **Media types**: JSON, form-encoded uploads, streaming responses.

## 3. Catalog the endpoints

Build a table of endpoints you will actually wire up. Do not paste the whole
spec — record, per endpoint:

| Method | Path | Purpose | Inputs (path/query/body) | Output shape | Auth |
|---|---|---|---|---|---|
| GET | `/projects` | list projects | `page`, `per_page` | array | key |

Mark which endpoints are speculative (seen in docs but unverified) vs. which
you will smoke-test. Filter out noise (health endpoints, admin-only routes) when
the user's goal is a focused tool.

## 4. Map resources to commands

Conventions that keep the CLI predictable:

- **Nouns → commands.** A resource becomes a command: `projects`, `users`,
  `issues`. One command per resource that has useful operations.
- **Verbs → subcommands/flags.** Standard CRUD subcommands: `list`, `get`,
  `create`, `update`, `delete`. Non-CRUD actions become subcommands
  (`deploy`, `invite`) or flags (`--archive`) when they are a write on the
  same resource.
- **Resource identity → positional arg.** `projects get <id>`,
  `issues list --project <id>`.
- **Filters/pagination → flags.** `--limit`, `--cursor` / `--page`,
  `--status`, and query params become kebab-case flags.
- **Field selection.** Where the API supports it, offer `--fields a,b,c` that
  narrows both the request and the `--json` output.

## 5. Decide the command tree

Produce a small tree like:

```
<cli>
├── projects
│   ├── list
│   ├── get <id>
│   ├── create
│   ├── update <id>
│   └── delete <id>
└── users
    ├── list
    └── get <id>
```

Show this to the user before moving to Step 4 if there are judgment calls
(which resources, which actions, which need auth). The plan is cheap to change
now and expensive after you write commands.

## 6. Edge cases to record, not skip

- **Optional-auth endpoints**: commands that work with no key must run without
  one (never demand a credential for a public binding).
- **Undocumented endpoints**: flag them in the brief; verify by a real call or
  by asking the user before wiring them in.
- **Rate-limited surface**: a write-heavy CLI may need `--retries`/backoff
  documentation; note it.
- **Streaming/events**: if the API streams, note whether a `--follow`/`watch`
  flag is in scope (it is often the headline feature — ask the user).

## 7. Deliverable

One brief, 30–80 lines, with: source used, auth + rate-limit + pagination
facts, endpoint table, and the command tree. Write it to the run's research
directory and reference it in later steps. Do not produce multi-file research
reports unless the user asks.