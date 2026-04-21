#!/usr/bin/env bash
# 统一的小红书 MCP 操作入口
# 通过 MCP 协议（JSON-RPC over HTTP）与小红书 MCP Server 交互
#
# v2 风控优化（2026-04-21）:
#   1. 分级节流：每个接口独立 MIN_GAP + ±30% 抖动
#   2. 日限额保险丝：按接口当日调用上限，触顶退出
#   3. Session 复用（opt-in）：默认关闭；实测 xiaohongshu-mcp 服务端
#      session 在 2-3 次调用后失效，需要重新 handshake 才能恢复。
#      设 XHS_REUSE_SESSION=1 启用（建议仅用于低频场景或等上游修复）
#
# 可调环境变量:
#   XHS_CACHE_DIR         状态文件目录（默认 ~/.cache/shuling）
#   XHS_REUSE_SESSION     设为 1 启用 session 复用（默认 0）
#   XHS_SESSION_TTL       session 复用 TTL 秒数（默认 120）
#   XHS_DISABLE_THROTTLE  设为 1 跳过节流（仅调试）
#   XHS_DISABLE_QUOTA     设为 1 跳过日限额（仅调试）
#   XHS_DISABLE_LOG       设为 1 跳过请求日志（仅调试）

set -e

MCP_URL="${MCP_URL:-http://localhost:18060/mcp}"
export no_proxy="${no_proxy:+$no_proxy,}localhost,127.0.0.1"

CACHE_DIR="${XHS_CACHE_DIR:-$HOME/.cache/shuling}"
mkdir -p "$CACHE_DIR"
SESSION_FILE="$CACHE_DIR/mcp-session"
QUOTA_FILE="$CACHE_DIR/mcp-quota.json"
SESSION_TTL="${XHS_SESSION_TTL:-120}"
REUSE_SESSION="${XHS_REUSE_SESSION:-0}"
LOG_ENABLED="${XHS_DISABLE_LOG:-0}"   # 1 表示禁用（变量名取反便于 env set 1 生效）

# ── 帮助信息 ──────────────────────────────────────────────
usage() {
  cat <<EOF
用法: $(basename "$0") <子命令> [参数...]

子命令:
  search   <关键词>              搜索小红书内容
  recommend                     获取首页推荐
  detail   <note_id>            获取笔记详情
  publish  <meta.json路径>      发布图文（读取 meta.json）
  comment  <note_id> <内容>     发表评论
  status                        检查登录状态
  login                         获取登录二维码
  import-cookie <cookie|@文件>  导入已抓取的 cookie 替代扫码
  user     <user_id>            获取用户主页
  quota                         查看当日调用计数
  log [--summary] [--days N]    查看请求日志（默认 1 天明细）

环境变量:
  MCP_URL   MCP 服务地址（默认 http://localhost:18060/mcp）
  XHS_DISABLE_THROTTLE=1  跳过节流
  XHS_DISABLE_QUOTA=1     跳过日限额

示例:
  $(basename "$0") search "咖啡推荐"
  $(basename "$0") detail 66a1b2c3d4e5f60001000001
  $(basename "$0") publish ./output/meta.json
  $(basename "$0") quota
EOF
  exit 1
}

# ── 输出格式化 ────────────────────────────────────────────
format_json() {
  if command -v jq &>/dev/null; then
    jq .
  else
    cat
  fi
}

# ── 分级节流配置 ──────────────────────────────────────────
min_gap_for() {
  case "$1" in
    search_feeds)         echo 20 ;;
    get_feed_detail)      echo 10 ;;
    list_feeds)           echo 15 ;;
    publish_content)      echo 300 ;;
    post_comment_to_feed) echo 180 ;;
    user_profile)         echo 30 ;;
    check_login_status)   echo 0 ;;
    get_login_qrcode)     echo 0 ;;
    import_cookie)        echo 0 ;;
    *)                    echo 5 ;;
  esac
}

daily_cap_for() {
  case "$1" in
    search_feeds)         echo 15 ;;
    get_feed_detail)      echo 50 ;;
    list_feeds)           echo 20 ;;
    publish_content)      echo 2 ;;
    post_comment_to_feed) echo 5 ;;
    user_profile)         echo 20 ;;
    *)                    echo 0 ;;
  esac
}

# ── 节流：上一次调用+MIN_GAP+抖动 ────────────────────────
throttle() {
  [ "${XHS_DISABLE_THROTTLE:-0}" = "1" ] && return 0
  local tool="$1"
  local min_gap
  min_gap=$(min_gap_for "$tool")
  [ "$min_gap" -le 0 ] && return 0

  local stamp_file="$CACHE_DIR/last-$tool"
  local now last elapsed wait jitter_range jitter
  now=$(date +%s)
  if [ -f "$stamp_file" ]; then
    last=$(cat "$stamp_file" 2>/dev/null || echo 0)
    elapsed=$((now - last))
    if [ "$elapsed" -lt "$min_gap" ]; then
      wait=$((min_gap - elapsed))
      jitter_range=$(( wait * 30 / 100 ))
      [ "$jitter_range" -lt 1 ] && jitter_range=1
      jitter=$(( (RANDOM % (2 * jitter_range + 1)) - jitter_range ))
      wait=$((wait + jitter))
      [ "$wait" -lt 1 ] && wait=1
      echo "[throttle] $tool: sleeping ${wait}s (min_gap=$min_gap, elapsed=$elapsed)" >&2
      sleep "$wait"
    fi
  fi
  date +%s > "$stamp_file"
}

# ── 日限额保险丝 ──────────────────────────────────────────
check_quota() {
  [ "${XHS_DISABLE_QUOTA:-0}" = "1" ] && return 0
  local tool="$1"
  local cap
  cap=$(daily_cap_for "$tool")
  [ "$cap" -le 0 ] && return 0

  python3 - "$tool" "$cap" "$QUOTA_FILE" << 'PYEOF'
import json, os, sys, datetime
tool, cap_s, path = sys.argv[1], sys.argv[2], sys.argv[3]
cap = int(cap_s)
today = datetime.date.today().isoformat()

try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

if data.get("date") != today:
    data = {"date": today, "counts": {}}

cnt = data["counts"].get(tool, 0)
if cnt >= cap:
    print(f"[quota] {tool} 今日已达上限 {cnt}/{cap}，保护性拒绝调用", file=sys.stderr)
    sys.exit(3)

data["counts"][tool] = cnt + 1
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
  return $?
}

# ── Session 复用 ──────────────────────────────────────────
fetch_session() {
  local response session_id
  response=$(curl --noproxy '*' -s -i --max-time 120 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"xhs-cli","version":"1.0"}}}' 2>/dev/null)
  session_id=$(echo "$response" | grep -i "Mcp-Session-Id" | awk '{print $2}' | tr -d '\r\n')
  if [ -z "$session_id" ]; then
    return 1
  fi

  curl --noproxy '*' -s --max-time 120 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -H "Mcp-Session-Id: $session_id" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null 2>&1

  {
    printf '%s\n' "$session_id"
    date +%s
  } > "$SESSION_FILE"
  printf '%s\n' "$session_id"
}

get_session() {
  if [ "$REUSE_SESSION" = "1" ] && [ -f "$SESSION_FILE" ]; then
    local sid ts age
    sid=$(sed -n 1p "$SESSION_FILE" 2>/dev/null || echo "")
    ts=$(sed -n 2p "$SESSION_FILE" 2>/dev/null || echo 0)
    age=$(( $(date +%s) - ts ))
    if [ -n "$sid" ] && [ "$age" -lt "$SESSION_TTL" ]; then
      printf '%s\n' "$sid"
      return 0
    fi
  fi
  fetch_session
}

invalidate_session() {
  rm -f "$SESSION_FILE"
}

# ── 请求日志（v2.1.1） ────────────────────────────────────
# 异步写入 request_log 表。永不阻塞主流程；DB 故障时静默忽略。
log_request() {
  [ "${XHS_DISABLE_LOG:-0}" = "1" ] && return 0
  local tool="$1" status="$2" latency_ms="${3:-}" args_preview="${4:-}" error_hint="${5:-}" session_tag="${6:-}"
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({
  "tool": sys.argv[1],
  "status": sys.argv[2],
  "latency_ms": int(sys.argv[3]) if sys.argv[3] else None,
  "args_preview": sys.argv[4][:120],
  "error_hint": sys.argv[5][:200],
  "session_tag": sys.argv[6],
}, ensure_ascii=False))
' "$tool" "$status" "$latency_ms" "$args_preview" "$error_hint" "$session_tag" 2>/dev/null) || return 0
  (bash "$(dirname "$0")/db.sh" add-request-log "$payload" >/dev/null 2>&1) &
  return 0
}

# 辅助：裁剪字符串
_preview() {
  local s="$1" n="${2:-80}"
  printf '%s' "${s:0:$n}"
}

# ── 查找 start-mcp.sh ────────────────────────────────────
find_start_mcp() {
  if [ -x "$HOME/.local/bin/xiaohongshu-mcp" ]; then
    printf '%s\n' "$HOME/.local/bin/xiaohongshu-mcp"
    return 0
  fi
  local which_mcp
  which_mcp=$(which xiaohongshu-mcp 2>/dev/null || true)
  if [ -n "$which_mcp" ] && [ -x "$which_mcp" ]; then
    printf '%s\n' "$which_mcp"
    return 0
  fi

  local candidates=(
    "$HOME/.agents/skills/shuling/scripts/start-mcp.sh"
    "$HOME/.claude/skills/shuling/scripts/start-mcp.sh"
    "$HOME/.codex/skills/shuling/scripts/start-mcp.sh"
    "$HOME/.hermes/skills/social-media/shuling/scripts/start-mcp.sh"
  )
  for path in "${candidates[@]}"; do
    if [ -x "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  which_mcp=$(which xiaohongshu-mcp 2>/dev/null || true)
  if [ -n "$which_mcp" ]; then
    printf '%s\n' "$which_mcp"
    return 0
  fi
  return 1
}

# ── MCP 就绪检测（复用 session） ──────────────────────────
ensure_mcp() {
  if get_session >/dev/null 2>&1; then
    return 0
  fi

  echo "MCP 未就绪，尝试自动启动..." >&2
  local start_script
  if ! start_script=$(find_start_mcp); then
    echo "错误: MCP 服务未运行，且找不到 start-mcp.sh" >&2
    echo "请手动启动 MCP 服务后重试" >&2
    exit 2
  fi

  "$start_script" >/dev/null 2>&1 || true
  for _ in $(seq 1 10); do
    sleep 1
    if get_session >/dev/null 2>&1; then
      echo "MCP 服务已启动" >&2
      return 0
    fi
  done

  echo "错误: MCP 服务启动超时" >&2
  exit 2
}

# ── 单次工具调用（使用传入的 session） ────────────────────
_invoke_tool() {
  local session_id="$1"
  local tool_name="$2"
  local tool_args="$3"
  curl --noproxy '*' -s --max-time 120 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -H "Mcp-Session-Id: $session_id" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool_name\",\"arguments\":$tool_args}}"
}

# ── MCP 调用核心（节流 → 限额 → session 复用 → 失败重试） ─
mcp_call() {
  local tool_name="$1"
  local tool_args="$2"
  local args_preview
  args_preview=$(_preview "$tool_args" 100)

  throttle "$tool_name"

  # 限额检查（不再直接 exit，以便记录日志）
  if ! check_quota "$tool_name"; then
    log_request "$tool_name" "quota_block" "" "$args_preview" "daily cap reached" ""
    exit 3
  fi

  local session_id result start_ts end_ts latency_ms session_tag status="ok" error_hint=""
  session_id=$(get_session) || {
    log_request "$tool_name" "mcp_unavailable" "" "$args_preview" "get_session failed" ""
    echo '{"error": "无法获取 MCP Session ID，请确保 MCP 服务正在运行"}' | format_json
    exit 1
  }
  session_tag="${session_id: -8}"

  start_ts=$(python3 -c "import time; print(int(time.time()*1000))")
  result=$(_invoke_tool "$session_id" "$tool_name" "$tool_args")
  end_ts=$(python3 -c "import time; print(int(time.time()*1000))")
  latency_ms=$((end_ts - start_ts))

  # Session 失效时刷新一次重试
  if echo "$result" | grep -qiE '"(session[^"]*(invalid|expired|not[ _]found)|invalid[ _]session)"'; then
    echo "[session] 缓存失效，刷新后重试" >&2
    log_request "$tool_name" "session_refresh" "$latency_ms" "$args_preview" "session invalid, retrying" "$session_tag"
    invalidate_session
    session_id=$(get_session) || {
      log_request "$tool_name" "mcp_unavailable" "" "$args_preview" "session refresh failed" ""
      echo '{"error": "session 刷新失败"}' | format_json
      exit 1
    }
    session_tag="${session_id: -8}"
    start_ts=$(python3 -c "import time; print(int(time.time()*1000))")
    result=$(_invoke_tool "$session_id" "$tool_name" "$tool_args")
    end_ts=$(python3 -c "import time; print(int(time.time()*1000))")
    latency_ms=$((end_ts - start_ts))
  fi

  # 根据响应判定 status
  if echo "$result" | grep -qE '"(error|isError)"[[:space:]]*:[[:space:]]*(true|"[^"]+")'; then
    status="error"
    error_hint=$(echo "$result" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    e = d.get('error') or d.get('result', {}).get('content', [{}])[0].get('text', '')
    print(str(e)[:150])
except Exception:
    pass
" 2>/dev/null)
  fi
  log_request "$tool_name" "$status" "$latency_ms" "$args_preview" "$error_hint" "$session_tag"

  echo "$result" | format_json
}

# ── 子命令路由 ────────────────────────────────────────────
[ $# -eq 0 ] && usage

CMD="$1"
shift

# quota / log 子命令不需要启动 MCP
if [ "$CMD" = "quota" ]; then
  if [ -f "$QUOTA_FILE" ]; then
    cat "$QUOTA_FILE" | format_json
  else
    echo '{"date": null, "counts": {}}' | format_json
  fi
  exit 0
fi

if [ "$CMD" = "log" ]; then
  DB_SCRIPT="$(dirname "$0")/db.sh"
  bash "$DB_SCRIPT" query-request-log "$@" | format_json
  exit 0
fi

ensure_mcp

case "$CMD" in
  search)
    [ -z "$1" ] && { echo "错误: 缺少关键词"; echo "用法: $(basename "$0") search <关键词>"; exit 1; }
    KEYWORD="$1"
    ESCAPED=$(printf '%s' "$KEYWORD" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || printf '"%s"' "$KEYWORD")
    mcp_call "search_feeds" "{\"keyword\": $ESCAPED}"
    ;;

  recommend)
    mcp_call "list_feeds" "{}"
    ;;

  detail)
    [ -z "$1" ] && { echo "错误: 缺少 note_id"; echo "用法: $(basename "$0") detail <note_id>"; exit 1; }
    XSEC_TOKEN="${2:-}"
    if [ -n "$XSEC_TOKEN" ]; then
      mcp_call "get_feed_detail" "{\"feed_id\": \"$1\", \"xsec_token\": \"$XSEC_TOKEN\"}"
    else
      mcp_call "get_feed_detail" "{\"feed_id\": \"$1\"}"
    fi
    ;;

  publish)
    [ -z "$1" ] && { echo "错误: 缺少 meta.json 路径"; echo "用法: $(basename "$0") publish <meta.json路径>"; exit 1; }
    META_PATH="$1"
    if [ ! -f "$META_PATH" ]; then
      echo "错误: 文件不存在: $META_PATH" >&2
      exit 1
    fi

    PAYLOAD=$(python3 << PYEOF
import json, sys, os

meta_path = os.path.expanduser("$META_PATH")
try:
    meta = json.load(open(meta_path))
except Exception as e:
    print(json.dumps({"error": f"无法读取 meta.json: {e}"}))
    sys.exit(1)

data = {
    "title": meta.get("title", ""),
    "content": meta.get("content", ""),
}

meta_dir = os.path.dirname(os.path.abspath(meta_path))
if "images" in meta:
    images = []
    for img in meta["images"]:
        if os.path.isabs(img):
            images.append(img)
        else:
            images.append(os.path.join(meta_dir, img))
    data["images"] = images

for field in ("tags", "schedule_at", "visibility", "is_original"):
    if field in meta:
        data[field] = meta[field]

print(json.dumps(data, ensure_ascii=False))
PYEOF
    )
    mcp_call "publish_content" "$PAYLOAD"
    ;;

  comment)
    [ -z "$1" ] && { echo "错误: 缺少 note_id"; echo "用法: $(basename "$0") comment <note_id> <内容>"; exit 1; }
    [ -z "$2" ] && { echo "错误: 缺少评论内容"; echo "用法: $(basename "$0") comment <note_id> <内容>"; exit 1; }
    NOTE_ID="$1"
    CONTENT="$2"
    ESCAPED=$(printf '%s' "$CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || printf '"%s"' "$CONTENT")
    XSEC_TOKEN="${3:-}"
    if [ -n "$XSEC_TOKEN" ]; then
      mcp_call "post_comment_to_feed" "{\"feed_id\": \"$NOTE_ID\", \"xsec_token\": \"$XSEC_TOKEN\", \"content\": $ESCAPED}"
    else
      mcp_call "post_comment_to_feed" "{\"feed_id\": \"$NOTE_ID\", \"content\": $ESCAPED}"
    fi
    ;;

  status)
    mcp_call "check_login_status" "{}"
    ;;

  login)
    mcp_call "get_login_qrcode" "{}"
    ;;

  import-cookie)
    [ -z "${1:-}" ] && { echo "错误: 缺少 cookie 字符串或文件路径"; echo "用法: $(basename "$0") import-cookie <cookie字符串|@cookie.txt>"; exit 1; }
    if [[ "$1" == @* ]]; then
      COOKIE_FILE="${1#@}"
      [ ! -f "$COOKIE_FILE" ] && { echo "错误: cookie 文件不存在: $COOKIE_FILE" >&2; exit 1; }
      COOKIE_RAW=$(cat "$COOKIE_FILE")
    else
      COOKIE_RAW="$1"
    fi
    ESCAPED=$(printf '%s' "$COOKIE_RAW" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()), end="")')
    mcp_call "import_cookie" "{\"cookie\": $ESCAPED}"
    ;;

  user)
    [ -z "$1" ] && { echo "错误: 缺少 user_id"; echo "用法: $(basename "$0") user <user_id>"; exit 1; }
    mcp_call "user_profile" "{\"user_id\": \"$1\"}"
    ;;

  *)
    echo "错误: 未知子命令 '$CMD'" >&2
    echo "" >&2
    usage
    ;;
esac
