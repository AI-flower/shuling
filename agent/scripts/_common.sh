#!/usr/bin/env bash
# agent/scripts/_common.sh — v3.0+ 通用辅助函数
#
# 所有 agent/scripts/*.sh 在 source _paths.sh 之后再 source 本文件。
# 提供：
#   - 退出码常量（0/1/2 三级，对齐 preflight.py）
#   - 日志辅助（log_info / log_warn / log_error，写到 stderr）
#   - JSON 单行输出（emit_json）
#   - 用户态保护守卫（assert_user_data_safe）
#
# 退出码语义（与 ADR-0001 §第 12 条降级路径强制对齐）：
#   0  成功
#   1  auto-fixable（脚本可自行修复，调用方决定是否触发）
#   2  need-user（需要人介入，绝不自动修复）
#  10  磁盘 / 文件系统错误
#  11  权限错误
#  12  marker / 状态文件损坏
#  20  schema 校验失败
#  30  外部依赖（MCP / Gemini）不可达

readonly EXIT_OK=0
readonly EXIT_AUTOFIX=1
readonly EXIT_NEEDUSER=2
readonly EXIT_FS=10
readonly EXIT_PERM=11
readonly EXIT_MARKER=12
readonly EXIT_SCHEMA=20
readonly EXIT_DEPS=30

# ─── 日志（写 stderr，不污染 JSON stdout）──────────────────────────
_shuling_log() {
    local level="$1"; shift
    printf '[%s][%s] %s\n' "$(date +%H:%M:%S)" "$level" "$*" >&2
}

log_info()  { _shuling_log "INFO"  "$@"; }
log_warn()  { _shuling_log "WARN"  "$@"; }
log_error() { _shuling_log "ERROR" "$@"; }

# ─── JSON 输出（agent 可解析的单行）─────────────────────────────────
# 用法：emit_json status=ok message="initialized" count=11
emit_json() {
    local pairs=()
    for kv in "$@"; do
        local k="${kv%%=*}"
        local v="${kv#*=}"
        # 字符串值加引号；纯数字/布尔不加
        if [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || [[ "$v" == "true" ]] || [[ "$v" == "false" ]] || [[ "$v" == "null" ]]; then
            pairs+=("\"$k\":$v")
        else
            # 转义内部双引号
            v="${v//\"/\\\"}"
            pairs+=("\"$k\":\"$v\"")
        fi
    done
    local IFS=,
    printf '{%s}\n' "${pairs[*]}"
}

# ─── 用户态保护守卫 ─────────────────────────────────────────────────
# 任何 destructive 操作前先调一次。如果发现真实用户态文件存在但
# 当前脚本没有 SHULING_FORCE_UNSAFE=1 显式授权，立即退出。
assert_user_data_safe() {
    local target="$1"
    if [ -e "$target" ] && [ "${SHULING_FORCE_UNSAFE:-0}" != "1" ]; then
        log_error "user data exists at $target — refuse to overwrite (set SHULING_FORCE_UNSAFE=1 to bypass)"
        exit "$EXIT_PERM"
    fi
}

# ─── schema-degraded mode 检测 ──────────────────────────────────────
# 当 ensure-schema 失败留下锁文件时，db.sh 进入 read-only 模式。
is_schema_degraded() {
    [ -f "${SHULING_SCHEMA_DEGRADED_LOCK:-/dev/null}" ]
}

# ─── 平台检测（macOS / Linux）─────────────────────────────────────
detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

# ─── 依赖检测 ───────────────────────────────────────────────────────
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "required command not found: $cmd"
        exit "$EXIT_DEPS"
    fi
}
