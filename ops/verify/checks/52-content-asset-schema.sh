#!/usr/bin/env bash
# ops/verify/checks/52-content-asset-schema.sh — content-asset schema + asset-ledger 完整性
# severity: error
#
# 验证：
#   1. agent/schemas/content-asset.schema.json 存在 + 可解析
#   2. asset_type enum ≥ 10 类（topic_seed / series_arc / title_evidence / audience_language /
#      faq / case / objection / offer_signal / benchmark_insight / workflow_rule）
#   3. 必含字段：source / content / why_it_matters / reuse_plan / confidence
#   4. agent/knowledge-base/asset-ledger.md 存在
set -uo pipefail

CHECK_NAME="52-content-asset-schema"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

schema="$ROOT/agent/schemas/content-asset.schema.json"
ledger="$ROOT/agent/knowledge-base/asset-ledger.md"

if [ ! -f "$schema" ]; then
    emit "fail" "missing agent/schemas/content-asset.schema.json"
    exit 2
fi
if [ ! -f "$ledger" ]; then
    emit "fail" "missing agent/knowledge-base/asset-ledger.md"
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

asset_type_enum = props.get("asset_type", {}).get("enum", [])
required_types = [
    "topic_seed", "series_arc", "title_evidence", "audience_language",
    "faq", "case", "objection", "offer_signal", "benchmark_insight", "workflow_rule",
]
missing_types = [t for t in required_types if t not in asset_type_enum]
if missing_types:
    print(f"MISSING_ASSET_TYPES: {missing_types}")
    sys.exit(1)
if len(asset_type_enum) < 10:
    print(f"INSUFFICIENT_ASSET_TYPES: {len(asset_type_enum)} < 10")
    sys.exit(1)

for f in ["source", "content", "why_it_matters", "reuse_plan", "confidence"]:
    if f not in props:
        print(f"MISSING_FIELD: {f}")
        sys.exit(1)

print(f"OK types={len(asset_type_enum)}")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK"; then
    emit "fail" "content-asset schema check failed: ${result:0:200}"
    exit 2
fi

emit "pass" "content-asset schema valid + asset-ledger.md present"
exit 0
