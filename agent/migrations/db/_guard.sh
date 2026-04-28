#!/usr/bin/env bash
# Migration idempotency guard —— source 自所有 migration 脚本。
#
# Contract:
#   - migration 用 `source "$(dirname "$0")/_guard.sh"` 加载本文件
#   - SKILL_DIR 优先 env var；否则按 v2/v3 布局自检
#   - DB 路径: $SHULING_DB 优先, 否则 $SKILL_DIR/data/xhs.db
#   - source 时自动 ensure __migrations 表存在（DB 不存在则先跑 db.sh init）
#
# Public functions:
#   already_applied <version>  —— return 0 if applied, 1 otherwise
#   mark_applied    <version>  —— insert into __migrations (no-op if duplicate)

# v3.0+ 自检 v2/v3 布局：
#   v2: $_GUARD_DIR = .../migrations/         → SKILL_DIR = .../  (skill root)
#   v3: $_GUARD_DIR = .../agent/migrations/db/ → SKILL_DIR = .../agent/
_GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$_GUARD_DIR")" = "db" ] && [ "$(basename "$(cd "$_GUARD_DIR/.." && pwd)")" = "migrations" ]; then
    # v3 布局
    SKILL_DIR="${SKILL_DIR:-$(cd "$_GUARD_DIR/../.." && pwd)}"
    _GUARD_DB_SH="$SKILL_DIR/scripts/db.sh"
else
    # v2 布局（向后兼容，老用户回滚到 v2.4.x 时仍可用）
    SKILL_DIR="${SKILL_DIR:-$(cd "$_GUARD_DIR/.." && pwd)}"
    _GUARD_DB_SH="$SKILL_DIR/scripts/db.sh"
fi

# 解析 DB 路径
_GUARD_DB="${SHULING_DB:-$SKILL_DIR/data/xhs.db}"
_GUARD_APPLIED_SQL="$_GUARD_DIR/_applied_table.sql"

# 若 DB 不存在, 初始化. 若 db.sh init 失败则静默让首个 migration 自己处理.
# v2.4.2: 把 _GUARD_DB 通过 SHULING_DB env var 透传给 db.sh, 避免 db.sh 用自己的
# SKILL_DIR 推导出来的源 DB 路径, 导致 target 的 migration 调用反而 init 源 DB.
if [ ! -f "$_GUARD_DB" ]; then
    if [ -x "$_GUARD_DB_SH" ]; then
        SHULING_DB="$_GUARD_DB" bash "$_GUARD_DB_SH" init >/dev/null 2>&1 || true
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
