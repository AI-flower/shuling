#!/usr/bin/env bash
# 统一的小红书 MCP 操作入口
# 通过 MCP 协议（JSON-RPC over HTTP）与小红书 MCP Server 交互

set -e

MCP_URL="${MCP_URL:-http://localhost:18060/mcp}"
export no_proxy="${no_proxy:+$no_proxy,}localhost,127.0.0.1"

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
  user     <user_id>            获取用户主页

环境变量:
  MCP_URL   MCP 服务地址（默认 http://localhost:18060/mcp）

示例:
  $(basename "$0") search "咖啡推荐"
  $(basename "$0") recommend
  $(basename "$0") detail 66a1b2c3d4e5f60001000001
  $(basename "$0") publish ./output/meta.json
  $(basename "$0") comment 66a1b2c3d4e5f60001000001 "写得真好！"
  $(basename "$0") status
  $(basename "$0") login
  $(basename "$0") user 5a1b2c3d4e5f6000010000ff
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

# ── 查找 start-mcp.sh ────────────────────────────────────
find_start_mcp() {
  local candidates=(
    "$HOME/.agents/skills/xiaohongshu/scripts/start-mcp.sh"
    "$HOME/.claude/skills/xiaohongshu/scripts/start-mcp.sh"
    "$HOME/.codex/skills/xiaohongshu/scripts/start-mcp.sh"
    "$HOME/.hermes/skills/social-media/xiaohongshu/scripts/start-mcp.sh"
  )
  for path in "${candidates[@]}"; do
    if [ -x "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

# ── MCP 就绪检测 ─────────────────────────────────────────
mcp_ready() {
  local response
  response=$(curl --noproxy '*' -s -i --max-time 3 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"xhs-cli","version":"1.0"}}}' 2>/dev/null || true)
  echo "$response" | grep -qi "^Mcp-Session-Id:"
}

# ── 自动启动 MCP ─────────────────────────────────────────
ensure_mcp() {
  if mcp_ready; then
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
    if mcp_ready; then
      echo "MCP 服务已启动" >&2
      return 0
    fi
  done

  echo "错误: MCP 服务启动超时" >&2
  exit 2
}

# ── MCP 调用核心 ──────────────────────────────────────────
mcp_call() {
  local tool_name="$1"
  local tool_args="$2"

  # 1. Initialize 并获取 Session ID
  local init_response
  init_response=$(curl --noproxy '*' -s -i --max-time 120 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"xhs-cli","version":"1.0"}}}')

  local session_id
  session_id=$(echo "$init_response" | grep -i "Mcp-Session-Id" | awk '{print $2}' | tr -d '\r\n')

  if [ -z "$session_id" ]; then
    echo '{"error": "无法获取 MCP Session ID，请确保 MCP 服务正在运行"}' | format_json
    exit 1
  fi

  # 2. Initialized 通知
  curl --noproxy '*' -s --max-time 120 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -H "Mcp-Session-Id: $session_id" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null

  # 3. 调用工具
  local result
  result=$(curl --noproxy '*' -s --max-time 120 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -H "Mcp-Session-Id: $session_id" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool_name\",\"arguments\":$tool_args}}")

  echo "$result" | format_json
}

# ── 子命令路由 ────────────────────────────────────────────
[ $# -eq 0 ] && usage

CMD="$1"
shift

ensure_mcp

case "$CMD" in
  search)
    [ -z "$1" ] && { echo "错误: 缺少关键词"; echo "用法: $(basename "$0") search <关键词>"; exit 1; }
    KEYWORD="$1"
    # 对关键词做 JSON 转义
    ESCAPED=$(printf '%s' "$KEYWORD" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || printf '"%s"' "$KEYWORD")
    mcp_call "search_feeds" "{\"keyword\": $ESCAPED}"
    ;;

  recommend)
    mcp_call "list_feeds" "{}"
    ;;

  detail)
    [ -z "$1" ] && { echo "错误: 缺少 note_id"; echo "用法: $(basename "$0") detail <note_id>"; exit 1; }
    mcp_call "get_feed_detail" "{\"feed_id\": \"$1\", \"xsec_token\": \"\"}"
    ;;

  publish)
    [ -z "$1" ] && { echo "错误: 缺少 meta.json 路径"; echo "用法: $(basename "$0") publish <meta.json路径>"; exit 1; }
    META_PATH="$1"
    if [ ! -f "$META_PATH" ]; then
      echo "错误: 文件不存在: $META_PATH" >&2
      exit 1
    fi

    # 读取 meta.json 并构造 publish_content 参数
    PAYLOAD=$(python3 << PYEOF
import json, sys, os

meta_path = os.path.expanduser("$META_PATH")
try:
    meta = json.load(open(meta_path))
except Exception as e:
    print(json.dumps({"error": f"无法读取 meta.json: {e}"}))
    sys.exit(1)

# 构造发布参数
data = {
    "title": meta.get("title", ""),
    "content": meta.get("content", ""),
}

# 处理图片路径（转为绝对路径）
meta_dir = os.path.dirname(os.path.abspath(meta_path))
if "images" in meta:
    images = []
    for img in meta["images"]:
        if os.path.isabs(img):
            images.append(img)
        else:
            images.append(os.path.join(meta_dir, img))
    data["images"] = images

# 可选字段
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
    # 对评论内容做 JSON 转义
    ESCAPED=$(printf '%s' "$CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || printf '"%s"' "$CONTENT")
    mcp_call "post_comment_to_feed" "{\"feed_id\": \"$NOTE_ID\", \"xsec_token\": \"\", \"content\": $ESCAPED}"
    ;;

  status)
    mcp_call "check_login_status" "{}"
    ;;

  login)
    mcp_call "get_login_qrcode" "{}"
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
