#!/usr/bin/env bash
# ops/verify/checks/39-account-safety-schema.sh — 6 个新 schema 可解析 + default policy 自校验
# severity: error
set -uo pipefail

CHECK_NAME="39-account-safety-schema"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

schemas=(approval account-safety-policy account-safety-state external-intelligence-policy external-signal content-qa-report)

for s in "${schemas[@]}"; do
    schema_path="$ROOT/agent/schemas/${s}.schema.json"
    if [ ! -f "$schema_path" ]; then
        emit "fail" "schema file missing: agent/schemas/${s}.schema.json"
        exit 2
    fi
    if ! python3 -c "import json; json.load(open('$schema_path'))" 2>/dev/null; then
        emit "fail" "schema parse failed: ${s}.schema.json"
        exit 2
    fi
done

# Deep policy validation with jsonschema if available; fallback to json.load
result=$(python3 - "$ROOT" << 'PYEOF'
import json, sys, os

root = sys.argv[1]

def load(path):
    with open(path) as f:
        return json.load(f)

try:
    import jsonschema

    pol = load(os.path.join(root, "agent/policies/account-safety.default.json"))
    sch = load(os.path.join(root, "agent/schemas/account-safety-policy.schema.json"))
    jsonschema.validate(pol, sch)

    pol2 = load(os.path.join(root, "agent/policies/external-intelligence.default.json"))
    sch2 = load(os.path.join(root, "agent/schemas/external-intelligence-policy.schema.json"))
    jsonschema.validate(pol2, sch2)
    print("OK")

except ImportError:
    # jsonschema not installed — just check JSON parse
    load(os.path.join(root, "agent/policies/account-safety.default.json"))
    load(os.path.join(root, "agent/policies/external-intelligence.default.json"))
    print("SKIP_DEEP")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
) || {
    emit "fail" "policy validation failed against schema"
    exit 2
}

if [ "$result" = "SKIP_DEEP" ]; then
    emit "pass" "all account safety schemas parse OK (deep validation skipped: jsonschema not installed)"
else
    emit "pass" "all account safety schemas + default policies parse and validate OK"
fi
exit 0
