# Threat model

**Goal:** tell you whether your `op://` references are well-formed and resolve to non-empty values, while never
exposing a secret value and never changing anything.

## What it reads
- Git-tracked files only (`git ls-files` / `git grep`) in the chosen repositories. Untracked and ignored files
  (including your real local `.env`) are never opened.
- For `check`: the 1Password CLI. `op item get <item> --vault <v> --format json` returns the full item, **including
  concealed values** (community-reported, see RESEARCH.md). op-doctor pipes that straight into `jq` with a filter
  that outputs only `reference<TAB>state`. The response is never written to a file, variable, log or stdout.
  `op read --no-newline` output is piped to `wc -c`. So values live only in the pipe and the `op`/`jq` processes'
  memory for the duration of one call.

## What it never does
- Print, log, cache or write secret values (not even partially); no `--reveal`; no `set -x`; `OP_DEBUG` forced off.
- Accept secrets on the command line (`--token`, `--password` etc. are rejected). The service account token is
  only read from the environment by `op` itself. The tool never reads or echoes it. Variables whose names look
  secret-like (KEY, TOKEN, SECRET, PASSWORD, PASS, PRIVATE, CREDENTIAL) are refused for substitution.
- Write inside scanned repos (asserted in tests by checksumming fixtures). Only a private temp dir (mode 0700,
  removed on exit) holds reference names, never values.
- Send telemetry or make network calls itself. The only network traffic is `op`'s.

## What can leak anyway
- Reference text (vault/item/field names) appears in reports and CI logs. Those are metadata, not secrets, but in
  public repos prefer `op://$OP_VAULT/...` (lint warns with `--public`).
- A one-line sanitized first line of `op`'s own stderr is shown for unclassified errors. `op` does not print secret
  values in errors as far as is known (**UNVERIFIED**).
- JSON reports reveal which references exist and which are broken. Treat them like logs.

## Quota and rate limits
Personal-plan service accounts: 1,000 requests/day/account, 100 writes/hour (writes are never used). Reads by name
cost 3 per item, by ID 1. op-doctor makes one call per distinct vault+item, caches vault-level failures, refuses
plans above `--max-requests` (default 200), and `--dry-run` shows the cost first. Run live checks at most daily.
A rate-limit response stops the run and exits 3.

## Service account scope
Create a service account with read-only access to only the vaults your references use. If the token leaks, that
is its blast radius. Use a CI secret named `OP_SERVICE_ACCOUNT_TOKEN`; never commit it.
