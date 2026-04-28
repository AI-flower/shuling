#!/usr/bin/env bash
# ops/verify/checks/43-business-profile-schema.sh — business-profile schema 与 example 完整性
# severity: error
#
# 验证：
#   1. agent/schemas/business-profile.schema.json 存在 + 可解析
#   2. schema 必含字段：creator_track / creator_stage / primary_goal / monetization_stage / business_model_probe
#   3. creator_track enum 必含 creator_first / offer_first / exploration
#   4. business_model_probe 必含 profit_evidence_level / replacement_risk
#   5. agent/knowledge-base/business-profile.json.example 存在并满足关键字段（ad-hoc 检查，不引入 jsonschema）
set -uo pipefail

CHECK_NAME="43-business-profile-schema"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

schema="$ROOT/agent/schemas/business-profile.schema.json"
example="$ROOT/agent/knowledge-base/business-profile.json.example"

if [ ! -f "$schema" ]; then
    emit "fail" "missing agent/schemas/business-profile.schema.json"
    exit 2
fi
if [ ! -f "$example" ]; then
    emit "fail" "missing agent/knowledge-base/business-profile.json.example"
    exit 2
fi

result=$(python3 - "$schema" "$example" << 'PYEOF'
import json, sys

schema_path, example_path = sys.argv[1], sys.argv[2]

try:
    schema = json.load(open(schema_path))
except Exception as e:
    print(f"SCHEMA_PARSE_ERROR: {e}")
    sys.exit(1)

try:
    example = json.load(open(example_path))
except Exception as e:
    print(f"EXAMPLE_PARSE_ERROR: {e}")
    sys.exit(1)

props = schema.get("properties", {})
required_fields = ["creator_track", "creator_stage", "primary_goal", "monetization_stage", "business_model_probe"]
for f in required_fields:
    if f not in props:
        print(f"MISSING_FIELD: schema.properties.{f}")
        sys.exit(1)

ct_enum = props.get("creator_track", {}).get("enum", [])
for v in ["creator_first", "offer_first", "exploration"]:
    if v not in ct_enum:
        print(f"MISSING_ENUM: creator_track.{v}")
        sys.exit(1)

probe = props.get("business_model_probe", {}).get("properties", {})
for f in ["profit_evidence_level", "replacement_risk"]:
    if f not in probe:
        print(f"MISSING_PROBE_FIELD: business_model_probe.{f}")
        sys.exit(1)

# Example ad-hoc field presence check
for f in required_fields:
    if f not in example:
        print(f"EXAMPLE_MISSING_FIELD: {f}")
        sys.exit(1)

if example.get("creator_track") not in ct_enum:
    print(f"EXAMPLE_BAD_TRACK: {example.get('creator_track')}")
    sys.exit(1)

ex_probe = example.get("business_model_probe", {})
for f in ["profit_evidence_level", "replacement_risk"]:
    if f not in ex_probe:
        print(f"EXAMPLE_PROBE_MISSING: {f}")
        sys.exit(1)

print("OK")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK$"; then
    emit "fail" "business-profile schema/example check failed: ${result:0:200}"
    exit 2
fi

emit "pass" "business-profile schema + example fields valid"
exit 0
