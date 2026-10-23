# Contributing

- Bash 3.2 compatible (macOS) and Linux; dependencies: bash, git, awk/sed/grep, jq, and `op` (live checks only).
- `bash tests/run.sh` must pass. Tests use a fake `op` (tests/fixtures/op) and generate secrets at run time; never
  add real or secret-looking literals, real vault/item names, or personal data.
- Conventional Commits for commits and PR titles (`feat(check): ...`, `fix: ...`). Branches: `type/slug`.
- Behavior changes: update docs/SCHEMA.md, AGENTS.md, CHANGELOG.md.

## Developer Certificate of Origin
Sign off every commit (`git commit -s`), certifying you wrote it or may submit it under Apache-2.0
(<https://developercertificate.org/>). Fix a branch with `git rebase --signoff main`.
