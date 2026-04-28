#!/usr/bin/env bash
# ops/verify/checks/21-cron-yaml-parse.sh — hermes.yaml.example 用 yq 解析；无 yq 仅做存在性 warn
# severity: warn
set -euo pipefail

CHECK_NAME="21-cron-yaml-parse"
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

YAML="$ROOT/ops/cron/hermes.yaml.example"

if [ ! -f "$YAML" ]; then
    emit "warn" "ops/cron/hermes.yaml.example missing"
    exit 1
fi

if [ ! -s "$YAML" ]; then
    emit "warn" "ops/cron/hermes.yaml.example is empty"
    exit 1
fi

if command -v yq >/dev/null 2>&1; then
    if yq eval '.' "$YAML" >/dev/null 2>&1; then
        emit "pass" "hermes.yaml.example parsed by yq"
        exit 0
    else
        emit "warn" "yq parse failed"
        exit 1
    fi
fi

emit "warn" "no yq, skipped strict parse"
exit 1
