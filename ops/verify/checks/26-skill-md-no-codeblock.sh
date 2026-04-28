#!/usr/bin/env bash
# ops/verify/checks/26-skill-md-no-codeblock.sh — 根 SKILL.md 仅允许 ```bash 代码块
# severity: error
#
# v3.0 起 SKILL.md 是协议适配层，不放业务示例。仅启动协议 4 步可能含 bash 命令。
# 任何 ```python ```json ```yaml 等示例 → fail
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="26-skill-md-no-codeblock"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

skill="$ROOT/SKILL.md"
if [ ! -f "$skill" ]; then
  emit "fail" "SKILL.md not found at $skill"
  exit 2
fi

# 提取所有 ```xxx 起始围栏的语言标签
# 仅取每对围栏的"开"行，奇数位置的围栏视为 open
bad=()
in_block=0
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno+1))
  case "$line" in
    '```'*)
      if [ "$in_block" = "0" ]; then
        # 这是开始围栏，提取语言
        lang="${line#\`\`\`}"
        # 去掉首尾空白
        lang="${lang## }"
        lang="${lang%% *}"
        if [ -n "$lang" ] && [ "$lang" != "bash" ]; then
          bad+=("L${lineno}:${lang}")
        fi
        in_block=1
      else
        in_block=0
      fi
      ;;
  esac
done < "$skill"

if [ ${#bad[@]} -gt 0 ]; then
  emit "fail" "SKILL.md contains non-bash code blocks: ${bad[*]}"
  exit 2
fi

emit "pass" "SKILL.md only contains bash code blocks (or none)"
exit 0
