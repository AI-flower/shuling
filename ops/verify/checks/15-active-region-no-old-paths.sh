#!/usr/bin/env bash
# ops/verify/checks/15-active-region-no-old-paths.sh — active 区域不允许 v2 旧根路径硬编码
# severity: error
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="15-active-region-no-old-paths"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

# v2 旧根路径模式（必须改成 agent/...）
# 用 grep -E 反向匹配；下列正则任一命中即视为违规
# 注意：避免误伤 agent/scripts/ 等已正确路径，使用 (?<!agent/) 思路
# bash grep 不支持 lookbehind，用替代写法：先找候选行，再剔除 agent/ 前缀
PATTERNS=(
  '(^|[^A-Za-z0-9_/])scripts/db\.sh'
  '(^|[^A-Za-z0-9_/])scripts/xhs\.sh'
  '(^|[^A-Za-z0-9_/])scripts/preflight\.py'
  '(^|[^A-Za-z0-9_/])scripts/validate\.py'
  '(^|[^A-Za-z0-9_/])scripts/image\.py'
  '(^|[^A-Za-z0-9_/])scripts/pre-submit-verify\.sh'
  'bash[[:space:]]+scripts/'
  '(^|[^A-Za-z0-9_/])data/content-rules\.md'
  '(^|[^A-Za-z0-9_/])data/xhs\.db'
  '(^|[^A-Za-z0-9_/])schemas/[A-Za-z0-9_.-]+\.schema\.json'
  '(^|[^A-Za-z0-9_/])migrations/v[0-9]'
  '(^|[^A-Za-z0-9_/])prompts/'
  '(^|[^A-Za-z0-9_/])config/runtime\.env'
  '(^|[^A-Za-z0-9_/])knowledge-base/'
)

# active 区域：根 SKILL.md + agent/ + ops/ + build/
# 完全跳过：legacy/ docs/archive/ marketing/ + 文档白名单
# 文件类型：md / sh / py / json
SCAN_DIRS=("$ROOT/agent" "$ROOT/ops" "$ROOT/build")

# 白名单（允许提到 v2 路径作对照说明）
is_whitelisted() {
  local f="$1"
  local rel="${f#$ROOT/}"
  case "$rel" in
    docs/adr/0001-*|docs/adr/0002-*) return 0 ;;
    docs/plans/v3-*) return 0 ;;
    # 检查脚本自身（含正则字面量）
    ops/verify/checks/15-*) return 0 ;;
    # 32-* 用 'knowledge-base/profile.json' 作字符串字面量做 substring 匹配（兼容 agent/knowledge-base/profile.json）
    ops/verify/checks/32-*) return 0 ;;
    # 升级 hooks 与 layout 迁移：本质就是处理 v2 → v3
    ops/upgrade-hooks/*) return 0 ;;
    ops/layout-migrations/*) return 0 ;;
    # ops/install.sh 是跨版本安装器，包含 rollback-to-v2 / upgrade-all v2 兼容层 / rsync 排除模板等
    # 不可避免地引用 v2 路径作探针字符串
    ops/install.sh) return 0 ;;
    # README / 升级文档允许出现 v2 引用
    agent/migrations/README.md) return 0 ;;
    agent/scripts/README.md) return 0 ;;
  esac
  return 1
}

# 检查某行是否处于 v2 兼容层豁免区
# - agent/migrations/db/v*.sh 内全文 v2 兼容层允许
is_legacy_migration_file() {
  local f="$1"
  local rel="${f#$ROOT/}"
  case "$rel" in
    agent/migrations/db/v*.sh) return 0 ;;
    agent/migrations/db/_guard.sh) return 0 ;;
    agent/migrations/db/_applied_table.sql) return 0 ;;
  esac
  return 1
}

# 收集候选文件
candidates=()
# 根 SKILL.md
[ -f "$ROOT/SKILL.md" ] && candidates+=("$ROOT/SKILL.md")

for d in "${SCAN_DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do
    candidates+=("$f")
  done < <(find "$d" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.py' -o -name '*.json' \) -print0)
done

violations=()
violation_count=0
MAX_REPORT=20

for f in "${candidates[@]}"; do
  is_whitelisted "$f" && continue
  is_legacy_migration_file "$f" && continue

  rel="${f#$ROOT/}"

  # 逐 pattern 扫
  for pat in "${PATTERNS[@]}"; do
    # grep -nE 输出 行号:内容；过滤掉 agent/scripts/ agent/data/ agent/schemas/ agent/migrations/ agent/prompts/ agent/config/ agent/knowledge-base/ 这些正确前缀
    while IFS= read -r line; do
      # 排除：以 agent/ 起头的合法路径
      stripped="$line"
      # 行内任何位置出现 v2 模式但同时该匹配位置前是 "agent/" 的，我们跳过
      # 简化：取匹配子串，看其前一字符
      # 用 grep -oE 配合 -b 获取偏移开销大；改用 awk 模式实际判断
      echo "$rel|$line"
    done < <(grep -nE "$pat" "$f" 2>/dev/null || true)
  done
done > /tmp/_15_raw.$$

# 二次过滤：剔除以 "agent/" 为正确前缀的命中
# 同时剔除注释中带 "v2:" 或 "兼容" 标记的行（保留为最小放行）
filtered=()
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  rel="${entry%%|*}"
  rest="${entry#*|}"
  # rest 形式: NN:行内容
  lineno="${rest%%:*}"
  content="${rest#*:}"

  # 剔除 agent/ 合法路径：若 content 中所有 v2 关键词命中位置前都是 "agent/"，则跳过
  # 简化策略：若 content 不含独立 v2 路径片段（即被 agent/ 前缀的），则保留
  skip=0
  # 对每个候选 token 做存在性判断
  # 把 content 中 "agent/scripts/" 等正确前缀替换掉再检查
  scrubbed="$content"
  scrubbed="${scrubbed//agent\/scripts\//XXSAFEXX}"
  scrubbed="${scrubbed//agent\/data\//XXSAFEXX}"
  scrubbed="${scrubbed//agent\/schemas\//XXSAFEXX}"
  scrubbed="${scrubbed//agent\/migrations\//XXSAFEXX}"
  scrubbed="${scrubbed//agent\/prompts\//XXSAFEXX}"
  scrubbed="${scrubbed//agent\/config\//XXSAFEXX}"
  scrubbed="${scrubbed//agent\/knowledge-base\//XXSAFEXX}"
  scrubbed="${scrubbed//agent\/playbook\//XXSAFEXX}"
  scrubbed="${scrubbed//agent\/policies\//XXSAFEXX}"

  # 在 scrubbed 内重新跑模式
  hit=0
  for pat in "${PATTERNS[@]}"; do
    if printf '%s' "$scrubbed" | grep -Eq "$pat"; then
      hit=1
      break
    fi
  done

  # 行内 v2 兼容层标记豁免：注释里写明 "v2 兼容层" / "v2-compat" 就放行
  # 这是兼容层引用的最小放行机制（必须显式标注，不允许默写）
  if [ "$hit" -eq 1 ]; then
    if printf '%s' "$content" | grep -qE 'v2[[:space:]]*兼容层|v2-compat|v2 compatibility'; then
      hit=0
    fi
  fi

  if [ "$hit" -eq 1 ]; then
    filtered+=("${rel}:${lineno}")
    violation_count=$((violation_count + 1))
  fi
done < /tmp/_15_raw.$$
rm -f /tmp/_15_raw.$$

if [ "$violation_count" -gt 0 ]; then
  # 截断报告
  if [ "$violation_count" -gt "$MAX_REPORT" ]; then
    summary="${filtered[*]:0:$MAX_REPORT} ... (+$((violation_count - MAX_REPORT)) more)"
  else
    summary="${filtered[*]}"
  fi
  emit "fail" "v2 path usage in active region (${violation_count} hits): ${summary}"
  exit 2
fi

emit "pass" "no v2 root paths in active region (${#candidates[@]} files scanned)"
exit 0
