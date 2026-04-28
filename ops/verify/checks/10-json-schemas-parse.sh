#!/usr/bin/env bash
# ops/verify/checks/10-json-schemas-parse.sh — agent/schemas/*.json 都能被 python json.tool 解析
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="10-json-schemas-parse"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

dir="$ROOT/agent/schemas"
if [ ! -d "$dir" ]; then
  emit "fail" "agent/schemas/ not found"
  exit 2
fi

shopt -s nullglob
files=( "$dir"/*.json )
if [ ${#files[@]} -eq 0 ]; then
  emit "fail" "no *.json under agent/schemas/"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  emit "fail" "python3 not on PATH"
  exit 2
fi

bad=()
for f in "${files[@]}"; do
  if ! python3 -m json.tool "$f" >/dev/null 2>&1; then
    bad+=("$(basename "$f")")
  fi
done

if [ ${#bad[@]} -gt 0 ]; then
  emit "fail" "invalid JSON: ${bad[*]}"
  exit 2
fi

emit "pass" "${#files[@]} schema files parse OK"
exit 0
