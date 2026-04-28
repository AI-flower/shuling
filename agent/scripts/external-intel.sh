#!/usr/bin/env bash
# agent/scripts/external-intel.sh — v3.1+ External Intelligence 入口
#
# 见 docs/plans/v3-account-execution-safety-hardening.md §12
#     docs/runbooks/external-intelligence.md
#     agent/policies/external-intelligence.default.json
#     agent/schemas/external-signal.schema.json
#
# 契约（§12.5）：
#   external-intel.sh research-topic "<主题>" [--budget conservative|balanced|aggressive]
#   external-intel.sh competition-gap "<主题>"
#   external-intel.sh comment-demand <note_id> [--limit 30]
#   external-intel.sh cache-get "<主题>"
#   external-intel.sh cache-prune
#   external-intel.sh budget-status
#
# 设计纪律（§12.6 / §12.8 / §12.10）：
#   - 必须走 xhs.sh（继承节流/限额/风险关键词识别），绝不裸调 MCP
#   - 不存原文：写盘前用 external-signal.schema.json 自校验
#   - cooldown / locked 状态完全停止采样（exit 30）
#   - 预算耗尽 / MCP 失败 → 输出 degraded JSON，exit 0（让 caller 降级到内部记忆）
#
# 退出码：
#   0   ok / cache hit / degraded（已落部分信号）
#   1   usage / 缺参
#   2   policy 解析失败
#   20  schema 校验失败（写盘前发现非法字段）
#   30  cooldown / locked，完全停止
#   31  风险信号触发，本次采样中止（已写 risk event）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/_paths.sh" ] && . "$SCRIPT_DIR/_paths.sh"
[ -f "$SCRIPT_DIR/_common.sh" ] && . "$SCRIPT_DIR/_common.sh"

# ─── 路径 ──────────────────────────────────────────────────────────────
POLICIES_DIR="${SHULING_POLICIES_DIR:-$SCRIPT_DIR/../policies}"
CONFIG_DIR="${SHULING_CONFIG_DIR:-$SCRIPT_DIR/../config}"
KB_DIR="${SHULING_KB_DIR:-$SCRIPT_DIR/../knowledge-base}"
DATA_DIR="${SHULING_DATA_DIR:-$SCRIPT_DIR/../data}"
SCHEMAS_DIR="${SHULING_SCHEMAS_DIR:-$SCRIPT_DIR/../schemas}"

DEFAULT_POLICY="$POLICIES_DIR/external-intelligence.default.json"
USER_POLICY="$CONFIG_DIR/external-intelligence.json"

SIGNALS_DIR="$KB_DIR/external-signals"
COUNTERS_FILE="$DATA_DIR/external-intel-counters.json"
SIGNAL_SCHEMA="$SCHEMAS_DIR/external-signal.schema.json"

mkdir -p "$SIGNALS_DIR" "$DATA_DIR" 2>/dev/null || true

# ─── session id ────────────────────────────────────────────────────────
SESSION_ID="${SHULING_SESSION_ID:-pid-$$}"

# ─── 工具函数 ──────────────────────────────────────────────────────────
_today_utc() { date -u +"%Y-%m-%d"; }
_now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_now_epoch() { date +%s; }

# 计算 sha256 前缀（16 位），输入 stdin
_sha256_16() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}' | cut -c1-16
    else
        sha256sum | awk '{print $1}' | cut -c1-16
    fi
}

# 添加 N 天后的日期（YYYY-MM-DD）
_date_plus_days() {
    local days="$1"
    if date -u -v+"${days}d" +"%Y-%m-%d" >/dev/null 2>&1; then
        date -u -v+"${days}d" +"%Y-%m-%d"
    else
        date -u -d "+${days} days" +"%Y-%m-%d"
    fi
}

# ttl 表（§12.7）→ 默认按 signal_type 取
_ttl_days_for() {
    case "$1" in
        trend)            echo 3 ;;
        competition)      echo 7 ;;
        comment_demand)   echo 14 ;;
        evergreen)        echo 30 ;;
        *)                echo 7 ;;
    esac
}

# topic → cache 路径
_cache_path_for() {
    local topic="$1"
    local h
    h="$(printf '%s' "$topic" | _sha256_16)"
    printf '%s' "$SIGNALS_DIR/${h}.json"
}

# ─── 策略读取（merge user override over default）────────────────────────
_read_policy_json() {
    python3 - "$DEFAULT_POLICY" "$USER_POLICY" <<'PYEOF'
import json, sys, os
def load(p):
    if not p or not os.path.exists(p):
        return None
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return None
def deep_merge(base, override):
    if not isinstance(base, dict) or not isinstance(override, dict):
        return override if override is not None else base
    out = dict(base)
    for k, v in override.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out
default = load(sys.argv[1]) or {}
user = load(sys.argv[2]) or {}
merged = deep_merge(default, user)
print(json.dumps(merged, ensure_ascii=False))
PYEOF
}

# 取一个嵌套路径（如 daily_budget.search_feeds）
_policy_get() {
    local path="$1"
    _read_policy_json | python3 - "$path" <<'PYEOF'
import json, sys
d = json.loads(sys.stdin.read())
keys = sys.argv[1].split(".")
v = d
for k in keys:
    if isinstance(v, dict) and k in v:
        v = v[k]
    else:
        v = None
        break
if v is None:
    print("")
elif isinstance(v, bool):
    print("true" if v else "false")
elif isinstance(v, (int, float)):
    print(v)
else:
    print(v)
PYEOF
}

# ─── 计数器 ────────────────────────────────────────────────────────────
# counters.json 形如：
# {
#   "date": "2026-04-28",
#   "daily": {"search_feeds": 0, "list_feeds": 0, ...},
#   "sessions": {
#     "<sid>": {"search_feeds": 0, "get_feed_detail": 0, ...}
#   }
# }
_counters_load_and_reset() {
    local today
    today="$(_today_utc)"
    python3 - "$COUNTERS_FILE" "$today" <<'PYEOF'
import json, os, sys
p, today = sys.argv[1], sys.argv[2]
if os.path.exists(p):
    try:
        with open(p) as f:
            d = json.load(f)
    except Exception:
        d = {}
else:
    d = {}
if d.get("date") != today:
    d = {"date": today, "daily": {}, "sessions": {}}
d.setdefault("daily", {})
d.setdefault("sessions", {})
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(json.dumps(d, ensure_ascii=False))
PYEOF
}

# 取 daily/session 计数
_counters_get() {
    local scope="$1"  # daily / session
    local key="$2"    # search_feeds / get_feed_detail / fetch_comments / list_feeds
    local sid="${3:-$SESSION_ID}"
    if [ ! -f "$COUNTERS_FILE" ]; then
        echo 0; return
    fi
    python3 - "$COUNTERS_FILE" "$scope" "$key" "$sid" <<'PYEOF'
import json, sys
p, scope, key, sid = sys.argv[1:5]
try:
    with open(p) as f:
        d = json.load(f)
except Exception:
    print(0); sys.exit(0)
if scope == "daily":
    print(d.get("daily", {}).get(key, 0))
else:
    print(d.get("sessions", {}).get(sid, {}).get(key, 0))
PYEOF
}

# +1 daily + session
_counters_inc() {
    local key="$1"
    local sid="${2:-$SESSION_ID}"
    _counters_load_and_reset >/dev/null
    python3 - "$COUNTERS_FILE" "$key" "$sid" <<'PYEOF'
import json, sys
p, key, sid = sys.argv[1:4]
with open(p) as f:
    d = json.load(f)
d.setdefault("daily", {})
d["daily"][key] = int(d["daily"].get(key, 0)) + 1
d.setdefault("sessions", {})
d["sessions"].setdefault(sid, {})
d["sessions"][sid][key] = int(d["sessions"][sid].get(key, 0)) + 1
with open(p, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
}

# 是否还有预算（不增计数）
_can_consume() {
    local key="$1"  # search_feeds / get_feed_detail / fetch_comments / list_feeds
    local daily_used session_used
    local daily_cap session_cap
    daily_used="$(_counters_get daily "$key")"
    session_used="$(_counters_get session "$key")"
    daily_cap="$(_policy_get "daily_budget.$key")"
    session_cap="$(_policy_get "per_session_budget.$key")"
    daily_cap="${daily_cap:-0}"
    session_cap="${session_cap:-0}"
    # 没设 session 上限就只看 daily
    if [ -n "$daily_cap" ] && [ "$daily_cap" != "0" ] && [ "$daily_used" -ge "$daily_cap" ]; then
        return 1
    fi
    if [ -n "$session_cap" ] && [ "$session_cap" != "0" ] && [ "$session_used" -ge "$session_cap" ]; then
        return 1
    fi
    return 0
}

# ─── safety state 检查 ─────────────────────────────────────────────────
# 不阻断 normal/watch；cooldown/locked 时拒绝
_safety_blocking() {
    local out rc
    out="$(bash "$SCRIPT_DIR/account-safety.sh" status 2>/dev/null)" || return 0
    local risk
    risk="$(printf '%s' "$out" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('risk_level',''))" 2>/dev/null)"
    case "$risk" in
        cooldown|locked) printf '%s' "$risk"; return 0 ;;
        *) return 1 ;;
    esac
}

# 风险信号写入 + 终止
_record_risk() {
    local hint="$1"
    bash "$SCRIPT_DIR/account-safety.sh" record-event external_intel "$hint" >/dev/null 2>&1 || true
}

# ─── schema 校验 ───────────────────────────────────────────────────────
_validate_signal() {
    local file="$1"
    python3 - "$file" "$SIGNAL_SCHEMA" <<'PYEOF'
import json, sys, re
data_path, schema_path = sys.argv[1], sys.argv[2]
try:
    with open(data_path) as f:
        data = json.load(f)
except Exception as e:
    print(f"data_load_error: {e}", file=sys.stderr); sys.exit(20)

# 优先用 jsonschema；否则做最小结构性检查
try:
    import jsonschema
    with open(schema_path) as f:
        schema = json.load(f)
    jsonschema.validate(data, schema)
    print("ok")
except ImportError:
    required = ["topic", "observed_at", "sample_size", "competition_density",
                "common_angles", "overused_patterns", "comment_demands",
                "white_space", "confidence", "expires_at"]
    forbidden = ["full_body", "raw_comments", "full_comments",
                 "raw_post_body", "note_body", "raw_html"]
    for k in required:
        if k not in data:
            print(f"missing_required: {k}", file=sys.stderr); sys.exit(20)
    for k in forbidden:
        if k in data:
            print(f"forbidden_field: {k}", file=sys.stderr); sys.exit(20)
    print("ok-fallback")
except Exception as e:
    print(f"validate_error: {e}", file=sys.stderr); sys.exit(20)
PYEOF
}

# ─── 调用 xhs.sh ────────────────────────────────────────────────────────
# 失败/风险信号 → 返回 1 + 设置 _last_risk=1
_xhs_search() {
    local kw="$1"
    local out
    out="$(bash "$SCRIPT_DIR/xhs.sh" search "$kw" 2>&1)" || {
        _last_xhs_err="$out"
        return 1
    }
    printf '%s' "$out"
}

_xhs_detail() {
    local note_id="$1"
    local out
    out="$(bash "$SCRIPT_DIR/xhs.sh" detail "$note_id" 2>&1)" || {
        _last_xhs_err="$out"
        return 1
    }
    printf '%s' "$out"
}

_xhs_recommend() {
    local out
    out="$(bash "$SCRIPT_DIR/xhs.sh" recommend 2>&1)" || {
        _last_xhs_err="$out"
        return 1
    }
    printf '%s' "$out"
}

# 检查响应是否含风险关键词（与 account-safety.sh 同列表）
_response_has_risk() {
    local s
    s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$s" in
        *429*|*captcha*|*verify*|*risk*|*forbidden*|*blocked*|*"rate limit"*|*"login required"*|*"cookie invalid"*|*风控*|*验证*|*频繁*|*异常*) return 0 ;;
        *) return 1 ;;
    esac
}

# ─── 子命令：cache-get ─────────────────────────────────────────────────
cmd_cache_get() {
    local topic="${1:-}"
    if [ -z "$topic" ]; then
        emit_json ok=false error=usage message="cache-get \"<主题>\""
        return 1
    fi
    local path
    path="$(_cache_path_for "$topic")"
    if [ ! -f "$path" ]; then
        emit_json ok=true cache_hit=false topic="$topic" message="cache_miss"
        return 0
    fi
    local now expires
    now="$(_today_utc)"
    expires="$(python3 -c "import json; print(json.load(open('$path')).get('expires_at',''))" 2>/dev/null)"
    if [ -z "$expires" ] || [ "$expires" \< "$now" ]; then
        emit_json ok=true cache_hit=false topic="$topic" message="cache_expired" expires_at="$expires"
        return 0
    fi
    # 命中：原样输出 signal + 包装
    python3 - "$path" "$topic" <<'PYEOF'
import json, sys
p, topic = sys.argv[1], sys.argv[2]
sig = json.load(open(p))
out = {"ok": True, "cache_hit": True, "topic": topic, "signal": sig}
print(json.dumps(out, ensure_ascii=False))
PYEOF
}

# ─── 子命令：cache-prune ───────────────────────────────────────────────
cmd_cache_prune() {
    local removed=0 kept=0
    local now
    now="$(_today_utc)"
    if [ -d "$SIGNALS_DIR" ]; then
        for f in "$SIGNALS_DIR"/*.json; do
            [ -e "$f" ] || continue
            local exp
            exp="$(python3 -c "import json; print(json.load(open('$f')).get('expires_at',''))" 2>/dev/null)"
            if [ -z "$exp" ] || [ "$exp" \< "$now" ]; then
                rm -f "$f"
                removed=$((removed+1))
            else
                kept=$((kept+1))
            fi
        done
    fi
    emit_json ok=true removed="$removed" kept="$kept" pruned_at="$now"
}

# ─── 子命令：budget-status ─────────────────────────────────────────────
cmd_budget_status() {
    _counters_load_and_reset >/dev/null
    local policy_tmp
    policy_tmp="$(mktemp -t shuling-extint.XXXXXX)"
    _read_policy_json > "$policy_tmp"
    python3 - "$COUNTERS_FILE" "$SESSION_ID" "$policy_tmp" <<'PYEOF'
import json, sys
counters = json.load(open(sys.argv[1]))
sid = sys.argv[2]
policy = json.load(open(sys.argv[3]))
daily_cap = policy.get("daily_budget", {})
session_cap = policy.get("per_session_budget", {})
daily_used = counters.get("daily", {})
session_used = counters.get("sessions", {}).get(sid, {})
out = {
    "ok": True,
    "date": counters.get("date"),
    "session_id": sid,
    "daily": {k: {"used": daily_used.get(k, 0), "cap": daily_cap.get(k, 0)} for k in daily_cap},
    "session": {k: {"used": session_used.get(k, 0), "cap": session_cap.get(k, 0)} for k in session_cap},
    "mode": policy.get("mode"),
    "cooldown_minutes_after_risk": policy.get("cooldown_minutes_after_risk"),
}
print(json.dumps(out, ensure_ascii=False))
PYEOF
    rm -f "$policy_tmp"
}

# ─── 子命令：research-topic ─────────────────────────────────────────────
# §12.6 采样原则：每主题 ≤ 3 关键词 × ≤ 5 结果 × ≤ 3-5 深读
cmd_research_topic() {
    local topic="" budget="conservative"
    while [ $# -gt 0 ]; do
        case "$1" in
            --budget) shift; budget="${1:-conservative}"; shift ;;
            *) [ -z "$topic" ] && topic="$1"; shift ;;
        esac
    done
    if [ -z "$topic" ]; then
        emit_json ok=false error=usage message="research-topic \"<主题>\" [--budget conservative|balanced|aggressive]"
        return 1
    fi

    # 1. cache 优先
    local cache_path
    cache_path="$(_cache_path_for "$topic")"
    if [ -f "$cache_path" ]; then
        local exp now
        exp="$(python3 -c "import json; print(json.load(open('$cache_path')).get('expires_at',''))" 2>/dev/null)"
        now="$(_today_utc)"
        if [ -n "$exp" ] && [ ! "$exp" \< "$now" ]; then
            python3 - "$cache_path" "$topic" <<'PYEOF'
import json, sys
sig = json.load(open(sys.argv[1]))
print(json.dumps({"ok": True, "cache_hit": True, "topic": sys.argv[2], "signal": sig}, ensure_ascii=False))
PYEOF
            return 0
        fi
    fi

    # 2. safety state 检查
    local risk
    if risk="$(_safety_blocking)"; then
        emit_json ok=false error=safety_blocked risk_level="$risk" topic="$topic"
        return 30
    fi

    # 3. 预算检查
    if ! _can_consume search_feeds; then
        emit_json ok=true degraded=true reason=budget_exhausted topic="$topic" fallback="use cached or internal"
        return 0
    fi

    # 4. 采样：1 个主题用作 search keyword（保守模式）
    _counters_inc search_feeds
    local search_out
    if ! search_out="$(_xhs_search "$topic")"; then
        emit_json ok=true degraded=true reason=mcp_search_failed topic="$topic" hint="${_last_xhs_err:0:120}"
        return 0
    fi
    if _response_has_risk "$search_out"; then
        _record_risk "search_feeds risk during research-topic[$topic]"
        emit_json ok=false error=risk_signal_during_sampling topic="$topic" partial=true
        return 31
    fi

    # 5. 提取候选 note_id（最多 5 条），深读最多 3 条（保守）
    local detail_count=0
    local detail_max=3
    [ "$budget" = "balanced" ] && detail_max=4
    [ "$budget" = "aggressive" ] && detail_max=5
    local note_ids=()
    while IFS= read -r nid; do
        [ -z "$nid" ] && continue
        note_ids+=("$nid")
        [ "${#note_ids[@]}" -ge 5 ] && break
    done < <(printf '%s' "$search_out" | python3 -c "
import json, sys, re
try:
    raw = sys.stdin.read()
    # MCP 返回常见结构：result.content[0].text 是 JSON 字符串；或 result 直含 feeds
    note_ids = []
    try:
        d = json.loads(raw)
    except Exception:
        d = None
    if isinstance(d, dict):
        # 提取 feed_id / note_id 兼容多种结构
        text = json.dumps(d, ensure_ascii=False)
    else:
        text = raw
    for m in re.finditer(r'\"(?:feed_id|note_id|id)\"\\s*:\\s*\"([0-9a-fA-F]{16,32})\"', text):
        nid = m.group(1)
        if nid not in note_ids:
            note_ids.append(nid)
        if len(note_ids) >= 5:
            break
    for nid in note_ids:
        print(nid)
except Exception:
    pass
" 2>/dev/null)

    # 6. 深读详情（最多 detail_max）
    local details_collected=0
    local details_text=""
    for nid in "${note_ids[@]}"; do
        [ "$detail_count" -ge "$detail_max" ] && break
        if ! _can_consume get_feed_detail; then break; fi
        _counters_inc get_feed_detail
        local d_out
        if ! d_out="$(_xhs_detail "$nid")"; then
            continue
        fi
        if _response_has_risk "$d_out"; then
            _record_risk "get_feed_detail risk during research-topic[$topic]"
            # 已采样部分仍可使用 → partial 落盘
            break
        fi
        details_text="${details_text}
${d_out}"
        detail_count=$((detail_count+1))
        details_collected=$((details_collected+1))
    done

    # 7. 提炼信号（基于 search_out + details_text 做关键词聚类）
    # 用临时文件传 raw 文本，避免 here-string 引号转义问题
    local _raw_search_tmp _raw_details_tmp
    _raw_search_tmp="$(mktemp -t shuling-extint.XXXXXX)"
    _raw_details_tmp="$(mktemp -t shuling-extint.XXXXXX)"
    printf '%s' "$search_out" > "$_raw_search_tmp"
    printf '%s' "$details_text" > "$_raw_details_tmp"

    local signal_json
    signal_json="$(python3 - "$topic" "$detail_count" "${#note_ids[@]}" "$_raw_search_tmp" "$_raw_details_tmp" <<'PYEOF'
import json, sys, re, datetime, collections
topic = sys.argv[1]
details_count = int(sys.argv[2])
search_results = int(sys.argv[3])
raw_search = open(sys.argv[4]).read() if sys.argv[4] else ""
raw_details = open(sys.argv[5]).read() if sys.argv[5] else ""

def extract_titles(text):
    titles = []
    for m in re.finditer(r'"(?:title|display_title)"\s*:\s*"([^"]+)"', text or ""):
        t = m.group(1).strip()
        if t and len(t) < 60:
            titles.append(t)
    return titles

def extract_phrases(titles):
    counter = collections.Counter()
    for t in titles:
        for m in re.findall(r'[一-鿿]{2,6}', t):
            counter[m] += 1
    return [w for w, c in counter.most_common(20) if c >= 2]

titles_search = extract_titles(raw_search)
titles_detail = extract_titles(raw_details)
all_titles = titles_search + titles_detail

phrases = extract_phrases(all_titles)
common_angles = phrases[:5] or [topic + "（主入口）"]
overused = [t[:30] for t in titles_search if any(d in t for d in "0123456789")][:3]

n = len(titles_search)
if n >= 10: density = "high"
elif n >= 4: density = "medium"
else: density = "low"

white_space = []
if density == "high":
    white_space = ["差异化角度待验证：" + topic + "（按动线/场景/人群细分）"]

today = datetime.datetime.utcnow().strftime("%Y-%m-%d")
expires = (datetime.datetime.utcnow() + datetime.timedelta(days=3)).strftime("%Y-%m-%d")
confidence = round(min(1.0, 0.3 + 0.07 * details_count + 0.03 * min(search_results, 5)), 2)

signal = {
    "topic": topic,
    "observed_at": today,
    "sample_size": {
        "search_results": min(search_results, 30),
        "details": details_count,
        "comments": 0,
    },
    "competition_density": density,
    "common_angles": common_angles,
    "overused_patterns": overused,
    "comment_demands": [],
    "white_space": white_space,
    "confidence": confidence,
    "expires_at": expires,
}
print(json.dumps(signal, ensure_ascii=False))
PYEOF
)"
    rm -f "$_raw_search_tmp" "$_raw_details_tmp"

    # 8. 写盘前 schema 校验
    local tmp_path="$cache_path.tmp"
    printf '%s' "$signal_json" > "$tmp_path"
    if ! _validate_signal "$tmp_path" >/dev/null 2>&1; then
        rm -f "$tmp_path"
        emit_json ok=false error=schema_validation_failed topic="$topic"
        return 20
    fi
    mv "$tmp_path" "$cache_path"

    # 9. 输出
    python3 - "$cache_path" "$topic" "$SESSION_ID" <<'PYEOF'
import json, sys, os
sig = json.load(open(sys.argv[1]))
out = {
    "ok": True,
    "cache_hit": False,
    "topic": sys.argv[2],
    "signal": sig,
    "budget_used": {"search_feeds": 1, "get_feed_detail": sig["sample_size"]["details"]},
    "session_id": sys.argv[3],
}
print(json.dumps(out, ensure_ascii=False))
PYEOF
}

# ─── 子命令：competition-gap ───────────────────────────────────────────
# 与 research-topic 类似但只用 search（不深读 detail）
cmd_competition_gap() {
    local topic="${1:-}"
    if [ -z "$topic" ]; then
        emit_json ok=false error=usage message="competition-gap \"<主题>\""
        return 1
    fi

    # cache 优先
    local cache_path
    cache_path="$(_cache_path_for "$topic")"
    if [ -f "$cache_path" ]; then
        local exp now
        exp="$(python3 -c "import json; print(json.load(open('$cache_path')).get('expires_at',''))" 2>/dev/null)"
        now="$(_today_utc)"
        if [ -n "$exp" ] && [ ! "$exp" \< "$now" ]; then
            python3 - "$cache_path" "$topic" <<'PYEOF'
import json, sys
sig = json.load(open(sys.argv[1]))
out = {"ok": True, "cache_hit": True, "topic": sys.argv[2],
       "competition_density": sig.get("competition_density"),
       "white_space": sig.get("white_space", []),
       "signal": sig}
print(json.dumps(out, ensure_ascii=False))
PYEOF
            return 0
        fi
    fi

    # safety + budget
    local risk
    if risk="$(_safety_blocking)"; then
        emit_json ok=false error=safety_blocked risk_level="$risk" topic="$topic"
        return 30
    fi
    if ! _can_consume search_feeds; then
        emit_json ok=true degraded=true reason=budget_exhausted topic="$topic"
        return 0
    fi

    _counters_inc search_feeds
    local search_out
    if ! search_out="$(_xhs_search "$topic")"; then
        emit_json ok=true degraded=true reason=mcp_search_failed topic="$topic"
        return 0
    fi
    if _response_has_risk "$search_out"; then
        _record_risk "search_feeds risk during competition-gap[$topic]"
        emit_json ok=false error=risk_signal_during_sampling topic="$topic"
        return 31
    fi

    local _raw_tmp
    _raw_tmp="$(mktemp -t shuling-extint.XXXXXX)"
    printf '%s' "$search_out" > "$_raw_tmp"

    local signal_json
    signal_json="$(python3 - "$topic" "$_raw_tmp" <<'PYEOF'
import json, sys, re, datetime, collections
topic = sys.argv[1]
raw = open(sys.argv[2]).read() if sys.argv[2] else ""
titles = []
for m in re.finditer(r'"(?:title|display_title)"\s*:\s*"([^"]+)"', raw):
    t = m.group(1).strip()
    if t and len(t) < 60:
        titles.append(t)
n = len(titles)
if n >= 10: density = "high"
elif n >= 4: density = "medium"
else: density = "low"
counter = collections.Counter()
for t in titles:
    for m in re.findall(r'[一-鿿]{2,6}', t):
        counter[m] += 1
common = [w for w, c in counter.most_common(10) if c >= 2]
overused = common[:3]
white_space = []
if density == "high":
    white_space = ["差异化角度待验证：" + topic + "（按动线/场景/人群细分）"]
today = datetime.datetime.utcnow().strftime("%Y-%m-%d")
expires = (datetime.datetime.utcnow() + datetime.timedelta(days=7)).strftime("%Y-%m-%d")
sig = {
    "topic": topic,
    "observed_at": today,
    "sample_size": {"search_results": min(n, 30), "details": 0, "comments": 0},
    "competition_density": density,
    "common_angles": common[:5] or [topic],
    "overused_patterns": overused,
    "comment_demands": [],
    "white_space": white_space,
    "confidence": round(min(1.0, 0.3 + 0.05 * min(n, 10)), 2),
    "expires_at": expires,
}
print(json.dumps(sig, ensure_ascii=False))
PYEOF
)"
    rm -f "$_raw_tmp"
    local tmp_path="$cache_path.tmp"
    printf '%s' "$signal_json" > "$tmp_path"
    if ! _validate_signal "$tmp_path" >/dev/null 2>&1; then
        rm -f "$tmp_path"
        emit_json ok=false error=schema_validation_failed topic="$topic"
        return 20
    fi
    mv "$tmp_path" "$cache_path"

    python3 - "$cache_path" "$topic" <<'PYEOF'
import json, sys
sig = json.load(open(sys.argv[1]))
out = {"ok": True, "cache_hit": False, "topic": sys.argv[2],
       "competition_density": sig.get("competition_density"),
       "white_space": sig.get("white_space", []),
       "signal": sig,
       "budget_used": {"search_feeds": 1}}
print(json.dumps(out, ensure_ascii=False))
PYEOF
}

# ─── 子命令：comment-demand ────────────────────────────────────────────
# 取一个 note_id 的评论 → 提炼需求高频词，**不存原文**
cmd_comment_demand() {
    local note_id="" limit=30
    while [ $# -gt 0 ]; do
        case "$1" in
            --limit) shift; limit="${1:-30}"; shift ;;
            *) [ -z "$note_id" ] && note_id="$1"; shift ;;
        esac
    done
    if [ -z "$note_id" ]; then
        emit_json ok=false error=usage message="comment-demand <note_id> [--limit 30]"
        return 1
    fi
    if [ "$limit" -gt 30 ]; then
        limit=30
    fi

    # cache 优先（按 note_id 做主题）
    local topic_key="comment-demand:$note_id"
    local cache_path
    cache_path="$(_cache_path_for "$topic_key")"
    if [ -f "$cache_path" ]; then
        local exp now
        exp="$(python3 -c "import json; print(json.load(open('$cache_path')).get('expires_at',''))" 2>/dev/null)"
        now="$(_today_utc)"
        if [ -n "$exp" ] && [ ! "$exp" \< "$now" ]; then
            python3 - "$cache_path" "$note_id" <<'PYEOF'
import json, sys
sig = json.load(open(sys.argv[1]))
out = {"ok": True, "cache_hit": True, "note_id": sys.argv[2],
       "comment_demands": sig.get("comment_demands", []),
       "signal": sig}
print(json.dumps(out, ensure_ascii=False))
PYEOF
            return 0
        fi
    fi

    # safety + budget
    local risk
    if risk="$(_safety_blocking)"; then
        emit_json ok=false error=safety_blocked risk_level="$risk" note_id="$note_id"
        return 30
    fi
    if ! _can_consume fetch_comments; then
        emit_json ok=true degraded=true reason=budget_exhausted note_id="$note_id"
        return 0
    fi

    # 调 detail（小红书 MCP 中评论包含在 detail 里）
    if ! _can_consume get_feed_detail; then
        emit_json ok=true degraded=true reason=detail_budget_exhausted note_id="$note_id"
        return 0
    fi
    _counters_inc get_feed_detail
    _counters_inc fetch_comments

    local d_out
    if ! d_out="$(_xhs_detail "$note_id")"; then
        emit_json ok=true degraded=true reason=mcp_detail_failed note_id="$note_id"
        return 0
    fi
    if _response_has_risk "$d_out"; then
        _record_risk "get_feed_detail risk during comment-demand[$note_id]"
        emit_json ok=false error=risk_signal_during_sampling note_id="$note_id"
        return 31
    fi

    local _raw_tmp
    _raw_tmp="$(mktemp -t shuling-extint.XXXXXX)"
    printf '%s' "$d_out" > "$_raw_tmp"

    local signal_json
    signal_json="$(python3 - "$note_id" "$limit" "$_raw_tmp" <<'PYEOF'
import json, sys, re, collections, datetime
note_id = sys.argv[1]
limit = int(sys.argv[2])
raw = open(sys.argv[3]).read() if sys.argv[3] else ""

comments = []
for m in re.finditer(r'"(?:content|comment_text|text)"\s*:\s*"([^"]{2,200})"', raw):
    c = m.group(1).strip()
    if c and len(c) >= 2:
        comments.append(c)
    if len(comments) >= limit:
        break

demand_keywords = ["怎么", "如何", "在哪", "推荐", "求", "想问", "请问", "可以", "能不能", "为什么"]
counter = collections.Counter()
for c in comments:
    if any(k in c for k in demand_keywords):
        for m in re.findall(r'[一-鿿]{4,12}', c):
            counter[m] += 1
demands = [w for w, n in counter.most_common(8) if n >= 2]

today = datetime.datetime.utcnow().strftime("%Y-%m-%d")
expires = (datetime.datetime.utcnow() + datetime.timedelta(days=14)).strftime("%Y-%m-%d")
sig = {
    "topic": "comment-demand:" + note_id,
    "observed_at": today,
    "sample_size": {"search_results": 0, "details": 1, "comments": min(len(comments), 30)},
    "competition_density": "medium",
    "common_angles": [],
    "overused_patterns": [],
    "comment_demands": demands or ["（评论样本不足，无明显高频需求）"],
    "white_space": [],
    "confidence": round(min(1.0, 0.3 + 0.02 * min(len(comments), 20)), 2),
    "expires_at": expires,
}
print(json.dumps(sig, ensure_ascii=False))
PYEOF
)"
    rm -f "$_raw_tmp"
    local tmp_path="$cache_path.tmp"
    printf '%s' "$signal_json" > "$tmp_path"
    if ! _validate_signal "$tmp_path" >/dev/null 2>&1; then
        rm -f "$tmp_path"
        emit_json ok=false error=schema_validation_failed note_id="$note_id"
        return 20
    fi
    mv "$tmp_path" "$cache_path"

    python3 - "$cache_path" "$note_id" <<'PYEOF'
import json, sys
sig = json.load(open(sys.argv[1]))
out = {"ok": True, "cache_hit": False, "note_id": sys.argv[2],
       "comment_demands": sig.get("comment_demands", []),
       "signal": sig,
       "budget_used": {"get_feed_detail": 1, "fetch_comments": 1}}
print(json.dumps(out, ensure_ascii=False))
PYEOF
}

# ─── usage ─────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: external-intel.sh <subcommand> [args]

Subcommands:
  research-topic "<topic>" [--budget conservative|balanced|aggressive]
                                    主题外部研究：search → 深读 → 提炼信号 → 缓存
  competition-gap "<topic>"        差异化分析：仅 search，提炼竞品密度 + white_space
  comment-demand <note_id> [--limit 30]
                                    评论需求提炼（≤30 条评论，**不存原文**）
  cache-get "<topic>"              查 cache（不发起请求）
  cache-prune                      清理过期 cache
  budget-status                    查看预算余额（daily + per-session）

Files:
  policy default: $DEFAULT_POLICY
  policy user:    $USER_POLICY
  signals:        $SIGNALS_DIR
  counters:       $COUNTERS_FILE
  schema:         $SIGNAL_SCHEMA

Exit codes:
  0  ok / cache hit / degraded
  1  usage / 缺参
  2  policy 解析失败
  20 schema 校验失败
  30 cooldown / locked
  31 风险信号触发本次采样中止
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    research-topic)   cmd_research_topic "$@" ;;
    competition-gap)  cmd_competition_gap "$@" ;;
    comment-demand)   cmd_comment_demand "$@" ;;
    cache-get)        cmd_cache_get "$@" ;;
    cache-prune)      cmd_cache_prune "$@" ;;
    budget-status)    cmd_budget_status "$@" ;;
    -h|--help|"")     usage; exit 0 ;;
    *)
        emit_json ok=false error=unknown_cmd message="unknown subcommand: $cmd"
        usage >&2
        exit 1
        ;;
esac
