#!/usr/bin/env bash
# agent/scripts/approval.sh — v3.1+ 一次性账号写操作授权令牌
#
# 见 docs/adr/0003-account-execution-boundary.md §D1 / §D3
#     docs/plans/v3-account-execution-safety-hardening.md §6
#     docs/runbooks/account-safety.md §3
#
# 契约：
#   approval.sh request <action> <resource>          # 创建 pending request
#   approval.sh grant <request_id>                   # 用户授权 → status=granted
#   approval.sh verify <action> <resource> --approval-id <id>
#                                                    # 6 道闸校验，pass=0
#   approval.sh consume <approval_id>                # 一次性消费
#   approval.sh revoke <approval_id>                 # 撤销
#   approval.sh list [--status pending|granted|consumed|revoked|expired]
#   approval.sh cleanup-expired                       # 把所有过期未消费的标 expired
#
# 退出码：
#   0   ok
#   1   invalid grant / approval_required / approval_invalid / approval_expired /
#       approval_consumed / resource_changed / action_mismatch
#   2   missing approval / usage error
#   20  schema 错误（输出 JSON 不符合 approval.schema.json）
#   30  cooldown / locked（safety state 拒绝）
#
# 输出：单行 JSON，{"ok": true/false, "approval_id": "...", "error": "...", ...}

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/_paths.sh" ] && . "$SCRIPT_DIR/_paths.sh"
[ -f "$SCRIPT_DIR/_common.sh" ] && . "$SCRIPT_DIR/_common.sh"

APPROVAL_DIR="${SHULING_CONFIG_DIR:-$SCRIPT_DIR/../config}/approvals"
SAFETY_STATE="${SHULING_CONFIG_DIR:-$SCRIPT_DIR/../config}/account-safety-state.json"

DEFAULT_TTL_SECONDS="${SHULING_APPROVAL_TTL_SECONDS:-1800}"  # 30 分钟

mkdir -p "$APPROVAL_DIR" 2>/dev/null || true

# ─── jq / python3 兼容辅助 ─────────────────────────────────────────────
_has_jq() { command -v jq >/dev/null 2>&1; }

# 从 JSON 文件取一个顶层字段
_json_get() {
    local file="$1" key="$2"
    if [ ! -f "$file" ]; then
        return 1
    fi
    if _has_jq; then
        jq -r --arg k "$key" '.[$k] // empty' "$file"
    else
        python3 - "$file" "$key" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    v = d.get(sys.argv[2])
    if v is None:
        print("")
    else:
        print(v)
except Exception:
    sys.exit(1)
PYEOF
    fi
}

# 算 sha256：参数若是文件路径则取文件 sha；否则视为字面 resource string 取串 sha
_resource_hash() {
    local resource="$1"
    local hash=""
    if [ -f "$resource" ]; then
        if command -v shasum >/dev/null 2>&1; then
            hash="$(shasum -a 256 "$resource" 2>/dev/null | awk '{print $1}')"
        elif command -v sha256sum >/dev/null 2>&1; then
            hash="$(sha256sum "$resource" 2>/dev/null | awk '{print $1}')"
        fi
    else
        if command -v shasum >/dev/null 2>&1; then
            hash="$(printf '%s' "$resource" | shasum -a 256 | awk '{print $1}')"
        elif command -v sha256sum >/dev/null 2>&1; then
            hash="$(printf '%s' "$resource" | sha256sum | awk '{print $1}')"
        fi
    fi
    [ -z "$hash" ] && return 1
    printf 'sha256:%s\n' "$hash"
}

_now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

_now_epoch() { date +%s; }

# ISO8601 → epoch（macOS / Linux 兼容）
_iso_to_epoch() {
    local iso="$1"
    # 去掉 Z 用于 BSD date
    local trimmed="${iso%Z}"
    if date -d "$iso" +%s >/dev/null 2>&1; then
        date -d "$iso" +%s
    else
        # BSD date (macOS)
        date -j -u -f "%Y-%m-%dT%H:%M:%S" "$trimmed" +%s 2>/dev/null
    fi
}

# 写一行 JSON 到 stderr/stdout（emit_json 来自 _common.sh）
_emit_err() {
    # $1 error code, $2 message, optional $3 approval_id
    local err="$1" msg="$2" aid="${3:-}"
    if [ -n "$aid" ]; then
        emit_json ok=false error="$err" message="$msg" approval_id="$aid"
    else
        emit_json ok=false error="$err" message="$msg"
    fi
}

# ─── 子命令实现 ────────────────────────────────────────────────────────

cmd_request() {
    local action="${1:-}"
    local resource="${2:-}"
    if [ -z "$action" ] || [ -z "$resource" ]; then
        _emit_err usage "approval.sh request <action> <resource>"
        return 2
    fi
    case "$action" in
        publish|comment|import-cookie|override-quota) ;;
        *)
            _emit_err invalid_action "action 必须是 publish|comment|import-cookie|override-quota"
            return 2
            ;;
    esac

    local hash
    if ! hash="$(_resource_hash "$resource")"; then
        _emit_err hash_failed "无法计算 resource sha256（缺 shasum/sha256sum）"
        return 2
    fi

    local rand
    if command -v openssl >/dev/null 2>&1; then
        rand="$(openssl rand -hex 4 2>/dev/null)"
    fi
    if [ -z "${rand:-}" ]; then
        rand="$(head -c 4 /dev/urandom | xxd -p 2>/dev/null | tr -d '\n')"
    fi
    if [ -z "${rand:-}" ]; then
        # 终极降级：用 RANDOM
        rand="$(printf '%08x' $((RANDOM * RANDOM % 0xffffffff)))"
    fi

    local ts ts_id
    ts_id="$(date +%Y%m%d_%H%M%S)"
    local id="appr_${ts_id}_${rand}"
    local created_at expires_at expires_epoch
    created_at="$(_now_utc)"
    expires_epoch=$(( $(_now_epoch) + DEFAULT_TTL_SECONDS ))
    if date -u -r "$expires_epoch" +"%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
        expires_at="$(date -u -r "$expires_epoch" +"%Y-%m-%dT%H:%M:%SZ")"
    else
        expires_at="$(date -u -d "@$expires_epoch" +"%Y-%m-%dT%H:%M:%SZ")"
    fi

    local file="$APPROVAL_DIR/$id.json"
    # 用 python3 生成结构化 JSON（避免手拼引号失误）
    python3 - "$file" "$id" "$action" "$resource" "$hash" "$created_at" "$expires_at" <<'PYEOF'
import json, sys
file_, _id, action, resource, rhash, created, expires = sys.argv[1:8]
data = {
    "id": _id,
    "action": action,
    "resource": resource,
    "resource_hash": rhash,
    "created_at": created,
    "expires_at": expires,
    "granted_by": "user",
    "consumed_at": None,
    "status": "pending",
}
with open(file_, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PYEOF

    emit_json ok=true status=pending approval_id="$id" action="$action" expires_at="$expires_at"
    return 0
}

cmd_grant() {
    local id="${1:-}"
    if [ -z "$id" ]; then
        _emit_err usage "approval.sh grant <request_id>"
        return 2
    fi
    local file="$APPROVAL_DIR/$id.json"
    if [ ! -f "$file" ]; then
        _emit_err not_found "approval $id 不存在" "$id"
        return 2
    fi

    # 读 status
    local status
    status="$(_json_get "$file" status)"
    if [ "$status" = "granted" ]; then
        emit_json ok=true status=granted approval_id="$id" message="already granted"
        return 0
    fi
    if [ "$status" = "consumed" ] || [ "$status" = "revoked" ] || [ "$status" = "expired" ]; then
        _emit_err invalid_grant "approval 当前状态 $status，不能 grant" "$id"
        return 1
    fi

    # 改 status -> granted
    python3 - "$file" <<'PYEOF'
import json, sys, datetime
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
d["status"] = "granted"
d["granted_by"] = d.get("granted_by") or "user"
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF

    emit_json ok=true status=granted approval_id="$id" granted_at="$(_now_utc)"
    return 0
}

cmd_verify() {
    local action="" resource="" approval_id=""
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --approval-id) shift; approval_id="${1:-}"; shift ;;
            *) args+=("$1"); shift ;;
        esac
    done
    action="${args[0]:-}"
    resource="${args[1]:-}"
    if [ -z "$action" ] || [ -z "$resource" ] || [ -z "$approval_id" ]; then
        _emit_err usage "approval.sh verify <action> <resource> --approval-id <id>"
        return 2
    fi

    local file="$APPROVAL_DIR/$approval_id.json"
    # 1. 文件存在
    if [ ! -f "$file" ]; then
        _emit_err approval_missing "approval $approval_id 不存在" "$approval_id"
        return 2
    fi

    local f_status f_action f_resource f_hash f_expires f_consumed
    f_status="$(_json_get "$file" status)"
    f_action="$(_json_get "$file" action)"
    f_resource="$(_json_get "$file" resource)"
    f_hash="$(_json_get "$file" resource_hash)"
    f_expires="$(_json_get "$file" expires_at)"
    f_consumed="$(_json_get "$file" consumed_at)"

    # 2. status == granted
    if [ "$f_status" != "granted" ]; then
        case "$f_status" in
            consumed)
                _emit_err approval_consumed "approval 已被消费过" "$approval_id"
                return 1
                ;;
            revoked)
                _emit_err approval_revoked "approval 已被撤销" "$approval_id"
                return 1
                ;;
            expired)
                _emit_err approval_expired "approval 已过期" "$approval_id"
                return 1
                ;;
            pending)
                _emit_err approval_pending "approval 未 grant" "$approval_id"
                return 1
                ;;
            *)
                _emit_err approval_invalid "approval status=$f_status" "$approval_id"
                return 1
                ;;
        esac
    fi

    # 3. action 匹配
    if [ "$f_action" != "$action" ]; then
        _emit_err action_mismatch "approval action=$f_action 与请求的 $action 不一致" "$approval_id"
        return 1
    fi

    # 4. resource_hash 匹配（重新算 resource sha256）
    local cur_hash
    if ! cur_hash="$(_resource_hash "$resource")"; then
        _emit_err hash_failed "无法重新计算 resource sha256" "$approval_id"
        return 2
    fi
    if [ "$f_hash" != "$cur_hash" ]; then
        _emit_err resource_changed "resource hash 不匹配（资源被修改）" "$approval_id"
        return 1
    fi

    # 5. 未过期
    local now_e exp_e
    now_e="$(_now_epoch)"
    exp_e="$(_iso_to_epoch "$f_expires" 2>/dev/null || echo 0)"
    if [ -z "$exp_e" ] || [ "$exp_e" = "0" ] || [ "$now_e" -ge "$exp_e" ]; then
        # 顺手把 status 改为 expired
        python3 - "$file" <<'PYEOF' 2>/dev/null || true
import json, sys
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
if d.get("status") == "granted":
    d["status"] = "expired"
    with open(p, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
        _emit_err approval_expired "approval 已过期（expires_at=$f_expires）" "$approval_id"
        return 1
    fi

    # 6. 未消费
    if [ -n "$f_consumed" ] && [ "$f_consumed" != "null" ]; then
        _emit_err approval_consumed "approval 已被消费过（consumed_at=$f_consumed）" "$approval_id"
        return 1
    fi

    # 7. safety state 不在 cooldown / locked
    if [ -f "$SAFETY_STATE" ]; then
        local risk_level
        risk_level="$(_json_get "$SAFETY_STATE" risk_level 2>/dev/null || echo normal)"
        case "$risk_level" in
            cooldown)
                _emit_err safety_cooldown "account-safety risk_level=cooldown，拒绝放行" "$approval_id"
                return 30
                ;;
            locked)
                _emit_err safety_locked "account-safety risk_level=locked，拒绝放行" "$approval_id"
                return 30
                ;;
        esac
    fi

    emit_json ok=true approval_id="$approval_id" action="$action" resource_hash="$cur_hash"
    return 0
}

cmd_consume() {
    local id="${1:-}"
    if [ -z "$id" ]; then
        _emit_err usage "approval.sh consume <approval_id>"
        return 2
    fi
    local file="$APPROVAL_DIR/$id.json"
    if [ ! -f "$file" ]; then
        _emit_err not_found "approval $id 不存在" "$id"
        return 2
    fi
    local now
    now="$(_now_utc)"
    python3 - "$file" "$now" <<'PYEOF'
import json, sys
p, now = sys.argv[1], sys.argv[2]
with open(p) as f:
    d = json.load(f)
if d.get("status") == "consumed":
    print(json.dumps({"ok": True, "approval_id": d["id"], "status": "consumed", "message": "already consumed"}))
    sys.exit(0)
d["status"] = "consumed"
d["consumed_at"] = now
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(json.dumps({"ok": True, "approval_id": d["id"], "status": "consumed", "consumed_at": now}))
PYEOF
    return 0
}

cmd_revoke() {
    local id="${1:-}"
    if [ -z "$id" ]; then
        _emit_err usage "approval.sh revoke <approval_id>"
        return 2
    fi
    local file="$APPROVAL_DIR/$id.json"
    if [ ! -f "$file" ]; then
        _emit_err not_found "approval $id 不存在" "$id"
        return 2
    fi
    python3 - "$file" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
d["status"] = "revoked"
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(json.dumps({"ok": True, "approval_id": d["id"], "status": "revoked"}))
PYEOF
    return 0
}

cmd_list() {
    local filter_status=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --status) shift; filter_status="${1:-}"; shift ;;
            *) shift ;;
        esac
    done
    python3 - "$APPROVAL_DIR" "${filter_status}" <<'PYEOF'
import json, os, sys, glob
d, fs = sys.argv[1], sys.argv[2]
out = []
for p in sorted(glob.glob(os.path.join(d, "appr_*.json"))):
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception:
        continue
    if fs and data.get("status") != fs:
        continue
    out.append({
        "id": data.get("id"),
        "action": data.get("action"),
        "status": data.get("status"),
        "created_at": data.get("created_at"),
        "expires_at": data.get("expires_at"),
        "consumed_at": data.get("consumed_at"),
    })
print(json.dumps({"ok": True, "count": len(out), "approvals": out}, ensure_ascii=False))
PYEOF
    return 0
}

cmd_cleanup_expired() {
    local now
    now="$(_now_utc)"
    python3 - "$APPROVAL_DIR" "$now" <<'PYEOF'
import json, os, sys, glob, datetime
d, now_s = sys.argv[1], sys.argv[2]
now_dt = datetime.datetime.strptime(now_s, "%Y-%m-%dT%H:%M:%SZ")
expired = 0
for p in glob.glob(os.path.join(d, "appr_*.json")):
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception:
        continue
    if data.get("status") not in ("pending", "granted"):
        continue
    try:
        exp_dt = datetime.datetime.strptime(data.get("expires_at",""), "%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        continue
    if now_dt >= exp_dt:
        data["status"] = "expired"
        with open(p, "w") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        expired += 1
print(json.dumps({"ok": True, "expired_count": expired}))
PYEOF
    return 0
}

# ─── 路由 ──────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: approval.sh <subcommand> [args]

Subcommands:
  request <action> <resource>          创建 pending request
                                       action: publish|comment|import-cookie|override-quota
  grant   <request_id>                 用户授权 (status -> granted)
  verify  <action> <resource> --approval-id <id>
                                       6 道闸校验，pass=0
  consume <approval_id>                一次性消费 (status -> consumed)
  revoke  <approval_id>                撤销 (status -> revoked)
  list    [--status pending|granted|consumed|revoked|expired]
  cleanup-expired                      把所有过期未消费的标 expired

Approval files: $APPROVAL_DIR/<id>.json
TTL: ${DEFAULT_TTL_SECONDS}s (set SHULING_APPROVAL_TTL_SECONDS to override)
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    request) cmd_request "$@" ;;
    grant)   cmd_grant "$@" ;;
    verify)  cmd_verify "$@" ;;
    consume) cmd_consume "$@" ;;
    revoke)  cmd_revoke "$@" ;;
    list)    cmd_list "$@" ;;
    cleanup-expired) cmd_cleanup_expired "$@" ;;
    -h|--help|"") usage; exit 0 ;;
    *)
        _emit_err unknown_cmd "未知子命令: $cmd"
        usage >&2
        exit 2
        ;;
esac
