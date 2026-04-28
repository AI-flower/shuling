#!/usr/bin/env bash
# ops/verify/checks/47-business-review-schema.sh — business-review schema 完整性
# severity: error
#
# 验证：
#   1. agent/schemas/business-review.schema.json 存在 + 可解析
#   2. 必含 7 类信号字段：traffic / save / trust / lead / sales / controversy + performance_tier
#   3. 必含 evidence_level / evidence / confidence
#   4. next_action enum 至少含：repeat / iterate / series / change_title / change_offer /
#      change_benchmark / pause / unknown
set -uo pipefail

CHECK_NAME="47-business-review-schema"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

schema="$ROOT/agent/schemas/business-review.schema.json"

if [ ! -f "$schema" ]; then
    emit "fail" "missing agent/schemas/business-review.schema.json"
    exit 2
fi

result=$(python3 - "$schema" << 'PYEOF'
import json, sys

try:
    schema = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"SCHEMA_PARSE_ERROR: {e}")
    sys.exit(1)

props = schema.get("properties", {})

required_signals = [
    "performance_tier",
    "traffic_signal", "save_signal", "trust_signal",
    "lead_signal", "sales_signal", "controversy_signal",
]
for s in required_signals:
    if s not in props:
        print(f"MISSING_SIGNAL: {s}")
        sys.exit(1)

for f in ["evidence_level", "evidence", "confidence"]:
    if f not in props:
        print(f"MISSING_FIELD: {f}")
        sys.exit(1)

next_action_enum = props.get("next_action", {}).get("enum", [])
required_actions = [
    "repeat", "iterate", "series",
    "change_title", "change_offer", "change_benchmark",
    "pause", "unknown",
]
for a in required_actions:
    if a not in next_action_enum:
        print(f"MISSING_NEXT_ACTION: {a}")
        sys.exit(1)

print("OK")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK$"; then
    emit "fail" "business-review schema check failed: ${result:0:200}"
    exit 2
fi

emit "pass" "business-review schema valid (7 signals + 8 next_actions)"
exit 0
