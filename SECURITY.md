# Security Policy

Report vulnerabilities privately via GitHub: **Security tab -> Report a vulnerability**. Do not open a public
issue. Expect an acknowledgement within a few days.

Most relevant classes: anything that causes a secret value to be printed, logged, cached or written; writes inside
a scanned repository; command injection through file contents or reference text. Never include live secrets in a
report; redact them.

Supported: latest release / `main`.
