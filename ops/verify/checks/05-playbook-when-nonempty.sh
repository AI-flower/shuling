#!/usr/bin/env bash
# ops/verify/checks/05-playbook-when-nonempty.sh — 每个 playbook frontmatter 的 when 数组非空
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="05-playbook-when-nonempty"
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

shopt -s nullglob
files=( "$dir"/0[0-9]*.md )
if [ ${#files[@]} -eq 0 ]; then
  emit "fail" "no playbook 0X.md files"
  exit 2
fi

bad=()
for f in "${files[@]}"; do
  base="$(basename "$f")"
  # 提取 frontmatter 中 when: 块（直到下一个非缩进 key 或 frontmatter 结束）
  block="$(awk '
    NR==1 && /^---$/ {fm=1; next}
    fm && /^---$/ {exit}
    fm && /^when:[[:space:]]*$/ {cap=1; next}
    fm && cap && /^[A-Za-z0-9_-]+:/ {cap=0}
    fm && cap {print}
  ' "$f")"

  # 数组 item: 以 "- " 起头（允许前导空格）
  count="$(printf '%s\n' "$block" | grep -cE '^[[:space:]]*-[[:space:]]+' || true)"
  if [ "${count:-0}" -lt 1 ]; then
    bad+=("${base}")
  fi
done

if [ ${#bad[@]} -gt 0 ]; then
  emit "fail" "playbooks with empty when[]: ${bad[*]}"
  exit 2
fi

emit "pass" "all ${#files[@]} playbooks have non-empty when[]"
exit 0
