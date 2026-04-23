#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

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

usage() {
    sed -n '/^# ─── 参数解析/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# 先截获子命令（位置参数），不影响原有 option 解析
if [ $# -gt 0 ] && [ "$1" = "upgrade-all" ]; then
    UPGRADE_ALL=1
    shift
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
        step_record "rsync_code" "ok" "files_changed" "$files_changed"
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
    local migrations_dir="$SKILL_DIR/migrations"
    if [ ! -d "$migrations_dir" ]; then
        step_record "migrations" "skipped" "reason" "no_migrations_dir"
        return 0
    fi
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
        local out rc
        out="$(SKILL_DIR="$path" bash "$m" 2>&1)" && rc=0 || rc=$?
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
    local pf="$path/scripts/preflight.py"
    if [ ! -f "$pf" ]; then
        step_record "preflight" "skipped" "reason" "no_preflight_script"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        step_record "preflight" "planned" "script" "$pf"
        return 0
    fi
    if (cd "$path" && python3 scripts/preflight.py >/dev/null 2>&1); then
        step_record "preflight" "ok"
    else
        step_record "preflight" "failed" "reason" "preflight_nonzero"
    fi
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
        fail "未配置 Gemini Key —— 薯灵强制使用 Gemini 生图，没有 Key 将无法发帖"
        info "获取 Key: https://aistudio.google.com/app/apikey"
        info "之后可重跑 install 或运行: python3 scripts/image.py --set-key <KEY>"
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
    local target="$1" state_file="$target/config/state.json"
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
  bash install.sh --check                 # 只看依赖+平台+版本对比
  python3 scripts/preflight.py --human    # 人类可读的健康检查

详细的平台适配说明见 platform/ 目录：
  - platform/hermes.md       — Hermes 定时任务配置
  - platform/claude-code.md  — Claude Code 使用指南
  - platform/codex.md        — Codex 使用指南

EOF
