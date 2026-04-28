#!/usr/bin/env bash
# ops/verify/checks/02-skill-version-match.sh — SKILL.md frontmatter version 与根 VERSION 文件一致
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="02-skill-version-match"
SEVERITY="error"

emit() {
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$2" "$SEVERITY"
}

skill="$ROOT/SKILL.md"
ver="$ROOT/VERSION"

if [ ! -f "$skill" ]; then
  emit "fail" "SKILL.md not found at $skill"
  exit 2
fi
if [ ! -f "$ver" ]; then
  emit "fail" "VERSION not found at $ver"
  exit 2
fi

# frontmatter version
fm_version="$(awk 'NR==1 && /^---$/ {flag=1; next} flag && /^---$/ {exit} flag' "$skill" \
  | grep -E '^version:[[:space:]]*' | head -n 1 | sed -E 's/^version:[[:space:]]*//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//' | tr -d '[:space:]')"

if [ -z "$fm_version" ]; then
  emit "fail" "SKILL.md frontmatter has no version: field"
  exit 2
fi

# VERSION 第一行 version 字段
ver_line="$(grep -E '^version:[[:space:]]*' "$ver" | head -n 1 || true)"
if [ -z "$ver_line" ]; then
  emit "fail" "VERSION has no leading version: field"
  exit 2
fi
ver_value="$(printf '%s' "$ver_line" | sed -E 's/^version:[[:space:]]*//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//' | tr -d '[:space:]')"

if [ "$fm_version" != "$ver_value" ]; then
  emit "fail" "SKILL.md version=${fm_version} but VERSION=${ver_value}"
  exit 2
fi

emit "pass" "SKILL.md and VERSION agree on ${fm_version}"
exit 0
