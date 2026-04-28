#!/usr/bin/env bash
# ops/verify/checks/34-optional-fallback.sh — needs.optional 必须配 fallback（ADR-0002 D5）
# severity: error
#
# 任何 frontmatter 含 needs.optional: 字段的 playbook，必须含 fallback: 字段（在 needs 块内或顶级均可）
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="34-optional-fallback"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

dir="$ROOT/agent/playbook"
if [ ! -d "$dir" ]; then
  emit "fail" "agent/playbook/ not found"
  exit 2
fi

violations=()

while IFS= read -r f; do
  [ -z "$f" ] && continue
  base="$(basename "$f")"
  # 提取 frontmatter
  fm="$(awk 'NR==1 && /^---$/ {flag=1; next} flag && /^---$/ {exit} flag {print}' "$f")"
  [ -z "$fm" ] && continue

  # 是否在 needs 块下出现 optional:
  has_optional="$(printf '%s\n' "$fm" | awk '
    /^needs:[[:space:]]*$/ {flag=1; next}
    flag && /^[A-Za-z0-9_-]+:/ {flag=0}
    flag && /^[[:space:]]+optional:/ {print "y"; exit}
  ')"

  [ "$has_optional" != "y" ] && continue

  # 必须存在 fallback:（任何缩进任何位置，作为 yaml key）
  has_fallback="$(printf '%s\n' "$fm" | grep -Eq '^[[:space:]]*fallback:' && echo y || echo n)"
  if [ "$has_fallback" != "y" ]; then
    violations+=("$base")
  fi
done < <(find "$dir" -maxdepth 1 -type f -name "0[0-9]*.md" 2>/dev/null)

if [ ${#violations[@]} -gt 0 ]; then
  emit "fail" "optional without fallback: ${violations[*]}"
  exit 2
fi

emit "pass" "all needs.optional declarations have fallback"
exit 0
