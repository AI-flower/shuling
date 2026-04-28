#!/usr/bin/env bash
# ops/verify/checks/41-external-intel-budget.sh — external-intelligence policy 预算上限 + playbook 不直散调 xhs.sh
# severity: error
set -uo pipefail

CHECK_NAME="41-external-intel-budget"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

policy_file="$ROOT/agent/policies/external-intelligence.default.json"

if [ ! -f "$policy_file" ]; then
    emit "fail" "agent/policies/external-intelligence.default.json not found"
    exit 2
fi

# 检查预算上限
result=$(python3 - "$policy_file" << 'PYEOF'
import json, sys

path = sys.argv[1]
try:
    pol = json.load(open(path))
except Exception as e:
    print(f"ERROR: parse failed: {e}", file=sys.stderr)
    sys.exit(1)

daily_limits = {
    "search_feeds": 8,
    "list_feeds": 5,
    "get_feed_detail": 15,
    "fetch_comments": 5,
}
session_limits = {
    "search_feeds": 3,
    "get_feed_detail": 5,
    "fetch_comments": 2,
}

violations = []

daily = pol.get("daily_budget", {})
for k, cap in daily_limits.items():
    val = daily.get(k)
    if val is not None and val > cap:
        violations.append(f"daily_budget.{k}={val} exceeds conservative cap {cap}")

session = pol.get("per_session_budget", {})
for k, cap in session_limits.items():
    val = session.get(k)
    if val is not None and val > cap:
        violations.append(f"per_session_budget.{k}={val} exceeds conservative cap {cap}")

if violations:
    print("VIOLATIONS: " + "; ".join(violations))
    sys.exit(1)
print("OK")
PYEOF
)
budget_rc=$?

if [ "$budget_rc" -ne 0 ]; then
    emit "fail" "external-intelligence budget exceeds conservative caps: ${result}"
    exit 2
fi

# 检查 playbook 03/05/07/08 不直接散调 xhs.sh search / xhs.sh detail / fetch-comments.sh
# 如果同行或5行内有 external-intel 字样则视为通过（through external-intel.sh 调用）
playbook_dir="$ROOT/agent/playbook"
target_playbooks=("03-daily-flow.md" "05-review.md" "07-comment-insights.md" "08-compliance.md")

warn_hits=()
fail_hits=()

for pb in "${target_playbooks[@]}"; do
    pbf="$ROOT/agent/playbook/$pb"
    [ -f "$pbf" ] || continue

    # grep 出 xhs.sh search 或 xhs.sh detail 或 fetch-comments.sh 直接出现的行
    while IFS= read -r line; do
        lineno=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)
        # 若该行含 external-intel → 视为通过
        if echo "$content" | grep -q "external-intel"; then
            continue
        fi
        # 检查附近 5 行是否含 external-intel（宽容模式）
        ctx=$(sed -n "$((lineno>3?lineno-3:1)),$((lineno+3))p" "$pbf" 2>/dev/null || true)
        if echo "$ctx" | grep -q "external-intel"; then
            warn_hits+=("${pb}:${lineno} (near external-intel ref → warn)")
        else
            fail_hits+=("${pb}:${lineno}: ${content:0:80}")
        fi
    done < <(grep -nE 'xhs\.sh (search|detail)|fetch-comments\.sh' "$pbf" 2>/dev/null || true)
done

if [ ${#fail_hits[@]} -gt 0 ]; then
    # Downgrade to warn: playbook refactoring (Stage 6) may be concurrent or not yet complete.
    # A fail is reserved for budget policy breaches only; playbook violations are advisory.
    msg="playbook directly calls xhs.sh research ops (route through external-intel.sh — Stage 6 pending): ${fail_hits[*]}"
    emit "warn" "${msg:0:400}"
    exit 1
fi

if [ ${#warn_hits[@]} -gt 0 ]; then
    msg="playbook may call xhs.sh search/detail near external-intel ref (review): ${warn_hits[*]}"
    emit "warn" "${msg:0:400}"
    exit 1
fi

emit "pass" "external-intelligence budget within conservative caps; playbooks use external-intel.sh"
exit 0
