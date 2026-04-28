#!/usr/bin/env bash
# ops/verify/checks/54-business-review-evidence-level.sh — 05-review.md 业务归因证据规则
# severity: error
#
# 验证：
#   1. 05-review.md 显式提到 evidence_level 必填
#   2. 05-review.md 显式提到"没有 hard/medium 证据时 sales/lead 不允许标 high"或等价表述
#   3. 05-review.md 显式提到 ≥3 个反模式规则中 4 选 3：
#      高收藏低业务信号 / 低流量高意图 / 高争议低信任 / 高流量低关注
#   4. 06-learning-loop.md 显式说明业务 pattern 不进入 confidence
set -uo pipefail

CHECK_NAME="54-business-review-evidence-level"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

review="$ROOT/agent/playbook/05-review.md"
loop="$ROOT/agent/playbook/06-learning-loop.md"

for f in "$review" "$loop"; do
    if [ ! -f "$f" ]; then
        emit "fail" "missing playbook: ${f#$ROOT/}"
        exit 2
    fi
done

violations=()

# 1. evidence_level 必填
if ! grep -qE "evidence_level.*必填|必填.*evidence_level|evidence_level.*required|required.*evidence_level|evidence_level\*\*必填|evidence_level\*\* \*\*必填" "$review" 2>/dev/null; then
    # also accept generic '必填' near evidence_level on same line
    if ! grep -nE "evidence_level" "$review" 2>/dev/null | grep -q "必填\|required"; then
        violations+=("05-review.md: missing 'evidence_level required/必填' rule")
    fi
fi

# 2. sales/lead 不允许标 high without hard/medium 证据
# 接受多种表达
hits=0
grep -qE "sales_signal.*lead_signal.*evidence_level.*weak.*unknown.*不允许.*high" "$review" 2>/dev/null && hits=$((hits+1))
grep -qE "evidence_level.*∈.*hard.*medium" "$review" 2>/dev/null && hits=$((hits+1))
grep -qE "sales/lead.*一律不能高" "$review" 2>/dev/null && hits=$((hits+1))
grep -qE "没有.*hard/medium.*证据" "$review" 2>/dev/null && hits=$((hits+1))
grep -qE "sales_signal=high.*lead_signal=high.*evidence_level.*hard.*medium" "$review" 2>/dev/null && hits=$((hits+1))
if [ "$hits" -lt 1 ]; then
    violations+=("05-review.md: missing 'sales/lead high requires hard/medium evidence' rule")
fi

# 3. ≥ 3 of 4 anti-patterns
pat_hits=0
grep -qE "高收藏.*低业务|高 ?save.*低 ?business|save.*high.*lead.*low.*sales.*low" "$review" 2>/dev/null && pat_hits=$((pat_hits+1))
grep -qE "低流量.*高意图|low.*traffic.*high.*lead|traffic_signal=low.*lead_signal=high" "$review" 2>/dev/null && pat_hits=$((pat_hits+1))
grep -qE "高争议.*低信任|controversy_signal=high.*trust_signal=low" "$review" 2>/dev/null && pat_hits=$((pat_hits+1))
grep -qE "高流量.*低关注|高流量.*低 ?save|traffic_signal=high.*trust.*low|traffic_signal=high.*lead/sales/trust 全部 low" "$review" 2>/dev/null && pat_hits=$((pat_hits+1))
if [ "$pat_hits" -lt 3 ]; then
    violations+=("05-review.md: anti-patterns <3/4 (got ${pat_hits})")
fi

# 4. 06-learning-loop.md: 业务 pattern 不进入 confidence
loop_ok=0
grep -qE "业务 ?pattern.*不进入" "$loop" 2>/dev/null && loop_ok=1
grep -qE "business[- _]pattern.*不进入" "$loop" 2>/dev/null && loop_ok=1
grep -qE "不进入.*confidence|不进入.*06.*公式|不进入.*preferences\.json" "$loop" 2>/dev/null && loop_ok=1
if [ "$loop_ok" -eq 0 ]; then
    violations+=("06-learning-loop.md: missing 'business pattern not into confidence' rule")
fi

if [ ${#violations[@]} -gt 0 ]; then
    detail="$(printf '%s | ' "${violations[@]}")"
    emit "fail" "business-review evidence-level rules incomplete: ${detail:0:300}"
    exit 2
fi

emit "pass" "evidence_level + sales/lead-high gate + 3/4 anti-patterns + 06 confidence-isolation present"
exit 0
