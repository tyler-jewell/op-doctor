# AGENTS.md: contract for tools and agents

op-doctor is read-only, never prompts (no TTY/CI dependence), and never prints secret values.

## Commands
`op-doctor <scan|lint|check|doctor|roots> [options] [ROOT...]`. Offline: `scan`, `lint`, `roots`. Live: `check`,
`doctor` (use `--dry-run` first to see the request count; `--max-requests N` caps spend, default 200).
Run `op-doctor --help` for the structured option list.

## Output
- `--json`: one document on stdout, schema `op-doctor/v1`, documented in docs/SCHEMA.md. Diagnostics go to stderr.
- Human output is for people; parse JSON instead. `--quiet` prints only problems. Colour only on a TTY.

## Exit codes
| code | meaning |
|---|---|
| 0 | everything fine |
| 2 | problems: lint errors, or any check state other than `ok` |
| 3 | `op` missing, signed out, locked, or rate limited (hint on stderr / `errors[]`) |
| 4 | invalid config or invalid/non-git root |
| 64 | usage error (also: plan exceeds `--max-requests`) |

Precedence if several apply: 64 > 4 > 3 > 2 > 0.

## Rules for agents
- Never pass secrets as flags (rejected). Provide `OP_SERVICE_ACCOUNT_TOKEN` through the environment only.
- Do not add `--reveal`, `set -x`, or log `op` output in this repo.
- Tests: `bash tests/run.sh`. Secrets in tests are generated at run time; do not add secret-like literals.
- Keep examples neutral: `example-vault`, `example-item`, `$OP_VAULT`.
