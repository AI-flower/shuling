#!/usr/bin/env bash
# v2.3.0 upgrade hook: preferences.json 旧扁平 → 新 dimensions 嵌套
# 幂等：文件不存在 skip / 已是 dimensions skip / 旧格式则备份后重写
# 输出单行 JSON

set -e

TARGET_PATH="${1:-}"
if [ -z "$TARGET_PATH" ] || [ ! -d "$TARGET_PATH" ]; then
    echo '{"status":"failed","detail":"target_path required or not a directory"}'
    exit 1
fi

PREF_FILE="$TARGET_PATH/knowledge-base/preferences.json"

if [ ! -f "$PREF_FILE" ]; then
    echo "{\"status\":\"skipped\",\"reason\":\"preferences.json not found\",\"target\":\"$TARGET_PATH\"}"
    exit 0
fi

# ─── 检查是否有效 JSON ─────────────────────────────────────
if ! jq empty "$PREF_FILE" >/dev/null 2>&1; then
    echo "{\"status\":\"failed\",\"detail\":\"preferences.json is not valid JSON\",\"target\":\"$TARGET_PATH\"}"
    exit 1
fi

# ─── 判定结构 ──────────────────────────────────────────────
# 新结构：有 .dimensions 对象
# 旧结构：有 .topic_preferences / .style_preferences / .title_pattern_preferences 中任意一个
has_dimensions=$(jq 'has("dimensions")' "$PREF_FILE")
has_old=$(jq '(has("topic_preferences") or has("style_preferences") or has("title_pattern_preferences"))' "$PREF_FILE")

if [ "$has_dimensions" = "true" ]; then
    echo "{\"status\":\"skipped\",\"reason\":\"already dimensions format\",\"target\":\"$TARGET_PATH\"}"
    exit 0
fi

if [ "$has_old" != "true" ]; then
    # 既不是新、也不是旧 → 可能是其他自定义结构，不敢动
    echo "{\"status\":\"skipped\",\"reason\":\"neither dimensions nor legacy flat keys present\",\"target\":\"$TARGET_PATH\"}"
    exit 0
fi

# ─── 备份 ──────────────────────────────────────────────────
TS=$(date +%Y%m%d-%H%M%S)
BACKUP="${PREF_FILE}.bak-v2.3.0-${TS}"
cp "$PREF_FILE" "$BACKUP"

# ─── 改写：把旧 key 搬到 dimensions.* ──────────────────────
# 同时保留其他顶层字段（total_choices / confidence_level / choice_log / updated_at 等）
TODAY=$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')  # ISO 8601 with colon in tz
TMP="${PREF_FILE}.tmp.$$"

jq --arg updated_at "$TODAY" '
    {
        dimensions: {
            topic:         (.topic_preferences         // {}),
            style:         (.style_preferences         // {}),
            title_pattern: (.title_pattern_preferences // {})
        }
    }
    +
    (. | del(.topic_preferences, .style_preferences, .title_pattern_preferences, .dimensions))
    | .updated_at         = $updated_at
    | .total_choices      = (.total_choices // 0)
    | .confidence_level   = (.confidence_level // 0.0)
    | .consecutive_rejects = (.consecutive_rejects // 0)
    | .last_exploration_at = (.last_exploration_at // null)
    | .choice_log         = (.choice_log // [])
' "$PREF_FILE" > "$TMP"

# ─── 校验新文件仍是 JSON ───────────────────────────────────
if ! jq empty "$TMP" >/dev/null 2>&1; then
    rm -f "$TMP"
    # 备份已做，不回滚（留证据给人）
    echo "{\"status\":\"failed\",\"detail\":\"rewrite produced invalid JSON, backup kept at $BACKUP\",\"target\":\"$TARGET_PATH\"}"
    exit 1
fi

mv "$TMP" "$PREF_FILE"

echo "{\"status\":\"ok\",\"detail\":\"migrated legacy flat keys to dimensions, backup: $BACKUP\",\"target\":\"$TARGET_PATH\"}"
