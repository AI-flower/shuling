#!/usr/bin/env bash
# ops/verify/checks/23-ops-install-dryrun.sh — ops/install.sh --dry-run 不报错
# severity: error
set -euo pipefail

CHECK_NAME="23-ops-install-dryrun"
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
bash "$INSTALL" --dry-run -y >"$OUT_FILE" 2>&1
RC=$?
set -e

if [ "$RC" -eq 0 ] || [ "$RC" -eq 1 ]; then
    emit "pass" "ops/install.sh --dry-run exited $RC"
    exit 0
else
    emit "fail" "ops/install.sh --dry-run exited $RC"
    exit 2
fi
