#!/usr/bin/env bash
# ops/verify/checks/06-playbook-calls-exist.sh — frontmatter calls.scripts/calls.playbooks 引用必须真实存在
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="06-playbook-calls-exist"
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

# 提取 frontmatter 中某个嵌套数组：第一个参数 file，第二个 outer key (calls)，第三个 inner key (scripts/playbooks)
extract_list() {
  local f="$1" outer="$2" inner="$3"
  awk -v outer="$outer" -v inner="$inner" '
    NR==1 && /^---$/ {fm=1; next}
    fm && /^---$/ {exit}
    fm {
      # outer key (顶层)
      if ($0 ~ "^"outer":[[:space:]]*$") { in_outer=1; next }
      if (in_outer && $0 ~ "^[A-Za-z0-9_-]+:") { in_outer=0 }
      if (in_outer && $0 ~ "^[[:space:]]+"inner":[[:space:]]*$") { in_inner=1; next }
      # 退出 inner: 出现新的 2-space key 或 顶层 key
      if (in_inner && $0 ~ "^[[:space:]]+[A-Za-z0-9_-]+:") {
        # 仍在 outer 内的下一个 inner 键 -> 关闭
        in_inner=0
      }
      if (in_inner && $0 ~ "^[[:space:]]*-[[:space:]]+") {
        line=$0
        sub(/^[[:space:]]*-[[:space:]]+/, "", line)
        gsub(/^["'\'']|["'\'']$/, "", line)
        # 去掉行尾注释
        sub(/[[:space:]]+#.*$/, "", line)
        if (length(line)) print line
      }
    }
  ' "$f"
}

shopt -s nullglob
files=( "$dir"/0[0-9]*.md )

bad=()
total_refs=0
for f in "${files[@]}"; do
  base="$(basename "$f")"

  while IFS= read -r script_path; do
    [ -z "$script_path" ] && continue
    total_refs=$((total_refs + 1))
    abs="$ROOT/$script_path"
    if [ ! -e "$abs" ]; then
      bad+=("${base}:script:${script_path}")
    fi
  done < <(extract_list "$f" "calls" "scripts")

  while IFS= read -r pb_ref; do
    [ -z "$pb_ref" ] && continue
    total_refs=$((total_refs + 1))
    # 允许引用为相对 playbook 名 (XX-name.md) 或带路径
    if [[ "$pb_ref" == */* ]]; then
      abs="$ROOT/$pb_ref"
    else
      abs="$dir/$pb_ref"
    fi
    if [ ! -e "$abs" ]; then
      bad+=("${base}:playbook:${pb_ref}")
    fi
  done < <(extract_list "$f" "calls" "playbooks")
done

if [ ${#bad[@]} -gt 0 ]; then
  emit "fail" "broken refs: ${bad[*]}"
  exit 2
fi

emit "pass" "${total_refs} call refs all resolve"
exit 0
