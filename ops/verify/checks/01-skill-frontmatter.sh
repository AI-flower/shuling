#!/usr/bin/env bash
# ops/verify/checks/01-skill-frontmatter.sh — 根 SKILL.md 必须含 frontmatter + name/description/version
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="01-skill-frontmatter"
SEVERITY="error"

emit() {
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$2" "$SEVERITY"
}

skill="$ROOT/SKILL.md"
if [ ! -f "$skill" ]; then
  emit "fail" "SKILL.md not found at $skill"
  exit 2
fi

# 第一行必须是 ---
first_line="$(head -n 1 "$skill")"
if [ "$first_line" != "---" ]; then
  emit "fail" "SKILL.md does not start with frontmatter (---)"
  exit 2
fi

# 提取 frontmatter 块（第一个 --- 到第二个 ---）
fm="$(awk 'NR==1 && /^---$/ {flag=1; next} flag && /^---$/ {exit} flag {print}' "$skill")"
if [ -z "$fm" ]; then
  emit "fail" "SKILL.md frontmatter is empty or unterminated"
  exit 2
fi

missing=()
for key in name description version; do
  if ! printf '%s\n' "$fm" | grep -Eq "^${key}:[[:space:]]*"; then
    missing+=("$key")
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  emit "fail" "SKILL.md frontmatter missing keys: ${missing[*]}"
  exit 2
fi

emit "pass" "SKILL.md frontmatter has name/description/version"
exit 0
