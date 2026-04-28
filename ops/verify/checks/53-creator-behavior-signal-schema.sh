#!/usr/bin/env bash
# ops/verify/checks/53-creator-behavior-signal-schema.sh — creator-behavior-signal schema 完整性
# severity: error
#
# 验证：
#   1. agent/schemas/creator-behavior-signal.schema.json 存在 + 可解析
#   2. signal_type enum ≥ 6 类：planning_loop / direction_hopping / draft_no_publish /
#      benchmark_overstudy / perfectionism / external_blame
#   3. 必含字段：severity / observed_events / interpretation / next_small_action / cooldown_until
#   4. agent/knowledge-base/creator-behavior-signals.md 存在
set -uo pipefail

CHECK_NAME="53-creator-behavior-signal-schema"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

schema="$ROOT/agent/schemas/creator-behavior-signal.schema.json"
md="$ROOT/agent/knowledge-base/creator-behavior-signals.md"

if [ ! -f "$schema" ]; then
    emit "fail" "missing agent/schemas/creator-behavior-signal.schema.json"
    exit 2
fi
if [ ! -f "$md" ]; then
    emit "fail" "missing agent/knowledge-base/creator-behavior-signals.md"
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

signal_type_enum = props.get("signal_type", {}).get("enum", [])
required_signals = [
    "planning_loop", "direction_hopping", "draft_no_publish",
    "benchmark_overstudy", "perfectionism", "external_blame",
]
missing = [s for s in required_signals if s not in signal_type_enum]
if missing:
    print(f"MISSING_SIGNAL_TYPES: {missing}")
    sys.exit(1)
if len(signal_type_enum) < 6:
    print(f"INSUFFICIENT_SIGNAL_TYPES: {len(signal_type_enum)} < 6")
    sys.exit(1)

for f in ["severity", "observed_events", "interpretation", "next_small_action", "cooldown_until"]:
    if f not in props:
        print(f"MISSING_FIELD: {f}")
        sys.exit(1)

print(f"OK signals={len(signal_type_enum)}")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK"; then
    emit "fail" "creator-behavior-signal schema check failed: ${result:0:200}"
    exit 2
fi

emit "pass" "creator-behavior-signal schema valid + KB md present"
exit 0
