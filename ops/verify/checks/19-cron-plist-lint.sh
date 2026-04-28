#!/usr/bin/env bash
# ops/verify/checks/19-cron-plist-lint.sh — launchd plist 通过 plutil -lint（macOS 限定）
# severity: warn
set -euo pipefail

CHECK_NAME="19-cron-plist-lint"
SEVERITY="warn"

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

PLIST="$ROOT/ops/cron/launchd.plist.example"

if [ "$(uname -s)" != "Darwin" ]; then
    emit "pass" "non-darwin platform"
    exit 0
fi

if [ ! -f "$PLIST" ]; then
    emit "warn" "ops/cron/launchd.plist.example missing"
    exit 1
fi

if ! command -v plutil >/dev/null 2>&1; then
    emit "warn" "plutil not available"
    exit 1
fi

OUT="$(plutil -lint "$PLIST" 2>&1)" || {
    msg="${OUT//\"/\\\"}"
    msg="${msg//$'\n'/ }"
    emit "warn" "plutil -lint failed: $msg"
    exit 1
}

emit "pass" "launchd plist lint OK"
exit 0
