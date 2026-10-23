# JSON schema `op-doctor/v1`

`--json` prints exactly one JSON document to stdout (diagnostics go to stderr). Keys are stable within `v1`;
new keys may be added, none removed or retyped. **Values of secrets never appear.** Every key below is always
present (arrays are empty when a command does not produce them).

```
{
  "schema": "op-doctor/v1",
  "version": "0.1.0",
  "command": "scan|lint|check|doctor|roots",
  "exit_code": 0,
  "dry_run": false,
  "roots":      [{"path": str, "name": str, "status": "scanned|excluded|error", "detail": str|null}],
  "references": [{"root": str, "file": str, "line": int, "variable": str|null, "ref": str,
                  "parse": "ok|malformed", "parse_detail": str|null,
                  "vault": str|null, "item": str|null, "section": str|null, "field": str|null,
                  "query": str|null}],
  "findings":   [{"root": str, "file": str, "line": int|null, "code": "L001|L002|L003|L004",
                  "severity": "error|warning", "key": str|null, "message": str}],
  "checks":     [{"ref": str, "state": "ok|empty|missing-item|missing-field|missing-vault|denied|unresolved-variable|error",
                  "detail": str|null, "locations": [{"root": str, "file": str, "line": int, "variable": str|null}]}],
  "plan":       {"items": int, "requests_estimated": int, "max_requests": int} | null,
  "errors":     [{"code": "op-unavailable|root|roots|rootsfile", "message": str}],
  "summary": {"roots": int, "references": int, "distinct_references": int,
              "lint_errors": int, "lint_warnings": int,
              "states": {"ok": int, "empty": int, "missing-item": int, "missing-field": int,
                         "missing-vault": int, "denied": int, "unresolved-variable": int, "error": int},
              "requests_used": int}
}
```

- `references[].ref`, `vault`, `item`, `section`, `field` are the reference text as written (variables like `$OP_VAULT`
  are not substituted). `file` is relative to its `root`. `variable` is the `KEY` of a `KEY=op://...` line.
- `checks` has one entry per distinct reference text; `locations` lists every occurrence. `plan` is non-null for
  `check`/`doctor`. `requests_estimated` is an upper bound (3 per item by name, 1 by ID).
- Lint codes: `L001` malformed reference (error); `L002` tracked plaintext env file (error); `L003` plaintext
  secret-like value in an env-style file (error; `key` names the variable, the value is never printed);
  `L004` hardcoded vault name in a public repo (warning).
- `checks[].detail` for `error` may carry a short sanitized first line of `op`'s stderr (never a value), or
  `op-unavailable`, `op-ratelimited`, `max-requests-reached`, `malformed-reference: ...`, `not-checked: ...`.
- Exit codes: see AGENTS.md.
