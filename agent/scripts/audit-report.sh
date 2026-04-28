#!/usr/bin/env bash
# audit-report.sh — 账号体检报告生成器（v2.2.0 新增）
#
# 读 DB 做纯统计，输出两份文件:
#   agent/knowledge-base/audit-<YYYY-MM-DD>.json   结构化（AI 读 + agent/schemas/audit-report.schema.json 校验）
#   agent/knowledge-base/audit-<YYYY-MM-DD>.md     人类可读骨架（AI 后续追加归因分析）
#
# 统计维度（MVP 8 项）:
#   1. 账号快照 (historical_stats 最新行)
#   2. 流量趋势（最近 N 天每日发布量 × 平均收藏率）
#   3. Top 5 / Bottom 5 帖（按收藏率）
#   4. 主题分布 (topic_type × 帖子数 × avg 收藏率)
#   5. 标题模式命中率 (title_pattern × 平均收藏率)
#   6. 评论需求积压（comment_insights.content_requests top-K）
#   7. 风险信号（连续低表现 / 发布密度异常）
#   8. (Layer 1 不含) AI 归因分析 — 由 AI 读 JSON 后追加到 md
#
# 用法:
#   bash agent/scripts/audit-report.sh                         # 默认最近 90 天
#   bash agent/scripts/audit-report.sh --days 180
#   bash agent/scripts/audit-report.sh --output /path/out.md
#   bash agent/scripts/audit-report.sh --json-only             # 不写 md，只输出 JSON 到 stdout
#   bash agent/scripts/audit-report.sh --extract-patterns      # 额外输出 patterns 候选（供 AI 写 patterns.md）
#   bash agent/scripts/audit-report.sh --include-organic       # 含 source='shuling' 的帖（默认只看 imported 老博主历史）
#
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DB_PATH="$SKILL_DIR/data/xhs.db"
KB_DIR="$SKILL_DIR/knowledge-base"
TODAY="$(date +%Y-%m-%d)"

# ─── 参数 ───────────────────────────────────────────────────────────
DAYS=90
OUTPUT=""
JSON_ONLY=0
EXTRACT_PATTERNS=0
INCLUDE_ORGANIC=0
SOURCE_FILTER="source='imported'"

while [ $# -gt 0 ]; do
    case "$1" in
        --days)             shift; DAYS="$1"; shift ;;
        --output)           shift; OUTPUT="$1"; shift ;;
        --json-only)        JSON_ONLY=1; shift ;;
        --extract-patterns) EXTRACT_PATTERNS=1; shift ;;
        --include-organic)  INCLUDE_ORGANIC=1; shift ;;
        -h|--help)          sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

if [ "$INCLUDE_ORGANIC" = "1" ]; then
    SOURCE_FILTER="(source='imported' OR source='shuling')"
fi

command -v sqlite3 >/dev/null 2>&1 || { echo "ERR: sqlite3 未安装" >&2; exit 1; }
command -v jq      >/dev/null 2>&1 || { echo "ERR: jq 未安装" >&2; exit 1; }
[ -f "$DB_PATH" ] || { echo "ERR: DB 不存在 ($DB_PATH)。先跑 bash agent/scripts/db.sh init" >&2; exit 1; }

mkdir -p "$KB_DIR"
JSON_OUT="${OUTPUT:-$KB_DIR/audit-${TODAY}.json}"
MD_OUT="${JSON_OUT%.json}.md"

# ─── SQL 助手（latest metric per post） ─────────────────────────────
# 对每条 imported post 取 post_metrics 最新一行作为"当前表现"
# 收藏率 = saves / max(likes, 1)
LATEST_METRICS_SQL="
WITH latest_m AS (
  SELECT post_id, MAX(checked_at) AS latest_at FROM post_metrics GROUP BY post_id
),
pm AS (
  SELECT m.post_id, m.likes, m.saves, m.comments, m.shares, m.checked_at
  FROM post_metrics m
  INNER JOIN latest_m lm ON m.post_id = lm.post_id AND m.checked_at = lm.latest_at
),
pos AS (
  SELECT p.id, p.title, p.note_id, p.published_at, p.topic_type, p.title_pattern, p.content_style, p.tags
  FROM posts p
  WHERE $SOURCE_FILTER
    AND (p.published_at IS NULL OR p.published_at >= date('now', '-${DAYS} days'))
)
SELECT pos.*, pm.likes, pm.saves, pm.comments, pm.shares,
       CAST(pm.saves AS REAL) / MAX(pm.likes, 1) AS save_rate
FROM pos INNER JOIN pm ON pos.id = pm.post_id
"

# ─── 1. 账号快照（最近 historical_stats 行） ────────────────────────
snapshot_json="$(sqlite3 -json "$DB_PATH" "SELECT * FROM historical_stats ORDER BY snapshotted_at DESC LIMIT 1;" 2>/dev/null || echo '[]')"
[ -z "$snapshot_json" ] && snapshot_json='[]'
snapshot="$(echo "$snapshot_json" | jq '.[0] // {}')"

# ─── 2. 流量趋势（按天聚合） ────────────────────────────────────────
trend_sql="
SELECT substr(pos.published_at, 1, 10) AS day,
       COUNT(*) AS posts_count,
       ROUND(AVG(CAST(pm.saves AS REAL) / MAX(pm.likes, 1)), 4) AS avg_save_rate,
       SUM(pm.likes) AS total_likes, SUM(pm.saves) AS total_saves
FROM posts pos
LEFT JOIN (
  SELECT m.post_id, m.likes, m.saves FROM post_metrics m
  INNER JOIN (SELECT post_id, MAX(checked_at) AS mx FROM post_metrics GROUP BY post_id) lm
    ON m.post_id = lm.post_id AND m.checked_at = lm.mx
) pm ON pos.id = pm.post_id
WHERE $SOURCE_FILTER AND pos.published_at >= date('now', '-${DAYS} days')
GROUP BY day ORDER BY day DESC;
"
trend_json="$(sqlite3 -json "$DB_PATH" "$trend_sql" 2>/dev/null || echo '[]')"
[ -z "$trend_json" ] && trend_json='[]'

# ─── 3. Top 5 / Bottom 5 ────────────────────────────────────────────
top5_json="$(sqlite3 -json "$DB_PATH" "$LATEST_METRICS_SQL ORDER BY save_rate DESC LIMIT 5;" 2>/dev/null || echo '[]')"
[ -z "$top5_json" ] && top5_json='[]'

# Bottom 排除 published < 7 天的（数据还没稳定）
bottom5_json="$(sqlite3 -json "$DB_PATH" "$LATEST_METRICS_SQL AND (pos.published_at IS NULL OR pos.published_at <= date('now', '-7 days')) ORDER BY save_rate ASC LIMIT 5;" 2>/dev/null || echo '[]')"
[ -z "$bottom5_json" ] && bottom5_json='[]'

# ─── 4. 主题分布 ────────────────────────────────────────────────────
topics_json="$(sqlite3 -json "$DB_PATH" "
SELECT COALESCE(pos.topic_type, '__unclassified__') AS topic_type,
       COUNT(*) AS posts_count,
       ROUND(AVG(CAST(pm.saves AS REAL) / MAX(pm.likes, 1)), 4) AS avg_save_rate
FROM posts pos
LEFT JOIN (SELECT m.post_id, m.likes, m.saves FROM post_metrics m
  INNER JOIN (SELECT post_id, MAX(checked_at) AS mx FROM post_metrics GROUP BY post_id) lm
    ON m.post_id = lm.post_id AND m.checked_at = lm.mx) pm ON pos.id = pm.post_id
WHERE $SOURCE_FILTER AND pos.published_at >= date('now', '-${DAYS} days')
GROUP BY topic_type ORDER BY posts_count DESC;" 2>/dev/null || echo '[]')"
[ -z "$topics_json" ] && topics_json='[]'

# ─── 5. 标题模式命中率 ──────────────────────────────────────────────
patterns_json="$(sqlite3 -json "$DB_PATH" "
SELECT COALESCE(pos.title_pattern, '__unclassified__') AS title_pattern,
       COUNT(*) AS posts_count,
       ROUND(AVG(CAST(pm.saves AS REAL) / MAX(pm.likes, 1)), 4) AS avg_save_rate,
       ROUND(MAX(CAST(pm.saves AS REAL) / MAX(pm.likes, 1)), 4) AS max_save_rate
FROM posts pos
LEFT JOIN (SELECT m.post_id, m.likes, m.saves FROM post_metrics m
  INNER JOIN (SELECT post_id, MAX(checked_at) AS mx FROM post_metrics GROUP BY post_id) lm
    ON m.post_id = lm.post_id AND m.checked_at = lm.mx) pm ON pos.id = pm.post_id
WHERE $SOURCE_FILTER AND pos.published_at >= date('now', '-${DAYS} days')
GROUP BY title_pattern ORDER BY avg_save_rate DESC;" 2>/dev/null || echo '[]')"
[ -z "$patterns_json" ] && patterns_json='[]'

# ─── 6. 评论需求积压 ────────────────────────────────────────────────
comments_json="$(sqlite3 -json "$DB_PATH" "
SELECT ci.content_requests, ci.top_questions, ci.post_id, pos.title
FROM comment_insights ci
INNER JOIN posts pos ON ci.post_id = pos.id
WHERE $SOURCE_FILTER AND ci.content_requests IS NOT NULL AND ci.content_requests != ''
ORDER BY ci.analyzed_at DESC LIMIT 20;" 2>/dev/null || echo '[]')"
[ -z "$comments_json" ] && comments_json='[]'

# ─── 7. 风险信号 ────────────────────────────────────────────────────
# 规则:
#   - 连续 3 条 save_rate < 0.02 -> consecutive_low
#   - 最近 30 天发布间隔 p95 超 7 天 -> sparse_publishing
#   - imported posts 数量 < 10 -> insufficient_history
risk_imported_count="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM posts WHERE source='imported';" 2>/dev/null || echo 0)"
consecutive_low="$(sqlite3 "$DB_PATH" "
WITH ordered AS (
  SELECT pos.id, pos.published_at, CAST(pm.saves AS REAL) / MAX(pm.likes, 1) AS rate,
         ROW_NUMBER() OVER (ORDER BY pos.published_at DESC) AS rn
  FROM posts pos INNER JOIN (SELECT m.post_id, m.likes, m.saves FROM post_metrics m
    INNER JOIN (SELECT post_id, MAX(checked_at) AS mx FROM post_metrics GROUP BY post_id) lm
      ON m.post_id = lm.post_id AND m.checked_at = lm.mx) pm ON pos.id = pm.post_id
  WHERE $SOURCE_FILTER AND pos.published_at IS NOT NULL
)
SELECT COUNT(*) FROM ordered WHERE rn <= 3 AND rate < 0.02;" 2>/dev/null || echo 0)"

risks_json=$(jq -cn \
    --argjson imported_count "$risk_imported_count" \
    --argjson consecutive_low "$consecutive_low" \
    '[
        (if $imported_count < 10 then {code:"insufficient_history", detail: "历史帖 <10 条，画像反推置信度低"} else empty end),
        (if $consecutive_low >= 3 then {code:"consecutive_low_performance", detail: "最近 3 条收藏率均 < 2%"} else empty end)
    ]')

# ─── 组装 JSON ──────────────────────────────────────────────────────
audit_json=$(jq -cn \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson days "$DAYS" \
    --arg scope "$([ "$INCLUDE_ORGANIC" = "1" ] && echo 'imported+shuling' || echo 'imported')" \
    --argjson snapshot "$snapshot" \
    --argjson trend "$trend_json" \
    --argjson top5 "$top5_json" \
    --argjson bottom5 "$bottom5_json" \
    --argjson topics "$topics_json" \
    --argjson title_patterns "$patterns_json" \
    --argjson comments "$comments_json" \
    --argjson risks "$risks_json" \
    '{
        meta: {generated_at: $generated_at, window_days: $days, scope: $scope, schema_version: "audit-report-v1"},
        account_snapshot: $snapshot,
        traffic_trend: $trend,
        top_posts: $top5,
        bottom_posts: $bottom5,
        topic_distribution: $topics,
        title_pattern_performance: $title_patterns,
        comment_backlog: $comments,
        risk_signals: $risks,
        ai_narrative: null
    }')

# ─── extract-patterns 附加 ──────────────────────────────────────────
if [ "$EXTRACT_PATTERNS" = "1" ]; then
    # Top 20% 作为 pattern 候选；Bottom 10% 作为 anti-pattern 候选
    # 阈值 P80/P10 基于 imported 集合的 save_rate
    p_bounds_json="$(sqlite3 -json "$DB_PATH" "$LATEST_METRICS_SQL ORDER BY save_rate;" 2>/dev/null || echo '[]')"
    cnt="$(echo "$p_bounds_json" | jq 'length')"
    if [ "$cnt" -ge 10 ]; then
        p80_idx=$(( cnt * 80 / 100 ))
        p10_idx=$(( cnt * 10 / 100 ))
        pattern_candidates="$(echo "$p_bounds_json" | jq --argjson lo "$p80_idx" '.[$lo:]' )"
        anti_pattern_candidates="$(echo "$p_bounds_json" | jq --argjson hi "$p10_idx" '.[:$hi]' )"
    else
        pattern_candidates='[]'
        anti_pattern_candidates='[]'
    fi
    audit_json=$(echo "$audit_json" | jq \
        --argjson pc "$pattern_candidates" \
        --argjson apc "$anti_pattern_candidates" \
        '. + {extract_patterns: {pattern_candidates: $pc, anti_pattern_candidates: $apc, note: "AI 需提取标题/结构模式写入 patterns.md(confidence=medium) / anti-patterns.md"}}')
fi

# ─── 输出 ───────────────────────────────────────────────────────────
if [ "$JSON_ONLY" = "1" ]; then
    echo "$audit_json" | jq .
    exit 0
fi

echo "$audit_json" | jq . > "$JSON_OUT"
echo "✅ JSON 已写: $JSON_OUT"

# Markdown 骨架（AI 后续读 JSON 后追加归因与建议）
cat > "$MD_OUT" <<EOF
# 账号体检报告 · $TODAY

> 自动生成，AI 后续追加归因与建议。
> JSON 数据：[\`$(basename "$JSON_OUT")\`](./$(basename "$JSON_OUT"))
> 统计窗口：最近 $DAYS 天
> 范围：$([ "$INCLUDE_ORGANIC" = "1" ] && echo '薯灵创作 + 老博主导入' || echo '仅老博主导入')

---

## 1. 账号快照
\`\`\`json
$(echo "$snapshot" | jq .)
\`\`\`

## 2. 流量趋势（最近 $DAYS 天）
每日发布量 × 平均收藏率：见 JSON \`.traffic_trend\`

## 3. Top 5 帖（按收藏率）
$(echo "$top5_json" | jq -r '.[] | "- **" + (.save_rate|tostring) + "** \(.title) [\(.note_id)]"')

## 4. Bottom 5 帖
$(echo "$bottom5_json" | jq -r '.[] | "- **" + (.save_rate|tostring) + "** \(.title) [\(.note_id)]"')

## 5. 主题分布
$(echo "$topics_json" | jq -r '.[] | "- **\(.topic_type)**: \(.posts_count) 条, avg 收藏率 \(.avg_save_rate // 0)"')

## 6. 标题模式命中率
$(echo "$patterns_json" | jq -r '.[] | "- **\(.title_pattern)**: \(.posts_count) 条, avg \(.avg_save_rate // 0), max \(.max_save_rate // 0)"')

## 7. 评论需求积压（top 20）
$(echo "$comments_json" | jq -r '.[] | "- 《\(.title)》: \(.content_requests // "")"' | head -20)

## 8. 风险信号
$(echo "$risks_json" | jq -r '.[] | "- ⚠️ **\(.code)**: \(.detail)"')

---

## 🧠 AI 归因与建议（待填）

> AI 读完上述 JSON 后，在此追加：
> 1. Top/Bottom 的成因分析
> 2. 本周可立即执行的 3 个行动建议
> 3. 需要进一步观察的信号

EOF

echo "✅ Markdown 已写: $MD_OUT"
echo "✅ 建议让 AI 读 $JSON_OUT 做二次归因，追加到 $MD_OUT"
