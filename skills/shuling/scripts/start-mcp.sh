#!/bin/bash
# 启动小红书 MCP 服务

XHS_MCP="${XHS_MCP:-$(which xiaohongshu-mcp 2>/dev/null || echo $HOME/.local/bin/xiaohongshu-mcp)}"
PID_FILE="$HOME/.xiaohongshu/mcp.pid"
LOG_FILE="$HOME/.xiaohongshu/mcp.log"
ENV_FILE="$HOME/.hermes/skills/social-media/shuling/config/runtime.env"

mkdir -p "$HOME/.xiaohongshu"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# 同步 cookies（支持多个可能的来源）
sync_cookies() {
    local src=""

    if [ -n "$XHS_COOKIES_SRC" ] && [ -f "$XHS_COOKIES_SRC" ]; then
        src="$XHS_COOKIES_SRC"
    elif [ -f "$HOME/cookies.json" ]; then
        src="$HOME/cookies.json"
    elif [ -f "$HOME/.xiaohongshu/cookies.json" ]; then
        src="$HOME/.xiaohongshu/cookies.json"
    fi

    if [ -n "$src" ]; then
        if [ ! -f "/tmp/cookies.json" ] || [ "$src" -nt "/tmp/cookies.json" ]; then
            cp "$src" "/tmp/cookies.json"
            echo "已同步 cookies: $src -> /tmp/cookies.json"
        fi
    fi
}

sync_cookies

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "MCP 服务已在运行 (PID: $PID)"
        echo "如需重启，请先运行 stop-mcp.sh"
        exit 0
    fi
fi

HEADLESS="true"
for arg in "$@"; do
    case $arg in
        --headless=false)
            HEADLESS="false"
            ;;
    esac
done

echo "启动小红书 MCP 服务..."
if [ "$HEADLESS" = "false" ]; then
    nohup "$XHS_MCP" -headless=false > "$LOG_FILE" 2>&1 &
else
    nohup "$XHS_MCP" > "$LOG_FILE" 2>&1 &
fi

echo $! > "$PID_FILE"
sleep 3

if kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "✓ MCP 服务已启动 (PID: $(cat $PID_FILE))"
    echo "  端点: http://localhost:18060/mcp"
    echo "  日志: $LOG_FILE"
else
    echo "✗ 启动失败，查看日志: $LOG_FILE"
    cat "$LOG_FILE"
    exit 1
fi
