#!/usr/bin/env bash
# Migration for v2.1.1 — 只建 request_log 表（不调用 db.sh init）
#
# 历史 bug（v2.1.1 ~ v2.2.0）:
#   原实现调用 'db.sh init'，但 db.sh init 会跑所有当前 CREATE 语句，
#   包括 v2.2.0 的 CREATE INDEX idx_posts_source ON posts(source)。
#   存量旧版 DB（posts 无 source 字段）在这一步会炸，导致后续 migration
#   全部阻断（v2.2.0 的 ALTER TABLE 添加 source 根本跑不到）。
#
# 修复（v2.2.1）:
#   让 v2.1.1.sh 只做自己分内事——建 request_log 表。
#   各 migration 严格只改自己引入的 schema，不共用 db.sh init。
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DB_PATH="$SKILL_DIR/data/xhs.db"

if [ ! -f "$DB_PATH" ]; then
    echo "  [v2.1.1] DB 不存在（$DB_PATH），跳过 migration（install.sh 稍后会 db.sh init）"
    exit 0
fi

echo "  [v2.1.1] 建 request_log 表..."
sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS request_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    called_at TEXT NOT NULL,
    tool TEXT NOT NULL,
    args_preview TEXT,
    status TEXT NOT NULL,
    latency_ms INTEGER,
    error_hint TEXT,
    session_tag TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_request_log_called ON request_log(called_at);
CREATE INDEX IF NOT EXISTS idx_request_log_tool ON request_log(tool, called_at);
CREATE INDEX IF NOT EXISTS idx_request_log_status ON request_log(status);
SQL
echo "  [v2.1.1] OK"
