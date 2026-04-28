#!/usr/bin/env bash
# ops/verify/checks/27-migration-isolation.sh — migration / upgrade-hook 目录隔离
# severity: error
#
# 规则：
#   agent/migrations/db/    仅 .sh / .sql / README.md
#   agent/migrations/state/ 仅 .sh + README.md（含子目录里的 .sh）
#   ops/upgrade-hooks/      仅 .sh + README.md（含子目录里的 .sh）
#   db/ vs state/ 同名 hook（不含扩展名）禁止重叠
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="27-migration-isolation"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

db_dir="$ROOT/agent/migrations/db"
state_dir="$ROOT/agent/migrations/state"
hooks_dir="$ROOT/ops/upgrade-hooks"

violations=()

# ─── db/: .sh .sql README.md ──────────────────────
if [ -d "$db_dir" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base="$(basename "$f")"
    case "$base" in
      *.sh|*.sql|README.md) ;;
      *) violations+=("db/${base}") ;;
    esac
  done < <(find "$db_dir" -maxdepth 1 -type f 2>/dev/null)
fi

# ─── state/: .sh README.md（含子目录递归） ───────
if [ -d "$state_dir" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base="$(basename "$f")"
    rel="${f#$state_dir/}"
    case "$base" in
      *.sh|README.md) ;;
      *) violations+=("state/${rel}") ;;
    esac
  done < <(find "$state_dir" -type f 2>/dev/null)
fi

# ─── upgrade-hooks/: .sh README.md（含子目录递归） ───
if [ -d "$hooks_dir" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base="$(basename "$f")"
    rel="${f#$hooks_dir/}"
    case "$base" in
      *.sh|README.md) ;;
      *) violations+=("upgrade-hooks/${rel}") ;;
    esac
  done < <(find "$hooks_dir" -type f 2>/dev/null)
fi

# ─── db/ 与 state/ 不允许重叠（按 stem 比较） ────
declare -a db_stems=()
declare -a state_stems=()
if [ -d "$db_dir" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    stem="$(basename "$f")"
    stem="${stem%.*}"
    db_stems+=("$stem")
  done < <(find "$db_dir" -maxdepth 1 -type f -name "*.sh" 2>/dev/null)
fi
if [ -d "$state_dir" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    stem="$(basename "$f")"
    stem="${stem%.*}"
    state_stems+=("$stem")
  done < <(find "$state_dir" -type f -name "*.sh" 2>/dev/null)
fi

if [ ${#db_stems[@]} -gt 0 ] && [ ${#state_stems[@]} -gt 0 ]; then
  for s in "${db_stems[@]}"; do
    [ "$s" = "_guard" ] && continue
    [ "$s" = "README" ] && continue
    for t in "${state_stems[@]}"; do
      if [ "$s" = "$t" ]; then
        violations+=("overlap:${s}")
      fi
    done
  done
fi

if [ ${#violations[@]} -gt 0 ]; then
  emit "fail" "migration isolation violated: ${violations[*]}"
  exit 2
fi

emit "pass" "migrations/db, migrations/state, ops/upgrade-hooks all isolated"
exit 0
