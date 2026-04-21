#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── 参数解析（v2.1.3+） ─────────────────────────────────────────────
#
# 用法:
#   bash install.sh [选项]
#
# 选项:
#   -y, --yes, --non-interactive   不问任何问题，交互项用默认值跳过
#   --dry-run                      只打印将要执行的动作，不写任何东西
#   --check                        只跑预检（依赖 + 平台 + 版本对比），不部署
#   --target <path>                显式指定部署目标（可重复），覆盖默认自动检测
#   --skip-preflight               跳过部署后的 preflight 运行
#   -h, --help                     显示此帮助
#
# 环境变量（非交互模式下替代 prompt）:
#   GEMINI_API_KEY=xxx             预填 Gemini API Key，写入 .env
#   XHS_MCP_URL=http://...         预填 MCP URL，写入 .env
#   SHULING_ASSUME_YES=1           等同 --yes
#
# 示例:
#   bash install.sh --check                            # 只自检不动手
#   bash install.sh --dry-run                          # 预演一次
#   SHULING_ASSUME_YES=1 GEMINI_API_KEY=xxx bash install.sh   # CI/远程
#   bash install.sh --target ~/.myagents/skills/shuling       # 自定义目标

ASSUME_YES="${SHULING_ASSUME_YES:-0}"
DRY_RUN=0
CHECK_ONLY=0
SKIP_PREFLIGHT=0
declare -a EXPLICIT_TARGETS=()

usage() {
    sed -n '/^# ─── 参数解析/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes|--non-interactive) ASSUME_YES=1; shift ;;
        --dry-run)                  DRY_RUN=1; shift ;;
        --check)                    CHECK_ONLY=1; shift ;;
        --skip-preflight)           SKIP_PREFLIGHT=1; shift ;;
        --target)
            [ $# -ge 2 ] || { echo "错误: --target 需要一个路径参数" >&2; exit 2; }
            EXPLICIT_TARGETS+=("$2"); shift 2 ;;
        -h|--help)                  usage; exit 0 ;;
        *) echo "错误: 未知参数 $1（见 --help）" >&2; exit 2 ;;
    esac
done

# 非 TTY 环境自动进入非交互模式（cron/ssh/CI）
if [ ! -t 0 ] && [ "$ASSUME_YES" = "0" ]; then
    ASSUME_YES=1
fi

# ─── 颜色 ───────────────────────────────────────────────────────────
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

info()  { printf "${GREEN}[OK]${RESET}  %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${RESET}   %s\n" "$1"; }
fail()  { printf "${RED}[ERR]${RESET} %s\n" "$1"; }
step()  { printf "${DIM}[..] %s${RESET}\n" "$1"; }

# run <描述> <命令...> — dry-run 模式下只打印不执行
run() {
    local desc="$1"; shift
    if [ "$DRY_RUN" = "1" ]; then
        printf "${DIM}[dry]${RESET} %s ${DIM}→ %s${RESET}\n" "$desc" "$*"
    else
        "$@"
    fi
}

# prompt <提示语> <变量名> [默认值] — 非交互模式返回默认值
prompt() {
    local label="$1" varname="$2" default="${3:-}"
    if [ "$ASSUME_YES" = "1" ]; then
        printf -v "$varname" '%s' "$default"
        return 0
    fi
    printf "%s" "$label"
    read -r "$varname"
    if [ -z "${!varname}" ] && [ -n "$default" ]; then
        printf -v "$varname" '%s' "$default"
    fi
}

# ─── 版本工具（v2.1.2+） ─────────────────────────────────────────────
read_version() {
    local vfile="$1"
    [ -f "$vfile" ] || { echo "0.0.0"; return; }
    awk -F'"' '/^version:/ {print $2; exit}' "$vfile" 2>/dev/null || echo "0.0.0"
}

version_le() {
    python3 -c "
import sys
a = tuple(int(x) for x in sys.argv[1].split('.'))
b = tuple(int(x) for x in sys.argv[2].split('.'))
sys.exit(0 if a <= b else 1)
" "$1" "$2"
}

version_lt() {
    python3 -c "
import sys
a = tuple(int(x) for x in sys.argv[1].split('.'))
b = tuple(int(x) for x in sys.argv[2].split('.'))
sys.exit(0 if a < b else 1)
" "$1" "$2"
}

SRC_VERSION="$(read_version "$SKILL_DIR/VERSION")"

run_migrations() {
    local from_ver="$1" to_ver="$2" target="$3"
    local migrations_dir="$SKILL_DIR/migrations"
    [ -d "$migrations_dir" ] || return 0

    local ran=0
    for m in $(ls "$migrations_dir"/v*.sh 2>/dev/null | sort -V); do
        local fname v
        fname="$(basename "$m")"
        v="${fname#v}"; v="${v%.sh}"
        if version_lt "$from_ver" "$v" && version_le "$v" "$to_ver"; then
            if [ "$DRY_RUN" = "1" ]; then
                printf "${DIM}[dry]${RESET} migration %s → target %s\n" "$fname" "$target"
            else
                printf "  执行 migration %s (target: %s)\n" "$fname" "$target"
                (SKILL_DIR="$target" bash "$m")
            fi
            ran=$((ran + 1))
        fi
    done
    if [ "$ran" = "0" ]; then
        printf "  无需 migration（已是 %s）\n" "$to_ver"
    fi
}

# ─── 模式提示 ───────────────────────────────────────────────────────
MODE_BANNER=""
[ "$ASSUME_YES" = "1" ]    && MODE_BANNER="$MODE_BANNER [non-interactive]"
[ "$DRY_RUN" = "1" ]       && MODE_BANNER="$MODE_BANNER [dry-run]"
[ "$CHECK_ONLY" = "1" ]    && MODE_BANNER="$MODE_BANNER [check-only]"
[ -n "$MODE_BANNER" ]      && printf "${BOLD}模式:${RESET}${YELLOW}%s${RESET}\n" "$MODE_BANNER"

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
    info "Python $(python3 --version 2>&1 | awk '{print $2}')"
else
    fail "Python 3 未安装（图片生成需要）"
    MISSING=1
fi

if command -v sqlite3 >/dev/null 2>&1; then
    info "sqlite3 $(sqlite3 --version | awk '{print $1}')"
else
    fail "sqlite3 未安装（数据存储需要）"
    MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
    warn "部分依赖缺失，安装后部分功能可能不可用"
    if [ "$ASSUME_YES" = "1" ]; then
        warn "非交互模式：继续安装（缺失依赖按需后补）"
    else
        prompt "  继续安装？[Y/n] " ans "Y"
        if [ "${ans}" = "n" ] || [ "${ans}" = "N" ]; then
            printf "已取消\n"
            exit 1
        fi
    fi
fi

# ─── 2. 检测可用平台 ────────────────────────────────────────────────
printf "\n${BOLD}=== 检测平台 ===${RESET}\n\n"

PLATFORMS=()

check_deployed() {
    local name="$1" path="$2"
    PLATFORMS+=("$name:$path")
    if [ -f "$path/VERSION" ]; then
        local deployed_v
        deployed_v="$(read_version "$path/VERSION")"
        if [ "$deployed_v" = "$SRC_VERSION" ]; then
            info "$name → $path (v$deployed_v, 已是最新)"
        elif version_lt "$deployed_v" "$SRC_VERSION"; then
            warn "$name → $path (v$deployed_v → v$SRC_VERSION, 将升级)"
        else
            warn "$name → $path (v$deployed_v > v$SRC_VERSION, 降级将覆盖！)"
        fi
    else
        info "$name → $path (新安装 → v$SRC_VERSION)"
    fi
}

if [ ${#EXPLICIT_TARGETS[@]} -gt 0 ]; then
    for t in "${EXPLICIT_TARGETS[@]}"; do
        check_deployed "Custom" "$t"
    done
else
    if [ -d "$HOME/.hermes" ]; then
        check_deployed "Hermes" "$HOME/.hermes/skills/social-media/shuling"
    fi
    if [ -d "$HOME/.claude" ]; then
        check_deployed "Claude Code" "$HOME/.claude/skills/shuling"
    fi
    if [ -d "$HOME/.codex" ]; then
        check_deployed "Codex" "$HOME/.codex/skills/shuling"
    fi
    if [ -d "$HOME/.agents" ]; then
        check_deployed "Agents" "$HOME/.agents/skills/shuling"
    fi
fi

if [ ${#PLATFORMS[@]} -eq 0 ]; then
    warn "未检测到已知平台目录，将只初始化本地数据"
fi

# ─── check-only: 到此结束 ───────────────────────────────────────────
if [ "$CHECK_ONLY" = "1" ]; then
    printf "\n${BOLD}=== 自检完成 ===${RESET}\n\n"
    printf "源版本: v%s\n" "$SRC_VERSION"
    if [ ${#PLATFORMS[@]} -gt 0 ]; then
        printf "候选目标:\n"
        for entry in "${PLATFORMS[@]}"; do
            printf "  %s\n" "${entry#*:}"
        done
    fi
    printf "\n运行 ${BOLD}bash install.sh${RESET} 或 ${BOLD}bash install.sh --dry-run${RESET} 执行部署。\n"
    exit 0
fi

# ─── 3. 复制 skill 文件 ─────────────────────────────────────────────
printf "\n${BOLD}=== 安装 Skill ===${RESET}\n\n"

for entry in "${PLATFORMS[@]}"; do
    platform="${entry%%:*}"
    target="${entry#*:}"
    OLD_VER="$(read_version "$target/VERSION")"
    run "确保目录" mkdir -p "$target"
    run "同步 skill 文件" rsync -a --exclude=.git --exclude=.DS_Store --exclude=.idea \
        --exclude=skills --exclude=docs \
        --exclude=.session-recorder --exclude=*.md \
        --exclude=config/runtime.env --exclude=config/state.json \
        --exclude=knowledge-base/profile.json \
        --exclude=knowledge-base/preferences.json --exclude=knowledge-base/patterns.md \
        --exclude=data/xhs.db --exclude=data/xhs.db-shm --exclude=data/xhs.db-wal \
        "$SKILL_DIR/" "$target/"
    for doc in SKILL.md README.md CHANGELOG.md UPGRADE.md RELEASING.md VERSION; do
        if [ -f "$SKILL_DIR/$doc" ]; then
            run "复制 $doc" cp "$SKILL_DIR/$doc" "$target/"
        fi
    done
    info "$platform: 已复制到 $target (v$OLD_VER → v$SRC_VERSION)"

    if version_lt "$OLD_VER" "$SRC_VERSION"; then
        printf "  → migration:\n"
        run_migrations "$OLD_VER" "$SRC_VERSION" "$target"
    fi
done

# ─── 4. 初始化 SQLite 数据库 ────────────────────────────────────────
printf "\n${BOLD}=== 初始化数据库 ===${RESET}\n\n"

if [ -x "$SKILL_DIR/scripts/db.sh" ]; then
    run "db.sh init" bash "$SKILL_DIR/scripts/db.sh" init
    info "数据库已初始化: $SKILL_DIR/data/xhs.db"
else
    warn "scripts/db.sh 不存在或不可执行，跳过数据库初始化"
fi

# ─── 5. 确保 knowledge-base 目录存在 ────────────────────────────────
run "建 knowledge-base/" mkdir -p "$SKILL_DIR/knowledge-base"
info "knowledge-base/ 目录就绪"

# ─── 6. 可选：配置 Gemini API Key ───────────────────────────────────
printf "\n${BOLD}=== 可选配置 ===${RESET}\n\n"

ENV_FILE="$SKILL_DIR/.env"

if [ -f "$ENV_FILE" ] && grep -q "GEMINI_API_KEY" "$ENV_FILE"; then
    info "Gemini API Key 已配置"
else
    # 优先读 env var（非交互模式下唯一通道）
    gemini_key="${GEMINI_API_KEY:-}"
    if [ -z "$gemini_key" ] && [ "$ASSUME_YES" = "0" ]; then
        printf "配置 Gemini API Key？（用于 AI 图片生成，留空跳过）\n"
        printf "  获取地址: https://aistudio.google.com/api-keys\n"
        prompt "  API Key: " gemini_key ""
    fi
    if [ -n "$gemini_key" ]; then
        run "写入 GEMINI_API_KEY" bash -c "echo 'GEMINI_API_KEY=$gemini_key' >> '$ENV_FILE'"
        info "Gemini API Key 已保存到 .env"
    else
        warn "未配置 Gemini Key，将使用 HTML 截图模式生成图片"
    fi
fi

# ─── 7. 可选：配置 MCP URL ──────────────────────────────────────────
if [ -f "$ENV_FILE" ] && grep -q "XHS_MCP_URL" "$ENV_FILE"; then
    info "MCP URL 已配置"
else
    mcp_url="${XHS_MCP_URL:-}"
    if [ -z "$mcp_url" ] && [ "$ASSUME_YES" = "0" ]; then
        printf "\n配置 MCP URL？（留空使用本机默认地址）\n"
        prompt "  MCP URL: " mcp_url ""
    fi
    if [ -n "$mcp_url" ]; then
        run "写入 XHS_MCP_URL" bash -c "echo 'XHS_MCP_URL=$mcp_url' >> '$ENV_FILE'"
        info "MCP URL 已保存到 .env"
    else
        info "使用本机默认 MCP 地址"
    fi
fi


# ─── 7.5 确保每个 target 有 config/runtime.env（无交互，仅初始化）──
# Telegram / IM 通讯凭证不在 skill 配置范围内 —— 由 hermes-agent 自己管理。
RUNTIME_ENV_TEMPLATE="$SKILL_DIR/config/runtime.env.example"

if [ -f "$RUNTIME_ENV_TEMPLATE" ]; then
    for entry in "${PLATFORMS[@]}"; do
        target="${entry#*:}"
        cfg_dir="$target/config"
        runtime_env="$cfg_dir/runtime.env"
        run "确保 $cfg_dir" mkdir -p "$cfg_dir"
        if [ ! -f "$runtime_env" ]; then
            run "拷贝 runtime.env 模板" cp "$RUNTIME_ENV_TEMPLATE" "$runtime_env"
            info "$target: 已创建 config/runtime.env（来自模板）"
        else
            info "$target: config/runtime.env 已存在，保留"
        fi
    done
fi

# ─── 7.6 运行环境预检（按 target 逐个跑）─────────────────────────
if [ "$SKIP_PREFLIGHT" = "0" ] && [ "$DRY_RUN" = "0" ]; then
    printf "\n${BOLD}=== 环境预检 ===${RESET}\n\n"

    for entry in "${PLATFORMS[@]}"; do
        target="${entry#*:}"
        if [ -f "$target/scripts/preflight.py" ]; then
            printf "${BOLD}-- %s --${RESET}\n" "$target"
            python3 "$target/scripts/preflight.py" 2>&1 >/dev/null || true
        fi
    done
elif [ "$SKIP_PREFLIGHT" = "1" ]; then
    warn "已跳过 preflight（--skip-preflight）"
fi

# ─── 8. 验证 & 输出下一步 ───────────────────────────────────────────
printf "\n${BOLD}=== 安装完成 ===${RESET}\n\n"

printf "当前版本: ${BOLD}v%s${RESET} (%s)\n" "$SRC_VERSION" "$(awk -F'"' '/^codename:/ {print $2; exit}' "$SKILL_DIR/VERSION" 2>/dev/null)"
printf "已安装到以下位置：\n"
for entry in "${PLATFORMS[@]}"; do
    target="${entry#*:}"
    printf "  %s\n" "$target"
done
printf "  %s （源目录）\n" "$SKILL_DIR"

if [ "$DRY_RUN" = "1" ]; then
    printf "\n${YELLOW}[dry-run]${RESET} 没有实际写入任何文件。去掉 --dry-run 再跑一次即可真正部署。\n"
    exit 0
fi

cat << EOF

下一步：
  1. 在你的 AI 助手中说"帮我发小红书"
  2. 首次使用会进入博主画像建立流程
  3. 画像建立完成后即可开始选题、创作、发布

常用自检命令：
  bash install.sh --check                 # 只看依赖+平台+版本对比
  python3 scripts/preflight.py --human    # 人类可读的健康检查

详细的平台适配说明见 platform/ 目录：
  - platform/hermes.md       — Hermes 定时任务配置
  - platform/claude-code.md  — Claude Code 使用指南
  - platform/codex.md        — Codex 使用指南

EOF
