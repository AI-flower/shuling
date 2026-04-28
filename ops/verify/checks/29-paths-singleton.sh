#!/usr/bin/env bash
# ops/verify/checks/29-paths-singleton.sh — agent/scripts/*.sh 不允许 hardcode 路径常量
# severity: error
#
# 规则：除 _paths.sh 自身外，其他脚本不允许出现：
#   - 自定义常量赋值 *_DIR=$(cd ...)/data 等业务数据路径
#   - 直接 mkdir -p ... agent/data agent/config agent/knowledge-base 等
#   - cd "$(dirname ..." 然后跟 /data /config /knowledge-base 拼接
# 允许：
#   - 顶部 SCRIPT_DIR / _DB_SCRIPT_DIR 推导（用于 source _paths.sh）
#   - source _paths.sh 之后引用 SHULING_* 变量
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="29-paths-singleton"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

scripts_dir="$ROOT/agent/scripts"
if [ ! -d "$scripts_dir" ]; then
  emit "fail" "agent/scripts/ not found"
  exit 2
fi

violations=()

# 模式：cd ... 之后拼上 /data /config /knowledge-base /policies /schemas /playbook
# 排除：含 BASH_SOURCE/dirname "$0" 仅用于 SCRIPT_DIR 推导（不带子路径拼接）
pattern_dir_concat='cd "?\$\(.*\)"?[[:space:]]*&&[[:space:]]*pwd[[:space:]]*\)/(data|config|knowledge-base|policies|schemas|playbook|migrations)'
# 直接对硬编码后缀路径做 mkdir
pattern_mkdir='mkdir[[:space:]]+(-p[[:space:]]+)?[^"$]*agent/(data|config|knowledge-base|policies|schemas)'

while IFS= read -r f; do
  [ -z "$f" ] && continue
  base="$(basename "$f")"
  # 豁免：_paths.sh 是路径单一来源
  [ "$base" = "_paths.sh" ] && continue

  # 检查是否 source 了 _paths.sh
  has_source=0
  if grep -Eq '(\.|source)[[:space:]]+["$]?[^"]*_paths\.sh' "$f" 2>/dev/null; then
    has_source=1
  fi

  # 1) cd ... && pwd)/<禁用子目录>
  if grep -Eq "$pattern_dir_concat" "$f" 2>/dev/null; then
    violations+=("${base}:hardcoded-dir-concat")
  fi

  # 2) mkdir -p .../agent/<禁用子目录>
  if grep -Eq "$pattern_mkdir" "$f" 2>/dev/null; then
    violations+=("${base}:hardcoded-mkdir")
  fi

  # 3) 没 source _paths.sh，但出现 SHULING_* 变量引用，疑似漏 source
  #   （温和提示，不强制；这里跳过避免误报）
done < <(find "$scripts_dir" -maxdepth 1 -type f -name "*.sh" 2>/dev/null)

if [ ${#violations[@]} -gt 0 ]; then
  emit "fail" "hardcoded paths found: ${violations[*]}"
  exit 2
fi

emit "pass" "agent/scripts/*.sh comply with _paths.sh single-source rule"
exit 0
