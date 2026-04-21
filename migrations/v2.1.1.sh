#!/usr/bin/env bash
# Migration for v2.1.1 — 补建 request_log 表
# 幂等：db.sh init 对已有表 CREATE TABLE IF NOT EXISTS，重复跑无害
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "  [v2.1.1] 补建 request_log 表..."
bash "$SKILL_DIR/scripts/db.sh" init >/dev/null
echo "  [v2.1.1] OK"
