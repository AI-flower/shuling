#!/usr/bin/env bash
# ops/verify/checks/38-disable-throttle-dev-only.sh — XHS_DISABLE_THROTTLE/QUOTA 只允许在 SHULING_DEV_MODE=1 下使用
# severity: error
set -uo pipefail

CHECK_NAME="38-disable-throttle-dev-only"
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

# 测试 XHS_DISABLE_THROTTLE=1 在非 dev mode 下被拒
out_throttle=$(XHS_DISABLE_THROTTLE=1 SHULING_DEV_MODE=0 bash "$xhs" status 2>&1) || true
if ! echo "$out_throttle" | grep -q "dev_mode_required"; then
    emit "fail" "xhs.sh allowed XHS_DISABLE_THROTTLE=1 outside dev mode: ${out_throttle:0:200}"
    exit 2
fi

# 测试 XHS_DISABLE_QUOTA=1 在非 dev mode 下被拒
out_quota=$(XHS_DISABLE_QUOTA=1 SHULING_DEV_MODE=0 bash "$xhs" status 2>&1) || true
if ! echo "$out_quota" | grep -q "dev_mode_required"; then
    emit "fail" "xhs.sh allowed XHS_DISABLE_QUOTA=1 outside dev mode: ${out_quota:0:200}"
    exit 2
fi

emit "pass" "xhs.sh blocks throttle/quota bypass outside dev mode"
exit 0
