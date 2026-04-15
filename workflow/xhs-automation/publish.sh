#!/bin/bash
# 小红书发布脚本（支持 tags / schedule_at / is_original）
# 用法: ./publish.sh <post_dir>
# post_dir 里需要有: meta.json + page-*.png

set -e

POST_DIR="$1"
MCP_URL="${MCP_URL:-http://localhost:18060/mcp}"

resolve_mcp_script() {
  local script_name="$1"
  local env_name="XHS_$(printf '%s' "$script_name" | tr '[:lower:].-' '[:upper:]__')"
  local env_path="${!env_name}"
  local candidates=(
    "$env_path"
    "$HOME/.agents/skills/xiaohongshu/scripts/$script_name"
    "$HOME/.claude/skills/xiaohongshu/scripts/$script_name"
    "$HOME/.codex/skills/xiaohongshu/scripts/$script_name"
  )
  local path
  for path in "${candidates[@]}"; do
    if [ -n "$path" ] && [ -x "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  printf '%s\n' "$HOME/.agents/skills/xiaohongshu/scripts/$script_name"
}

MCP_START_SH="$(resolve_mcp_script start-mcp.sh)"
MCP_CALL_SH="$(resolve_mcp_script mcp-call.sh)"
if [ -z "$POST_DIR" ] || [ ! -d "$POST_DIR" ]; then
  echo "用法: $0 <post_dir>"
  exit 1
fi

META="$POST_DIR/meta.json"
if [ ! -f "$META" ]; then
  echo "错误: 找不到 $META"
  exit 1
fi

mcp_ready() {
  local response
  response=$(curl --noproxy '*' -s -i --max-time 3 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"xhs-automation","version":"1.0"}}}' || true)
  echo "$response" | grep -qi "^Mcp-Session-Id:"
}

ensure_mcp() {
  if mcp_ready; then
    return 0
  fi

  echo "MCP 未就绪，尝试启动..."
  if ! "$MCP_START_SH" >/dev/null 2>&1; then
    echo "发布失败: MCP 启动脚本执行失败" >&2
    exit 3
  fi

  for _ in $(seq 1 10); do
    sleep 1
    if mcp_ready; then
      return 0
    fi
  done

  echo "发布失败: MCP 服务未就绪" >&2
  exit 3
}

# 收集图片（绝对路径）
IMAGES=""
for img in "$POST_DIR"/page-*.png; do
  if [ -f "$img" ]; then
    ABS_PATH=$(cd "$(dirname "$img")" && pwd)/$(basename "$img")
    IMAGES="$IMAGES\"$ABS_PATH\","
  fi
done
IMAGES="[${IMAGES%,}]"

# 用 Python 构建完整 payload（从 meta.json 读取所有字段）
PAYLOAD=$(python3 << PYEOF
import json, sys

meta = json.load(open('$META'))
images = json.loads('$IMAGES')

if not images:
    print("错误: 没有找到 page-*.png 图片", file=sys.stderr)
    sys.exit(1)

data = {
    "title": meta["title"],
    "content": meta["content"],
    "images": images,
    "is_original": meta.get("is_original", True)
}

# 可选字段
if meta.get("tags"):
    data["tags"] = meta["tags"]
if meta.get("schedule_at"):
    data["schedule_at"] = meta["schedule_at"]
if meta.get("visibility"):
    data["visibility"] = meta["visibility"]

print(json.dumps(data, ensure_ascii=False))
PYEOF
)

TITLE=$(python3 -c "import json; print(json.load(open('$META'))['title'])")
IMG_COUNT=$(echo "$IMAGES" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
SCHEDULE=$(python3 -c "import json; print(json.load(open('$META')).get('schedule_at', '立即发布'))")

echo "发布: $TITLE"
echo "图片数: $IMG_COUNT"
echo "时间: $SCHEDULE"

ensure_mcp

if ! MCP_RESULT=$(cd ~/.xiaohongshu && "$MCP_CALL_SH" publish_content "$PAYLOAD" 2>&1); then
  echo "发布失败: $MCP_RESULT" >&2
  exit 3
fi

echo "$MCP_RESULT"

export MCP_RESULT
python3 <<'PYEOF'
import json
import os
import sys

raw = os.environ.get("MCP_RESULT", "").strip()
if not raw:
    print("发布失败: MCP 未返回结果", file=sys.stderr)
    sys.exit(2)

try:
    data = json.loads(raw)
except Exception as exc:
    print(f"发布失败: 无法解析 MCP 返回 ({exc})", file=sys.stderr)
    sys.exit(2)

if data.get("error"):
    print(f"发布失败: {data['error'].get('message', 'unknown error')}", file=sys.stderr)
    sys.exit(2)

result = data.get("result", {})
texts = []
for item in result.get("content", []):
    if isinstance(item, dict) and item.get("type") == "text":
        texts.append(item.get("text", ""))

message = "\n".join(t for t in texts if t).strip()
if result.get("isError") or "发布失败" in message:
    print(message or "发布失败", file=sys.stderr)
    sys.exit(2)
PYEOF

echo ""
echo "✅ 发布完成: $(date)"
