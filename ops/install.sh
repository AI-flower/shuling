#!/usr/bin/env bash
set -euo pipefail

# v3.0: 此脚本物理位置在 ops/install.sh，源仓库根 = ops/ 的父目录。
# 兼容旧布局：若父目录没有 VERSION 但同级有，则同级当作 SKILL_DIR（兼容 install.sh stub
# 直接 source 进来 / 老版本 ops/install.sh 同级布局两种调用方式）。
_self_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$_self_dir/../VERSION" ] && [ -f "$_self_dir/../SKILL.md" ]; then
    SKILL_DIR="$(cd "$_self_dir/.." && pwd)"
elif [ -f "$_self_dir/VERSION" ] && [ -f "$_self_dir/SKILL.md" ]; then
    SKILL_DIR="$_self_dir"
else
    # 兜底：父目录（即使 VERSION/SKILL.md 缺失，也按 ops/ 父目录算源）
    SKILL_DIR="$(cd "$_self_dir/.." && pwd)"
fi
unset _self_dir

# ─── 参数解析（v2.1.3+ / v2.4.0+） ───────────────────────────────────
#
# 用法:
#   bash install.sh [选项]                          # 原 install 流程
#   bash install.sh upgrade-all [选项]              # agent-first 批量升级（v2.4.0+）
#
# 选项:
#   -y, --yes, --non-interactive   不问任何问题，交互项用默认值跳过
#   --dry-run                      只打印将要执行的动作，不写任何东西
#   --check                        只跑预检（依赖 + 平台 + 版本对比），不部署
#   --target <path>                显式指定部署目标（可重复），覆盖默认自动检测
#                                  upgrade-all 下：--target=<name> 只升指定 target
#   --mode <new|existing|ask>      创作者模式（v2.2.0+）；existing = 老博主走 §0c 流程
#   --skip-preflight               跳过部署后的 preflight 运行
#   --json                         upgrade-all 强制机器可读 JSON 输出
#   -h, --help                     显示此帮助
#
# 子命令 upgrade-all (v2.4.0+):
#   bash install.sh upgrade-all                    # 升级所有发现 target
#   bash install.sh upgrade-all --dry-run          # 只出 plan JSON 不执行
#   bash install.sh upgrade-all --target=<name>    # 只升某一个
#   bash install.sh upgrade-all --json             # 强制机器可读 JSON
#
# 环境变量（非交互模式下替代 prompt）:
#   GEMINI_API_KEY=xxx             预填 Gemini API Key，写入 .env
#   XHS_MCP_URL=http://...         预填 MCP URL，写入 .env
#   SHULING_ASSUME_YES=1           等同 --yes
#   SHULING_CREATOR_MODE=existing  等同 --mode=existing
#
# 示例:
#   bash install.sh --check                            # 只自检不动手
#   bash install.sh --dry-run                          # 预演一次
#   bash install.sh --mode=existing-creator            # 老博主接入模式
#   bash install.sh upgrade-all --dry-run --json       # 计划 JSON
#   SHULING_ASSUME_YES=1 GEMINI_API_KEY=xxx bash install.sh   # CI/远程
#   bash install.sh --target ~/.myagents/skills/shuling       # 自定义目标

ASSUME_YES="${SHULING_ASSUME_YES:-0}"
DRY_RUN=0
CHECK_ONLY=0
SKIP_PREFLIGHT=0
CREATOR_MODE="${SHULING_CREATOR_MODE:-ask}"
declare -a EXPLICIT_TARGETS=()

# upgrade-all 子命令（v2.4.0+）
UPGRADE_ALL=0
JSON_OUT=0
UA_TARGET_FILTER=""

# v3.0 子命令
DOCTOR=0
MIGRATE_LAYOUT=0
ROLLBACK_TO_V2=0
SUBCMD_TARGET=""    # doctor / migrate-layout / rollback-to-v2 接受的位置参数

usage() {
    cat <<'USAGE'
shuling install.sh — agent-friendly installer / upgrader (v3.0)

用法:
  bash ops/install.sh                          # 默认 install 流程
  bash ops/install.sh upgrade-all [选项]       # agent-first 批量升级
  bash ops/install.sh doctor [TARGET]          # 12 项体检（输出表格或 JSON）
  bash ops/install.sh migrate-layout [TARGET]  # v2 → v3 布局迁移
  bash ops/install.sh rollback-to-v2 <TARGET>  # 输出 v2 回滚指引（不动用户态）

选项:
  -y, --yes, --non-interactive   非交互模式
  --dry-run                      只打印将要执行的动作
  --check                        只跑预检
  --target <path>                显式部署目标（可重复）
  --target=<name>                upgrade-all 下：只升指定 target name
  --mode <new|existing|ask>      创作者模式（v2.2.0+）
  --skip-preflight               跳过 preflight
  --json                         机器可读 JSON（doctor / upgrade-all 支持）
  -h, --help                     本帮助

子命令汇总:
  install            (默认)
  upgrade-all
  doctor [TARGET]
  migrate-layout [TARGET]
  rollback-to-v2 <TARGET>
  --check / --dry-run            install 流程的等效开关

环境变量:
  GEMINI_API_KEY                 Gemini API Key（写 runtime.env）
  XHS_MCP_URL                    MCP URL（写 runtime.env）
  SHULING_ASSUME_YES=1           等同 --yes
  SHULING_CREATOR_MODE=existing  等同 --mode=existing

示例:
  bash ops/install.sh --check
  bash ops/install.sh upgrade-all --dry-run --json
  bash ops/install.sh doctor ~/.hermes/skills/shuling --json
  bash ops/install.sh migrate-layout ~/.claude/skills/shuling
  bash ops/install.sh rollback-to-v2 ~/.hermes/skills/shuling
USAGE
}

# 先截获子命令（位置参数），不影响原有 option 解析
if [ $# -gt 0 ]; then
    case "$1" in
        upgrade-all)        UPGRADE_ALL=1; shift ;;
        doctor)             DOCTOR=1; shift
                            # 可选位置参数 = target path
                            if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
                                SUBCMD_TARGET="$1"; shift
                            fi ;;
        migrate-layout)     MIGRATE_LAYOUT=1; shift
                            if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
                                SUBCMD_TARGET="$1"; shift
                            fi ;;
        rollback-to-v2)     ROLLBACK_TO_V2=1; shift
                            if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
                                SUBCMD_TARGET="$1"; shift
                            fi ;;
    esac
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes|--non-interactive) ASSUME_YES=1; shift ;;
        --dry-run)                  DRY_RUN=1; shift ;;
        --check)                    CHECK_ONLY=1; shift ;;
        --skip-preflight)           SKIP_PREFLIGHT=1; shift ;;
        --json)                     JSON_OUT=1; shift ;;
        --target=*)
            # upgrade-all 下 --target=<name> 是 target name 过滤；install 模式下允许也当路径看待
            if [ "$UPGRADE_ALL" = "1" ]; then
                UA_TARGET_FILTER="${1#*=}"; shift
            else
                EXPLICIT_TARGETS+=("${1#*=}"); shift
            fi ;;
        --target)
            [ $# -ge 2 ] || { echo "错误: --target 需要一个路径参数" >&2; exit 2; }
            if [ "$UPGRADE_ALL" = "1" ]; then
                UA_TARGET_FILTER="$2"; shift 2
            else
                EXPLICIT_TARGETS+=("$2"); shift 2
            fi ;;
        --mode=*)
            case "${1#*=}" in
                new|existing|ask)             CREATOR_MODE="${1#*=}" ;;
                existing-creator)             CREATOR_MODE="existing" ;;
                *) echo "错误: --mode 只接受 new / existing / existing-creator / ask" >&2; exit 2 ;;
            esac; shift ;;
        --mode)
            [ $# -ge 2 ] || { echo "错误: --mode 需要一个值" >&2; exit 2; }
            case "$2" in
                new|existing|ask)             CREATOR_MODE="$2" ;;
                existing-creator)             CREATOR_MODE="existing" ;;
                *) echo "错误: --mode 只接受 new / existing / existing-creator / ask" >&2; exit 2 ;;
            esac; shift 2 ;;
        -h|--help)                  usage; exit 0 ;;
        *) echo "错误: 未知参数 $1（见 --help）" >&2; exit 2 ;;
    esac
done

# upgrade-all 默认强制 JSON 输出（agent-first）
if [ "$UPGRADE_ALL" = "1" ]; then
    JSON_OUT=1
fi

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

# v3-compat path resolvers — agent/ first, fallback v2 layout
# resolve_scripts_dir <root>  → echo "<root>/agent/scripts" or "<root>/scripts"
resolve_scripts_dir() {
    local root="$1"
    if [ -d "$root/agent/scripts" ]; then
        echo "$root/agent/scripts"
    else
        echo "$root/scripts"
    fi
}

# resolve_migrations_dir <root> → echo v3 path or v2 path (whichever exists)
resolve_migrations_dir() {
    local root="$1"
    if [ -d "$root/agent/migrations/db" ]; then
        echo "$root/agent/migrations/db"
    elif [ -d "$root/migrations" ]; then
        echo "$root/migrations"
    else
        echo ""
    fi
}

# resolve_db_path <root> → echo target DB path (v3 first, v2 fallback)
resolve_db_path() {
    local root="$1"
    if [ -d "$root/agent" ]; then
        echo "$root/agent/data/xhs.db"
    else
        echo "$root/data/xhs.db"
    fi
}

# resolve_runtime_env <root> → echo target runtime.env path (v3 first, v2 fallback)
resolve_runtime_env() {
    local root="$1"
    if [ -d "$root/agent" ]; then
        echo "$root/agent/config/runtime.env"
    else
        echo "$root/config/runtime.env"
    fi
}

run_migrations() {
    local from_ver="$1" to_ver="$2" target="$3"
    # 优先用源仓库的 v3 migrations/db/，否则回退源仓库 v2 migrations/
    local migrations_dir=""
    if [ -d "$SKILL_DIR/agent/migrations/db" ]; then
        migrations_dir="$SKILL_DIR/agent/migrations/db"
    elif [ -d "$SKILL_DIR/migrations" ]; then
        migrations_dir="$SKILL_DIR/migrations"
    fi
    [ -n "$migrations_dir" ] && [ -d "$migrations_dir" ] || return 0

    local target_db
    target_db="$(resolve_db_path "$target")"

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
                (env SHULING_DB="$target_db" SKILL_DIR="$target" bash "$m")
            fi
            ran=$((ran + 1))
        fi
    done
    if [ "$ran" = "0" ]; then
        printf "  无需 migration（已是 %s）\n" "$to_ver"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# upgrade-all 子命令（v2.4.0+）—— agent-first 批量升级
# ═══════════════════════════════════════════════════════════════════
#
# 设计原则：
#   - 零人类文案依赖：结果全 JSON，stderr 只输步骤调试、stdout 只输最终 JSON
#   - 幂等：backup/rsync/migrations/hooks/pip 全部可重跑
#   - 声明式：每 target 每 step 都有 {id,status,...} 记录
#   - 容错：单 step 失败本 target 其余 step 标 skipped/prior_failed，继续下一 target

# ─── JSON 小工具 ────────────────────────────────────────────────────
# 用 python3 做 JSON 转义（bash 写 JSON 会挂在引号 / 控制字符上）
json_escape() {
    python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"
}

# 日志输出到 stderr（以避免污染 stdout 的 JSON）
ua_log() {
    [ "$JSON_OUT" = "1" ] || return 0
    # JSON 模式下全部静音；非 JSON 模式（未来保留扩展）这里可以 printf
    :
}

# ─── 发现 targets ──────────────────────────────────────────────────
#
# 扫描三路径：
#   ~/.codex/skills/*
#   ~/.hermes/skills/**   （最多两层，支持 social-media/shuling）
#   ~/.claude/skills/*
#
# 识别条件：目录内同时有 VERSION + SKILL.md
#
# 输出全局数组 UA_TARGETS，每项为 "name\tpath\truntime_env\tscheduler_kind\tscheduler_config"
#   scheduler_kind   : "none" | "hermes-cron"
#   scheduler_config : 调度器配置文件绝对路径，none 时为空
declare -a UA_TARGETS=()

_ua_is_target() {
    local dir="$1"
    [ -f "$dir/VERSION" ] && [ -f "$dir/SKILL.md" ] || return 1
    # 排除备份目录（install.sh 自己生成的命名约定 *.bak-v<ver>-<ts>）
    case "$(basename "$dir")" in
        *.bak-*|*.bak|*.backup|*.old) return 1 ;;
    esac
    return 0
}

_ua_guess_name() {
    local path="$1" base
    case "$path" in
        "$HOME/.codex/skills/"*)    echo "codex" ;;
        "$HOME/.hermes/skills/"*)   echo "hermes" ;;
        "$HOME/.claude/skills/"*)   echo "claude" ;;
        *)
            base="$(basename "$path")"
            # 兜底：目录名不是 shuling 就用它；是 shuling 就用上级
            if [ "$base" = "shuling" ]; then
                base="$(basename "$(dirname "$path")")"
            fi
            echo "${base:-custom}"
            ;;
    esac
}

discover_targets() {
    UA_TARGETS=()
    local seen=""
    local d

    # ~/.codex/skills/* （一层）
    if [ -d "$HOME/.codex/skills" ]; then
        for d in "$HOME/.codex/skills"/*; do
            [ -d "$d" ] || continue
            _ua_is_target "$d" || continue
            case "$seen" in *"|$d|"*) continue ;; esac
            seen="$seen|$d|"
            UA_TARGETS+=("codex	$d	$d/config/runtime.env	none	")
        done
    fi

    # ~/.hermes/skills/** （最多两层：扫 skills/* 和 skills/*/*）
    if [ -d "$HOME/.hermes/skills" ]; then
        local jobs_json="$HOME/.hermes/cron/jobs.json"
        local sched_kind="none" sched_cfg=""
        if [ -f "$jobs_json" ]; then
            sched_kind="hermes-cron"
            sched_cfg="$jobs_json"
        fi
        # 一层
        for d in "$HOME/.hermes/skills"/*; do
            [ -d "$d" ] || continue
            if _ua_is_target "$d"; then
                case "$seen" in *"|$d|"*) continue ;; esac
                seen="$seen|$d|"
                UA_TARGETS+=("hermes	$d	$d/config/runtime.env	$sched_kind	$sched_cfg")
            fi
        done
        # 两层（如 social-media/shuling）
        for d in "$HOME/.hermes/skills"/*/*; do
            [ -d "$d" ] || continue
            if _ua_is_target "$d"; then
                case "$seen" in *"|$d|"*) continue ;; esac
                seen="$seen|$d|"
                UA_TARGETS+=("hermes	$d	$d/config/runtime.env	$sched_kind	$sched_cfg")
            fi
        done
    fi

    # ~/.claude/skills/* （一层）
    if [ -d "$HOME/.claude/skills" ]; then
        for d in "$HOME/.claude/skills"/*; do
            [ -d "$d" ] || continue
            _ua_is_target "$d" || continue
            case "$seen" in *"|$d|"*) continue ;; esac
            seen="$seen|$d|"
            UA_TARGETS+=("claude	$d	$d/config/runtime.env	none	")
        done
    fi
}

# ─── 每 step 构造 JSON 片段（拼到 STEP_JSONS 里）────────────────────
# step_record <id> <status> [key1 val1 key2 val2 ...]
#   生成 {"id":"...","status":"...",<extra k/v>} 并追加到全局 STEP_JSONS
declare -a STEP_JSONS=()
CURRENT_TARGET_FAILED=0

step_record() {
    local id="$1" status="$2"; shift 2
    local extras=""
    while [ $# -ge 2 ]; do
        local k="$1" v="$2"; shift 2
        # 数字类型（files_changed）特殊处理——纯数字就不引号
        if [[ "$v" =~ ^[0-9]+$ ]]; then
            extras="$extras,$(json_escape "$k"):$v"
        else
            extras="$extras,$(json_escape "$k"):$(json_escape "$v")"
        fi
    done
    STEP_JSONS+=("{$(json_escape "id"):$(json_escape "$id"),$(json_escape "status"):$(json_escape "$status")$extras}")
    [ "$status" = "failed" ] && CURRENT_TARGET_FAILED=1
}

# ─── 6 个 step 的具体实现 ───────────────────────────────────────────

ua_step_backup() {
    local path="$1" to_ver="$2"
    local ts backup_path
    ts="$(date +%Y%m%d-%H%M%S)"
    backup_path="${path}.bak-v${to_ver}-${ts}"
    if [ "$DRY_RUN" = "1" ]; then
        step_record "backup" "planned" "artifact" "$backup_path"
        return 0
    fi
    if cp -R "$path" "$backup_path" 2>/dev/null; then
        step_record "backup" "ok" "artifact" "$backup_path"
    else
        step_record "backup" "failed" "reason" "cp_failed" "artifact" "$backup_path"
    fi
}

ua_step_rsync_code() {
    local path="$1"
    if [ "$CURRENT_TARGET_FAILED" = "1" ]; then
        step_record "rsync_code" "skipped" "reason" "prior_failed"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        step_record "rsync_code" "planned" "source" "$SKILL_DIR"
        return 0
    fi

    # ─── v3 source layout (ADR-0001 + §F): source-side white-list ────
    # 当源仓库已经迁到 v3 布局（含 agent/ 目录）时，改用 staging + atomic swap，
    # 只 rsync 已知的代码资产，避免任何源仓库杂项（landing/ docs/ skills/ etc.）漏到 target。
    # 保留用户态：target/agent/data/、target/agent/config/、target/agent/knowledge-base/。
    if [ -d "$SKILL_DIR/agent" ]; then
        local staging="$path/.staging-v3-rsync"
        local log files_changed=0 doc rc=0
        log="$(mktemp)"
        rm -rf "$staging" 2>/dev/null
        mkdir -p "$staging" || { step_record "rsync_code" "failed" "reason" "staging_mkdir_failed"; rm -f "$log"; return 0; }

        # 白名单：SKILL.md / VERSION + agents/ + agent/（不含用户态子目录）
        local rsync_args=(-a --itemize-changes)
        # agent/ 子树排除用户态目录
        rsync_args+=(--exclude='agent/data/' --exclude='agent/config/runtime.env' --exclude='agent/config/state.json' --exclude='agent/knowledge-base/')
        # 显式列出 source 资产
        local -a sources=()
        [ -f "$SKILL_DIR/SKILL.md" ] && sources+=("$SKILL_DIR/SKILL.md")
        [ -f "$SKILL_DIR/VERSION" ]  && sources+=("$SKILL_DIR/VERSION")
        [ -d "$SKILL_DIR/agents" ]   && sources+=("$SKILL_DIR/agents")
        [ -d "$SKILL_DIR/agent" ]    && sources+=("$SKILL_DIR/agent")
        # 兼容核心文档（保留旧行为）
        for doc in README.md CHANGELOG.md UPGRADE.md RELEASING.md; do
            [ -f "$SKILL_DIR/$doc" ] && sources+=("$SKILL_DIR/$doc")
        done

        if [ "${#sources[@]}" -eq 0 ]; then
            step_record "rsync_code" "failed" "reason" "no_v3_sources_found"
            rm -rf "$staging"; rm -f "$log"; return 0
        fi

        if rsync "${rsync_args[@]}" "${sources[@]}" "$staging/" > "$log" 2>&1; then
            files_changed="$(grep -c '^' "$log" 2>/dev/null || echo 0)"
            # Atomic swap：把 staging 内文件 mv 到 target，保留用户态目录
            # 顶层文件 / 顶层目录逐个搬
            local item
            for item in "$staging"/*; do
                [ -e "$item" ] || continue
                local bn
                bn="$(basename "$item")"
                if [ "$bn" = "agent" ] && [ -d "$path/agent" ]; then
                    # 合并 agent 子树：在 agent/ 内逐项替换非用户态子树
                    local sub
                    for sub in "$item"/*; do
                        [ -e "$sub" ] || continue
                        local sbn
                        sbn="$(basename "$sub")"
                        # 用户态子目录不动
                        case "$sbn" in
                            data|config|knowledge-base) continue ;;
                        esac
                        rm -rf "$path/agent/$sbn" 2>/dev/null
                        mv "$sub" "$path/agent/$sbn"
                    done
                else
                    rm -rf "$path/$bn" 2>/dev/null
                    mv "$item" "$path/$bn"
                fi
            done
            rm -rf "$staging"
            step_record "rsync_code" "ok" "files_changed" "$files_changed" "mode" "v3_whitelist"
            rm -f "$log"
            return 0
        else
            step_record "rsync_code" "failed" "reason" "rsync_failed_v3"
            rm -rf "$staging"; rm -f "$log"
            return 0
        fi
    fi

    # ─── v2 legacy black-list mode（保留兼容） ───────────────────────
    local log files_changed
    log="$(mktemp)"
    if rsync -a --delete \
        --exclude=data/ \
        --exclude=config/runtime.env \
        --exclude=config/state.json \
        --exclude=knowledge-base/ \
        --exclude=landing/ \
        --exclude=.playwright-mcp/ \
        --exclude=.git \
        --exclude=.DS_Store \
        --exclude=.idea \
        --exclude=.session-recorder \
        --exclude=skills \
        --exclude=docs \
        --exclude='*.md' \
        --itemize-changes \
        "$SKILL_DIR/" "$path/" > "$log" 2>&1; then
        # 每一行是一个文件变化
        files_changed="$(grep -c '^' "$log" 2>/dev/null || echo 0)"
        # 保留核心 .md（SKILL / README / CHANGELOG / UPGRADE / RELEASING / VERSION）
        local doc
        for doc in SKILL.md README.md CHANGELOG.md UPGRADE.md RELEASING.md VERSION; do
            [ -f "$SKILL_DIR/$doc" ] && cp "$SKILL_DIR/$doc" "$path/" 2>/dev/null || true
        done
        step_record "rsync_code" "ok" "files_changed" "$files_changed" "mode" "v2_blacklist"
        rm -f "$log"
    else
        step_record "rsync_code" "failed" "reason" "rsync_failed"
        rm -f "$log"
    fi
}

ua_step_migrations() {
    local path="$1" from_ver="$2" to_ver="$3"
    if [ "$CURRENT_TARGET_FAILED" = "1" ]; then
        step_record "migrations" "skipped" "reason" "prior_failed"
        return 0
    fi
    # 优先用源仓库 v3 migrations/db/，否则回退 v2 migrations/
    local migrations_dir=""
    if [ -d "$SKILL_DIR/agent/migrations/db" ]; then
        migrations_dir="$SKILL_DIR/agent/migrations/db"
    elif [ -d "$SKILL_DIR/migrations" ]; then
        migrations_dir="$SKILL_DIR/migrations"
    fi
    if [ -z "$migrations_dir" ] || [ ! -d "$migrations_dir" ]; then
        step_record "migrations" "skipped" "reason" "no_migrations_dir"
        return 0
    fi
    local target_db
    target_db="$(resolve_db_path "$path")"
    local any=0 m fname v
    for m in $(ls "$migrations_dir"/v*.sh 2>/dev/null | sort -V); do
        fname="$(basename "$m")"
        v="${fname#v}"; v="${v%.sh}"
        # 只跑 from < v <= to
        version_lt "$from_ver" "$v" || continue
        version_le "$v" "$to_ver" || continue
        any=1
        local step_id="migration_v${v}"
        if [ "$DRY_RUN" = "1" ]; then
            step_record "$step_id" "planned" "script" "$fname"
            continue
        fi
        # migration 脚本自身通过 _guard.sh 查 __migrations 表做幂等
        # 我们检测退出码 + 输出关键字来判定 ok/skipped
        #
        # v2.4.2: 同时传 SHULING_DB, 让 _guard.sh 里的 _GUARD_DB 指向 target DB 而非源 DB.
        # 旧版仅传 SKILL_DIR 会被 migration/v*.sh 的 `SKILL_DIR="$(cd "$(dirname "$0")/..")` 覆盖,
        # 导致 migration 永远写源仓库 data/xhs.db, target 的 __migrations 永远空.
        # _guard.sh 的 DB 解析优先级: SHULING_DB > $SKILL_DIR/data/xhs.db
        # v3.0: target_db 通过 resolve_db_path 解析（agent/data 或 data）
        local out rc
        out="$(env SHULING_DB="$target_db" SKILL_DIR="$path" bash "$m" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "0" ]; then
            # 脚本打印 "already applied" 视为 skipped；其余视为 ok
            if echo "$out" | grep -qiE "already[ _-]?applied|skipped|no_schema_change"; then
                step_record "$step_id" "skipped" "reason" "already_applied"
            else
                step_record "$step_id" "ok" "script" "$fname"
            fi
        else
            step_record "$step_id" "failed" "reason" "migration_exit_$rc" "script" "$fname"
        fi
    done
    if [ "$any" = "0" ]; then
        step_record "migrations" "skipped" "reason" "no_pending_migration"
    fi
}

ua_step_upgrade_hooks() {
    local path="$1" from_ver="$2" to_ver="$3"
    if [ "$CURRENT_TARGET_FAILED" = "1" ]; then
        step_record "upgrade_hooks" "skipped" "reason" "prior_failed"
        return 0
    fi
    local hooks_root="$SKILL_DIR/upgrade-hooks"
    if [ ! -d "$hooks_root" ]; then
        step_record "upgrade_hooks" "skipped" "reason" "no_hooks_dir"
        return 0
    fi
    local any=0 vdir vname
    for vdir in $(ls -d "$hooks_root"/v*/ 2>/dev/null | sort -V); do
        vname="$(basename "$vdir")"          # "v2.3.0"
        local v="${vname#v}"
        version_lt "$from_ver" "$v" || continue
        version_le "$v" "$to_ver" || continue
        # 跑该版本下所有 *.sh
        local hook hname
        local hooks_in_ver=0
        for hook in "$vdir"*.sh; do
            [ -f "$hook" ] || continue
            hooks_in_ver=$((hooks_in_ver + 1))
            any=1
            hname="$(basename "$hook" .sh)"
            local step_id="upgrade_hook_${hname}"
            if [ "$DRY_RUN" = "1" ]; then
                step_record "$step_id" "planned" "version" "$v" "hook" "$hname"
                continue
            fi
            local out rc
            out="$(bash "$hook" "$path" 2>&1)" && rc=0 || rc=$?
            if [ "$rc" = "0" ]; then
                if echo "$out" | grep -qiE "already|skipped|no_change"; then
                    step_record "$step_id" "skipped" "reason" "already_applied" "version" "$v"
                else
                    step_record "$step_id" "ok" "version" "$v" "hook" "$hname"
                fi
            else
                step_record "$step_id" "failed" "reason" "hook_exit_$rc" "version" "$v" "hook" "$hname"
            fi
        done
        if [ "$hooks_in_ver" = "0" ]; then
            # 空目录（Team-2 未交付），明确记录
            step_record "upgrade_hooks_${vname}" "skipped" "reason" "empty_version_dir"
        fi
    done
    if [ "$any" = "0" ]; then
        step_record "upgrade_hooks" "skipped" "reason" "no_applicable_hooks"
    fi
}

ua_step_pip_install() {
    local path="$1"
    if [ "$CURRENT_TARGET_FAILED" = "1" ]; then
        step_record "pip_install" "skipped" "reason" "prior_failed"
        return 0
    fi
    local req="$SKILL_DIR/requirements.txt"
    if [ ! -f "$req" ]; then
        step_record "pip_install" "skipped" "reason" "no_requirements_txt"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        step_record "pip_install" "planned" "source" "$req"
        return 0
    fi
    if pip3 install -r "$req" --disable-pip-version-check --quiet >/dev/null 2>&1; then
        step_record "pip_install" "ok" "source" "$req"
    else
        step_record "pip_install" "failed" "reason" "pip_install_failed"
    fi
}

ua_step_preflight() {
    local path="$1"
    if [ "$CURRENT_TARGET_FAILED" = "1" ]; then
        step_record "preflight" "skipped" "reason" "prior_failed"
        return 0
    fi
    local scripts_dir
    scripts_dir="$(resolve_scripts_dir "$path")"
    local pf="$scripts_dir/preflight.py"
    if [ ! -f "$pf" ]; then
        step_record "preflight" "skipped" "reason" "no_preflight_script"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        step_record "preflight" "planned" "script" "$pf"
        return 0
    fi
    # v2.4.2: preflight 退出码分级 (见 scripts/preflight.py _exit_code):
    #   0 = 全绿; 1 = auto_fixable; 2 = need_user (用户需补 MCP/key/profile)
    # upgrade-all 只对"代码/DB 升级"负责, 运行时配置就绪不是 upgrade 的责任.
    # 所以 exit 0/1/2 都视为 upgrade 成功, 只有脚本 crash / 非 0/1/2 才算 failed.
    # v3.0: pf 路径走 resolve_scripts_dir（agent/scripts 优先，回退 scripts）
    (cd "$path" && python3 "$pf" >/dev/null 2>&1)
    local pf_rc=$?
    case "$pf_rc" in
        0)
            step_record "preflight" "ok"
            ;;
        1|2)
            step_record "preflight" "ok" "note" "runtime_config_incomplete_rc${pf_rc}"
            ;;
        *)
            step_record "preflight" "failed" "reason" "preflight_crashed_rc${pf_rc}"
            ;;
    esac
}

# ─── 升级单个 target ───────────────────────────────────────────────
# $1..$5 = name \t path \t runtime_env \t scheduler_kind \t scheduler_config
#  输出：一段 JSON 对象片段（不带外层逗号）
upgrade_one_target() {
    local name="$1" path="$2" runtime_env="$3" sched_kind="$4" sched_cfg="$5"
    local from_ver to_ver
    from_ver="$(read_version "$path/VERSION")"
    to_ver="$SRC_VERSION"

    STEP_JSONS=()
    CURRENT_TARGET_FAILED=0

    ua_step_backup          "$path" "$to_ver"
    ua_step_rsync_code      "$path"
    ua_step_migrations      "$path" "$from_ver" "$to_ver"
    ua_step_upgrade_hooks   "$path" "$from_ver" "$to_ver"
    ua_step_pip_install     "$path"
    ua_step_preflight       "$path"

    # 组装 steps 数组
    local steps_joined="" i
    for i in "${!STEP_JSONS[@]}"; do
        if [ "$i" = "0" ]; then
            steps_joined="${STEP_JSONS[$i]}"
        else
            steps_joined="$steps_joined,${STEP_JSONS[$i]}"
        fi
    done

    # 调度器元信息
    local sched_json
    if [ "$sched_kind" = "none" ] || [ -z "$sched_kind" ]; then
        sched_json="{$(json_escape kind):$(json_escape none)}"
    else
        sched_json="{$(json_escape kind):$(json_escape "$sched_kind"),$(json_escape config):$(json_escape "$sched_cfg")}"
    fi

    printf '{%s:%s,%s:%s,%s:%s,%s:%s,%s:%s,%s:%s,%s:[%s]}' \
        "$(json_escape name)"         "$(json_escape "$name")" \
        "$(json_escape path)"         "$(json_escape "$path")" \
        "$(json_escape from_version)" "$(json_escape "$from_ver")" \
        "$(json_escape to_version)"   "$(json_escape "$to_ver")" \
        "$(json_escape runtime_env)"  "$(json_escape "$runtime_env")" \
        "$(json_escape scheduler)"    "$sched_json" \
        "$(json_escape steps)"        "$steps_joined"

    # 若该 target 任一 step failed，标记 overall 需降级
    if [ "$CURRENT_TARGET_FAILED" = "1" ]; then
        return 1
    fi
    return 0
}

# ─── 主入口 ────────────────────────────────────────────────────────
run_upgrade_all() {
    discover_targets

    local filtered=()
    local entry name path re sk sc
    for entry in "${UA_TARGETS[@]+"${UA_TARGETS[@]}"}"; do
        IFS=$'\t' read -r name path re sk sc <<< "$entry"
        if [ -n "$UA_TARGET_FILTER" ] && [ "$name" != "$UA_TARGET_FILTER" ]; then
            continue
        fi
        filtered+=("$entry")
    done

    if [ "${#filtered[@]}" = "0" ]; then
        local reason="no_targets_found"
        [ -n "$UA_TARGET_FILTER" ] && reason="filter_matched_nothing"
        printf '{"overall":"failed","reason":%s,"targets":[]}\n' "$(json_escape "$reason")"
        exit 3
    fi

    local targets_joined="" any_failed=0 i=0
    for entry in "${filtered[@]}"; do
        IFS=$'\t' read -r name path re sk sc <<< "$entry"
        local target_json
        if target_json="$(upgrade_one_target "$name" "$path" "$re" "$sk" "$sc")"; then
            :
        else
            any_failed=1
        fi
        if [ "$i" = "0" ]; then
            targets_joined="$target_json"
        else
            targets_joined="$targets_joined,$target_json"
        fi
        i=$((i + 1))
    done

    local overall
    if [ "$DRY_RUN" = "1" ]; then
        overall="planned"
    elif [ "$any_failed" = "1" ]; then
        overall="failed"
    else
        overall="success"
    fi

    # 单行 JSON 输出到 stdout
    printf '{"overall":%s,"src_version":%s,"target_count":%s,"targets":[%s]}\n' \
        "$(json_escape "$overall")" \
        "$(json_escape "$SRC_VERSION")" \
        "${#filtered[@]}" \
        "$targets_joined"

    [ "$any_failed" = "1" ] && exit 1
    exit 0
}

# ═══════════════════════════════════════════════════════════════════
# v3.0 新子命令实现：doctor / migrate-layout / rollback-to-v2
# ═══════════════════════════════════════════════════════════════════

# _resolve_subcmd_target — 选 target 路径优先级：位置参数 > --target > 自动发现首个
_resolve_subcmd_target() {
    if [ -n "$SUBCMD_TARGET" ]; then
        echo "$SUBCMD_TARGET"; return 0
    fi
    if [ "${#EXPLICIT_TARGETS[@]}" -gt 0 ]; then
        echo "${EXPLICIT_TARGETS[0]}"; return 0
    fi
    # 自动发现：用 discover_targets 取第一个
    discover_targets
    if [ "${#UA_TARGETS[@]}" -gt 0 ]; then
        IFS=$'\t' read -r _n _p _re _sk _sc <<< "${UA_TARGETS[0]}"
        echo "$_p"; return 0
    fi
    echo ""; return 1
}

# ─── doctor 子命令 ──────────────────────────────────────────────────
# 12 项检查，输出表格或 JSON
cmd_doctor() {
    local target
    target="$(_resolve_subcmd_target)" || true
    if [ -z "$target" ]; then
        if [ "$JSON_OUT" = "1" ]; then
            printf '{"overall":"error","reason":"no_target_found","checks":[]}\n'
        else
            fail "doctor: 未指定 TARGET 且未发现任何已安装目标"
            info "用法: bash ops/install.sh doctor <TARGET_PATH>"
        fi
        exit 2
    fi

    # 各项检查结果：name / status (ok/fail/skip) / detail
    local -a names=()
    local -a statuses=()
    local -a details=()

    _add_check() { names+=("$1"); statuses+=("$2"); details+=("$3"); }

    # 1. SKILL.md 存在
    if [ -f "$target/SKILL.md" ]; then
        _add_check "skill_md_exists" "ok" "$target/SKILL.md"
    else
        _add_check "skill_md_exists" "fail" "missing"
    fi

    # 2. agent/ 目录存在
    if [ -d "$target/agent" ]; then
        _add_check "agent_dir_exists" "ok" "$target/agent"
    else
        _add_check "agent_dir_exists" "fail" "v2_layout_or_missing"
    fi

    # 3. agent/data/xhs.db 存在
    local db_path
    db_path="$(resolve_db_path "$target")"
    if [ -f "$db_path" ]; then
        _add_check "db_exists" "ok" "$db_path"
    else
        _add_check "db_exists" "fail" "$db_path"
    fi

    # 4. agent/config/runtime.env 存在或 .example 存在
    local runtime_env runtime_example
    runtime_env="$(resolve_runtime_env "$target")"
    runtime_example=""
    if [ -f "$target/agent/config/runtime.env.example" ]; then
        runtime_example="$target/agent/config/runtime.env.example"
    elif [ -f "$target/config/runtime.env.example" ]; then
        runtime_example="$target/config/runtime.env.example"
    fi
    if [ -f "$runtime_env" ]; then
        _add_check "runtime_env_present" "ok" "$runtime_env"
    elif [ -n "$runtime_example" ]; then
        _add_check "runtime_env_present" "ok" "example_only:$runtime_example"
    else
        _add_check "runtime_env_present" "fail" "neither_found"
    fi

    # 5. scripts/db.sh 可执行
    local scripts_dir
    scripts_dir="$(resolve_scripts_dir "$target")"
    if [ -x "$scripts_dir/db.sh" ]; then
        _add_check "db_sh_executable" "ok" "$scripts_dir/db.sh"
    else
        _add_check "db_sh_executable" "fail" "$scripts_dir/db.sh"
    fi

    # 6. .layout-v3.done marker 存在
    local marker="$target/agent/config/.layout-v3.done"
    if [ -f "$marker" ]; then
        _add_check "layout_v3_marker" "ok" "$marker"
    else
        _add_check "layout_v3_marker" "fail" "missing"
    fi

    # 7. preflight.py 退出码
    local pf="$scripts_dir/preflight.py"
    if [ -f "$pf" ]; then
        local pf_rc=0
        (cd "$target" && python3 "$pf" >/dev/null 2>&1) || pf_rc=$?
        case "$pf_rc" in
            0)   _add_check "preflight_exit" "ok"   "rc=0_all_green" ;;
            1|2) _add_check "preflight_exit" "ok"   "rc=${pf_rc}_runtime_config_incomplete" ;;
            *)   _add_check "preflight_exit" "fail" "rc=${pf_rc}_crashed" ;;
        esac
    else
        _add_check "preflight_exit" "fail" "no_preflight_script"
    fi

    # 8. ensure-runtime-layout dry-run 通过
    local erl="$scripts_dir/ensure-runtime-layout.sh"
    if [ -x "$erl" ]; then
        if (cd "$target" && bash "$erl" --dry-run >/dev/null 2>&1); then
            _add_check "ensure_runtime_layout_dryrun" "ok" "passed"
        else
            _add_check "ensure_runtime_layout_dryrun" "fail" "exit_nonzero"
        fi
    else
        _add_check "ensure_runtime_layout_dryrun" "skip" "script_not_found"
    fi

    # 9. ensure-schema dry-run 通过
    local es="$scripts_dir/ensure-schema.sh"
    if [ -x "$es" ]; then
        if (cd "$target" && bash "$es" --dry-run >/dev/null 2>&1); then
            _add_check "ensure_schema_dryrun" "ok" "passed"
        else
            _add_check "ensure_schema_dryrun" "fail" "exit_nonzero"
        fi
    else
        _add_check "ensure_schema_dryrun" "skip" "script_not_found"
    fi

    # 10. agent/playbook/ 至少 9 个文件
    local playbook_dir="$target/agent/playbook"
    if [ -d "$playbook_dir" ]; then
        local pb_count
        pb_count="$(find "$playbook_dir" -maxdepth 2 -type f 2>/dev/null | wc -l | tr -d ' ')"
        if [ "${pb_count:-0}" -ge 9 ]; then
            _add_check "playbook_min_9" "ok" "count=$pb_count"
        else
            _add_check "playbook_min_9" "fail" "count=$pb_count"
        fi
    else
        _add_check "playbook_min_9" "fail" "no_playbook_dir"
    fi

    # 11. agent/schemas/ 至少 4 个 JSON
    local schemas_dir
    if [ -d "$target/agent/schemas" ]; then
        schemas_dir="$target/agent/schemas"
    else
        schemas_dir="$target/schemas"
    fi
    if [ -d "$schemas_dir" ]; then
        local sc_count
        sc_count="$(find "$schemas_dir" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
        if [ "${sc_count:-0}" -ge 4 ]; then
            _add_check "schemas_min_4_json" "ok" "count=$sc_count@$schemas_dir"
        else
            _add_check "schemas_min_4_json" "fail" "count=$sc_count@$schemas_dir"
        fi
    else
        _add_check "schemas_min_4_json" "fail" "no_schemas_dir"
    fi

    # 12. SKILL.md frontmatter 含 version
    if [ -f "$target/SKILL.md" ]; then
        if head -30 "$target/SKILL.md" | grep -qE '^version:[[:space:]]*' 2>/dev/null; then
            local v_line
            # 兼容 `version: 3.0.0` 与 `version: "3.0.0"` 两种写法
            v_line="$(head -30 "$target/SKILL.md" | awk '/^version:/ {gsub(/[[:space:]"]/,"",$2); print $2; exit}')"
            _add_check "skill_md_frontmatter_version" "ok" "version=${v_line:-?}"
        else
            _add_check "skill_md_frontmatter_version" "fail" "no_version_key"
        fi
    else
        _add_check "skill_md_frontmatter_version" "fail" "no_skill_md"
    fi

    # ─── 输出 ────────────────────────────────────────────────────
    local total="${#names[@]}" pass=0 fail_n=0 skip_n=0 i
    for ((i=0; i<total; i++)); do
        case "${statuses[$i]}" in
            ok)   pass=$((pass+1)) ;;
            fail) fail_n=$((fail_n+1)) ;;
            skip) skip_n=$((skip_n+1)) ;;
        esac
    done

    if [ "$JSON_OUT" = "1" ]; then
        local overall="ok"
        [ "$fail_n" -gt 0 ] && overall="failed"
        local checks_joined="" j
        for ((j=0; j<total; j++)); do
            local item
            item="{$(json_escape id):$(json_escape "${names[$j]}"),$(json_escape status):$(json_escape "${statuses[$j]}"),$(json_escape detail):$(json_escape "${details[$j]}")}"
            if [ "$j" = "0" ]; then
                checks_joined="$item"
            else
                checks_joined="$checks_joined,$item"
            fi
        done
        printf '{"overall":%s,"target":%s,"total":%s,"passed":%s,"failed":%s,"skipped":%s,"checks":[%s]}\n' \
            "$(json_escape "$overall")" \
            "$(json_escape "$target")" \
            "$total" "$pass" "$fail_n" "$skip_n" \
            "$checks_joined"
        [ "$fail_n" -gt 0 ] && exit 1
        exit 0
    fi

    # 人类可读表格
    printf "${BOLD}=== shuling doctor ===${RESET}\n"
    printf "Target: %s\n\n" "$target"
    printf "%-3s  %-32s  %-6s  %s\n" "#" "Check" "Status" "Detail"
    printf "%-3s  %-32s  %-6s  %s\n" "---" "--------------------------------" "------" "------------------------------"
    for ((i=0; i<total; i++)); do
        local color="$RESET" badge="${statuses[$i]}"
        case "${statuses[$i]}" in
            ok)   color="$GREEN" ;;
            fail) color="$RED" ;;
            skip) color="$YELLOW" ;;
        esac
        printf "%-3s  %-32s  ${color}%-6s${RESET}  %s\n" "$((i+1))" "${names[$i]}" "$badge" "${details[$i]}"
    done
    printf "\nSummary: ${GREEN}%d ok${RESET}, ${RED}%d fail${RESET}, ${YELLOW}%d skip${RESET} (total %d)\n" \
        "$pass" "$fail_n" "$skip_n" "$total"
    [ "$fail_n" -gt 0 ] && exit 1
    exit 0
}

# ─── migrate-layout 子命令 ──────────────────────────────────────────
# 调用 ops/layout-migrations/v2-to-v3.sh "$target"
cmd_migrate_layout() {
    local target
    target="$(_resolve_subcmd_target)" || true
    if [ -z "$target" ]; then
        if [ "$JSON_OUT" = "1" ]; then
            printf '{"status":"error","reason":"no_target"}\n'
        else
            fail "migrate-layout: 需要 TARGET 参数"
            info "用法: bash ops/install.sh migrate-layout <TARGET_PATH>"
        fi
        exit 2
    fi

    local migrator="$SKILL_DIR/ops/layout-migrations/v2-to-v3.sh"
    # 同时兼容：当 install.sh 是从 target 直接拷贝运行（脚本同级 ops/）
    if [ ! -f "$migrator" ]; then
        # 当前脚本在 ops/ 下 → 找平级 layout-migrations/
        local self_dir
        self_dir="$(cd "$(dirname "$0")" && pwd)"
        if [ -f "$self_dir/layout-migrations/v2-to-v3.sh" ]; then
            migrator="$self_dir/layout-migrations/v2-to-v3.sh"
        fi
    fi

    if [ ! -f "$migrator" ]; then
        if [ "$JSON_OUT" = "1" ]; then
            printf '{"status":"error","reason":"migrator_not_found","expected":%s}\n' "$(json_escape "$migrator")"
        else
            fail "migrate-layout: 未找到 layout migrator: $migrator"
            info "提示：layout-migrations/v2-to-v3.sh 由 layout-migration agent 提供"
        fi
        exit 2
    fi

    if [ "$DRY_RUN" = "1" ]; then
        if [ "$JSON_OUT" = "1" ]; then
            printf '{"status":"planned","target":%s,"migrator":%s}\n' \
                "$(json_escape "$target")" "$(json_escape "$migrator")"
        else
            info "[dry-run] 将执行: bash $migrator $target"
        fi
        exit 0
    fi

    # 直接 exec（保留 migrator 自己的 stdout/exitcode）
    local extra_args=()
    [ "$JSON_OUT" = "1" ] && extra_args+=("--json")
    [ "$ASSUME_YES" = "1" ] && extra_args+=("--yes")
    bash "$migrator" "$target" "${extra_args[@]+"${extra_args[@]}"}"
    exit $?
}

# ─── rollback-to-v2 子命令 ──────────────────────────────────────────
# 仅输出操作清单，不动用户态
cmd_rollback_to_v2() {
    local target
    target="$(_resolve_subcmd_target)" || true
    if [ -z "$target" ]; then
        if [ "$JSON_OUT" = "1" ]; then
            printf '{"status":"error","reason":"no_target"}\n'
        else
            fail "rollback-to-v2: 需要 TARGET 参数"
            info "用法: bash ops/install.sh rollback-to-v2 <TARGET_PATH>"
        fi
        exit 2
    fi

    local marker="$target/agent/config/.layout-v3.done"
    local v2_db="$target/data/xhs.db"
    local v2_runtime="$target/config/runtime.env"
    local v3_dir="$target/agent"

    # 三项探针
    local has_marker=0 has_v2_db=0 has_v2_runtime=0 has_v3=0
    [ -f "$marker" ]      && has_marker=1
    [ -f "$v2_db" ]       && has_v2_db=1
    [ -f "$v2_runtime" ]  && has_v2_runtime=1
    [ -d "$v3_dir" ]      && has_v3=1

    local rollback_ok=0
    if [ "$has_marker" = "1" ] && [ "$has_v2_db" = "1" ] && [ "$has_v2_runtime" = "1" ]; then
        rollback_ok=1
    fi

    if [ "$JSON_OUT" = "1" ]; then
        local status="not_safe"
        [ "$rollback_ok" = "1" ] && status="safe"
        local instr=""
        if [ "$rollback_ok" = "1" ]; then
            instr="$(json_escape "ls -la $target/data $target/config")"
            instr="$instr,$(json_escape "rm -rf $target/agent")"
            instr="$instr,$(json_escape "use $target/{data,config}/ directly as in v2")"
        else
            instr="$(json_escape "Pre-conditions not met; rollback unsafe.")"
        fi
        printf '{"status":%s,"target":%s,"checks":{"layout_v3_marker":%s,"v2_db_present":%s,"v2_runtime_present":%s,"v3_agent_dir":%s},"instructions":[%s]}\n' \
            "$(json_escape "$status")" \
            "$(json_escape "$target")" \
            "$( [ $has_marker = 1 ]      && echo true || echo false )" \
            "$( [ $has_v2_db = 1 ]       && echo true || echo false )" \
            "$( [ $has_v2_runtime = 1 ]  && echo true || echo false )" \
            "$( [ $has_v3 = 1 ]          && echo true || echo false )" \
            "$instr"
        [ "$rollback_ok" = "1" ] && exit 0 || exit 1
    fi

    printf "${BOLD}=== rollback-to-v2 (read-only) ===${RESET}\n"
    printf "Target: %s\n\n" "$target"
    printf "Probes:\n"
    printf "  layout-v3 marker      : %s  (%s)\n" "$([ $has_marker = 1 ] && echo yes || echo no )" "$marker"
    printf "  v2 data/xhs.db        : %s  (%s)\n" "$([ $has_v2_db = 1 ] && echo yes || echo no )" "$v2_db"
    printf "  v2 config/runtime.env : %s  (%s)\n" "$([ $has_v2_runtime = 1 ] && echo yes || echo no )" "$v2_runtime"
    printf "  v3 agent/ dir         : %s  (%s)\n" "$([ $has_v3 = 1 ] && echo yes || echo no )" "$v3_dir"
    printf "\n"

    if [ "$rollback_ok" = "1" ]; then
        info "v2 paths preserved; safe to rollback by removing $target/agent/ and using $target/{data,config}/ directly"
        printf "\nSuggested manual steps (this command does NOT execute them):\n"
        printf "  1. ls -la %s/data %s/config           # verify v2 user state present\n" "$target" "$target"
        printf "  2. rm -rf %s/agent                    # drop v3 layout\n" "$target"
        printf "  3. (optional) rm -f %s\n" "$marker"
        printf "  4. relaunch your AI assistant; it will read from v2 paths.\n"
        exit 0
    else
        warn "Rollback pre-conditions NOT all met. The v3 layout may have removed v2 paths."
        info "If you really need to roll back, restore from the upgrade-all backup directory (.bak-vX.Y.Z-<ts>) instead."
        exit 1
    fi
}

# ─── v3.0 子命令分发 ────────────────────────────────────────────────
if [ "$DOCTOR" = "1" ]; then
    cmd_doctor
fi
if [ "$MIGRATE_LAYOUT" = "1" ]; then
    cmd_migrate_layout
fi
if [ "$ROLLBACK_TO_V2" = "1" ]; then
    cmd_rollback_to_v2
fi

# 如果是 upgrade-all 模式，立刻执行并退出（不跑下面的 install 流程）
if [ "$UPGRADE_ALL" = "1" ]; then
    run_upgrade_all
fi

# ─── 模式提示 ───────────────────────────────────────────────────────
MODE_BANNER=""
[ "$ASSUME_YES" = "1" ]    && MODE_BANNER="$MODE_BANNER [non-interactive]"
[ "$DRY_RUN" = "1" ]       && MODE_BANNER="$MODE_BANNER [dry-run]"
[ "$CHECK_ONLY" = "1" ]    && MODE_BANNER="$MODE_BANNER [check-only]"
[ -n "$MODE_BANNER" ]      && printf "${BOLD}模式:${RESET}${YELLOW}%s${RESET}\n" "$MODE_BANNER"

# ─── 1. 检查依赖 ────────────────────────────────────────────────────
printf "\n${BOLD}=== 检查依赖 ===${RESET}\n\n"

MISSING=0

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

if command -v jq >/dev/null 2>&1; then
    info "jq $(jq --version | sed 's/^jq-//')"
else
    fail "jq 未安装（脚本 JSON 解析需要）"
    if [ "$(uname -s)" = "Darwin" ]; then
        info "安装: brew install jq"
    else
        info "安装: apt install jq  或  yum install jq"
    fi
    MISSING=1
fi

if command -v rsync >/dev/null 2>&1; then
    info "rsync $(rsync --version 2>/dev/null | head -1 | awk '{print $3}')"
else
    fail "rsync 未安装（install / upgrade-all 同步源码需要）"
    if [ "$(uname -s)" = "Darwin" ]; then
        info "安装: brew install rsync"
    else
        info "安装: apt install rsync  或  yum install rsync"
    fi
    MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
    fail "关键依赖缺失，无法继续安装"
    info "装完缺失项后重跑 bash ops/install.sh"
    exit 1
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
    printf "\n运行 ${BOLD}bash ops/install.sh${RESET} 或 ${BOLD}bash ops/install.sh --dry-run${RESET} 执行部署。\n"
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

# v3-compat: 源仓库 db.sh 路径 + DB 路径走 resolver
SRC_SCRIPTS_DIR="$(resolve_scripts_dir "$SKILL_DIR")"
SRC_DB_PATH="$(resolve_db_path "$SKILL_DIR")"
if [ -x "$SRC_SCRIPTS_DIR/db.sh" ]; then
    run "db.sh init" env SHULING_DB="$SRC_DB_PATH" bash "$SRC_SCRIPTS_DIR/db.sh" init
    info "数据库已初始化: $SRC_DB_PATH"
else
    warn "$SRC_SCRIPTS_DIR/db.sh 不存在或不可执行，跳过数据库初始化"
fi

# ─── 5. 确保 knowledge-base 目录存在 ────────────────────────────────
run "建 knowledge-base/" mkdir -p "$SKILL_DIR/knowledge-base"
info "knowledge-base/ 目录就绪"

# ─── 6. 可选：收集 Gemini API Key（实际写入在 §7.5 的 config/runtime.env）──
printf "\n${BOLD}=== 可选配置 ===${RESET}\n\n"

# 优先读 env var（非交互模式下唯一通道）。变量名兼容历史：GEMINI_API_KEY (v2.3-)
# 和运行时实际读取的 IMAGE_GEN_API_KEY (v2.3+)，任一提供即可。
gemini_key="${IMAGE_GEN_API_KEY:-${GEMINI_API_KEY:-}}"
if [ -z "$gemini_key" ] && [ "$ASSUME_YES" = "0" ]; then
    printf "配置 Gemini API Key？（用于 AI 图片生成，留空跳过）\n"
    printf "  获取地址: https://aistudio.google.com/api-keys\n"
    prompt "  API Key: " gemini_key ""
fi
if [ -n "$gemini_key" ]; then
    info "已收集 Gemini Key，稍后写入各 target 的 config/runtime.env"
else
    fail "未配置 Gemini Key —— 薯灵强制使用 Gemini 生图，没有 Key 将无法发帖"
    info "获取 Key: https://aistudio.google.com/app/apikey"
    info "之后可重跑 install 或运行: python3 scripts/image.py --set-key <KEY>"
fi

# ─── 7. 可选：收集 MCP URL（实际写入在 §7.5）─────────────────────────
mcp_url="${XHS_MCP_URL:-${MCP_URL:-}}"
if [ -z "$mcp_url" ] && [ "$ASSUME_YES" = "0" ]; then
    printf "\n配置 MCP URL？（留空使用模板默认 http://localhost:18060/mcp）\n"
    prompt "  MCP URL: " mcp_url ""
fi
if [ -n "$mcp_url" ]; then
    info "已收集 MCP URL：$mcp_url"
else
    info "将使用 runtime.env.example 模板里的默认 MCP 地址"
fi


# ─── 7.5 为每个 target 落 config/runtime.env（含 IMAGE_GEN_API_KEY / MCP_URL）──
# 这是运行时实际读取的配置位置（详见 scripts/image.py 和 scripts/preflight.py）。
# install 只写"空字段"：如果 target 的 runtime.env 已经有值，不覆盖用户已配。
# Telegram / IM 通讯凭证不在 skill 配置范围内 —— 由 hermes-agent 自己管理。
RUNTIME_ENV_TEMPLATE="$SKILL_DIR/config/runtime.env.example"

_runtime_env_set() {
    # 幂等写入 KEY=VALUE：如果 key 存在但值为空则替换，有值则保留
    local file="$1" key="$2" value="$3"
    [ -z "$value" ] && return 0
    [ -f "$file" ] || return 0
    python3 - "$file" "$key" "$value" <<'PY'
import sys, re, pathlib
# v2.4.2: force override. 调用者仅在用户显式提供值（env var 或 prompt 非空）时才调这里,
# 所以进入此函数 = 强意图; 无条件覆盖模板默认值.
# 旧版(v2.4.1)"非空保留"策略会被 runtime.env.example 的模板默认值(如 MCP_URL=http://localhost:18060/mcp)顶掉用户传入的 XHS_MCP_URL, 已通过社区 verify 复盘移除.
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
lines = p.read_text().splitlines()
pat = re.compile(rf"^\s*{re.escape(key)}\s*=\s*.*$")
new = []
seen = False
for ln in lines:
    if pat.match(ln) and not seen:
        seen = True
        new.append(f"{key}={value}")
    else:
        new.append(ln)
if not seen:
    new.append(f"{key}={value}")
p.write_text("\n".join(new) + "\n")
PY
}

if [ -f "$RUNTIME_ENV_TEMPLATE" ]; then
    for entry in "${PLATFORMS[@]}"; do
        target="${entry#*:}"
        # v3.0: runtime.env / db / scripts 路径全走 resolver
        runtime_env="$(resolve_runtime_env "$target")"
        cfg_dir="$(dirname "$runtime_env")"
        target_db="$(resolve_db_path "$target")"
        target_scripts="$(resolve_scripts_dir "$target")"
        run "确保 $cfg_dir" mkdir -p "$cfg_dir"
        if [ ! -f "$runtime_env" ]; then
            run "拷贝 runtime.env 模板" cp "$RUNTIME_ENV_TEMPLATE" "$runtime_env"
            info "$target: 已创建 $runtime_env（来自模板）"
        else
            info "$target: $runtime_env 已存在，保留"
        fi
        if [ -n "$gemini_key" ]; then
            _runtime_env_set "$runtime_env" "IMAGE_GEN_API_KEY" "$gemini_key"
            info "$target: IMAGE_GEN_API_KEY 已写入"
        fi
        if [ -n "$mcp_url" ]; then
            _runtime_env_set "$runtime_env" "MCP_URL" "$mcp_url"
            info "$target: MCP_URL 已写入"
        fi

        # v2.4.2: 在 target 自己的路径上跑 db.sh init, 让 target DB 真实初始化
        # 包含 __migrations 台账(供后续 upgrade-all 幂等判定使用)。
        # 旧版本(v2.4.1 及以前)只 init 源目录 DB, target preflight 会报 not_initialized.
        # v3.0: db.sh / DB 路径走 resolver
        if [ -x "$target_scripts/db.sh" ]; then
            run "$target: db.sh init" env SHULING_DB="$target_db" bash "$target_scripts/db.sh" init
            info "$target: $target_db 已初始化"
        fi
    done

    # 同步源目录自己的 config/runtime.env，方便在源目录跑 scripts/ 验证
    src_runtime_env="$(resolve_runtime_env "$SKILL_DIR")"
    mkdir -p "$(dirname "$src_runtime_env")" 2>/dev/null || true
    if [ ! -f "$src_runtime_env" ]; then
        cp "$RUNTIME_ENV_TEMPLATE" "$src_runtime_env" 2>/dev/null || true
    fi
    [ -n "$gemini_key" ] && _runtime_env_set "$src_runtime_env" "IMAGE_GEN_API_KEY" "$gemini_key"
    [ -n "$mcp_url" ]    && _runtime_env_set "$src_runtime_env" "MCP_URL"            "$mcp_url"
fi

# ─── 7.7 创作者模式（v2.2.0+）─────────────────────────────────────
printf "\n${BOLD}=== 创作者模式 ===${RESET}\n\n"

if [ "$CREATOR_MODE" = "ask" ]; then
    if [ "$ASSUME_YES" = "1" ]; then
        CREATOR_MODE="new"
        info "非交互模式：默认按新创作者（--mode=existing 可切换）"
    else
        printf "你是新创作者还是已有账号？\n"
        printf "  1) 新创作者（从零起步，对话三问建画像）\n"
        printf "  2) 已有账号（强烈推荐——你的历史内容就是最精准的画像）\n"
        prompt "  选择 [1/2，默认 1]: " choice "1"
        case "$choice" in
            2|existing) CREATOR_MODE="existing" ;;
            *)          CREATOR_MODE="new" ;;
        esac
    fi
fi

info "创作者模式: $CREATOR_MODE"

# 写入每个 target 的 state.json
write_creator_state() {
    local target="$1"
    # v3.0: state.json 跟 runtime.env 同目录（agent/config 优先，回退 config）
    local cfg_dir state_file
    cfg_dir="$(dirname "$(resolve_runtime_env "$target")")"
    state_file="$cfg_dir/state.json"
    run "写 state.json creator_mode" mkdir -p "$(dirname "$state_file")"
    if [ "$DRY_RUN" = "1" ]; then
        printf "${DIM}[dry]${RESET} 写 %s creator_mode=%s\n" "$state_file" "$CREATOR_MODE"
        return 0
    fi
    local existing='{}'
    [ -f "$state_file" ] && existing="$(cat "$state_file" 2>/dev/null || echo '{}')"
    # 不依赖 jq（install.sh 可能在无 jq 环境跑）；用 python3 做 JSON 合并
    python3 - "$state_file" "$CREATOR_MODE" <<'PY'
import json, sys, os
state_file, mode = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(state_file):
    try: data = json.load(open(state_file))
    except: data = {}
data["creator_mode"] = mode
if mode == "existing":
    data.setdefault("existing_import_done", False)
with open(state_file, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
    info "$target: state.json 已写 creator_mode=$CREATOR_MODE"
}

for entry in "${PLATFORMS[@]}"; do
    write_creator_state "${entry#*:}"
done

# ─── 7.6 运行环境预检（按 target 逐个跑）─────────────────────────
if [ "$SKIP_PREFLIGHT" = "0" ] && [ "$DRY_RUN" = "0" ]; then
    printf "\n${BOLD}=== 环境预检 ===${RESET}\n\n"

    for entry in "${PLATFORMS[@]}"; do
        target="${entry#*:}"
        # v3.0: preflight.py 路径走 resolver
        target_scripts="$(resolve_scripts_dir "$target")"
        if [ -f "$target_scripts/preflight.py" ]; then
            printf "${BOLD}-- %s --${RESET}\n" "$target"
            python3 "$target_scripts/preflight.py" 2>&1 >/dev/null || true
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

if [ "$CREATOR_MODE" = "existing" ]; then
cat << EOF

下一步（老博主接入路径）：
  1. 在你的 AI 助手中说"我已经在运营小红书，帮我接入"
  2. AI 会按 SKILL.md §0c 流程走 5 步：登录 → 批量导入 → 分类 → 画像反推 → 出体检报告
  3. 体检报告就绪后即进入日常流程，带历史记忆加权

或者手动跑：
  bash scripts/import-existing.sh --limit 200       # 批量导入历史（耗时约 30 分钟）
  bash scripts/audit-report.sh --extract-patterns   # 出体检报告 + patterns 候选

EOF
else
cat << EOF

下一步：
  1. 在你的 AI 助手中说"帮我发小红书"
  2. 首次使用会进入博主画像建立流程
  3. 画像建立完成后即可开始选题、创作、发布

EOF
fi

cat << EOF
常用自检命令：
  bash ops/install.sh --check             # 只看依赖+平台+版本对比
  bash ops/install.sh doctor              # 12 项体检（自动选首个 target）
  python3 scripts/preflight.py --human    # 人类可读的健康检查

详细的平台适配说明见 platform/ 目录：
  - platform/hermes.md       — Hermes 定时任务配置
  - platform/claude-code.md  — Claude Code 使用指南
  - platform/codex.md        — Codex 使用指南

EOF

# ─── 8.5 cron 模板提示（v3.0+）──────────────────────────────────────
# 不修改任何 cron 行为，只在检测到 ops/cron/ 模板存在时给用户提示。
if [ -d "$SKILL_DIR/ops/cron" ]; then
    cat << EOF
${BOLD}=== 定时任务（可选）===${RESET}

已检测到 ops/cron/ 模板。薯灵的午/晚发布 + 夜间复盘 + 周日回顾默认需要一个调度器。
请按你的平台手动选择一种方式（install.sh 不会自动写入）：

  1) Hermes:   cp ops/cron/hermes-jobs.example.json ~/.hermes/cron/jobs.json
  2) launchd:  cp ops/cron/launchd-*.plist ~/Library/LaunchAgents/  &&  launchctl load ...
  3) systemd:  cp ops/cron/systemd-*.{service,timer} ~/.config/systemd/user/  &&  systemctl --user enable --now ...

详见 ops/cron/README.md（如已提供）。

EOF
fi
