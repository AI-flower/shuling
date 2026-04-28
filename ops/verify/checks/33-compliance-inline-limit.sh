#!/usr/bin/env bash
# ops/verify/checks/33-compliance-inline-limit.sh — daily/publish flow 内联合规摘要长度上限（ADR-0002 D4）
# severity: warn
#
# 03-daily-flow.md   内联 compliance summary ≤ 25 行
# 04-publish-flow.md 内联 compliance summary ≤ 20 行
# 完整规则在 08-compliance.md。
#
# 实现：从含 "合规摘要" / "compliance summary" 的锚定行起，向下数到：
#   - 遇到下一个 "## " 标题；或
#   - 遇到下一个 "**xxx**" 粗体段落标题；或
#   - 遇到 "## " 或文件末尾
# 取该 anchor 范围的行数（含 anchor 行）。
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="33-compliance-inline-limit"
SEVERITY="warn"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

count_block() {
  # 找含 "合规摘要" 或 "compliance summary"（不区分大小写）的锚定行
  # 从该行起，到下一个 "## " 标题或下一个 "**...**" 粗体起头段落 或文件末尾
  awk '
    BEGIN { in_block=0; cnt=0; max=0; }
    {
      if (in_block) {
        # 触发结束：下一个 ## 标题
        if ($0 ~ /^##[[:space:]]/) {
          if (cnt > max) max = cnt
          in_block = 0
          cnt = 0
        # 触发结束：下一个 **xxx** 粗体段落标题（且不是当前 anchor 行）
        } else if ($0 ~ /^\*\*[^*]+\*\*/) {
          if (cnt > max) max = cnt
          in_block = 0
          cnt = 0
        }
      }
      # 是否是新 anchor 行
      if ($0 ~ /合规摘要/ || tolower($0) ~ /compliance summary/) {
        if (in_block && cnt > max) max = cnt
        in_block = 1
        cnt = 1
        next
      }
      if (in_block) cnt++
    }
    END {
      if (in_block && cnt > max) max = cnt
      print max+0
    }
  ' "$1"
}

p3="$ROOT/agent/playbook/03-daily-flow.md"
p4="$ROOT/agent/playbook/04-publish-flow.md"

if [ ! -f "$p3" ] || [ ! -f "$p4" ]; then
  emit "fail" "playbook 03/04 not found"
  exit 2
fi

n3="$(count_block "$p3")"
n4="$(count_block "$p4")"

issues=()
[ "$n3" -gt 25 ] && issues+=("03-daily-flow:${n3}>25")
[ "$n4" -gt 20 ] && issues+=("04-publish-flow:${n4}>20")

if [ ${#issues[@]} -gt 0 ]; then
  emit "warn" "inline compliance block too long: ${issues[*]}"
  exit 1
fi

emit "pass" "inline compliance: 03=${n3} (<=25), 04=${n4} (<=20)"
exit 0
