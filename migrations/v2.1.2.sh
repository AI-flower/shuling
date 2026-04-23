#!/usr/bin/env bash
# Migration for v2.1.2 "Release Polish" —— 无 DB 迁移, 仅版本留痕
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/migrations/_guard.sh"

if already_applied "2.1.2"; then
    echo '{"status":"skipped","reason":"already_applied","version":"2.1.2"}'
    exit 0
fi

mark_applied "2.1.2"
echo '{"status":"ok","reason":"no_schema_change","version":"2.1.2"}'
