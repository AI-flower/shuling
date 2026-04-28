#!/usr/bin/env bash
# ops/verify/checks/17-active-region-no-tech-bias.sh — active .md 不出现 v2 默认 prompt 偏置词
# severity: warn
set -euo pipefail

CHECK_NAME="17-active-region-no-tech-bias"
SEVERITY="warn"

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

TMPLIST="$(mktemp)"
trap 'rm -f "$TMPLIST"' EXIT

# 收集 active .md 文件，跳过 inactive / 营销 / 归档区与 docs/adr docs/plans
{
    [ -f "$ROOT/SKILL.md" ] && printf '%s\n' "$ROOT/SKILL.md"
    for d in agent ops build; do
        if [ -d "$ROOT/$d" ]; then
            find "$ROOT/$d" -type f -name '*.md'
        fi
    done
} > "$TMPLIST"

# 偏置词列表（中英混合；用 grep -E 多分支）
# 仅捕"默认 prompt 偏置内容"——不含合法平台名 / 合法受众示例
# - "程序员" 在 audience 示例中合法（与 "宝妈"、"职场新人" 并列），不该捕
# - "OpenClaw" 是真实平台名（与 Hermes / Claude Code / Codex 并列），不该捕
PATTERN='AI 工具推荐|AI工具推荐|GitHub trending|GitHub Trending|科技博主'

VIOLATIONS=0
VIOL_SAMPLE=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        */ops/verify/checks/*) continue ;;
        */docs/adr/*|*/docs/plans/*) continue ;;
    esac
    if grep -E -l "$PATTERN" "$f" >/dev/null 2>&1; then
        VIOLATIONS=$((VIOLATIONS+1))
        if [ -z "$VIOL_SAMPLE" ]; then
            VIOL_SAMPLE="${f#$ROOT/}"
        fi
    fi
done < "$TMPLIST"

if [ "$VIOLATIONS" -eq 0 ]; then
    emit "pass" "no v2 prompt bias terms in active .md"
    exit 0
else
    emit "warn" "$VIOLATIONS active .md file(s) contain v2 bias terms (e.g. $VIOL_SAMPLE)"
    exit 1
fi
