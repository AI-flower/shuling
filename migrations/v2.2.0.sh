#!/usr/bin/env bash
# Migration for v2.2.0 "Existing Creator Support"
# 变化:
#   1. posts 表新增 source 字段（shuling/imported/manual, 默认 shuling）
#   2. 新建 historical_stats 表（账号快照 + 体检纵向趋势）
# 幂等:
#   - ALTER TABLE 如果列已存在会报错, 我们通过 PRAGMA 检查
#   - CREATE TABLE IF NOT EXISTS 天然幂等
#   - _guard.sh 的 already_applied/mark_applied 做整体幂等判断
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/migrations/_guard.sh"

if already_applied "2.2.0"; then
    echo '{"status":"skipped","reason":"already_applied","version":"2.2.0"}'
    exit 0
fi

DB_PATH="$_GUARD_DB"

if [ ! -f "$DB_PATH" ]; then
    echo '{"status":"skipped","reason":"db_not_found","version":"2.2.0"}'
    exit 0
fi

has_source_col="$(sqlite3 "$DB_PATH" "PRAGMA table_info(posts);" | awk -F'|' '$2=="source"{print "yes"}')"
if [ "$has_source_col" != "yes" ]; then
    sqlite3 "$DB_PATH" "ALTER TABLE posts ADD COLUMN source TEXT DEFAULT 'shuling';"
fi

sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS historical_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    snapshotted_at TEXT NOT NULL,
    followers INTEGER,
    total_likes INTEGER,
    total_posts INTEGER,
    imported_posts_count INTEGER,
    earliest_post_at TEXT,
    latest_post_at TEXT,
    meta_json TEXT
);
CREATE INDEX IF NOT EXISTS idx_hstats_snapshotted_at ON historical_stats(snapshotted_at DESC);
SQL

mark_applied "2.2.0"
echo '{"status":"ok","reason":"applied","version":"2.2.0"}'
