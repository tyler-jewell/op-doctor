# Patterns

## 1. `op.refs`: references in git, values in 1Password
Commit a file of `KEY=op://...` lines. No `.env` with real values.

```
# op.refs
DATABASE_URL=op://example-vault/example-item/connection-string
API_TOKEN=op://example-vault/example-item/token
```
Run anything with `op run --env-file=op.refs -- <command>`. `op run` conceals values in stdout/stderr (best effort).
Conventional names op-doctor looks for: `op.refs`, `*.op.env`, `.env.op`, `.op/*`. Any other tracked text file that
contains `op://` is also scanned. Keep `.env`/`.env.local` out of git (`.gitignore`); if you must keep a template,
name it `.env.example` with placeholders only.

## 2. Per-environment vaults without vault names in public repos
Use a variable so a public template carries no vault names:

```
DB_PASSWORD=op://$OP_VAULT/db/password
```
```
OP_VAULT=example-dev op run --env-file=op.refs -- ./start.sh
op-doctor check --var OP_VAULT=example-dev
```
`$VAR` / `${VAR}` are supported by `op run` and `op inject`; op-doctor substitutes them from the environment or
`--var NAME=VALUE`. Use non-secret variables only (op-doctor refuses names like `*_TOKEN`).

## 3. Naming
`KEY` = the env var your app reads. Item = one per service/environment; field = the credential. Prefer names made
of letters, digits, `-`, `_`, `.`; otherwise use IDs (also cheaper: 1 request instead of 3 per lookup).
Sections: `op://vault/item/section/field`. One-time passwords: `op://vault/item/one-time password?attribute=otp`
(quote references containing spaces).

## 4. Local development
Install the 1Password desktop app, enable Settings > Developer > CLI integration, then `op run` prompts for
biometrics. Without the desktop app (headless machines), use a service account token in the environment.

## 5. CI
Create a read-only service account scoped to needed vaults; store its token as the repo secret
`OP_SERVICE_ACCOUNT_TOKEN`; use `1password/install-cli-action`, then `op run --env-file=op.refs -- ...`.
Add op-doctor's reusable workflow (`.github/workflows/op-doctor.yml`) for offline `scan` + `lint` on every PR and an
optional live `check` on a schedule.

## 6. 1Password Environments (alternative)
`op run --environment <environment-id> -- <cmd>` loads variables from a 1Password Environment with no file at all
(present in `op` 2.41; ID is copied from the desktop app). There is no CLI to list Environments, so op-doctor
cannot health-check them yet; use `op-doctor lint` to keep plaintext out of git, and verify Environments with
`op run --environment <id> -- sh -c 'test -n "$VAR"'`.
