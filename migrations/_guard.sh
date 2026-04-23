#!/usr/bin/env bash
# Migration idempotency guard —— source 自所有 migration 脚本。
#
# Contract:
#   - SKILL_DIR 必须在 source 前由调用方用 'cd $(dirname $0)/..' 推导并 export/设置
#   - DB 路径: $SHULING_DB 优先, 否则 $SKILL_DIR/data/xhs.db
#   - source 时自动 ensure __migrations 表存在（DB 不存在则先跑 db.sh init）
#
# Public functions:
#   already_applied <version>  —— return 0 if applied, 1 otherwise
#   mark_applied    <version>  —— insert into __migrations (no-op if duplicate)

# 解析 DB 路径
_GUARD_DB="${SHULING_DB:-$SKILL_DIR/data/xhs.db}"
_GUARD_APPLIED_SQL="$SKILL_DIR/migrations/_applied_table.sql"

# 若 DB 不存在, 初始化. 若 db.sh init 失败则静默让首个 migration 自己处理.
if [ ! -f "$_GUARD_DB" ]; then
    if [ -x "$SKILL_DIR/scripts/db.sh" ]; then
        bash "$SKILL_DIR/scripts/db.sh" init >/dev/null 2>&1 || true
    fi
fi

# Ensure tracking table.  DB 可能仍不存在（老 DB 目录缺失且 db.sh init 失败）——
# 直接 sqlite3 建 DB + 表, 保证 already_applied/mark_applied 可用.
if [ -f "$_GUARD_APPLIED_SQL" ]; then
    sqlite3 "$_GUARD_DB" ".read $_GUARD_APPLIED_SQL" 2>/dev/null || \
        sqlite3 "$_GUARD_DB" "CREATE TABLE IF NOT EXISTS __migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')));"
else
    sqlite3 "$_GUARD_DB" "CREATE TABLE IF NOT EXISTS __migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')));"
fi

already_applied() {
    local version="$1"
    [ -z "$version" ] && return 1
    local count
    count="$(sqlite3 "$_GUARD_DB" "SELECT COUNT(*) FROM __migrations WHERE version='$version';" 2>/dev/null || echo 0)"
    [ "$count" = "1" ]
}

mark_applied() {
    local version="$1"
    [ -z "$version" ] && return 1
    sqlite3 "$_GUARD_DB" "INSERT OR IGNORE INTO __migrations(version) VALUES('$version');" 2>/dev/null
}
