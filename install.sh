#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── 颜色 ───────────────────────────────────────────────────────────
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BOLD="\033[1m"
RESET="\033[0m"

info()  { printf "${GREEN}[OK]${RESET}  %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${RESET}   %s\n" "$1"; }
fail()  { printf "${RED}[ERR]${RESET} %s\n" "$1"; }

# ─── 1. 检查依赖 ────────────────────────────────────────────────────
printf "\n${BOLD}=== 检查依赖 ===${RESET}\n\n"

MISSING=0

if command -v node >/dev/null 2>&1; then
    info "Node.js $(node -v)"
else
    fail "Node.js 未安装（截图功能需要）"
    MISSING=1
fi

if command -v python3 >/dev/null 2>&1; then
    info "Python $(python3 --version 2>&1 | awk {print })"
else
    fail "Python 3 未安装（图片生成需要）"
    MISSING=1
fi

if command -v sqlite3 >/dev/null 2>&1; then
    info "sqlite3 $(sqlite3 --version | awk {print })"
else
    fail "sqlite3 未安装（数据存储需要）"
    MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
    warn "部分依赖缺失，安装后部分功能可能不可用"
    printf "  继续安装？[Y/n] "
    read -r ans
    if [ "${ans:-Y}" = "n" ] || [ "${ans:-Y}" = "N" ]; then
        printf "已取消\n"
        exit 1
    fi
fi

# ─── 2. 检测可用平台 ────────────────────────────────────────────────
printf "\n${BOLD}=== 检测平台 ===${RESET}\n\n"

PLATFORMS=()

if [ -d "$HOME/.hermes" ]; then
    PLATFORMS+=("hermes:$HOME/.hermes/skills/social-media/xiaohongshu")
    info "Hermes  → ~/.hermes/skills/social-media/xiaohongshu/"
fi

if [ -d "$HOME/.claude" ]; then
    PLATFORMS+=("claude:$HOME/.claude/skills/xiaohongshu")
    info "Claude Code → ~/.claude/skills/xiaohongshu/"
fi

if [ -d "$HOME/.codex" ]; then
    PLATFORMS+=("codex:$HOME/.codex/skills/xiaohongshu")
    info "Codex   → ~/.codex/skills/xiaohongshu/"
fi

if [ -d "$HOME/.agents" ]; then
    PLATFORMS+=("agents:$HOME/.agents/skills/xiaohongshu")
    info "Agents  → ~/.agents/skills/xiaohongshu/"
fi

if [ ${#PLATFORMS[@]} -eq 0 ]; then
    warn "未检测到已知平台目录，将只初始化本地数据"
fi

# ─── 3. 复制 skill 文件 ─────────────────────────────────────────────
printf "\n${BOLD}=== 安装 Skill ===${RESET}\n\n"

for entry in "${PLATFORMS[@]}"; do
    platform="${entry%%:*}"
    target="${entry#*:}"
    mkdir -p "$target"
    rsync -a --exclude=.git --exclude=.DS_Store --exclude=.idea \
        --exclude=workflow --exclude=skills --exclude=docs \
        --exclude=.session-recorder --exclude=*.md \
        "$SKILL_DIR/" "$target/"
    # 单独复制需要的 md 文件
    cp "$SKILL_DIR/SKILL.md" "$target/"
    info "$platform: 已复制到 $target"
done

# ─── 4. 初始化 SQLite 数据库 ────────────────────────────────────────
printf "\n${BOLD}=== 初始化数据库 ===${RESET}\n\n"

if [ -x "$SKILL_DIR/scripts/db.sh" ]; then
    bash "$SKILL_DIR/scripts/db.sh" init
    info "数据库已初始化: $SKILL_DIR/data/xhs.db"
else
    warn "scripts/db.sh 不存在或不可执行，跳过数据库初始化"
fi

# ─── 5. 确保 knowledge-base 目录存在 ────────────────────────────────
mkdir -p "$SKILL_DIR/knowledge-base"
info "knowledge-base/ 目录就绪"

# ─── 6. 可选：配置 Gemini API Key ───────────────────────────────────
printf "\n${BOLD}=== 可选配置 ===${RESET}\n\n"

ENV_FILE="$SKILL_DIR/.env"

if [ -f "$ENV_FILE" ] && grep -q "GEMINI_API_KEY" "$ENV_FILE"; then
    info "Gemini API Key 已配置"
else
    printf "配置 Gemini API Key？（用于 AI 图片生成，留空跳过）\n"
    printf "  获取地址: https://aistudio.google.com/api-keys\n"
    printf "  API Key: "
    read -r gemini_key
    if [ -n "$gemini_key" ]; then
        echo "GEMINI_API_KEY=$gemini_key" >> "$ENV_FILE"
        info "Gemini API Key 已保存到 .env"
    else
        warn "跳过，将使用 HTML 截图模式生成图片"
    fi
fi

# ─── 7. 可选：配置 MCP URL ──────────────────────────────────────────
if [ -f "$ENV_FILE" ] && grep -q "XHS_MCP_URL" "$ENV_FILE"; then
    info "MCP URL 已配置"
else
    printf "\n配置 MCP URL？（留空使用本机默认地址）\n"
    printf "  MCP URL: "
    read -r mcp_url
    if [ -n "$mcp_url" ]; then
        echo "XHS_MCP_URL=$mcp_url" >> "$ENV_FILE"
        info "MCP URL 已保存到 .env"
    else
        info "使用本机默认 MCP 地址"
    fi
fi


# ─── 7.5 配置 Telegram Bot ──────────────────────────────────────
WORKFLOW_DIR="$SKILL_DIR/workflow/xhs-automation"
CONFIG_DIR="$WORKFLOW_DIR/config"
RUNTIME_ENV="$CONFIG_DIR/runtime.env"

if [ -d "$WORKFLOW_DIR" ] && [ -d "$CONFIG_DIR" ]; then
    if [ ! -f "$RUNTIME_ENV" ] && [ -f "$CONFIG_DIR/runtime.env.example" ]; then
        cp "$CONFIG_DIR/runtime.env.example" "$RUNTIME_ENV"
        info "runtime.env 已从模板创建"
    fi

    if [ -f "$RUNTIME_ENV" ]; then
        EXISTING_TOKEN=$(grep "^XHS_TELEGRAM_BOT_TOKEN=" "$RUNTIME_ENV" 2>/dev/null | cut -d= -f2 | tr -d "'" | tr -d '"' || true)
        if [ -z "$EXISTING_TOKEN" ]; then
            printf "\n${BOLD}配置 Telegram Bot${RESET}（用于接收选题推送和日报）\n"
            printf "  1. Telegram 搜索 @BotFather → /newbot → 记下 Token\n"
            printf "  2. 向 Bot 发消息后，打开 https://api.telegram.org/bot<Token>/getUpdates 找 chat.id\n\n"
            printf "  Bot Token（留空跳过）: "
            read -r tg_token
            if [ -n "$tg_token" ]; then
                sed -i.bak "s|^XHS_TELEGRAM_BOT_TOKEN=.*|XHS_TELEGRAM_BOT_TOKEN=$tg_token|" "$RUNTIME_ENV"
                info "Telegram Bot Token 已写入"
                printf "  Chat ID: "
                read -r tg_chat
                if [ -n "$tg_chat" ]; then
                    sed -i.bak "s|^XHS_TELEGRAM_CHAT_ID=.*|XHS_TELEGRAM_CHAT_ID=$tg_chat|" "$RUNTIME_ENV"
                    info "Telegram Chat ID 已写入"
                fi
                rm -f "$RUNTIME_ENV.bak"
            else
                warn "跳过 Telegram 配置（后续可编辑 $RUNTIME_ENV）"
            fi
        else
            info "Telegram Bot Token 已配置"
        fi
    fi
fi

# ─── 7.6 运行环境预检 ────────────────────────────────────────────
printf "\n${BOLD}=== 环境预检 ===${RESET}\n\n"

if [ -f "$SKILL_DIR/scripts/preflight.py" ]; then
    python3 "$SKILL_DIR/scripts/preflight.py" 2>&1 >/dev/null
else
    warn "preflight.py 未找到，跳过环境预检"
fi

# ─── 8. 验证 & 输出下一步 ───────────────────────────────────────────
printf "\n${BOLD}=== 安装完成 ===${RESET}\n\n"

printf "已安装到以下位置：\n"
for entry in "${PLATFORMS[@]}"; do
    target="${entry#*:}"
    printf "  %s\n" "$target"
done
printf "  %s （源目录）\n" "$SKILL_DIR"

cat << EOF

下一步：
  1. 在你的 AI 助手中说"帮我发小红书"
  2. 首次使用会进入博主画像建立流程
  3. 画像建立完成后即可开始选题、创作、发布

详细的平台适配说明见 platform/ 目录：
  - platform/hermes.md      — Hermes 定时任务配置
  - platform/claude-code.md  — Claude Code 使用指南
  - platform/codex.md        — Codex 使用指南

EOF
