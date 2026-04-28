#!/usr/bin/env bash
# ops/verify/checks/16-active-region-no-legacy-refs.sh — 扫描 active 区域不允许引用 legacy/ 或 docs/archive/
# severity: error
set -euo pipefail

CHECK_NAME="16-active-region-no-legacy-refs"
SEVERITY="error"

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

emit() {
    local status="$1" message="$2"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

if [ ! -d "$ROOT" ]; then
    emit "fail" "repo root not found: $ROOT"
    exit 2
fi

# Active 区域：根 SKILL.md + agent/ + ops/ + build/
declare -a TARGETS=()
[ -f "$ROOT/SKILL.md" ] && TARGETS+=("$ROOT/SKILL.md")
[ -d "$ROOT/agent" ]   && TARGETS+=("$ROOT/agent")
[ -d "$ROOT/ops" ]     && TARGETS+=("$ROOT/ops")
[ -d "$ROOT/build" ]   && TARGETS+=("$ROOT/build")

if [ "${#TARGETS[@]}" -eq 0 ]; then
    emit "fail" "no active region found under $ROOT"
    exit 2
fi

# 收集 .md / .sh / .py 文件
TMPLIST="$(mktemp)"
trap 'rm -f "$TMPLIST"' EXIT

for t in "${TARGETS[@]}"; do
    if [ -f "$t" ]; then
        printf '%s\n' "$t" >> "$TMPLIST"
    else
        # 排除 docs/adr docs/plans (inactive — 但它们不在 active 列表内此处其实无关)
        find "$t" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.py' \) >> "$TMPLIST"
    fi
done

VIOLATIONS=0
VIOL_SAMPLE=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    # 自排除：本 check 脚本含 legacy/ 关键字会误命中
    case "$f" in
        */ops/verify/checks/*) continue ;;
        # build/README.md 解释 build 工具职责，必须能写 legacy/ docs/archive/ 路径名
        */build/README.md) continue ;;
        # build/check-active-region-refs.py 自身就是扫描 inactive 路径的工具
        */build/check-active-region-refs.py) continue ;;
    esac
    if grep -E -l '(^|[^a-zA-Z0-9_/-])(legacy/|docs/archive/)' "$f" >/dev/null 2>&1; then
        VIOLATIONS=$((VIOLATIONS+1))
        if [ -z "$VIOL_SAMPLE" ]; then
            VIOL_SAMPLE="${f#$ROOT/}"
        fi
    fi
done < "$TMPLIST"

if [ "$VIOLATIONS" -eq 0 ]; then
    emit "pass" "no legacy/ or docs/archive/ refs in active region"
    exit 0
else
    emit "fail" "$VIOLATIONS active file(s) reference legacy/ or docs/archive/ (e.g. $VIOL_SAMPLE)"
    exit 2
fi
