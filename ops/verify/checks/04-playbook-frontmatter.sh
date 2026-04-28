#!/usr/bin/env bash
# ops/verify/checks/04-playbook-frontmatter.sh — agent/playbook/0X*.md 必须有 frontmatter（id/title/when/version）
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="04-playbook-frontmatter"
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
  emit "fail" "no playbook 0X.md files under agent/playbook/"
  exit 2
fi

bad=()
required_keys=(id title when version)

for f in "${files[@]}"; do
  base="$(basename "$f")"
  first_line="$(head -n 1 "$f")"
  if [ "$first_line" != "---" ]; then
    bad+=("${base}:no-frontmatter")
    continue
  fi
  fm="$(awk 'NR==1 && /^---$/ {flag=1; next} flag && /^---$/ {exit} flag {print}' "$f")"
  if [ -z "$fm" ]; then
    bad+=("${base}:empty-frontmatter")
    continue
  fi
  for key in "${required_keys[@]}"; do
    if ! printf '%s\n' "$fm" | grep -Eq "^${key}:[[:space:]]*"; then
      bad+=("${base}:missing-${key}")
    fi
  done
done

if [ ${#bad[@]} -gt 0 ]; then
  emit "fail" "playbook frontmatter issues: ${bad[*]}"
  exit 2
fi

emit "pass" "${#files[@]} playbooks have id/title/when/version"
exit 0
