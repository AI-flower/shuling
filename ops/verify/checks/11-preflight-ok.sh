#!/usr/bin/env bash
# ops/verify/checks/11-preflight-ok.sh — preflight.py --json 退出码 ≤2 (≥3 视为 fail)
# severity: warn
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="11-preflight-ok"
SEVERITY="warn"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

script="$ROOT/agent/scripts/preflight.py"
if [ ! -f "$script" ]; then
  emit "fail" "agent/scripts/preflight.py not found"
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  emit "fail" "python3 not on PATH"
  exit 2
fi

# 不让 set -e 因 preflight 非零退出而终止本脚本
set +e
out="$(python3 "$script" --json 2>&1)"
rc=$?
set -e

case "$rc" in
  0)
    emit "pass" "preflight all green (exit=0)"
    exit 0
    ;;
  1|2)
    emit "warn" "preflight returned exit=${rc} (auto-fixable / need-user)"
    exit 1
    ;;
  *)
    emit "fail" "preflight exit=${rc}, output=${out:0:200}"
    exit 2
    ;;
esac
