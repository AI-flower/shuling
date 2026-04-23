#!/usr/bin/env bash
# Migration for v2.2.1 "Migration Safety Fix" —— 无 DB schema 变化，占位保持版本线连续
# 本版本的所有改动都在 migrations/ 自身（_guard.sh / _applied_table.sql / 存量 migration 幂等化）。
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/migrations/_guard.sh"

if already_applied "2.2.1"; then
    echo '{"status":"skipped","reason":"already_applied","version":"2.2.1"}'
    exit 0
fi

mark_applied "2.2.1"
echo '{"status":"ok","reason":"no_schema_change","version":"2.2.1"}'
