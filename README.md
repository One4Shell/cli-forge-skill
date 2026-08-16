# cli-forge-skill

Installs the **cli-forge-skill** agent skill into any project: `SKILL.md`,
the `references/` docs, `scripts/` helpers, and any bundled `assets/`.

Builds a complete, ship-ready Go CLI for an API using Cobra, engineered for stable machine-readable output that AI models, scripts, and pipelines can consume. Use whenever the user wants to turn an API, OpenAPI spec, or REST endpoint into a command-line tool -- even if they phrase it as 'build a CLI for X', 'create a Go CLI', 'wrap this API for the terminal', or 'a CLI with --json output an AI can read'.

## Install (recommended)

This repo follows the [Agent Skills specification](https://agentskills.io),
so it installs with a single command via [`npx skills`](https://github.com/vercel-labs/skills)
— no cloning, no config:

```bash
npx skills add https://github.com/One4Shell/cli-forge-skill --skill cli-forge-skill
```

`npx skills` auto-detects which coding agents you have installed and copies
(or symlinks) the skill into the right directory for each — `.agents/skills/`
for OpenCode/Codex/Cursor/Amp, `.claude/skills/` for Claude Code, and so on.
Add `-a <agent>` to target a specific one, or `-g` to install globally
instead of per-project.

## Install (no npm required)

If you'd rather not depend on the `skills` CLI, use the plain shell
installer bundled in this repo instead:

```bash
curl -fsSL https://raw.githubusercontent.com/One4Shell/cli-forge-skill/main/install.sh | bash
```

To pass options through the pipe, use `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/One4Shell/cli-forge-skill/main/install.sh | bash -s -- --claude
```

Or clone and run it locally (no network access needed at install time):

```bash
git clone https://github.com/One4Shell/cli-forge-skill.git
cd cli-forge-skill
./install.sh --dir /path/to/your/project
```

### `install.sh` options

```
--dir <path>     Project root to install into (default: current directory)
--path <path>    Custom install path, relative to --dir
                  (default: .agents/skills/cli-forge-skill)
--claude         Shorthand for --path .claude/skills/cli-forge-skill
--force          Overwrite existing files (default: skip files that already exist)
-h, --help       Show help
```

Env vars (only used in the `curl | bash` case, i.e. no local checkout):

```
CLI_FORGE_SKILL_REPO     GitHub "owner/repo" to fetch from (default: baked into install.sh)
CLI_FORGE_SKILL_BRANCH   Branch/ref to fetch (default: main)
```

Either method never overwrites existing files unless `--force` is passed, so
it's safe to re-run.

## What gets installed

```
skills/cli-forge-skill/            # repo layout — also discoverable as .agents/skills/cli-forge-skill
├── SKILL.md                      # entry point the agent reads
├── scripts/                      # executable helpers, if any
├── references/                   # docs loaded into context as needed
└── assets/                       # files used in output, if any
```

## After installing

Point your agent at a project containing the skill and describe what you
need — it will pick up `SKILL.md` and follow its instructions from there.

## License

MIT
