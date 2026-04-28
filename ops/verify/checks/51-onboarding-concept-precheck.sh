#!/usr/bin/env bash
# ops/verify/checks/51-onboarding-concept-precheck.sh — 概念预检规则不持久化（关键负向断言）
# severity: error
#
# 验证（关键 negative-rule）：
#   1. 不应在 agent/schemas/ 下出现 concept-clarification.schema.json
#   2. 不应在 agent/knowledge-base/ 下出现 concept-clarifications.md 或类似文件
#   3. 概念预检规则必须出现在 01-onboarding-new.md（触发词清单存在）
#   4. plan §9.6 文档纪律被遵守（不持久化结论）
set -uo pipefail

CHECK_NAME="51-onboarding-concept-precheck"
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
schemas_dir="$ROOT/agent/schemas"
kb_dir="$ROOT/agent/knowledge-base"

if [ ! -f "$new" ]; then
    emit "fail" "missing 01-onboarding-new.md"
    exit 2
fi

violations=()

# 1. 不能存在 concept-clarification.schema.json（或类似命名）
if [ -d "$schemas_dir" ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rel="${f#$ROOT/}"
        violations+=("must-not-exist: ${rel}")
    done < <(find "$schemas_dir" -maxdepth 1 -type f \( \
        -iname "concept-clarification*.json" -o \
        -iname "concept_clarification*.json" -o \
        -iname "concept-precheck*.json" \) 2>/dev/null)
fi

# 2. 不能存在 concept-clarifications.md / concepts/ 文件
if [ -d "$kb_dir" ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rel="${f#$ROOT/}"
        violations+=("must-not-exist: ${rel}")
    done < <(find "$kb_dir" -type f \( \
        -iname "concept-clarification*.md" -o \
        -iname "concept_clarification*.md" -o \
        -iname "concept-clarifications*.md" -o \
        -iname "concepts.md" \) 2>/dev/null)
    if [ -d "$kb_dir/concepts" ]; then
        violations+=("must-not-exist: agent/knowledge-base/concepts/ (directory)")
    fi
fi

# 3. 概念预检规则必须出现在 01-onboarding-new.md 触发词清单
# 任何 3 个触发词出现即视为清单存在
declare -a triggers=("IP" "私域" "精准流量" "赛道" "变现" "副业" "干货" "知识付费")
hits=0
for t in "${triggers[@]}"; do
    if grep -qF "$t" "$new" 2>/dev/null; then
        hits=$((hits + 1))
    fi
done
if [ "$hits" -lt 3 ]; then
    violations+=("01-onboarding-new.md: trigger-keyword list <3 (got ${hits})")
fi
if ! grep -qE "Concept Precheck|概念预检" "$new" 2>/dev/null; then
    violations+=("01-onboarding-new.md: missing Concept Precheck heading")
fi

# 4. 文档纪律：不持久化结论（关键短语必须出现）
if ! grep -qE "不持久化|不单独写文件|不创建.*concept|不写.*concept" "$new" 2>/dev/null; then
    # 也允许在 08-compliance.md 里
    comp="$ROOT/agent/playbook/08-compliance.md"
    if [ ! -f "$comp" ] || ! grep -qE "不持久化|不单独写文件|不创建.*concept|不写.*concept" "$comp" 2>/dev/null; then
        violations+=("non-persistence rule missing in 01-onboarding-new.md or 08-compliance.md")
    fi
fi

if [ ${#violations[@]} -gt 0 ]; then
    detail="$(printf '%s | ' "${violations[@]}")"
    emit "fail" "concept-precheck non-persistence violated: ${detail:0:300}"
    exit 2
fi

emit "pass" "concept-precheck rule present + non-persistence enforced"
exit 0
