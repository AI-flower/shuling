#!/usr/bin/env bash
# Migration for v3.1.0 "External Intelligence Cache Table"
#
# 见 docs/plans/v3-account-execution-safety-hardening.md §12.7
#
# 变化：
#   1. 新建 external_signals 表（外部情报摘要信号缓存）
#   2. 新建 idx_ext_signals_topic / idx_ext_signals_expires 索引
#
# 注：external-intel.sh 主要以 JSON 文件（agent/knowledge-base/external-signals/）
# 为权威 cache。本表是辅助索引，方便：
#   - 按 expires_at 批量 prune
#   - 按 topic + signal_type 聚合查询
#   - db.sh query-external-signals 子命令读取
#
# 幂等：CREATE TABLE/INDEX IF NOT EXISTS 天然幂等；__migrations 台账兜底
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/_guard.sh"

if already_applied "3.1.0"; then
    echo '{"status":"skipped","reason":"already_applied","version":"3.1.0"}'
    exit 0
fi

DB_PATH="$_GUARD_DB"

if [ ! -f "$DB_PATH" ]; then
    echo '{"status":"skipped","reason":"db_not_found","version":"3.1.0"}'
    exit 0
fi

sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS external_signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    topic TEXT NOT NULL,
    source_type TEXT,
    signal_type TEXT,
    summary TEXT,
    confidence REAL,
    sample_size INTEGER,
    observed_at TEXT NOT NULL,
    expires_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_ext_signals_topic ON external_signals(topic);
CREATE INDEX IF NOT EXISTS idx_ext_signals_expires ON external_signals(expires_at);
SQL

mark_applied "3.1.0"
echo '{"status":"ok","reason":"applied","version":"3.1.0"}'
