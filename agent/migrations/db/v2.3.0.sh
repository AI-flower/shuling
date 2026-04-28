#!/usr/bin/env bash
# Migration for v2.3.0 —— 无 DB schema 变化，占位保持版本线连续
# 本版本的改动（若有）在文档/脚本/skill 层，不涉及 data/xhs.db 的表结构。
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/_guard.sh"

if already_applied "2.3.0"; then
    echo '{"status":"skipped","reason":"already_applied","version":"2.3.0"}'
    exit 0
fi

mark_applied "2.3.0"
echo '{"status":"ok","reason":"no_schema_change","version":"2.3.0"}'
