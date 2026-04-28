#!/usr/bin/env bash
# ops/verify/checks/08-ensure-runtime-layout-dryrun.sh — db.sh ensure-runtime-layout --dry-run --json 必须 OK
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="08-ensure-runtime-layout-dryrun"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

script="$ROOT/agent/scripts/db.sh"
if [ ! -x "$script" ]; then
  emit "fail" "agent/scripts/db.sh missing or not executable"
  exit 2
fi

out="$(bash "$script" ensure-runtime-layout --dry-run --json 2>&1)" || rc=$?
rc="${rc:-0}"

if [ "$rc" -ne 0 ]; then
  emit "fail" "exit=${rc}, output=${out:0:200}"
  exit 2
fi

# JSON sanity: 包含 "status"
if ! printf '%s' "$out" | grep -q '"status"'; then
  emit "fail" "JSON missing status field, output=${out:0:200}"
  exit 2
fi

emit "pass" "ensure-runtime-layout dry-run returned status JSON"
exit 0
