#!/usr/bin/env bash
# ops/verify/checks/55-title-intent-cooldown.sh — title-formulas intent + cooldown_posts + content-qa cooldown
# severity: error
#
# 验证：
#   1. title-formulas.json 每条公式都有 intent（7 类 enum 任一：click/save/comment/trust/lead/conversion/series）
#   2. 每条公式都有 constraints.cooldown_posts（整数 ≥ 1）
#   3. agent/scripts/content-qa.py 包含 cooldown 相关检测函数
set -uo pipefail

CHECK_NAME="55-title-intent-cooldown"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

kb="$ROOT/agent/knowledge-base/title-formulas.json"
qa="$ROOT/agent/scripts/content-qa.py"

if [ ! -f "$kb" ]; then
    emit "fail" "missing agent/knowledge-base/title-formulas.json"
    exit 2
fi
if [ ! -f "$qa" ]; then
    emit "fail" "missing agent/scripts/content-qa.py"
    exit 2
fi

result=$(python3 - "$kb" << 'PYEOF'
import json, sys

try:
    formulas = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"KB_PARSE_ERROR: {e}")
    sys.exit(1)

if not isinstance(formulas, list) or not formulas:
    print("KB_EMPTY_OR_NOT_LIST")
    sys.exit(1)

VALID_INTENTS = {"click", "save", "comment", "trust", "lead", "conversion", "series"}

violations = []
for f in formulas:
    fid = f.get("id", "?")
    intent = f.get("intent")
    if intent not in VALID_INTENTS:
        violations.append(f"bad-intent:{fid}={intent}")
    constraints = f.get("constraints", {})
    cd = constraints.get("cooldown_posts")
    if not isinstance(cd, int) or cd < 1:
        violations.append(f"bad-cooldown:{fid}={cd}")

if violations:
    print("VIOLATIONS:")
    for v in violations[:8]:
        print(v)
    sys.exit(1)

print(f"OK count={len(formulas)}")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK"; then
    detail=$(echo "$result" | head -8 | tr '\n' '|')
    emit "fail" "title formulas intent/cooldown invalid: ${detail:0:300}"
    exit 2
fi

# 3. content-qa.py 含 cooldown 检测
if ! grep -qE "cooldown|formula_id_repeat|trigger_repeat|title_formula_repeat|title_trigger_repeat" "$qa" 2>/dev/null; then
    emit "fail" "agent/scripts/content-qa.py missing cooldown / formula_id_repeat / trigger_repeat detection"
    exit 2
fi

emit "pass" "every formula has intent (∈7) + cooldown_posts ≥1; content-qa.py has cooldown checks"
exit 0
