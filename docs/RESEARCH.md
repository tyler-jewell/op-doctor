# Research notes

Evidence behind op-doctor's design. Researched 2026-10-23 against `op` 2.41.0 (local `--help`, no account
used) and the 1Password developer docs (docs moved from developer.1password.com to www.1password.dev).
Items marked **UNVERIFIED** could not be tested without a signed-in account.

## Secret reference syntax
Source: <https://www.1password.dev/cli/secret-reference-syntax/>, `op read --help`.

- `op://<vault>/<item>/[<section>/]<field>`. Names may be replaced by IDs. Case-insensitive.
- Allowed in names: letters, digits, hyphen, underscore, period, whitespace (whitespace requires quoting the whole
  reference). Other characters: use the ID. There is no escaping mechanism. (op-doctor lint flags other characters.)
- Query parameters: `?attribute=` (alias `attr`) with `otp`, `type`, `value`, `id`, `purpose` (fields) or
  `content`, `size`, `id`, `name` (files); `?ssh-format=openssh` for SSH private keys.
  op-doctor accepts `attribute`, `attr`, `ssh-format` and flags anything else as malformed.
- File attachments: `op://vault/item/[section/]file-name`.
- Variables: `op://$APP_ENV/mysql/database` (docs) and `echo "x: op://$env/db/password" | env=prod op inject`
  (`op inject --help`). The `op run --help` example is `DB_USERNAME = op://$APP_ENV/db/username` in an env file,
  with `APP_ENV` exported. Both `$VAR` and `${VAR}` are expanded in env files (see below). Variables appear to be
  usable in any segment, not just the vault; op-doctor supports all segments.
- `op inject` templates use `{{ op://vault/item/field }}`.

## How `op run --env-file` parses (docs: <https://www.1password.dev/cli/secrets-environment-variables/>)
- `KEY=VALUE` per line; blank lines skipped; `#` comments and inline comments; whitespace around keys/values
  ignored; multi-line values in matching quotes; quotes stripped; double-quoted values expand variables,
  single-quoted do not; `$VAR`/`${VAR}` come from the environment or earlier lines; backslash escapes.
- References are resolved as template syntax after dotenv parsing, so templates cannot build variable names.
- Precedence (`op run --help`): `--environment` > `--env-file` (last file wins) > shell environment.
- What `op run` does when a referenced secret is missing: not documented on that page. **UNVERIFIED**.

## Checking a field without printing it
- `op read --no-newline REF` exists (`op read --help`, flags `-n/--no-newline`, `-o/--out-file`). Piping to `wc -c`
  gives a byte count without displaying the value; this is op-doctor's fallback path.
- `op item get ITEM --vault V --format json` returns the whole item. Community reports (April 2026 and Jan 2025,
  1password.community) say **JSON output includes concealed values even without `--reveal`** (the human format
  hides them). So op-doctor only ever pipes this output into `jq` with a filter that emits states, never to disk,
  stdout, or a log. **UNVERIFIED live**: exact JSON shape (assumed `.fields[]` with `id`, `label`, `type`, `value`,
  `section{id,label}`, and `.files[]` with `name`, `size`) is from experience; if a field holds a placeholder
  rather than the value, an empty field could be misreported as ok.
- Request cost with service accounts (docs, <https://www.1password.dev/service-accounts/use-with-1password-cli/>):
  `op item get` and `op read` cost 3 reads by name, **1 when both vault and item are IDs**. `op item list` costs
  1 per accessible vault. Service accounts must pass `--vault` to `op item get`. Hence: one `item get` per
  distinct vault+item, `--max-requests` estimate = 3 per item (1 with IDs). `op service-account ratelimit`
  exists (listed as supported) and could report remaining quota; not used yet.

## Not signed in / locked / service accounts
- Local observation (no account, no desktop app): every account-requiring command (`op whoami`, `op vault list`,
  `op read`, `op item get`) prints `[ERROR] <ts> ... connecting to desktop app: 1Password CLI couldn't connect to
  the 1Password desktop app ...` and exits **1**. Exit codes are not otherwise documented (reference page silent).
- Service accounts: `OP_SERVICE_ACCOUNT_TOKEN`, CLI 2.18.0+, verify with `op user get --me`. If
  `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN` are set they take precedence over the service account token.
  `op connect`, `op group`, `op events-api` are unsupported with service accounts.
- Error texts for missing vault/item (from community threads, op 2.3x): `"X" isn't a vault in this account.
  Specify the vault with its ID or name.` and `"X" isn't an item in the "Y" vault. Specify the item with its UUID,
  name, or domain.` Missing-field, denied, rate-limit and expired-token wordings are **UNVERIFIED**; op-doctor
  classifies by substring and falls back to state `error` with a one-line sanitized message. A service account
  without access to a vault probably reports "isn't a vault" (indistinguishable from nonexistent): **UNVERIFIED**.
- The CLI documents no exit-code contract, so op-doctor decides availability from stderr text plus a non-zero status.

## 1Password Environments from the CLI
Sources: `op run --help` on 2.41.0 (local), <https://www.1password.dev/environments/read-environment-variables>,
CLI beta release notes 2.33.0-beta.02.
- `op run --environment <environment-uuid> -- cmd` exists in **stable 2.41.0** (present in local `--help`; a community
  reply says 2.34.1 lacked it). It takes an Environment ID copied from the desktop app (Developer > Environments >
  Manage environment > Copy environment ID); variables are concealed in output; usable with service accounts scoped
  to the Environment, or desktop-app auth.
- `op environment ...` (e.g. `op environment read <id>`) is documented as beta but is **not present in local 2.41.0**
  (`unknown command "environment"`). There is no CLI listing, so Environments cannot be health-checked by
  reference. They are therefore **out of scope for `check`** in 0.1; they are a valid no-file alternative
  documented in docs/PATTERNS.md. Environment IDs are not `op://` references, so `scan`/`lint` ignore them.

## Design consequences
1. Static `lint` carries most value offline; live `check` is optional and quota-aware.
2. Dedupe by vault+item; cache vault-level failures (missing vault / denied) to avoid wasted requests.
3. Never print or store values; only states. Treat `item get --format json` as sensitive in-memory data.
4. Variable substitution reads only from the environment or `--var`; secret-like variable names are refused so a
   token can never be spliced into a reference and echoed.
