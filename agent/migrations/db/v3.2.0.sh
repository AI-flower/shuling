#!/usr/bin/env bash
# Migration for v3.2.0 "Creator Business Intelligence"
#
# 见 docs/plans/v3.2-creator-business-intelligence-plan.md §6.2
#
# 变化：
#   1. posts 表增加 3 列：title_formula_id / title_trigger / title_intent
#      用 PRAGMA table_info 检查列存在性以保证幂等
#   2. topic_candidates 表增加 7 列：
#      business_score / goal_alignment_score / monetization_distance_score /
#      benchmark_score / asset_score / decision / reasoning_json
#   3. 新建 3 张表（CREATE TABLE IF NOT EXISTS，天然幂等）：
#      - business_reviews         （05-review 业务归因落库）
#      - content_assets           （asset-ledger 结构化版）
#      - creator_behavior_signals （执行摩擦信号；Stage 2 提前建好供 02-onboarding-existing 反推时直接写表）
#
# 幂等：ALTER 列检测 + CREATE TABLE IF NOT EXISTS + __migrations 台账兜底
set -e

# 默认按 v3 布局 (.../agent/migrations/db/vX.Y.Z.sh) 推导 SKILL_DIR=.../agent/
# 若 caller (ensure-schema / install.sh) 已通过 env 覆写 SKILL_DIR/SHULING_DB，则尊重 caller。
SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$(dirname "$0")/_guard.sh"

if already_applied "3.2.0"; then
    echo '{"status":"skipped","reason":"already_applied","version":"3.2.0"}'
    exit 0
fi

DB_PATH="$_GUARD_DB"

if [ ! -f "$DB_PATH" ]; then
    echo '{"status":"skipped","reason":"db_not_found","version":"3.2.0"}'
    exit 0
fi

# ─── helper: 幂等加列 ─────────────────────────────────────────────────
add_col_if_missing() {
    local table="$1"
    local col="$2"
    local decl="$3"
    local exists
    exists="$(sqlite3 "$DB_PATH" "PRAGMA table_info($table);" | awk -F'|' -v c="$col" '$2==c{print "yes"}')"
    if [ "$exists" != "yes" ]; then
        sqlite3 "$DB_PATH" "ALTER TABLE $table ADD COLUMN $col $decl;"
    fi
}

# 1. posts 表 +3 列
add_col_if_missing posts title_formula_id "TEXT"
add_col_if_missing posts title_trigger    "TEXT"
add_col_if_missing posts title_intent     "TEXT"

# 2. topic_candidates 表 +7 列
add_col_if_missing topic_candidates business_score                "REAL"
add_col_if_missing topic_candidates goal_alignment_score          "REAL"
add_col_if_missing topic_candidates monetization_distance_score   "REAL"
add_col_if_missing topic_candidates benchmark_score               "REAL"
add_col_if_missing topic_candidates asset_score                   "REAL"
add_col_if_missing topic_candidates decision                      "TEXT"
add_col_if_missing topic_candidates reasoning_json                "TEXT"

# 3. 3 张新表
sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS business_reviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER REFERENCES posts(id),
    reviewed_at TEXT NOT NULL,
    performance_tier TEXT,
    traffic_signal TEXT,
    save_signal TEXT,
    trust_signal TEXT,
    lead_signal TEXT,
    sales_signal TEXT,
    controversy_signal TEXT,
    main_attribution TEXT,
    evidence_level TEXT,
    confidence TEXT,
    business_interpretation TEXT,
    next_action TEXT,
    review_json TEXT
);
CREATE INDEX IF NOT EXISTS idx_business_reviews_post_id   ON business_reviews(post_id);
CREATE INDEX IF NOT EXISTS idx_business_reviews_reviewed  ON business_reviews(reviewed_at DESC);

CREATE TABLE IF NOT EXISTS content_assets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    asset_key TEXT,
    asset_type TEXT NOT NULL,
    source_type TEXT,
    source_id TEXT,
    confidence TEXT,
    created_at TEXT NOT NULL,
    last_used_at TEXT,
    asset_json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_content_assets_type    ON content_assets(asset_type);
CREATE INDEX IF NOT EXISTS idx_content_assets_created ON content_assets(created_at DESC);

CREATE TABLE IF NOT EXISTS creator_behavior_signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signal_type TEXT NOT NULL,
    severity TEXT,
    observed_at TEXT NOT NULL,
    resolved_at TEXT,
    signal_json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cbs_signal_type ON creator_behavior_signals(signal_type);
CREATE INDEX IF NOT EXISTS idx_cbs_observed   ON creator_behavior_signals(observed_at DESC);
SQL

mark_applied "3.2.0"
echo '{"status":"ok","reason":"applied","version":"3.2.0"}'
