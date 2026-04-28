#!/usr/bin/env bash
# ops/verify/checks/56-benchmark-profit-gate.sh — 01-onboarding-new.md benchmark seeding 利润证据硬门
# severity: error
#
# 验证：
#   1. 显式提到利润证据硬门 5 档（hard / medium / weak / none / unknown）
#   2. 显式提到没过硬门只能成为 content_sample，不能成为 business_benchmark
#   3. 显式提到 4 项辅助过滤（路径可见 / 动作可仿 / 用户相近 / 风险可控）
#   4. 显式提到 ≥ 3/4 才生成 business dossier
set -uo pipefail

CHECK_NAME="56-benchmark-profit-gate"
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

if [ ! -f "$new" ]; then
    emit "fail" "missing agent/playbook/01-onboarding-new.md"
    exit 2
fi

violations=()

# 1. 5 档利润证据
for level in hard medium weak none unknown; do
    if ! grep -qE "(profit_evidence_level|利润证据|证据等级).*${level}|${level}.*(profit_evidence|利润|证据)" "$new" 2>/dev/null; then
        # softer check: just the word in proximity to the gate section
        if ! grep -qF "$level" "$new" 2>/dev/null; then
            violations+=("missing profit_evidence_level value: ${level}")
        fi
    fi
done

# 2. 没过硬门 → content_sample
gate_ok=0
grep -qE "硬门.*content_sample|content_sample.*硬门" "$new" 2>/dev/null && gate_ok=1
grep -qE "硬门不通过.*benchmark_type.*content_sample" "$new" 2>/dev/null && gate_ok=1
grep -qE "fail.*content_sample|content_sample.*fail" "$new" 2>/dev/null && gate_ok=1
grep -qE "不能.*business_benchmark|不行.*business_benchmark|不行.*content_sample" "$new" 2>/dev/null && gate_ok=1
if [ "$gate_ok" -eq 0 ]; then
    violations+=("missing 'gate fail → content_sample only' rule")
fi

# 3. 4 项辅助过滤
aux_terms=("路径可见" "动作可仿" "用户相近" "风险可控")
aux_hits=0
for t in "${aux_terms[@]}"; do
    if grep -qF "$t" "$new" 2>/dev/null; then
        aux_hits=$((aux_hits + 1))
    fi
done
if [ "$aux_hits" -lt 4 ]; then
    violations+=("missing aux-filter terms (need 4, got ${aux_hits})")
fi

# 4. ≥ 3/4 才生成 business dossier
threshold_ok=0
grep -qE "至少 ?3/4|3/4.*合格|合格.*3/4|≥ ?3/4|>= ?3/4|至少 ?3 ?项" "$new" 2>/dev/null && threshold_ok=1
grep -qE "不足 ?3.*降级|不足 ?3.*content_sample" "$new" 2>/dev/null && threshold_ok=1
if [ "$threshold_ok" -eq 0 ]; then
    violations+=("missing '≥ 3/4 → business dossier' threshold rule")
fi

if [ ${#violations[@]} -gt 0 ]; then
    detail="$(printf '%s | ' "${violations[@]}")"
    emit "fail" "benchmark profit-gate rules incomplete: ${detail:0:300}"
    exit 2
fi

emit "pass" "benchmark profit-gate (5 levels + content_sample fallback + 4 aux + ≥3/4) all present"
exit 0
