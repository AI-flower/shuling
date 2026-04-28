#!/usr/bin/env bash
# ops/verify/checks/14-package-no-user-state.sh — dist/ 包内不能含用户态数据（DB/runtime.env/knowledge-base 实文件）
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="14-package-no-user-state"
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

shopt -s nullglob
pkg_dirs=()
for d in "$dist"/*/; do
  [ -d "$d" ] || continue
  if [ -f "${d}SKILL.md" ]; then
    pkg_dirs+=("${d%/}")
  fi
done

if [ ${#pkg_dirs[@]} -eq 0 ]; then
  emit "pass" "no v3 package directory under dist/ (skipped)"
  exit 0
fi

violations=()
for pkg in "${pkg_dirs[@]}"; do
  pkg_name="$(basename "$pkg")"

  # agent/data/*.db
  for f in "$pkg/agent/data/"*.db; do
    [ -e "$f" ] && violations+=("${pkg_name}/agent/data/$(basename "$f")")
  done

  # agent/config/runtime.env
  if [ -e "$pkg/agent/config/runtime.env" ]; then
    violations+=("${pkg_name}/agent/config/runtime.env")
  fi

  # agent/knowledge-base/*.json|*.md (.gitkeep 豁免)
  if [ -d "$pkg/agent/knowledge-base" ]; then
    for f in "$pkg/agent/knowledge-base/"*.json "$pkg/agent/knowledge-base/"*.md; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      if [ "$base" != ".gitkeep" ]; then
        violations+=("${pkg_name}/agent/knowledge-base/${base}")
      fi
    done
  fi
done

if [ ${#violations[@]} -gt 0 ]; then
  emit "fail" "user state in package: ${violations[*]}"
  exit 2
fi

emit "pass" "no user state files in ${#pkg_dirs[@]} package(s)"
exit 0
