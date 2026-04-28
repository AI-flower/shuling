#!/usr/bin/env bash
# ops/verify/checks/37-cron-no-auto-publish.sh — ops/cron/*.example 不含自动发布禁用词
# severity: error
set -uo pipefail

CHECK_NAME="37-cron-no-auto-publish"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

cron_dir="$ROOT/ops/cron"
if [ ! -d "$cron_dir" ]; then
    emit "pass" "ops/cron/ not found — nothing to check"
    exit 0
fi

# 扫描 .example 文件 + claude-code.md（如存在）
scan_files=()
while IFS= read -r f; do
    [ -f "$f" ] && scan_files+=("$f")
done < <(find "$cron_dir" -name "*.example" 2>/dev/null)
[ -f "$ROOT/claude-code.md" ] && scan_files+=("$ROOT/claude-code.md")

if [ ${#scan_files[@]} -eq 0 ]; then
    emit "pass" "no cron files to scan"
    exit 0
fi

# 禁用词模式（含中英文）
banned_pattern='执行午间发布流程|执行晚间发布流程|自动发布|publish flow|xhs\.sh publish'

violations=()
for f in "${scan_files[@]}"; do
    hit=$(grep -nE "$banned_pattern" "$f" 2>/dev/null | head -3 || true)
    if [ -n "$hit" ]; then
        fname="$(basename "$f")"
        violations+=("${fname}: ${hit}")
    fi
done

if [ ${#violations[@]} -gt 0 ]; then
    msg="cron files contain auto-publish keywords: ${violations[*]}"
    emit "fail" "${msg:0:300}"
    exit 2
fi

emit "pass" "ops/cron/*.example contain no auto-publish keywords"
exit 0
