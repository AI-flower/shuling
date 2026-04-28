#!/usr/bin/env bash
# agent/scripts/account-safety.sh — v3.1+ 账号风险状态机
#
# 见 docs/adr/0003-account-execution-boundary.md §D6 / §D8
#     docs/plans/v3-account-execution-safety-hardening.md §7 / §8.5
#     docs/runbooks/account-safety.md §4-§5
#
# 契约：
#   account-safety.sh status                         # 输出当前 state JSON
#   account-safety.sh check publish|comment|import-cookie
#                                                    # 是否允许该动作（exit 0/1/30）
#   account-safety.sh record-event <tool> <hint>     # 写 last_risk_event + 评估
#   account-safety.sh enter-cooldown <reason> [<minutes>]
#   account-safety.sh exit-cooldown                  # 用户解除（recovery_window 校验）
#   account-safety.sh increment publish|comment     # daily_count + 1
#   account-safety.sh reset-daily                    # 跨日 0 点重置 count
#   account-safety.sh set-mode <mode>                # 切换运行模式
#
# 退出码：
#   0   allow / ok
#   1   policy disable（policy 拒）
#   2   usage error
#  30   cooldown / locked

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/_paths.sh" ] && . "$SCRIPT_DIR/_paths.sh"
[ -f "$SCRIPT_DIR/_common.sh" ] && . "$SCRIPT_DIR/_common.sh"

CFG_DIR="${SHULING_CONFIG_DIR:-$SCRIPT_DIR/../config}"
POLICY_FILE="$CFG_DIR/account-safety.json"
STATE_FILE="$CFG_DIR/account-safety-state.json"
POLICIES_DIR="${SHULING_POLICIES_DIR:-$SCRIPT_DIR/../policies}"
DEFAULT_POLICY="$POLICIES_DIR/account-safety.default.json"

mkdir -p "$CFG_DIR" 2>/dev/null || true

# ─── 辅助 ──────────────────────────────────────────────────────────────
_now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_now_epoch() { date +%s; }
_today_utc() { date -u +"%Y-%m-%d"; }

_iso_to_epoch() {
    local iso="$1"
    [ -z "$iso" ] || [ "$iso" = "null" ] && { echo 0; return; }
    local trimmed="${iso%Z}"
    if date -d "$iso" +%s >/dev/null 2>&1; then
        date -d "$iso" +%s
    else
        date -j -u -f "%Y-%m-%dT%H:%M:%S" "$trimmed" +%s 2>/dev/null || echo 0
    fi
}

# 读 policy（fallback 到 default）
_read_policy() {
    local key="$1"
    local file="$POLICY_FILE"
    [ ! -f "$file" ] && file="$DEFAULT_POLICY"
    [ ! -f "$file" ] && { echo ""; return 1; }
    python3 - "$file" "$key" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    v = d.get(sys.argv[2])
    if v is None:
        print("")
    elif isinstance(v, bool):
        print("true" if v else "false")
    else:
        print(v)
except Exception:
    pass
PYEOF
}

_read_state() {
    local key="$1"
    [ ! -f "$STATE_FILE" ] && { echo ""; return 1; }
    python3 - "$STATE_FILE" "$key" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    v = d.get(sys.argv[2])
    if v is None:
        print("")
    elif isinstance(v, (dict, list)):
        print(json.dumps(v, ensure_ascii=False))
    elif isinstance(v, bool):
        print("true" if v else "false")
    else:
        print(v)
except Exception:
    pass
PYEOF
}

# 初始化 state（如果不存在）
_ensure_state() {
    if [ -f "$STATE_FILE" ]; then return 0; fi
    local today
    today="$(_today_utc)"
    cat > "$STATE_FILE" <<EOF
{
  "risk_level": "normal",
  "mode": "draft-only",
  "daily_publish_count": 0,
  "daily_comment_count": 0,
  "last_publish_at": null,
  "last_comment_at": null,
  "cooldown_until": null,
  "cooldown_reason": null,
  "last_risk_event": null,
  "updated_at": "$today"
}
EOF
}

# 通用 mutator：用 python3 patch state JSON
_state_set() {
    # 调用方式：_state_set 'k1=v1' 'k2=v2' ... （v 字面量，json 类型靠 - 前缀）
    # 简化：直接传 python dict 字符串
    local pyexpr="$1"
    _ensure_state
    python3 - "$STATE_FILE" <<PYEOF
import json, sys, datetime
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
patch = $pyexpr
d.update(patch)
try:
    now_iso = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
except Exception:
    now_iso = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
d["updated_at"] = now_iso
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
}

# ─── 风险关键词识别 ────────────────────────────────────────────────────
# §7.3 关键词列表
_KEYWORDS=(429 captcha verify risk forbidden blocked "login required" "cookie invalid" "rate limit" 风控 验证 频繁 异常)

# 命中关键词返回 0 + 关键词；否则 1
_match_risk_keyword() {
    local hint_lc
    hint_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    for kw in "${_KEYWORDS[@]}"; do
        local kw_lc
        kw_lc="$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')"
        if [[ "$hint_lc" == *"$kw_lc"* ]]; then
            printf '%s' "$kw"
            return 0
        fi
    done
    return 1
}

# ─── 子命令实现 ────────────────────────────────────────────────────────

cmd_status() {
    _ensure_state
    cat "$STATE_FILE"
}

cmd_check() {
    local action="${1:-}"
    if [ -z "$action" ]; then
        emit_json ok=false error=usage message="check <publish|comment|import-cookie>"
        return 2
    fi
    _ensure_state

    local risk_level cooldown_until now_e exp_e
    risk_level="$(_read_state risk_level)"
    cooldown_until="$(_read_state cooldown_until)"

    # 自动恢复：如 cooldown_until 已过，自动转 normal
    if [ "$risk_level" = "cooldown" ] && [ -n "$cooldown_until" ] && [ "$cooldown_until" != "null" ]; then
        now_e="$(_now_epoch)"
        exp_e="$(_iso_to_epoch "$cooldown_until")"
        if [ "$now_e" -ge "$exp_e" ] && [ "$exp_e" -gt 0 ]; then
            _state_set "{'risk_level': 'normal', 'cooldown_until': None, 'cooldown_reason': None}"
            risk_level="normal"
        fi
    fi

    case "$risk_level" in
        cooldown)
            emit_json ok=false error=safety_cooldown risk_level=cooldown action="$action"
            return 30
            ;;
        locked)
            emit_json ok=false error=safety_locked risk_level=locked action="$action"
            return 30
            ;;
    esac

    # 读 policy 项
    local policy_key=""
    case "$action" in
        publish)
            policy_key="publishing_enabled"
            ;;
        comment)
            policy_key="commenting_enabled"
            ;;
        import-cookie)
            policy_key="cookie_import_enabled"
            ;;
        *)
            emit_json ok=false error=unknown_action action="$action"
            return 2
            ;;
    esac
    local enabled
    enabled="$(_read_policy "$policy_key")"
    if [ "$enabled" != "true" ]; then
        emit_json ok=false error=policy_disabled action="$action" policy_key="$policy_key"
        return 1
    fi

    # daily count check
    if [ "$action" = "publish" ]; then
        local cap cur
        cap="$(_read_policy max_daily_publishes)"
        cur="$(_read_state daily_publish_count)"
        cap="${cap:-1}"; cur="${cur:-0}"
        if [ "$cur" -ge "$cap" ]; then
            emit_json ok=false error=daily_cap_reached action=publish daily_count="$cur" cap="$cap"
            return 1
        fi
    elif [ "$action" = "comment" ]; then
        local cap cur
        cap="$(_read_policy max_daily_comments)"
        cur="$(_read_state daily_comment_count)"
        cap="${cap:-0}"; cur="${cur:-0}"
        if [ "$cur" -ge "$cap" ]; then
            emit_json ok=false error=daily_cap_reached action=comment daily_count="$cur" cap="$cap"
            return 1
        fi
    fi

    emit_json ok=true action="$action" risk_level="$risk_level"
    return 0
}

cmd_record_event() {
    local tool="${1:-}" hint="${2:-}"
    if [ -z "$tool" ]; then
        emit_json ok=false error=usage message="record-event <tool> <hint>"
        return 2
    fi
    _ensure_state

    local now matched=""
    now="$(_now_utc)"
    if matched="$(_match_risk_keyword "$hint")"; then
        # 命中风险信号：写 last_risk_event + 进入 cooldown
        local minutes=60
        # publish 失败连续 2 次 / comment 失败 1 次 / 登录连失 → 由 caller 控制
        local cooldown_until_epoch cooldown_until_iso
        cooldown_until_epoch=$(( $(_now_epoch) + minutes * 60 ))
        if date -u -r "$cooldown_until_epoch" +"%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
            cooldown_until_iso="$(date -u -r "$cooldown_until_epoch" +"%Y-%m-%dT%H:%M:%SZ")"
        else
            cooldown_until_iso="$(date -u -d "@$cooldown_until_epoch" +"%Y-%m-%dT%H:%M:%SZ")"
        fi

        # 检查 policy.cooldown_on_risk_signal
        local enabled
        enabled="$(_read_policy cooldown_on_risk_signal)"
        if [ "$enabled" = "false" ]; then
            # 不进 cooldown，仅记录事件
            _state_set "{'last_risk_event': {'event': 'risk_signal', 'tool': '$tool', 'hint': '''${hint:0:200}'''.replace(\"'\",\"\"), 'created_at': '$now'}}"
            emit_json ok=true matched="$matched" cooldown=false tool="$tool"
            return 0
        fi

        python3 - "$STATE_FILE" "$tool" "$hint" "$matched" "$now" "$cooldown_until_iso" <<'PYEOF'
import json, sys
p, tool, hint, matched, now, cu = sys.argv[1:7]
with open(p) as f:
    d = json.load(f)
d["risk_level"] = "cooldown"
d["cooldown_until"] = cu
d["cooldown_reason"] = f"risk_signal: {matched}"
d["last_risk_event"] = {
    "event": "risk_signal",
    "tool": tool,
    "hint": hint[:200],
    "created_at": now,
}
d["updated_at"] = now
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
        emit_json ok=true matched="$matched" cooldown=true cooldown_until="$cooldown_until_iso" tool="$tool"
        return 0
    fi

    # 未命中：仅记录事件，不进 cooldown
    python3 - "$STATE_FILE" "$tool" "$hint" "$now" <<'PYEOF'
import json, sys
p, tool, hint, now = sys.argv[1:5]
with open(p) as f:
    d = json.load(f)
d["last_risk_event"] = {
    "event": "tool_event",
    "tool": tool,
    "hint": hint[:200],
    "created_at": now,
}
d["updated_at"] = now
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
    emit_json ok=true matched=false tool="$tool"
    return 0
}

cmd_enter_cooldown() {
    local reason="${1:-manual}"
    local minutes="${2:-30}"
    _ensure_state
    local now cooldown_until_epoch cooldown_until_iso
    now="$(_now_utc)"
    cooldown_until_epoch=$(( $(_now_epoch) + minutes * 60 ))
    if date -u -r "$cooldown_until_epoch" +"%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
        cooldown_until_iso="$(date -u -r "$cooldown_until_epoch" +"%Y-%m-%dT%H:%M:%SZ")"
    else
        cooldown_until_iso="$(date -u -d "@$cooldown_until_epoch" +"%Y-%m-%dT%H:%M:%SZ")"
    fi
    python3 - "$STATE_FILE" "$reason" "$cooldown_until_iso" "$now" <<'PYEOF'
import json, sys
p, reason, cu, now = sys.argv[1:5]
with open(p) as f:
    d = json.load(f)
d["risk_level"] = "cooldown"
d["cooldown_until"] = cu
d["cooldown_reason"] = reason
d["updated_at"] = now
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
    emit_json ok=true risk_level=cooldown cooldown_until="$cooldown_until_iso" reason="$reason"
    return 0
}

cmd_exit_cooldown() {
    _ensure_state
    _state_set "{'risk_level': 'normal', 'cooldown_until': None, 'cooldown_reason': None}"
    emit_json ok=true risk_level=normal
    return 0
}

cmd_increment() {
    local action="${1:-}"
    if [ -z "$action" ]; then
        emit_json ok=false error=usage message="increment <publish|comment>"
        return 2
    fi
    _ensure_state
    local field=""
    local last_field=""
    case "$action" in
        publish) field=daily_publish_count; last_field=last_publish_at ;;
        comment) field=daily_comment_count; last_field=last_comment_at ;;
        *) emit_json ok=false error=unknown_action action="$action"; return 2 ;;
    esac
    local now
    now="$(_now_utc)"
    python3 - "$STATE_FILE" "$field" "$last_field" "$now" <<'PYEOF'
import json, sys, datetime
p, field, last_field, now = sys.argv[1:5]
with open(p) as f:
    d = json.load(f)
# 跨日重置
today = now[:10]
prev = (d.get("updated_at") or "")[:10]
if prev and prev != today:
    d["daily_publish_count"] = 0
    d["daily_comment_count"] = 0
d[field] = int(d.get(field, 0)) + 1
d[last_field] = now
d["updated_at"] = now
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(json.dumps({"ok": True, "field": field, "value": d[field]}))
PYEOF
    return 0
}

cmd_reset_daily() {
    _ensure_state
    _state_set "{'daily_publish_count': 0, 'daily_comment_count': 0}"
    emit_json ok=true reset=true
    return 0
}

cmd_set_mode() {
    local mode="${1:-}"
    case "$mode" in
        draft-only|supervised|read-only-research|ops-maintenance) ;;
        *) emit_json ok=false error=invalid_mode mode="$mode"; return 2 ;;
    esac
    _ensure_state
    _state_set "{'mode': '$mode'}"
    emit_json ok=true mode="$mode"
    return 0
}

usage() {
    cat <<EOF
Usage: account-safety.sh <subcommand> [args]

Subcommands:
  status                            输出当前 state JSON
  check <publish|comment|import-cookie>
                                    是否允许该动作（exit 0/1/30）
  record-event <tool> <hint>        写 last_risk_event + 命中风险关键词时进 cooldown
  enter-cooldown <reason> [<minutes>]
                                    手动进 cooldown（默认 30 min）
  exit-cooldown                     用户解除
  increment <publish|comment>       daily_count + 1
  reset-daily                       跨日重置
  set-mode <draft-only|supervised|read-only-research|ops-maintenance>

Files:
  policy: $POLICY_FILE
  state : $STATE_FILE
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    status)         cmd_status "$@" ;;
    check)          cmd_check "$@" ;;
    record-event)   cmd_record_event "$@" ;;
    enter-cooldown) cmd_enter_cooldown "$@" ;;
    exit-cooldown)  cmd_exit_cooldown "$@" ;;
    resume)         cmd_exit_cooldown "$@" ;;  # 别名
    increment)      cmd_increment "$@" ;;
    reset-daily)    cmd_reset_daily "$@" ;;
    set-mode)       cmd_set_mode "$@" ;;
    -h|--help|"")   usage; exit 0 ;;
    *)
        emit_json ok=false error=unknown_cmd message="unknown subcommand: $cmd"
        usage >&2
        exit 2
        ;;
esac
