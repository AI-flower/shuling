#!/usr/bin/env bash
# ops/verify/checks/49-business-profile-write-precondition.sh — onboarding playbook 概念预检前置规则
# severity: error
#
# 验证：
#   1. 01-onboarding-new.md 与 02-onboarding-existing.md **都**显式提到
#      Concept Precheck / 概念预检 / 触发词清单（IP / 私域 / 精准流量 / 赛道 / 变现 任意 3 个）
#   2. 两份文件**都**显式提到不把黑话原样写入画像（"原样写入" / "拒写" / "不能直接写入" 任一）
#   3. 08-compliance.md 包含 Concept Precheck Rule Validation 段（或等价）
set -uo pipefail

CHECK_NAME="49-business-profile-write-precondition"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

new="$ROOT/agent/playbook/01-onboarding-new.md"
exist="$ROOT/agent/playbook/02-onboarding-existing.md"
comp="$ROOT/agent/playbook/08-compliance.md"

for f in "$new" "$exist" "$comp"; do
    if [ ! -f "$f" ]; then
        emit "fail" "missing required playbook: ${f#$ROOT/}"
        exit 2
    fi
done

# trigger-keyword pool（任意 3 个出现即认为命中"触发词清单"）
declare -a triggers=("IP" "私域" "精准流量" "赛道" "变现")

count_trigger_hits() {
    local file="$1"
    local hits=0
    for t in "${triggers[@]}"; do
        if grep -qF "$t" "$file" 2>/dev/null; then
            hits=$((hits + 1))
        fi
    done
    echo "$hits"
}

violations=()

for f in "$new" "$exist"; do
    rel="${f#$ROOT/}"
    # 1. Concept Precheck / 概念预检 任一出现
    if ! grep -qE "Concept Precheck|概念预检|问题消解" "$f" 2>/dev/null; then
        violations+=("${rel}: missing Concept Precheck section")
    fi
    # 2. 触发词清单 ≥ 3 个
    h=$(count_trigger_hits "$f")
    if [ "$h" -lt 3 ]; then
        violations+=("${rel}: trigger keywords <3 (got ${h})")
    fi
    # 3. 不把黑话原样写入
    if ! grep -qE "原样写入|拒写|不能直接写入|不允许.*写入|禁止.*塞" "$f" 2>/dev/null; then
        violations+=("${rel}: missing 'cannot write raw jargon' clause")
    fi
done

# compliance.md
if ! grep -qE "Concept Precheck Rule Validation|概念预检规则" "$comp" 2>/dev/null; then
    violations+=("08-compliance.md: missing Concept Precheck Rule Validation section")
fi

if [ ${#violations[@]} -gt 0 ]; then
    detail="$(printf '%s | ' "${violations[@]}")"
    emit "fail" "concept-precheck preconditions violated: ${detail:0:300}"
    exit 2
fi

emit "pass" "concept-precheck preconditions present in onboarding + compliance"
exit 0
