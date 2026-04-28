#!/usr/bin/env bash
# ops/verify/checks/35-publish-requires-approval.sh — xhs.sh publish 无 --approval-id 必须报 approval_required
# severity: error
set -uo pipefail

CHECK_NAME="35-publish-requires-approval"
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

# 创建临时 meta.json（最小合法内容）
tmp_meta="$(mktemp /tmp/verify-pub-test-XXXXXX.json)"
echo '{"title":"test","content":"test"}' > "$tmp_meta"

out=$(bash "$xhs" publish "$tmp_meta" 2>&1) || true
rm -f "$tmp_meta"

if echo "$out" | grep -q "approval_required\|approval"; then
    emit "pass" "xhs.sh publish enforces approval requirement"
    exit 0
fi

emit "fail" "xhs.sh publish did not return approval_required: ${out:0:200}"
exit 2
