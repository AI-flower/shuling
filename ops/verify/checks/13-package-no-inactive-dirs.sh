#!/usr/bin/env bash
# ops/verify/checks/13-package-no-inactive-dirs.sh — dist/ 不能含 docs/ site/ marketing/ legacy/ ops/ build/
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="13-package-no-inactive-dirs"
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

forbidden=(docs site marketing legacy ops build)

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

found=()
for pkg in "${pkg_dirs[@]}"; do
  pkg_name="$(basename "$pkg")"
  for d in "${forbidden[@]}"; do
    if [ -e "$pkg/$d" ]; then
      found+=("${pkg_name}/${d}")
    fi
  done
done

if [ ${#found[@]} -gt 0 ]; then
  emit "fail" "forbidden dirs in package: ${found[*]}"
  exit 2
fi

emit "pass" "no inactive dirs (docs/site/marketing/legacy/ops/build) in ${#pkg_dirs[@]} package(s)"
exit 0
