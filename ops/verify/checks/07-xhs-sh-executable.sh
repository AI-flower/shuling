#!/usr/bin/env bash
# ops/verify/checks/07-xhs-sh-executable.sh — agent/scripts/xhs.sh 存在且可执行
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="07-xhs-sh-executable"
SEVERITY="error"

emit() {
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$2" "$SEVERITY"
}

target="$ROOT/agent/scripts/xhs.sh"
if [ ! -f "$target" ]; then
  emit "fail" "agent/scripts/xhs.sh not found"
  exit 2
fi
if [ ! -x "$target" ]; then
  emit "fail" "agent/scripts/xhs.sh exists but is not executable (chmod +x)"
  exit 2
fi

emit "pass" "agent/scripts/xhs.sh present and executable"
exit 0
