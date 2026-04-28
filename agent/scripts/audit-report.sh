#!/usr/bin/env bash
# audit-report.sh — 账号体检报告生成器（v2.2.0 新增）
#
# 读 DB 做纯统计，输出两份文件:
#   agent/knowledge-base/audit-<YYYY-MM-DD>.json   结构化（AI 读 + agent/schemas/audit-report.schema.json 校验）
#   agent/knowledge-base/audit-<YYYY-MM-DD>.md     人类可读骨架（AI 后续追加归因分析）
#
# 统计维度（MVP 8 项 + v3.2 业务情报 8 项）:
#   1. 账号快照 (historical_stats 最新行)
#   2. 流量趋势（最近 N 天每日发布量 × 平均收藏率）
#   3. Top 5 / Bottom 5 帖（按收藏率）
#   4. 主题分布 (topic_type × 帖子数 × avg 收藏率)
#   5. 标题模式命中率 (title_pattern × 平均收藏率)
#   6. 评论需求积压（comment_insights.content_requests top-K）
#   7. 风险信号（连续低表现 / 发布密度异常）
#   8. (Layer 1 不含) AI 归因分析 — 由 AI 读 JSON 后追加到 md
#
#   ─── v3.2: 业务情报段（plan §7.4）──
#   9.  业务画像推测（AI 待填：creator_track / creator_stage / primary_goal / 等）
#   10. 商业模式轻量测试（前 3 项必答：利润证据 / 平台匹配 / 商业阶段）
#   11. 利润证据与平台匹配（证据明细：商业意图评论笔记列表）
#   12. 高流量低业务价值内容（top_posts 中无商业意图信号的）
#   13. 低流量高意图内容（bottom_posts 中评论有意图信号的）
#   14. 方向漂移与执行摩擦信号（topic_type 切换次数 + creator_behavior_signals）
#   15. 建议保留的业务 pattern（AI 待填，落 business-patterns.md）
#   16. 建议停止的业务 anti-pattern（AI 待填，落 business-anti-patterns.md）
#
#   架构选择：v3.2 段落混合——脚本生成数据骨架（SQL/jq），LLM 后续读 JSON
#   填入业务画像推测、利润证据等级、平台变现匹配、商业阶段、商业 pattern 等需要判断的字段。
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

# ─── v3.2: 业务画像反推所需的辅助查询 ──────────────────────────────
# 这些查询给 AI 做业务归因时提供原料（高流量低互动 / 低流量高意图 / 评论商业意图等）。
# 字段从最近 $DAYS 天的 imported posts 中筛。

# 商业意图评论 hits（评论里出现「多少钱/价格/链接/购买/报名/咨询/微信/合作」等词的笔记）
buy_intent_posts_json="$(sqlite3 -json "$DB_PATH" "
SELECT ci.post_id, pos.title, pos.note_id,
       ci.content_requests, ci.top_questions
FROM comment_insights ci
INNER JOIN posts pos ON ci.post_id = pos.id
WHERE $SOURCE_FILTER
  AND (
    IFNULL(ci.content_requests, '') LIKE '%价%'
    OR IFNULL(ci.content_requests, '') LIKE '%多少钱%'
    OR IFNULL(ci.content_requests, '') LIKE '%购买%'
    OR IFNULL(ci.content_requests, '') LIKE '%链接%'
    OR IFNULL(ci.content_requests, '') LIKE '%报名%'
    OR IFNULL(ci.content_requests, '') LIKE '%咨询%'
    OR IFNULL(ci.content_requests, '') LIKE '%微信%'
    OR IFNULL(ci.content_requests, '') LIKE '%合作%'
    OR IFNULL(ci.top_questions,    '') LIKE '%价%'
    OR IFNULL(ci.top_questions,    '') LIKE '%多少钱%'
    OR IFNULL(ci.top_questions,    '') LIKE '%购买%'
    OR IFNULL(ci.top_questions,    '') LIKE '%报名%'
    OR IFNULL(ci.top_questions,    '') LIKE '%咨询%'
  )
ORDER BY ci.analyzed_at DESC LIMIT 30;" 2>/dev/null || echo '[]')"
[ -z "$buy_intent_posts_json" ] && buy_intent_posts_json='[]'

# 高流量低业务价值候选: 收藏率 ≥ P80 但评论里完全无商业意图信号
# 简化实现：取 top5_json 与 buy_intent_posts_json 的 note_id 差集
hi_traffic_lo_intent_json=$(jq -cn \
    --argjson top "$top5_json" \
    --argjson buy "$buy_intent_posts_json" \
    '
    ($buy | map(.note_id)) as $buy_ids
    | $top | map(select( ($buy_ids | index(.note_id // "")) | not ))
    ' 2>/dev/null || echo '[]')
[ -z "$hi_traffic_lo_intent_json" ] && hi_traffic_lo_intent_json='[]'

# 低流量高意图候选: 收藏率 ≤ 中位数但评论里出现商业意图
low_traffic_hi_intent_json=$(jq -cn \
    --argjson bot "$bottom5_json" \
    --argjson buy "$buy_intent_posts_json" \
    '
    ($buy | map(.note_id)) as $buy_ids
    | $bot | map(select( ($buy_ids | index(.note_id // "")) ))
    ' 2>/dev/null || echo '[]')
[ -z "$low_traffic_hi_intent_json" ] && low_traffic_hi_intent_json='[]'

# 方向漂移信号: 14 天滚动窗口内 topic_type 切换次数
direction_changes_14d="$(sqlite3 "$DB_PATH" "
WITH recent AS (
  SELECT topic_type, published_at
  FROM posts
  WHERE $SOURCE_FILTER
    AND published_at >= date('now', '-14 days')
    AND topic_type IS NOT NULL
    AND topic_type != ''
    AND topic_type != '__unclassified__'
  ORDER BY published_at
),
shifts AS (
  SELECT topic_type,
         LAG(topic_type) OVER (ORDER BY published_at) AS prev_topic
  FROM recent
)
SELECT COUNT(*) FROM shifts WHERE prev_topic IS NOT NULL AND topic_type != prev_topic;" 2>/dev/null || echo 0)"

# 已写入的行为信号（最近 30 天）
behavior_signals_json="$(sqlite3 -json "$DB_PATH" "
SELECT signal_type, severity, observed_at, signal_json
FROM creator_behavior_signals
WHERE date(observed_at) >= date('now', '-30 days')
ORDER BY observed_at DESC LIMIT 20;" 2>/dev/null || echo '[]')"
[ -z "$behavior_signals_json" ] && behavior_signals_json='[]'

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
    --argjson buy_intent "$buy_intent_posts_json" \
    --argjson hi_lo "$hi_traffic_lo_intent_json" \
    --argjson lo_hi "$low_traffic_hi_intent_json" \
    --argjson dir_changes "$direction_changes_14d" \
    --argjson behavior "$behavior_signals_json" \
    '{
        meta: {generated_at: $generated_at, window_days: $days, scope: $scope, schema_version: "audit-report-v2-business"},
        account_snapshot: $snapshot,
        traffic_trend: $trend,
        top_posts: $top5,
        bottom_posts: $bottom5,
        topic_distribution: $topics,
        title_pattern_performance: $title_patterns,
        comment_backlog: $comments,
        risk_signals: $risks,
        business_intelligence: {
            buy_intent_posts: $buy_intent,
            high_traffic_low_business_value: $hi_lo,
            low_traffic_high_intent: $lo_hi,
            direction_changes_14d: $dir_changes,
            behavior_signals_recent: $behavior,
            note: "AI 需基于本块原始数据反推业务画像 6 维度 + 商业模式 7 测试前 3 项 (利润证据 / 平台变现匹配 / 商业阶段)，并在 .md 对应段落填入。"
        },
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

# 业务情报（v3.2 新增）

> 以下段落由 audit-report.sh 提供原始统计 + 占位骨架，AI 必须读取本文配套 JSON 的 \`.business_intelligence\` 字段后回填判断与证据。
>
> 输出原则：只描述可观察证据 + 给出可统计指标，不做心理诊断、不评价人格、不断言用户收入（参考 \`agent/playbook/02-onboarding-existing.md\` Replacement Risk Hint 与 Behavior Signal Initial Scan 输出原则）。

## 9. 业务画像推测（AI 待填）

> AI 读 \`.business_intelligence\` + \`.comment_backlog\` + \`.topic_distribution\` 后，在此填入：
>
> - \`creator_track\`: creator_first / offer_first / exploration（说明判断依据）
> - \`creator_stage\`: new / has_posts / has_followers / has_leads / has_sales / has_repeat_sales
> - \`primary_goal\`: grow_followers / build_trust / get_leads / drive_sales / prepare_live / product_research / unknown
> - \`offer_status\`: none / idea / draft / selling / validated
> - \`monetization_stage\`: no_offer / offer_no_purchase / purchase_no_repeat / repeat_no_scale / scaled / unknown
> - \`current_bottleneck\`: 当前最阻塞瓶颈（schema 限定枚举值）
>
> 反推完成后必须展示给用户确认，**不直接写入 business-profile.json**。

## 10. 商业模式轻量测试（前 3 项必答）

> 老博主必须至少回答 3 项：利润证据 / 平台变现匹配 / 商业阶段。后 4 项尽量给出，证据不足允许 \`unknown\`，不强行下结论（plan §5.1.5）。

### 10.1 利润证据等级

> AI 基于 \`.business_intelligence.buy_intent_posts\` + \`.comment_backlog\` 填入：
>
> - 等级（hard / medium / weak / none / unknown）：
> - 证据列表（必须可观察、可计数；例：「评论区出现 12 次问价」「主页有咨询入口」）：

### 10.2 平台变现匹配

> 小红书流量与当前推测变现路径的匹配度（strong / medium / weak / unknown）：
>
> 判断依据（客单价 / 决策周期 / 内容信任要求 / 低毛利商品风险）：

### 10.3 商业阶段判断

> 当前所处阶段（从「无产品 / 有产品无人买 / 有人买不复购 / 有复购无规模化 / 已规模化」中选）：
>
> 判断依据：

## 11. 利润证据与平台匹配（证据明细）

商业意图评论笔记数：$(echo "$buy_intent_posts_json" | jq 'length') 条
$(echo "$buy_intent_posts_json" | jq -r '.[] | "- 《\(.title // "")》: \(.content_requests // "" | tostring | .[0:80])"' | head -10)

> AI 在此追加：评论原话样本 → 证据级别归类。

## 12. 高流量低业务价值内容

$(echo "$hi_traffic_lo_intent_json" | jq -r '.[]? | "- \(.title) [\(.note_id)] save_rate=\(.save_rate // 0)"')

> AI 在此判断：这些内容是否「高粉丝、低利润」陷阱？建议如何调整 CTA / 选题方向？

## 13. 低流量高意图内容

$(echo "$low_traffic_hi_intent_json" | jq -r '.[]? | "- \(.title) [\(.note_id)] save_rate=\(.save_rate // 0)"')

> AI 在此判断：这些低流量但有商业意图评论的内容是否值得复用 / 系列化 / 改写标题？

## 14. 方向漂移与执行摩擦信号

- 14 天内方向切换次数（基于 \`topic_type\`）：${direction_changes_14d:-0}
- 已记录的行为信号（最近 30 天）：$(echo "$behavior_signals_json" | jq 'length') 条

$(echo "$behavior_signals_json" | jq -r '.[]? | "- \(.observed_at) **\(.signal_type)** [\(.severity // "info")]: \(.signal_json | fromjson | .interpretation // "")"' | head -10)

> 注意：行为信号写入必须遵守 \`agent/playbook/08-compliance.md\` Behavior Signal Output Validation 输出原则——
> 仅描述可观察事件 + 给出当天可完成的下一步动作；
> **禁词**：逃避 / 自卑 / 不想赚钱 / 拖延症 / 心理咨询 / 人格 / 不够自律 / 害怕失败。

## 15. 建议保留的业务 pattern（AI 待填）

> AI 从历史 imported posts 中识别**反复出现且带正向业务信号**（询价 / 咨询 / 高收藏 / 高保存）的模式，写入：
>
> - 标题模式
> - 选题角度
> - 互动引导句式
> - 转化路径设计
>
> 同步建议 AI 落入 \`agent/knowledge-base/business-patterns.md\`（confidence=medium，证据来自用户自身历史）。

## 16. 建议停止的业务 anti-pattern（AI 待填）

> AI 从历史 imported posts 中识别**高流量低业务价值**或**重复无效**的模式，写入：
>
> - 高流量但完全无商业意图评论的标题/选题套路
> - 用户语言不匹配的措辞
> - 与当前 \`primary_goal\` 不对齐的内容方向
> - 信任损伤信号（争议 / 误解 / 反对意见处理失败）
>
> 同步建议 AI 落入 \`agent/knowledge-base/business-anti-patterns.md\`。

---

## 🧠 AI 归因与建议（待填）

> AI 读完上述 JSON 后，在此追加：
> 1. Top/Bottom 的成因分析
> 2. 本周可立即执行的 3 个行动建议
> 3. 需要进一步观察的信号
> 4. **\`replacement_risk\` 评估**：如果利润证据 ∈ {hard, medium} 且替代风险 == high，必须追加替代风险提示段（见 02-onboarding-existing.md Replacement Risk Hint）

EOF

echo "✅ Markdown 已写: $MD_OUT"
echo "✅ 建议让 AI 读 $JSON_OUT 做二次归因，追加到 $MD_OUT"
