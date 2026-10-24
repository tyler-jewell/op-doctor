# op-doctor

Healthchecks for `op://` secret references. Lint repos for plaintext env files, verify every reference resolves to a set value.

```mermaid
flowchart LR
  L[lint] -->|scan tracked files| E[.env files]
  C[check] -->|resolve| R[op:// refs]
  L -->|block<|end|> P[plaintext secrets]
  C -->|report| U[unset refs]
```

## Quickstart

```sh
op-doctor lint --json              # scan for plaintext .env files
op-doctor check --json             # verify all op:// refs resolve
op-doctor check --all-active       # check all tyler-jewell repos
```

## What it does

- **lint**: finds plaintext `.env`/`.env.*` files in tracked repos
- **check**: resolves every `op://vault/item/field` reference via 1Password CLI
- Never prints secret values, never writes to repos, read-only

## Compatibility

Requires `op` (1Password CLI). Node >= 22. Tests: `bash tests/run.sh`.

License: Apache-2.0.