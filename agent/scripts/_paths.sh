#!/usr/bin/env bash
# agent/scripts/_paths.sh — v3.0+ 路径单一来源
#
# 所有 agent/scripts/*.sh 都必须 `source` 本文件。
# 禁止在脚本里 hardcode `agent/data` `agent/config` 等路径。
#
# 设计原则（见 docs/adr/0001-stateful-creator-agent.md §第 9 条）：
#   - 路径单一来源：仓库内只有一个权威定义文件
#   - 用户态保护：agent/data/xhs.db / agent/config/runtime.env / agent/knowledge-base/ 永不覆盖
#   - 源 vs target 隔离：通过 SHULING_DB / SHULING_AGENT_ROOT env var override
#
# 用法：
#   #!/usr/bin/env bash
#   set -euo pipefail
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/_paths.sh"
#   echo "DB at $SHULING_DB_PATH"
#
# Env var override（优先级 env > 自动推导）：
#   SHULING_AGENT_ROOT  agent/ 根（自动推导：脚本所在目录的父目录）
#   SHULING_DB          xhs.db 完整路径（v2.4.2 兼容）
#   SHULING_RUNTIME_ENV runtime.env 完整路径
#   SHULING_KB_DIR      agent/knowledge-base/ 目录
#   SHULING_POLICIES_DIR policies/ 目录
#   SHULING_SCHEMAS_DIR  schemas/ 目录
#   SHULING_PLAYBOOK_DIR playbook/ 目录
#   SHULING_PROMPTS_DIR  agent/prompts/ 目录

# ─── agent root 推导 ───────────────────────────────────────────────
# _paths.sh 自身在 agent/scripts/ 下，agent/ 根是上两级
if [ -z "${SHULING_AGENT_ROOT:-}" ]; then
    SHULING_AGENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export SHULING_AGENT_ROOT

# ─── skill root（含 SKILL.md 的目录，agent/ 的父目录）─────────────
if [ -z "${SHULING_SKILL_ROOT:-}" ]; then
    SHULING_SKILL_ROOT="$(cd "$SHULING_AGENT_ROOT/.." && pwd)"
fi
export SHULING_SKILL_ROOT

# ─── 子目录路径（按 v3.0 布局）────────────────────────────────────
export SHULING_SCRIPTS_DIR="${SHULING_SCRIPTS_DIR:-$SHULING_AGENT_ROOT/scripts}"
export SHULING_PLAYBOOK_DIR="${SHULING_PLAYBOOK_DIR:-$SHULING_AGENT_ROOT/playbook}"
export SHULING_SCHEMAS_DIR="${SHULING_SCHEMAS_DIR:-$SHULING_AGENT_ROOT/schemas}"
export SHULING_PROMPTS_DIR="${SHULING_PROMPTS_DIR:-$SHULING_AGENT_ROOT/prompts}"
export SHULING_POLICIES_DIR="${SHULING_POLICIES_DIR:-$SHULING_AGENT_ROOT/policies}"
export SHULING_MIGRATIONS_DIR="${SHULING_MIGRATIONS_DIR:-$SHULING_AGENT_ROOT/migrations}"
export SHULING_MIGRATIONS_DB_DIR="${SHULING_MIGRATIONS_DB_DIR:-$SHULING_MIGRATIONS_DIR/db}"
export SHULING_MIGRATIONS_STATE_DIR="${SHULING_MIGRATIONS_STATE_DIR:-$SHULING_MIGRATIONS_DIR/state}"

# ─── 用户态目录（永不覆盖）─────────────────────────────────────────
export SHULING_DATA_DIR="${SHULING_DATA_DIR:-$SHULING_AGENT_ROOT/data}"
export SHULING_CONFIG_DIR="${SHULING_CONFIG_DIR:-$SHULING_AGENT_ROOT/config}"
export SHULING_KB_DIR="${SHULING_KB_DIR:-$SHULING_AGENT_ROOT/knowledge-base}"

# ─── 用户态文件（v2.4.2 SHULING_DB 兼容路径）──────────────────────
# SHULING_DB 在 v2.4.2 引入；此处保持向后兼容
if [ -z "${SHULING_DB:-}" ]; then
    SHULING_DB="$SHULING_DATA_DIR/xhs.db"
fi
export SHULING_DB
export SHULING_DB_PATH="$SHULING_DB"  # 别名，新代码用 _PATH 后缀

export SHULING_RUNTIME_ENV="${SHULING_RUNTIME_ENV:-$SHULING_CONFIG_DIR/runtime.env}"
export SHULING_RUNTIME_ENV_EXAMPLE="${SHULING_RUNTIME_ENV_EXAMPLE:-$SHULING_CONFIG_DIR/runtime.env.example}"
export SHULING_STATE_JSON="${SHULING_STATE_JSON:-$SHULING_CONFIG_DIR/state.json}"
export SHULING_LAYOUT_MARKER="${SHULING_LAYOUT_MARKER:-$SHULING_CONFIG_DIR/.layout-v3.done}"
export SHULING_SCHEMA_DEGRADED_LOCK="${SHULING_SCHEMA_DEGRADED_LOCK:-$SHULING_DATA_DIR/.schema-degraded.lock}"

# ─── 内容契约（policies/）─────────────────────────────────────────
export SHULING_CONTENT_RULES="${SHULING_CONTENT_RULES:-$SHULING_POLICIES_DIR/content-rules.md}"
export SHULING_THROTTLE_YAML="${SHULING_THROTTLE_YAML:-$SHULING_POLICIES_DIR/throttle.yaml}"
export SHULING_QUOTA_YAML="${SHULING_QUOTA_YAML:-$SHULING_POLICIES_DIR/quota.yaml}"

# ─── knowledge-base 关键文件 ──────────────────────────────────────
export SHULING_KB_PROFILE="${SHULING_KB_PROFILE:-$SHULING_KB_DIR/profile.json}"
export SHULING_KB_PREFERENCES="${SHULING_KB_PREFERENCES:-$SHULING_KB_DIR/preferences.json}"
export SHULING_KB_PATTERNS="${SHULING_KB_PATTERNS:-$SHULING_KB_DIR/patterns.md}"
export SHULING_KB_ANTI_PATTERNS="${SHULING_KB_ANTI_PATTERNS:-$SHULING_KB_DIR/anti-patterns.md}"
export SHULING_KB_EVOLUTION_LOG="${SHULING_KB_EVOLUTION_LOG:-$SHULING_KB_DIR/evolution-log.md}"

# ─── 调试输出（仅 SHULING_DEBUG=1 时）─────────────────────────────
if [ "${SHULING_DEBUG:-0}" = "1" ]; then
    cat >&2 <<EOF
[_paths.sh] resolved paths:
  SHULING_AGENT_ROOT      = $SHULING_AGENT_ROOT
  SHULING_SKILL_ROOT      = $SHULING_SKILL_ROOT
  SHULING_DB_PATH         = $SHULING_DB_PATH
  SHULING_RUNTIME_ENV     = $SHULING_RUNTIME_ENV
  SHULING_KB_DIR          = $SHULING_KB_DIR
  SHULING_POLICIES_DIR    = $SHULING_POLICIES_DIR
  SHULING_LAYOUT_MARKER   = $SHULING_LAYOUT_MARKER
EOF
fi
