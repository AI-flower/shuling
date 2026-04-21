#!/usr/bin/env bash
# Migration for v2.2.0 "Existing Creator Support"
# 变化:
#   1. posts 表新增 source 字段（shuling/imported/manual，默认 shuling）
#   2. 新建 historical_stats 表（账号快照 + 体检纵向趋势）
# 幂等:
#   - ALTER TABLE 如果列已存在会报错，我们通过 PRAGMA 检查
#   - CREATE TABLE IF NOT EXISTS 天然幂等
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DB_PATH="$SKILL_DIR/data/xhs.db"

if [ ! -f "$DB_PATH" ]; then
    echo "  [v2.2.0] DB 不存在（$DB_PATH），跳过 migration（install.sh 稍后会 db.sh init）"
    exit 0
fi

echo "  [v2.2.0] 检查 posts.source 字段..."
has_source_col="$(sqlite3 "$DB_PATH" "PRAGMA table_info(posts);" | awk -F'|' '$2=="source"{print "yes"}')"
if [ "$has_source_col" = "yes" ]; then
    echo "  [v2.2.0] posts.source 已存在，跳过"
else
    sqlite3 "$DB_PATH" "ALTER TABLE posts ADD COLUMN source TEXT DEFAULT 'shuling';"
    echo "  [v2.2.0] posts.source 已添加（默认 'shuling'）"
fi

echo "  [v2.2.0] 建 historical_stats 表..."
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

echo "  [v2.2.0] OK"
