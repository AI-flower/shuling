#!/usr/bin/env bash
# ops/doctor.sh — 用户态视角的 v3.0 安装健康检查
#
# 作用：以 target 安装目录为输入，跑 12 项检查，输出 JSON 或表格
# 用法：
#   bash ops/doctor.sh [TARGET_PATH]            # 默认检查脚本所在的 v3 安装
#   bash ops/doctor.sh --json [TARGET_PATH]
#   bash ops/doctor.sh --table [TARGET_PATH]    # 默认
#
# 退出码：
#   0 全部通过
#   1 至少 1 项 warn
#   2 至少 1 项 fail

set -uo pipefail

target=""
fmt="table"
for arg in "$@"; do
    case "$arg" in
        --json) fmt="json" ;;
        --table) fmt="table" ;;
        --*) ;;
        *) target="$arg" ;;
    esac
done

# 默认 target = ops/.. (即 skill 根)
if [ -z "$target" ]; then
    target="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

declare -a results  # "key|status|message"

add_check() {
    local key="$1" status="$2" msg="$3"
    results+=("$key|$status|$msg")
}

# 12 项检查
[ -f "$target/SKILL.md" ] && add_check "skill_md" ok "exists" || add_check "skill_md" fail "missing $target/SKILL.md"
[ -d "$target/agent" ] && add_check "agent_dir" ok "exists" || add_check "agent_dir" fail "missing $target/agent/"

[ -f "$target/agent/data/xhs.db" ] && add_check "user_db" ok "exists" || add_check "user_db" warn "$target/agent/data/xhs.db not found (run db.sh init)"
[ -f "$target/agent/config/runtime.env" ] && add_check "runtime_env" ok "exists" || add_check "runtime_env" warn "$target/agent/config/runtime.env not found (use .example as template)"
[ -f "$target/agent/config/runtime.env.example" ] && add_check "runtime_env_example" ok "exists" || add_check "runtime_env_example" warn "$target/agent/config/runtime.env.example missing"

[ -x "$target/agent/scripts/db.sh" ] && add_check "db_sh" ok "executable" || add_check "db_sh" fail "$target/agent/scripts/db.sh not executable"

[ -f "$target/agent/config/.layout-v3.done" ] && add_check "layout_marker" ok "v3 layout active" || add_check "layout_marker" warn "no .layout-v3.done marker (v2 layout?)"

if [ -x "$target/agent/scripts/preflight.py" ]; then
    pf_out="$(python3 "$target/agent/scripts/preflight.py" 2>/dev/null)"
    pf_exit=$?
    case "$pf_exit" in
        0) add_check "preflight" ok "all green" ;;
        1) add_check "preflight" warn "auto-fixable issues (exit 1)" ;;
        2) add_check "preflight" warn "user-needed issues (exit 2)" ;;
        *) add_check "preflight" fail "preflight crashed: $pf_exit" ;;
    esac
else
    add_check "preflight" fail "preflight.py not executable"
fi

if [ -x "$target/agent/scripts/db.sh" ]; then
    if bash "$target/agent/scripts/db.sh" ensure-runtime-layout --dry-run --json >/dev/null 2>&1; then
        add_check "ensure_layout" ok "dry-run passes"
    else
        add_check "ensure_layout" warn "dry-run failed"
    fi
    if bash "$target/agent/scripts/db.sh" ensure-schema --dry-run --json >/dev/null 2>&1; then
        add_check "ensure_schema" ok "dry-run passes"
    else
        add_check "ensure_schema" warn "dry-run failed"
    fi
else
    add_check "ensure_layout" fail "db.sh missing"
    add_check "ensure_schema" fail "db.sh missing"
fi

playbook_count=$(find "$target/agent/playbook" -maxdepth 1 -name '0[0-9]-*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$playbook_count" -ge 9 ]; then
    add_check "playbooks" ok "$playbook_count playbooks"
else
    add_check "playbooks" fail "only $playbook_count playbooks (need ≥9)"
fi

schema_count=$(find "$target/agent/schemas" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "$schema_count" -ge 4 ]; then
    add_check "schemas" ok "$schema_count schemas"
else
    add_check "schemas" warn "only $schema_count schemas (need ≥4)"
fi

if grep -q '^version:' "$target/SKILL.md" 2>/dev/null; then
    skill_version="$(grep '^version:' "$target/SKILL.md" | head -1 | awk '{print $2}')"
    add_check "skill_version" ok "$skill_version"
else
    add_check "skill_version" fail "SKILL.md frontmatter missing version"
fi

# ─── v3.1+ Account Safety Layer 检查 ───────────────────────────────────
# 见 docs/plans/v3-account-execution-safety-hardening.md §13.2
safety_policy_file="$target/agent/config/account-safety.json"
if [ -f "$safety_policy_file" ]; then
    if python3 -c "import json; json.load(open('$safety_policy_file'))" >/dev/null 2>&1; then
        sp_mode="$(python3 -c "import json; print(json.load(open('$safety_policy_file')).get('mode',''))" 2>/dev/null)"
        add_check "account_safety_policy" ok "mode=$sp_mode"
    else
        add_check "account_safety_policy" fail "account-safety.json invalid JSON"
    fi
else
    add_check "account_safety_policy" warn "account-safety.json missing (run db.sh ensure-runtime-layout)"
fi

safety_state_file="$target/agent/config/account-safety-state.json"
if [ -f "$safety_state_file" ]; then
    if python3 -c "import json; json.load(open('$safety_state_file'))" >/dev/null 2>&1; then
        risk_level="$(python3 -c "import json; print(json.load(open('$safety_state_file')).get('risk_level',''))" 2>/dev/null)"
        add_check "account_safety_state" ok "risk_level=$risk_level"
    else
        add_check "account_safety_state" fail "account-safety-state.json invalid JSON"
    fi
else
    add_check "account_safety_state" warn "account-safety-state.json missing"
fi

# cooldown_active 检查（额外详细信息）
if [ -f "$safety_state_file" ]; then
    cd_info="$(python3 - "$safety_state_file" <<'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    rl = d.get("risk_level","normal")
    if rl in ("cooldown","locked"):
        until = d.get("cooldown_until") or "n/a"
        reason = d.get("cooldown_reason") or "n/a"
        print(f"{rl}|{reason}|{until}")
    else:
        print(f"{rl}||")
except Exception:
    print("err||")
PYEOF
)"
    IFS='|' read -r cd_level cd_reason cd_until <<< "$cd_info"
    if [ "$cd_level" = "cooldown" ]; then
        add_check "cooldown_active" warn "risk_level=cooldown reason='$cd_reason' until=$cd_until"
    elif [ "$cd_level" = "locked" ]; then
        add_check "cooldown_active" fail "risk_level=locked reason='$cd_reason' (only doctor/preflight allowed)"
    else
        add_check "cooldown_active" ok "no active cooldown"
    fi
else
    add_check "cooldown_active" warn "state file missing, cannot determine cooldown"
fi

# 输出
fail_count=0
warn_count=0
for r in "${results[@]}"; do
    s="${r#*|}"; s="${s%%|*}"
    [ "$s" = "fail" ] && fail_count=$((fail_count+1))
    [ "$s" = "warn" ] && warn_count=$((warn_count+1))
done

if [ "$fmt" = "json" ]; then
    echo -n '{"target":"'"$target"'","results":['
    sep=""
    for r in "${results[@]}"; do
        IFS='|' read -r k s m <<< "$r"
        echo -n "$sep{\"key\":\"$k\",\"status\":\"$s\",\"message\":\"$m\"}"
        sep=","
    done
    echo "],\"fail\":$fail_count,\"warn\":$warn_count}"
else
    printf '%-22s %-5s %s\n' "CHECK" "STATUS" "MESSAGE"
    printf '%-22s %-5s %s\n' "----------------------" "------" "-------------------------"
    # ANSI 颜色（仅在 stdout 是 TTY 时启用，避免污染 pipeline）
    if [ -t 1 ]; then
        C_YELLOW='\033[33m'; C_RED='\033[31m'; C_RESET='\033[0m'
    else
        C_YELLOW=''; C_RED=''; C_RESET=''
    fi
    for r in "${results[@]}"; do
        IFS='|' read -r k s m <<< "$r"
        # account_safety / cooldown_active 高亮
        if [ "$k" = "cooldown_active" ] && [ "$s" = "warn" ]; then
            printf '%-22s %b%-5s%b %s\n' "$k" "$C_YELLOW" "$s" "$C_RESET" "$m"
        elif [ "$k" = "cooldown_active" ] && [ "$s" = "fail" ]; then
            printf '%-22s %b%-5s%b %s\n' "$k" "$C_RED" "$s" "$C_RESET" "$m"
        else
            printf '%-22s %-5s %s\n' "$k" "$s" "$m"
        fi
    done
    echo ""
    echo "Summary: fail=$fail_count warn=$warn_count total=${#results[@]}"
fi

[ "$fail_count" -gt 0 ] && exit 2
[ "$warn_count" -gt 0 ] && exit 1
exit 0
