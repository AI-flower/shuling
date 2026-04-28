#!/usr/bin/env bash
# ops/verify/checks/36-comment-disabled-by-default.sh — xhs.sh comment 未设 SHULING_ENABLE_COMMENT 时必须返回 comment_disabled
# severity: error
set -uo pipefail

CHECK_NAME="36-comment-disabled-by-default"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

xhs="$ROOT/agent/scripts/xhs.sh"
if [ ! -f "$xhs" ]; then
    emit "fail" "agent/scripts/xhs.sh not found"
    exit 2
fi

# 明确传空值，确保未启用
out=$(SHULING_ENABLE_COMMENT="" bash "$xhs" comment "fakenote" "test" 2>&1) || true

if echo "$out" | grep -q "comment_disabled"; then
    emit "pass" "xhs.sh comment is disabled by default"
    exit 0
fi

emit "fail" "xhs.sh comment did not enforce default-disabled: ${out:0:200}"
exit 2
