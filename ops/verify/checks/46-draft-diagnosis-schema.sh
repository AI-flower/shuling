#!/usr/bin/env bash
# ops/verify/checks/46-draft-diagnosis-schema.sh — draft-diagnosis schema 完整性
# severity: error
#
# 验证：
#   1. agent/schemas/draft-diagnosis.schema.json 存在 + 可解析
#   2. dimensions 下必含 6 维度：clarity / title_cover_fit / expression_efficiency /
#      cognitive_gap / human_signal / business_alignment
#   3. 每个维度子结构含 score / issue / evidence / fix / fix_priority / confidence
#   4. ai_fingerprint_hits 数组定义存在
set -uo pipefail

CHECK_NAME="46-draft-diagnosis-schema"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

schema="$ROOT/agent/schemas/draft-diagnosis.schema.json"

if [ ! -f "$schema" ]; then
    emit "fail" "missing agent/schemas/draft-diagnosis.schema.json"
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

# dimensions block
dim_block = props.get("dimensions", {})
dim_props = dim_block.get("properties", {})
required_dims = [
    "clarity", "title_cover_fit", "expression_efficiency",
    "cognitive_gap", "human_signal", "business_alignment",
]
for d in required_dims:
    if d not in dim_props:
        print(f"MISSING_DIMENSION: {d}")
        sys.exit(1)

# dimensionScore subfields
dim_def = schema.get("definitions", {}).get("dimensionScore", {})
dim_sub = dim_def.get("properties", {})
required_sub = ["score", "issue", "evidence", "fix", "fix_priority", "confidence"]
for sub in required_sub:
    if sub not in dim_sub:
        print(f"MISSING_DIMENSION_SUBFIELD: {sub}")
        sys.exit(1)

# verify each dimension uses the dimensionScore definition (or has same structure)
for d, dval in dim_props.items():
    ref = dval.get("$ref", "")
    has_inline = "properties" in dval
    if not ref.endswith("/dimensionScore") and not has_inline:
        print(f"DIMENSION_NOT_USING_DEF: {d}")
        sys.exit(1)

# ai_fingerprint_hits array
afh = props.get("ai_fingerprint_hits", {})
if afh.get("type") != "array":
    print("MISSING_AI_FINGERPRINT_HITS_ARRAY")
    sys.exit(1)

print("OK")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK$"; then
    emit "fail" "draft-diagnosis schema check failed: ${result:0:200}"
    exit 2
fi

emit "pass" "draft-diagnosis schema valid (6 dims + ai_fingerprint_hits)"
exit 0
