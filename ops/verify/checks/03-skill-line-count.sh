#!/usr/bin/env bash
# ops/verify/checks/03-skill-line-count.sh — 根 SKILL.md 不超过 150 行（v3 协议适配层硬约束）
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="03-skill-line-count"
SEVERITY="error"
MAX_LINES=150

emit() {
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$2" "$SEVERITY"
}

skill="$ROOT/SKILL.md"
if [ ! -f "$skill" ]; then
  emit "fail" "SKILL.md not found at $skill"
  exit 2
fi

lines="$(wc -l < "$skill" | tr -d ' ')"

if [ "$lines" -gt "$MAX_LINES" ]; then
  emit "fail" "SKILL.md has ${lines} lines (>${MAX_LINES})"
  exit 2
fi

emit "pass" "SKILL.md has ${lines} lines (<=${MAX_LINES})"
exit 0
