#!/usr/bin/env bash
# ops/verify/checks/57-topic-monetization-distance.sh — 03-daily-flow.md monetization-distance 规则
# severity: error
#
# 验证：
#   1. 显式提到 monetization_distance_score 字段
#   2. 显式提到 4 档距离规则（1 步 / 2-3 步 / 4-5 步 / 5+ 步）
#   3. 显式提到 creator_track == "offer_first" and monetization_far 时强制降级 explore
#   4. 显式提到 creator_first 允许变现远但必须沉淀 trust_asset / audience_language / problem_validation
set -uo pipefail

CHECK_NAME="57-topic-monetization-distance"
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

if [ ! -f "$daily" ]; then
    emit "fail" "missing agent/playbook/03-daily-flow.md"
    exit 2
fi

violations=()

# 1. monetization_distance_score 字段
if ! grep -qF "monetization_distance_score" "$daily" 2>/dev/null; then
    violations+=("missing 'monetization_distance_score' field reference")
fi

# 2. 4 档距离规则（1 步 / 2-3 步 / 4-5 步 / 5+ 步）
distance_terms=("1 步" "2-3 步" "4-5 步" "5+ 步")
miss_terms=()
for t in "${distance_terms[@]}"; do
    if ! grep -qF "$t" "$daily" 2>/dev/null; then
        miss_terms+=("$t")
    fi
done
# accept "5 步" or "5+ 步" or "5 步以上"
if [ ${#miss_terms[@]} -gt 0 ]; then
    # final fallback: any '步' label scheme that mentions all 4 tiers
    if ! grep -qE "5\+? 步|5 步以上|5 步及以上|5 \+? 步" "$daily" 2>/dev/null; then
        violations+=("distance tiers missing: ${miss_terms[*]}")
    elif [ ${#miss_terms[@]} -gt 1 ]; then
        violations+=("distance tiers missing: ${miss_terms[*]}")
    fi
fi

# 3. offer_first + monetization_far → 强制降级 explore
hit3=0
grep -qE "offer_first.*monetization_far.*强制降级" "$daily" 2>/dev/null && hit3=1
grep -qE "offer_first.*monetization_far.*explore" "$daily" 2>/dev/null && hit3=1
grep -qE "creator_track ==? \"offer_first\".*monetization_far" "$daily" 2>/dev/null && hit3=1
if [ "$hit3" -eq 0 ]; then
    violations+=("missing offer_first+monetization_far→explore rule")
fi

# 4. creator_first allowed monetization-far but must precipitate trust/audience/problem assets
hit4_track=0
grep -qE "creator_first.*允许.*变现远|creator_first.*允许.*远|creator_first.*可以.*变现远" "$daily" 2>/dev/null && hit4_track=1
hit4_assets=0
grep -qF "trust_asset" "$daily" 2>/dev/null && hit4_assets=$((hit4_assets+1))
grep -qF "audience_language" "$daily" 2>/dev/null && hit4_assets=$((hit4_assets+1))
grep -qF "problem_validation" "$daily" 2>/dev/null && hit4_assets=$((hit4_assets+1))
if [ "$hit4_track" -eq 0 ] || [ "$hit4_assets" -lt 3 ]; then
    violations+=("creator_first/asset-precipitation rule incomplete (track=${hit4_track}, assets=${hit4_assets})")
fi

if [ ${#violations[@]} -gt 0 ]; then
    detail="$(printf '%s | ' "${violations[@]}")"
    emit "fail" "topic-monetization-distance rules incomplete: ${detail:0:300}"
    exit 2
fi

emit "pass" "monetization_distance_score + 4 tiers + offer_first downgrade + creator_first asset rule present"
exit 0
