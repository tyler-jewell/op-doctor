#!/usr/bin/env bash
# Daily live healthcheck wrapper (used by dev.op-doctor.check.plist.tmpl). Not installed by default.
# Writes a JSON report (never contains values) and notifies via osascript only on failure.
# Token: OP_SERVICE_ACCOUNT_TOKEN must already be in the environment, or put the token alone in a
# file readable only by you and point OP_DOCTOR_TOKEN_FILE at it (chmod 600). Never in the plist.
here="$(cd "$(dirname "$0")/../.." && pwd)"
logs="$HOME/Library/Logs/op-doctor"; mkdir -p "$logs"
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && [ -n "${OP_DOCTOR_TOKEN_FILE:-}" ] && [ -r "$OP_DOCTOR_TOKEN_FILE" ]; then
  OP_SERVICE_ACCOUNT_TOKEN="$(cat "$OP_DOCTOR_TOKEN_FILE")"; export OP_SERVICE_ACCOUNT_TOKEN
fi
report="$logs/report-$(date +%Y%m%d).json"
"$here/bin/op-doctor" doctor --all --json --max-requests "${OP_DOCTOR_MAX_REQUESTS:-150}" > "$report" 2> "$logs/last.err"
rc=$?
ln -sf "$report" "$logs/latest.json"
find "$logs" -name 'report-*.json' -mtime +30 -delete 2>/dev/null
if [ "$rc" != 0 ] && command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"op-doctor exit $rc - see $logs/latest.json\" with title \"op-doctor\"" >/dev/null 2>&1
fi
exit "$rc"
