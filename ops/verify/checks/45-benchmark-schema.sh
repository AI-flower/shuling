#!/usr/bin/env bash
# ops/verify/checks/45-benchmark-schema.sh — benchmark schema 完整性 + benchmarks/ 目录哨兵
# severity: error
#
# 验证：
#   1. agent/schemas/benchmark.schema.json 存在 + 可解析
#   2. benchmark_type enum 必含 business_benchmark / content_sample
#   3. monetization_guess 必含 profit_evidence_gate / profit_evidence_level
#   4. 必含字段：coverage / evidence_level / why_worth_learning / imitable_actions / not_imitable_actions
#   5. agent/knowledge-base/benchmarks/.gitkeep 存在
set -uo pipefail

CHECK_NAME="45-benchmark-schema"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

schema="$ROOT/agent/schemas/benchmark.schema.json"
gitkeep="$ROOT/agent/knowledge-base/benchmarks/.gitkeep"

if [ ! -f "$schema" ]; then
    emit "fail" "missing agent/schemas/benchmark.schema.json"
    exit 2
fi
if [ ! -f "$gitkeep" ]; then
    emit "fail" "missing agent/knowledge-base/benchmarks/.gitkeep"
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

bt_enum = props.get("benchmark_type", {}).get("enum", [])
for v in ["business_benchmark", "content_sample"]:
    if v not in bt_enum:
        print(f"MISSING_BENCHMARK_TYPE_ENUM: {v}")
        sys.exit(1)

mg = props.get("monetization_guess", {}).get("properties", {})
for f in ["profit_evidence_gate", "profit_evidence_level"]:
    if f not in mg:
        print(f"MISSING_MG_FIELD: {f}")
        sys.exit(1)

required = [
    "coverage", "evidence_level",
    "why_worth_learning", "imitable_actions", "not_imitable_actions",
]
for f in required:
    if f not in props:
        print(f"MISSING_FIELD: {f}")
        sys.exit(1)

print("OK")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK$"; then
    emit "fail" "benchmark schema check failed: ${result:0:200}"
    exit 2
fi

emit "pass" "benchmark schema valid + benchmarks/.gitkeep present"
exit 0
