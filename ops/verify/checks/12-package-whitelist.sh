#!/usr/bin/env bash
# ops/verify/checks/12-package-whitelist.sh — dist/ 下 v3 包顶层只允许 SKILL.md / VERSION / agents/ / agent/
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="12-package-whitelist"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

dist="$ROOT/dist"
if [ ! -d "$dist" ]; then
  emit "pass" "dist/ does not exist (skipped)"
  exit 0
fi

# v3 包目录：dist/* 中含 SKILL.md 的子目录
shopt -s nullglob
pkg_dirs=()
for d in "$dist"/*/; do
  [ -d "$d" ] || continue
  if [ -f "${d}SKILL.md" ]; then
    pkg_dirs+=("${d%/}")
  fi
done

# 没有 v3 包目录就跳过
if [ ${#pkg_dirs[@]} -eq 0 ]; then
  emit "pass" "no v3 package directory under dist/ (skipped)"
  exit 0
fi

allowed_pat='^(SKILL\.md|VERSION|agents|agent)$'

violations=()
for pkg in "${pkg_dirs[@]}"; do
  pkg_name="$(basename "$pkg")"
  for entry in "$pkg"/* "$pkg"/.[!.]* "$pkg"/..?*; do
    [ -e "$entry" ] || continue
    name="$(basename "$entry")"
    if ! [[ "$name" =~ $allowed_pat ]]; then
      violations+=("${pkg_name}/${name}")
    fi
  done
done

if [ ${#violations[@]} -gt 0 ]; then
  emit "fail" "non-whitelisted top-level entries: ${violations[*]}"
  exit 2
fi

emit "pass" "all ${#pkg_dirs[@]} package(s) contain only SKILL.md/VERSION/agents/agent"
exit 0
