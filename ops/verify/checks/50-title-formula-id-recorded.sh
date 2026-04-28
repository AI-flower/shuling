#!/usr/bin/env bash
# ops/verify/checks/50-title-formula-id-recorded.sh — formula_id 在 daily-flow / publish / db.sh 落地
# severity: error
#
# 验证：
#   1. 03-daily-flow.md 显式提到标题候选必须有 formula_id
#   2. 04-publish-flow.md 显式提到 add-post 写入 title_formula_id / title_trigger / title_intent 三字段
#   3. agent/scripts/db.sh 的 add-post 命令支持这三个字段
set -uo pipefail

CHECK_NAME="50-title-formula-id-recorded"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

daily="$ROOT/agent/playbook/03-daily-flow.md"
pub="$ROOT/agent/playbook/04-publish-flow.md"
db="$ROOT/agent/scripts/db.sh"

for f in "$daily" "$pub" "$db"; do
    if [ ! -f "$f" ]; then
        emit "fail" "missing required file: ${f#$ROOT/}"
        exit 2
    fi
done

violations=()

# 1. daily-flow: formula_id mention
if ! grep -qE "formula_id" "$daily" 2>/dev/null; then
    violations+=("03-daily-flow.md: missing 'formula_id' mention")
fi

# 2. publish-flow: 三字段都得在 add-post 上下文
for col in title_formula_id title_trigger title_intent; do
    if ! grep -qF "$col" "$pub" 2>/dev/null; then
        violations+=("04-publish-flow.md: missing column '${col}'")
    fi
done
if ! grep -qE "add-post" "$pub" 2>/dev/null; then
    violations+=("04-publish-flow.md: missing 'add-post' reference")
fi

# 3. db.sh: 三字段被支持（命令体里 grep 即可）
for col in title_formula_id title_trigger title_intent; do
    if ! grep -qF "$col" "$db" 2>/dev/null; then
        violations+=("agent/scripts/db.sh: missing column '${col}'")
    fi
done

if [ ${#violations[@]} -gt 0 ]; then
    detail="$(printf '%s | ' "${violations[@]}")"
    emit "fail" "title-formula-id recording broken: ${detail:0:300}"
    exit 2
fi

emit "pass" "title formula_id recorded across daily-flow / publish / db.sh"
exit 0
