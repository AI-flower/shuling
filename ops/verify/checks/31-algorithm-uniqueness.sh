#!/usr/bin/env bash
# ops/verify/checks/31-algorithm-uniqueness.sh — 公式权威唯一（ADR-0002 D1）
# severity: error
#
# 06-learning-loop.md 是 weight / confidence 公式的唯一定义文件。
# 其他 playbook 中禁止出现：
#   - (chosen+1)/(chosen+skipped+2)
#   - concentration × sample_factor
# 豁免：legacy/ docs/adr/ docs/plans/
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="31-algorithm-uniqueness"
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

# 字面字符串两个 — 用 fgrep 风格
needle1='(chosen+1)/(chosen+skipped+2)'
needle2='concentration × sample_factor'

while IFS= read -r f; do
  [ -z "$f" ] && continue
  base="$(basename "$f")"
  # 豁免授权文件本身
  [ "$base" = "06-learning-loop.md" ] && continue
  if grep -F -q "$needle1" "$f" 2>/dev/null; then
    violations+=("${base}:weight-formula")
  fi
  if grep -F -q "$needle2" "$f" 2>/dev/null; then
    violations+=("${base}:confidence-formula")
  fi
done < <(find "$dir" -maxdepth 2 -type f -name "*.md" 2>/dev/null)

if [ ${#violations[@]} -gt 0 ]; then
  emit "fail" "formula leaked outside 06-learning-loop.md: ${violations[*]}"
  exit 2
fi

emit "pass" "weight/confidence formulas only appear in 06-learning-loop.md"
exit 0
