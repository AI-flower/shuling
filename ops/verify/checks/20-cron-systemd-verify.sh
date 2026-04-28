#!/usr/bin/env bash
# ops/verify/checks/20-cron-systemd-verify.sh — systemd timer 含 OnCalendar= 字段（基础格式校验）
# severity: warn
set -euo pipefail

CHECK_NAME="20-cron-systemd-verify"
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

TIMER="$ROOT/ops/cron/systemd.timer.example"

if [ "$(uname -s)" != "Linux" ]; then
    emit "pass" "non-linux platform"
    exit 0
fi

if [ ! -f "$TIMER" ]; then
    emit "warn" "ops/cron/systemd.timer.example missing"
    exit 1
fi

if grep -E '^[[:space:]]*OnCalendar=' "$TIMER" >/dev/null 2>&1; then
    emit "pass" "systemd timer contains OnCalendar="
    exit 0
else
    emit "warn" "systemd timer missing OnCalendar= directive"
    exit 1
fi
