#!/usr/bin/env bash
# import-existing.sh — 老博主接入：批量导入自己账号的历史发布
#
# v2.2.0 "Existing Creator Support" 新增。
# 把已登录账号的历史帖拉到本地 DB (posts.source='imported')，供:
#   - 画像反推 (AI 读样本)
#   - patterns.md 种子挖掘 (audit-report --extract-patterns)
#   - preferences.json bootstrap (本脚本自动完成)
#
# 用法（v3.1+ 默认 limit=50；plan/run 子命令）:
#   bash agent/scripts/import-existing.sh plan --limit 200       # 估算批次数 + 节流估时
#   bash agent/scripts/import-existing.sh run --batch 50         # 真跑（每批之间 cooldown）
#   bash agent/scripts/import-existing.sh                        # 兼容旧调用：直接 run --limit 50
#   bash agent/scripts/import-existing.sh --limit 500            # 调高 limit（仍走分批）
#   bash agent/scripts/import-existing.sh --dry-run              # 只打印计划，不写 DB
#   bash agent/scripts/import-existing.sh --resume               # 从 import-state.json 断点续跑
#   bash agent/scripts/import-existing.sh --batch-size 20        # 单批笔记数（控制节流总时长）
#   bash agent/scripts/import-existing.sh --unsafe-override-quota   # v3.1+ 名（仅 dev mode + TTY）
#   bash agent/scripts/import-existing.sh --override-quota       # v3.0 旧名，deprecated（仍生效一次）
#   bash agent/scripts/import-existing.sh --mock tests/mock-feeds.json   # 本地测试
#
# 环境变量:
#   SHULING_IMPORT_USER_ID   目标用户 ID（默认自动检测为自己）
#   SHULING_DEV_MODE=1       --unsafe-override-quota 必须的开关
#
# 注意:
#   - get_feed_detail MIN_GAP=10s + 50/日 (默认 profile)
#   - 50 条实际耗时 ~10 分钟（按 10s gap）
#   - cookie 过期会中断，--resume 可续
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# v3.1+ 一致性收口：用 _paths.sh 的 SHULING_SCRIPTS_DIR
_IMPORT_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$_IMPORT_SCRIPT_DIR/_paths.sh" ] && . "$_IMPORT_SCRIPT_DIR/_paths.sh"
SCRIPTS_DIR="${SHULING_SCRIPTS_DIR:-$SKILL_DIR/scripts}"
CACHE_DIR="${XHS_CACHE_DIR:-$HOME/.cache/shuling}"
STATE_FILE="$CACHE_DIR/import-state.json"
ERROR_LOG="$CACHE_DIR/import-errors.log"
mkdir -p "$CACHE_DIR"

# ─── 颜色 ───────────────────────────────────────────────────────────
C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'; C_BOLD='\033[1m'; C_DIM='\033[2m'; C_RESET='\033[0m'
info() { printf "${C_GREEN}[OK]${C_RESET}  %s\n" "$1"; }
warn() { printf "${C_YELLOW}[!]${C_RESET}   %s\n" "$1"; }
fail() { printf "${C_RED}[ERR]${C_RESET} %s\n" "$1" >&2; }
step() { printf "${C_DIM}[..]${C_RESET} %s\n" "$1"; }

# ─── 参数 ───────────────────────────────────────────────────────────
# v3.1+ default LIMIT 从 200 调到 50（高读请求保护，见 §14.1-§14.2）
LIMIT=50
BATCH_SIZE=50
DRY_RUN=0
RESUME=0
OVERRIDE_QUOTA=0
UNSAFE_OVERRIDE=0
DEPRECATED_OLD_FLAG=0
MOCK_FILE=""
USER_ID="${SHULING_IMPORT_USER_ID:-}"
SUBCMD=""   # plan / run；空表示走兼容旧路径

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

# v3.1+: 第一个非 - 起头的参数若是 plan/run，则识别为子命令
if [ $# -gt 0 ]; then
    case "$1" in
        plan|run) SUBCMD="$1"; shift ;;
    esac
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --limit)           shift; LIMIT="$1"; shift ;;
        --batch|--batch-size)
                           shift; BATCH_SIZE="$1"; shift ;;
        --dry-run)         DRY_RUN=1; shift ;;
        --resume)          RESUME=1; shift ;;
        --override-quota)
                           DEPRECATED_OLD_FLAG=1
                           OVERRIDE_QUOTA=1
                           UNSAFE_OVERRIDE=1
                           shift
                           ;;
        --unsafe-override-quota)
                           OVERRIDE_QUOTA=1
                           UNSAFE_OVERRIDE=1
                           shift
                           ;;
        --mock)            shift; MOCK_FILE="$1"; shift ;;
        --user)            shift; USER_ID="$1"; shift ;;
        -h|--help)         usage; exit 0 ;;
        *) fail "未知参数: $1"; usage; exit 2 ;;
    esac
done

if [ "$DEPRECATED_OLD_FLAG" = "1" ]; then
    warn "[deprecated] --override-quota 已改名为 --unsafe-override-quota（v3.1）。本次仍按旧名生效；v3.2 移除。"
fi

# v3.1+ unsafe override 守卫：必须 SHULING_DEV_MODE=1 + TTY
if [ "$UNSAFE_OVERRIDE" = "1" ]; then
    if [ "${SHULING_DEV_MODE:-0}" != "1" ]; then
        echo '{"ok":false,"error":"dev_mode_required","message":"--unsafe-override-quota 必须 SHULING_DEV_MODE=1（生产保护）"}'
        exit 2
    fi
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo '{"ok":false,"error":"unsafe_override_requires_tty","message":"--unsafe-override-quota 在非 TTY 环境（cron/CI）下被禁止"}'
        exit 2
    fi
fi

if [ "$OVERRIDE_QUOTA" = "1" ]; then
    export XHS_DISABLE_QUOTA=1
    warn "已设 XHS_DISABLE_QUOTA=1（限于此场景；仍受节流保护；仍写 request_log）"
fi

# ─── plan 子命令：估算批次数 + 节流估时 ────────────────────────────────
if [ "$SUBCMD" = "plan" ]; then
    batches=$(( (LIMIT + BATCH_SIZE - 1) / BATCH_SIZE ))
    # min_gap=10s × LIMIT + cooldown 5min × (batches-1)
    estimated_seconds=$(( LIMIT * 10 + (batches > 1 ? (batches - 1) * 300 : 0) ))
    estimated_minutes=$(( (estimated_seconds + 59) / 60 ))
    cat <<EOF
{"plan":{"total":$LIMIT,"batches":$batches,"batch_size":$BATCH_SIZE,"estimated_minutes":$estimated_minutes,"per_batch_cooldown_seconds":300}}
EOF
    exit 0
fi

# ─── 依赖检查 ───────────────────────────────────────────────────────
command -v jq       >/dev/null 2>&1 || { fail "jq 未安装（apt install jq / brew install jq）"; exit 1; }
command -v sqlite3  >/dev/null 2>&1 || { fail "sqlite3 未安装"; exit 1; }

# ─── MCP 调用包装（TODO: 真实 MCP list_feeds 语义要按 xiaohongshu-mcp README 确认） ──
#
# 目前 agent/scripts/xhs.sh 暴露的子命令没有 list-user-feeds；
# MCP 原生有 list_feeds 工具（见 VERSION hands.mcp_tools），但 xhs.sh 没包装。
# v2.2.0 阶段方案:
#   1. MOCK 模式: --mock <file.json> 读本地 JSON，格式见 tests/mock-feeds.schema
#   2. 真实模式: 调 xhs.sh mcp-call list_feeds <args>（后续迭代扩展 xhs.sh 暴露该子命令）
#
mcp_list_user_feeds() {
    local user_id="$1" cursor="${2:-}" count="${3:-20}"
    if [ -n "$MOCK_FILE" ]; then
        jq -c --arg cursor "$cursor" --argjson count "$count" '
            .feeds
            | [.[] | select(.note_id != null)]
            | if $cursor == "" then .[0:$count] else (map(select(.note_id > $cursor)))[0:$count] end
            | {feeds: ., next_cursor: (.[-1].note_id // "")}
        ' "$MOCK_FILE"
        return 0
    fi
    # TODO(v2.2.1): 调真实 MCP。占位实现返回空，让调用方感知到"未实现"而不是假装成功
    echo '{"feeds": [], "next_cursor": "", "__todo__": "list_feeds MCP integration pending"}' >&2
    echo '{"feeds": [], "next_cursor": "", "__todo__": "list_feeds MCP integration pending"}'
    return 0
}

mcp_get_detail() {
    local note_id="$1"
    if [ -n "$MOCK_FILE" ]; then
        jq -c --arg nid "$note_id" '.details[$nid] // empty' "$MOCK_FILE"
        return 0
    fi
    # 真实路径: 走 xhs.sh detail，自动吃节流/限额/日志
    bash "$SCRIPTS_DIR/xhs.sh" detail "$note_id" 2>/dev/null || echo "{}"
}

mcp_user_profile() {
    local user_id="$1"
    if [ -n "$MOCK_FILE" ]; then
        jq -c --arg uid "$user_id" '.user // empty' "$MOCK_FILE"
        return 0
    fi
    bash "$SCRIPTS_DIR/xhs.sh" user "$user_id" 2>/dev/null || echo "{}"
}

# ─── 状态管理 ───────────────────────────────────────────────────────
load_state() {
    [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo '{"completed":[],"failed":[]}'
}

save_state() {
    local state="$1"
    [ "$DRY_RUN" = "1" ] && return 0
    echo "$state" | jq . > "$STATE_FILE"
}

is_completed() {
    local note_id="$1" state="$2"
    echo "$state" | jq -e --arg nid "$note_id" '.completed | index($nid)' >/dev/null 2>&1
}

# ─── DB 写入 ────────────────────────────────────────────────────────
write_post() {
    local detail_json="$1"
    # 抽取字段。实际字段名依 xiaohongshu-mcp 输出而定，这里按约定名:
    # { note_id, title, content, tags[], published_at, likes, saves, comments, shares }
    local note_id title content tags published_at likes saves comments shares post_json
    note_id="$(echo "$detail_json" | jq -r '.note_id // empty')"
    [ -z "$note_id" ] && { warn "detail 缺 note_id，跳过"; return 1; }
    title="$(echo "$detail_json"   | jq -r '.title // ""')"
    content="$(echo "$detail_json" | jq -r '.content // ""')"
    tags="$(echo "$detail_json"    | jq -r 'if (.tags | type) == "array" then (.tags | join(",")) else (.tags // "") end')"
    published_at="$(echo "$detail_json" | jq -r '.published_at // .created_at // ""')"
    likes="$(echo "$detail_json"    | jq -r '.likes // 0')"
    saves="$(echo "$detail_json"    | jq -r '.saves // 0')"
    comments="$(echo "$detail_json" | jq -r '.comments // 0')"
    shares="$(echo "$detail_json"   | jq -r '.shares // 0')"

    local pub_date
    pub_date="${published_at:0:10}"
    [ -z "$pub_date" ] && pub_date="$(date +%Y-%m-%d)"

    post_json=$(jq -cn \
        --arg date "$pub_date" \
        --arg slot "imported" \
        --arg title "$title" \
        --arg content "$content" \
        --arg tags "$tags" \
        --arg note_id "$note_id" \
        --arg status "published" \
        --arg source "imported" \
        --arg published_at "$published_at" \
        '{date:$date,slot:$slot,title:$title,content:$content,tags:$tags,note_id:$note_id,status:$status,source:$source,published_at:$published_at}')

    if [ "$DRY_RUN" = "1" ]; then
        printf "${C_DIM}[dry]${C_RESET} add-post %s (%s)\n" "$note_id" "$(echo "$title" | head -c 40)"
        return 0
    fi

    local post_resp post_id
    post_resp="$(bash "$SCRIPTS_DIR/db.sh" add-post "$post_json")"
    post_id="$(echo "$post_resp" | jq -r '.id // empty')"
    [ -z "$post_id" ] && { warn "add-post 失败: $post_resp"; return 1; }

    # metrics 快照
    local metrics_json
    metrics_json=$(jq -cn \
        --argjson pid "$post_id" \
        --arg checkpoint "imported-snapshot" \
        --argjson likes "$likes" \
        --argjson saves "$saves" \
        --argjson comments "$comments" \
        --argjson shares "$shares" \
        '{post_id:$pid,checked_at:(now|strftime("%Y-%m-%dT%H:%M:%SZ")),checkpoint:$checkpoint,likes:$likes,saves:$saves,comments:$comments,shares:$shares}')
    bash "$SCRIPTS_DIR/db.sh" add-metrics "$metrics_json" >/dev/null || warn "add-metrics 失败 post_id=$post_id"

    echo "$post_id"
}

# ─── 主流程 ────────────────────────────────────────────────────────
printf "\n${C_BOLD}=== 薯灵 · 老博主接入 · import-existing ===${C_RESET}\n\n"
printf "limit=%s batch=%s dry_run=%s resume=%s mock=%s\n\n" \
    "$LIMIT" "$BATCH_SIZE" "$DRY_RUN" "$RESUME" "${MOCK_FILE:-none}"

# 1) 账号元信息
if [ -z "$USER_ID" ]; then
    step "检测当前登录账号..."
    if [ -n "$MOCK_FILE" ]; then
        USER_ID="$(jq -r '.user.user_id // "mock-self"' "$MOCK_FILE")"
    else
        # 未来: 从 xhs.sh status 解析 self user_id；目前用户未传则报错提示
        fail "未指定用户 ID。请传 --user <self_id> 或设 SHULING_IMPORT_USER_ID（后续版本会自动检测）"
        exit 1
    fi
fi
info "目标用户: $USER_ID"

profile_json="$(mcp_user_profile "$USER_ID")"
step "账号 profile 摘要: $(echo "$profile_json" | jq -c '{nickname, followers: (.followers // .fans), total_posts: (.total_posts // .notes_count)}' 2>/dev/null || echo "<unknown>")"

# 2) 状态初始化
if [ "$RESUME" = "1" ] && [ -f "$STATE_FILE" ]; then
    STATE="$(load_state)"
    done_count="$(echo "$STATE" | jq '.completed | length')"
    info "续跑：已完成 $done_count 条"
else
    STATE="$(jq -cn --arg uid "$USER_ID" --argjson target "$LIMIT" \
        '{started_at: (now|strftime("%Y-%m-%dT%H:%M:%SZ")), user_id: $uid, target_count: $target, completed: [], failed: []}')"
    save_state "$STATE"
fi

# 3) 分页拉取 note_id 列表
step "分页拉取历史 note_id 列表..."
declare -a NOTE_IDS=()
cursor=""
fetched=0
while [ "$fetched" -lt "$LIMIT" ]; do
    remaining=$((LIMIT - fetched))
    page_size=$([ "$remaining" -lt "$BATCH_SIZE" ] && echo "$remaining" || echo "$BATCH_SIZE")
    page_json="$(mcp_list_user_feeds "$USER_ID" "$cursor" "$page_size")"
    todo="$(echo "$page_json" | jq -r '.__todo__ // empty')"
    if [ -n "$todo" ]; then
        warn "$todo — 等后续 MCP 接口集成；当前只在 --mock 模式下可完整运行"
        break
    fi
    page_count="$(echo "$page_json" | jq '.feeds | length')"
    [ "$page_count" = "0" ] && break

    while IFS= read -r nid; do
        NOTE_IDS+=("$nid")
    done < <(echo "$page_json" | jq -r '.feeds[].note_id')

    cursor="$(echo "$page_json" | jq -r '.next_cursor // ""')"
    fetched=$((fetched + page_count))
    [ -z "$cursor" ] && break
done
info "准备处理 ${#NOTE_IDS[@]} 条历史笔记"

# 4) 逐条拉详情 + 写 DB（v3.1+ 每批之间强制 cooldown）
success=0; failed=0; skipped=0
BATCH_COOLDOWN_SECONDS="${SHULING_IMPORT_BATCH_COOLDOWN:-300}"
processed_in_batch=0
batch_idx=1
total=${#NOTE_IDS[@]}
for nid in "${NOTE_IDS[@]}"; do
    if is_completed "$nid" "$STATE"; then
        skipped=$((skipped+1))
        continue
    fi
    step "处理 $nid ..."
    detail="$(mcp_get_detail "$nid")"
    if [ -z "$detail" ] || [ "$detail" = "{}" ]; then
        echo "$(date -u +%FT%TZ) $nid get_detail_empty" >> "$ERROR_LOG"
        STATE="$(echo "$STATE" | jq --arg nid "$nid" '.failed += [{note_id: $nid, reason: "empty_detail"}]')"
        failed=$((failed+1)); save_state "$STATE"; continue
    fi
    if write_post "$detail" >/dev/null; then
        STATE="$(echo "$STATE" | jq --arg nid "$nid" '.completed += [$nid]')"
        success=$((success+1))
    else
        echo "$(date -u +%FT%TZ) $nid write_post_failed" >> "$ERROR_LOG"
        STATE="$(echo "$STATE" | jq --arg nid "$nid" '.failed += [{note_id: $nid, reason: "write_post_failed"}]')"
        failed=$((failed+1))
    fi
    save_state "$STATE"

    processed_in_batch=$((processed_in_batch + 1))
    # 当一个 batch 满 + 还有剩余 → cooldown
    remaining_total=$((total - success - failed - skipped))
    if [ "$processed_in_batch" -ge "$BATCH_SIZE" ] && [ "$remaining_total" -gt 0 ] && [ "$DRY_RUN" = "0" ]; then
        step "[batch $batch_idx done] cooldown ${BATCH_COOLDOWN_SECONDS}s 后继续下一批 (避免连续高频访问)..."
        sleep "$BATCH_COOLDOWN_SECONDS"
        processed_in_batch=0
        batch_idx=$((batch_idx + 1))
    fi
done

# 5) 快照 + bootstrap 偏好（仅非 dry-run）
if [ "$DRY_RUN" = "0" ]; then
    step "写账号快照 (historical_stats)..."
    imported_count="$(sqlite3 "$SKILL_DIR/data/xhs.db" "SELECT COUNT(*) FROM posts WHERE source='imported';" 2>/dev/null || echo 0)"
    earliest="$(sqlite3 "$SKILL_DIR/data/xhs.db" "SELECT MIN(published_at) FROM posts WHERE source='imported' AND published_at IS NOT NULL;" 2>/dev/null || echo "")"
    latest="$(sqlite3 "$SKILL_DIR/data/xhs.db"   "SELECT MAX(published_at) FROM posts WHERE source='imported' AND published_at IS NOT NULL;" 2>/dev/null || echo "")"
    followers="$(echo "$profile_json" | jq -r '.followers // .fans // 0' 2>/dev/null || echo 0)"
    total_likes="$(echo "$profile_json" | jq -r '.total_likes // .likes // 0' 2>/dev/null || echo 0)"
    total_posts="$(echo "$profile_json" | jq -r '.total_posts // .notes_count // 0' 2>/dev/null || echo 0)"

    stat_json=$(jq -cn \
        --arg earliest "$earliest" --arg latest "$latest" \
        --argjson followers "${followers:-0}" \
        --argjson total_likes "${total_likes:-0}" \
        --argjson total_posts "${total_posts:-0}" \
        --argjson imported_posts_count "${imported_count:-0}" \
        --arg meta "{\"user_id\":\"$USER_ID\"}" \
        '{snapshotted_at:(now|strftime("%Y-%m-%dT%H:%M:%SZ")),followers:$followers,total_likes:$total_likes,total_posts:$total_posts,imported_posts_count:$imported_posts_count,earliest_post_at:$earliest,latest_post_at:$latest,meta_json:$meta}')
    bash "$SCRIPTS_DIR/db.sh" add-historical-stat "$stat_json" >/dev/null || warn "快照写入失败"
fi

# 6) 汇总
printf "\n${C_BOLD}=== 导入汇总 ===${C_RESET}\n"
printf "  成功: %s\n  失败: %s\n  已处理(跳过): %s\n  目标: %s\n\n" "$success" "$failed" "$skipped" "$LIMIT"
info "状态文件: $STATE_FILE"
[ -f "$ERROR_LOG" ] && warn "错误日志: $ERROR_LOG"

cat <<EOF

下一步：
  1. 让 AI 读 SKILL.md §0c，对 imported posts 分类（topic_type/title_pattern/content_style）
  2. bash agent/scripts/audit-report.sh               # 出账号体检报告
  3. bash agent/scripts/audit-report.sh --extract-patterns   # 挖 patterns.md 种子

EOF
