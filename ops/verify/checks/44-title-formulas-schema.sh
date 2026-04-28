#!/usr/bin/env bash
# ops/verify/checks/44-title-formulas-schema.sh — title-formulas schema 与 KB 完整性
# severity: error
#
# 验证：
#   1. agent/schemas/title-formula.schema.json 存在 + 可解析
#   2. schema 必含 id/category/trigger/template/intent/best_for/avoid_for/constraints
#   3. agent/knowledge-base/title-formulas.json ≥ 24 条
#   4. 8 类 category 全覆盖
#   5. 每条 template 长度合理（[12, 200] 字符；Chinese title patterns with placeholders）
set -uo pipefail

CHECK_NAME="44-title-formulas-schema"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

schema="$ROOT/agent/schemas/title-formula.schema.json"
kb="$ROOT/agent/knowledge-base/title-formulas.json"

if [ ! -f "$schema" ]; then
    emit "fail" "missing agent/schemas/title-formula.schema.json"
    exit 2
fi
if [ ! -f "$kb" ]; then
    emit "fail" "missing agent/knowledge-base/title-formulas.json"
    exit 2
fi

result=$(python3 - "$schema" "$kb" << 'PYEOF'
import json, sys

schema_path, kb_path = sys.argv[1], sys.argv[2]

try:
    schema = json.load(open(schema_path))
except Exception as e:
    print(f"SCHEMA_PARSE_ERROR: {e}")
    sys.exit(1)

try:
    formulas = json.load(open(kb_path))
except Exception as e:
    print(f"KB_PARSE_ERROR: {e}")
    sys.exit(1)

props = schema.get("properties", {})
required_keys = ["id", "category", "trigger", "template", "intent", "best_for", "avoid_for", "constraints"]
for f in required_keys:
    if f not in props:
        print(f"MISSING_SCHEMA_FIELD: properties.{f}")
        sys.exit(1)

if not isinstance(formulas, list):
    print("KB_NOT_LIST")
    sys.exit(1)

if len(formulas) < 24:
    print(f"INSUFFICIENT_COUNT: {len(formulas)} < 24")
    sys.exit(1)

required_categories = {
    "cognitive_conflict", "curiosity_gap", "loss_aversion", "identity_mirror",
    "number_anchor", "result_promise", "social_proof", "controversy",
}
seen_categories = set()
for i, f in enumerate(formulas):
    if not isinstance(f, dict):
        print(f"BAD_ENTRY_TYPE: index {i}")
        sys.exit(1)
    for k in required_keys:
        if k not in f:
            print(f"ENTRY_MISSING_KEY: index {i}, key {k}")
            sys.exit(1)
    seen_categories.add(f.get("category", ""))
    tpl = f.get("template", "")
    if not isinstance(tpl, str):
        print(f"BAD_TEMPLATE_TYPE: index {i}")
        sys.exit(1)
    n = len(tpl)
    # 合理范围：考虑中文标题（含占位符）；硬上限 200 防长段，硬下限 12 防空模板
    if n < 12 or n > 200:
        print(f"TEMPLATE_LEN_OUT_OF_RANGE: id={f.get('id', '?')} len={n}")
        sys.exit(1)

missing = required_categories - seen_categories
if missing:
    print(f"MISSING_CATEGORIES: {sorted(missing)}")
    sys.exit(1)

print(f"OK count={len(formulas)} categories={len(seen_categories)}")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK"; then
    emit "fail" "title-formulas check failed: ${result:0:200}"
    exit 2
fi

count_msg=$(echo "$result" | head -1)
emit "pass" "title-formulas schema + KB valid ($count_msg)"
exit 0
