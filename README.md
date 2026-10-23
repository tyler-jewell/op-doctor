# op-doctor

Healthchecks for 1Password secret references. Keep only `op://` references in git, run with `op run`, and let
`op-doctor` tell you when a reference is malformed, a plaintext secret slipped into a tracked file, or a reference
no longer resolves to a **set** value in 1Password. It never prints a secret value, never writes to your repos, and
sends no telemetry.

## The problem
`.env` files with real values leak. The fix is to commit references (`KEY=op://vault/item/field`) and let
`op run` inject values at run time. Then the failure mode changes: a renamed item or an empty field only shows up
when the app starts. op-doctor finds those problems ahead of time, across all your repositories, frugally enough
for a service account's request quota.

## 60-second quickstart
Requires bash 3.2+ (macOS or Linux), git, awk/sed/grep, [jq](https://jqlang.github.io/jq/), and for live checks the
1Password CLI `op`.

```sh
git clone https://github.com/tyler-jewell/op-doctor ~/.local/share/op-doctor
ln -s ~/.local/share/op-doctor/bin/op-doctor ~/.local/bin/op-doctor

cd your-repo
printf 'API_TOKEN=op://example-vault/example-item/field\n' > op.refs
git add op.refs

op-doctor scan          # list references (offline)
op-doctor lint          # static checks, offline: exit 2 on problems
op-doctor check --dry-run   # show the plan and request count
OP_SERVICE_ACCOUNT_TOKEN=... op-doctor check   # live: ok | empty | missing-* | denied | ...
op run --env-file=op.refs -- ./your-app
```

## Recommended pattern
- Commit `op.refs` with `KEY=op://vault/item/field` lines. No `.env` files with real values.
- Run commands with `op run --env-file=op.refs -- <cmd>`.
- For public templates use a variable instead of a vault name: `op://$OP_VAULT/db/password`.
See [docs/PATTERNS.md](docs/PATTERNS.md).

## Commands
| command | needs `op` | what |
|---|---|---|
| `scan` | no | inventory of references: repo, file, line, variable, vault/item/field |
| `lint` | no | malformed refs (L001), tracked `.env` files (L002), plaintext secret-like values (L003), `--public` hardcoded vaults (L004) |
| `check` | yes | resolve distinct refs: `ok empty missing-item missing-field missing-vault denied unresolved-variable error` |
| `doctor` | yes | lint + check, combined summary |
| `roots` | no | show the repositories that would be examined |

Choosing repositories: default is the current git repo; or pass paths, `--roots FILE`, or `--all`
(`${XDG_CONFIG_HOME:-~/.config}/op-doctor/roots`, else `.../dotfiles/repos.txt`, else `~/workspaces/*/`).
`--exclude GLOB` or `exclude = GLOB` in `${XDG_CONFIG_HOME:-~/.config}/op-doctor/config` skips repos.
`check` options: `--var NAME=VALUE`, `--max-requests N` (default 200), `--dry-run`, `--method auto|read`.
Output: `--json` ([schema](docs/SCHEMA.md)), `--quiet`, `--no-color`.

Exit codes: `0` ok, `2` problems, `3` `op` unavailable/signed out/locked/rate limited, `4` invalid config or root,
`64` usage. Precedence 64 > 4 > 3 > 2 > 0.

## Quota
Service-account reads cost 3 requests per item by name (1 by ID). op-doctor does one `op item get` per distinct
vault+item and falls back to `op read` only if needed. On a personal plan (1,000 requests/day) run `check` at
most daily. See [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md).

## Optional integrations (all off by default)
`contrib/pre-commit-op-lint` (static lint hook), `.github/workflows/op-doctor.yml` (reusable workflow:
offline scan+lint, optional live check when the `OP_SERVICE_ACCOUNT_TOKEN` secret exists),
`contrib/launchd/` (daily live healthcheck on macOS with a JSON report and failure-only notification).

## Docs
[PATTERNS](docs/PATTERNS.md) | [THREAT-MODEL](docs/THREAT-MODEL.md) | [SCHEMA](docs/SCHEMA.md) |
[RESEARCH](docs/RESEARCH.md) | [AGENTS](AGENTS.md) | [CONTRIBUTING](CONTRIBUTING.md) | [SECURITY](SECURITY.md)

## License
Apache-2.0. Not affiliated with 1Password.
