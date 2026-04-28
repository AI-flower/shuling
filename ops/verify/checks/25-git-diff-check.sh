#!/usr/bin/env bash
# ops/verify/checks/25-git-diff-check.sh — git diff --check（空白错误 / 行结尾）
# severity: error
set -euo pipefail

CHECK_NAME="25-git-diff-check"
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

if ! command -v git >/dev/null 2>&1; then
    emit "fail" "git not available"
    exit 2
fi

if [ ! -d "$ROOT/.git" ]; then
    emit "fail" "not a git repo: $ROOT"
    exit 2
fi

OUT_FILE="$(mktemp)"
trap 'rm -f "$OUT_FILE"' EXIT

set +e
git -C "$ROOT" diff --check >"$OUT_FILE" 2>&1
RC=$?
git -C "$ROOT" diff --cached --check >>"$OUT_FILE" 2>&1
RC2=$?
set -e

if [ "$RC" -eq 0 ] && [ "$RC2" -eq 0 ]; then
    emit "pass" "git diff --check clean (incl. cached)"
    exit 0
fi

# 取首条违规作为 sample
SAMPLE=""
if [ -s "$OUT_FILE" ]; then
    SAMPLE="$(head -1 "$OUT_FILE" | tr -d '"' | tr '\n' ' ')"
fi
emit "fail" "whitespace/line-ending issue: $SAMPLE"
exit 2
