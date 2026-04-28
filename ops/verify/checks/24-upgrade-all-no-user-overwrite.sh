#!/usr/bin/env bash
# ops/verify/checks/24-upgrade-all-no-user-overwrite.sh — upgrade-all 计划不写 agent/ 用户态路径
# severity: error
set -euo pipefail

CHECK_NAME="24-upgrade-all-no-user-overwrite"
SEVERITY="error"

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

emit() {
    local status="$1" message="$2"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

INSTALL="$ROOT/ops/install.sh"
if [ ! -f "$INSTALL" ]; then
    emit "fail" "ops/install.sh missing"
    exit 2
fi

OUT_FILE="$(mktemp)"
trap 'rm -f "$OUT_FILE"' EXIT

set +e
bash "$INSTALL" upgrade-all --dry-run --json >"$OUT_FILE" 2>/dev/null
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
    emit "fail" "upgrade-all --dry-run --json exited $RC"
    exit 2
fi

if [ ! -s "$OUT_FILE" ]; then
    emit "fail" "upgrade-all --dry-run --json produced empty output"
    exit 2
fi

# 用户态敏感路径 —— 只匹配 plan 字符串字段值
# 形如 "agent/data/xhs.db" / "agent/config/runtime.env" / "agent/knowledge-base/*.json"
SENSITIVE_RE='agent/data/[^"]*\.db|agent/config/runtime\.env|agent/knowledge-base/[^"]*\.json'

VIOLATIONS=0
VIOL_SAMPLE=""

if command -v jq >/dev/null 2>&1; then
    # 用 jq 把所有字符串值平坦化后再匹配
    FLAT="$(jq -r '.. | strings? // empty' "$OUT_FILE" 2>/dev/null || true)"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if printf '%s' "$line" | grep -E "$SENSITIVE_RE" >/dev/null 2>&1; then
            VIOLATIONS=$((VIOLATIONS+1))
            if [ -z "$VIOL_SAMPLE" ]; then
                VIOL_SAMPLE="$(printf '%s' "$line" | grep -E -o "$SENSITIVE_RE" | head -1)"
            fi
        fi
    done <<< "$FLAT"
else
    # fallback: 直接 grep 原始 JSON
    if grep -E -o "$SENSITIVE_RE" "$OUT_FILE" >/dev/null 2>&1; then
        VIOLATIONS=$(grep -E -o "$SENSITIVE_RE" "$OUT_FILE" | wc -l | tr -d ' ')
        VIOL_SAMPLE="$(grep -E -o "$SENSITIVE_RE" "$OUT_FILE" | head -1)"
    fi
fi

if [ "$VIOLATIONS" -eq 0 ]; then
    emit "pass" "upgrade-all plan does not touch agent/ user-state paths"
    exit 0
else
    emit "fail" "upgrade-all plan would write user-state path: $VIOL_SAMPLE ($VIOLATIONS hit)"
    exit 2
fi
