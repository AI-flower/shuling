#!/usr/bin/env bash
# ops/verify/checks/32-profile-write-precondition.sh — 写 profile.json 必须有 preconditions（ADR-0002 D3）
# severity: error
#
# 凡 frontmatter writes.files 含 agent/knowledge-base/profile.json 的 playbook，
# 必须有非空 preconditions: 数组（防止跨 playbook 互相覆盖画像）
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="32-profile-write-precondition"
SEVERITY="error"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

dir="$ROOT/agent/playbook"
if [ ! -d "$dir" ]; then
  emit "fail" "agent/playbook/ not found"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  emit "fail" "python3 not available"
  exit 2
fi

result="$(python3 - "$dir" <<'PY'
import os, re, sys

playbook_dir = sys.argv[1]
violations = []

for fn in sorted(os.listdir(playbook_dir)):
    if not re.match(r'^[0-9][0-9].*\.md$', fn):
        continue
    path = os.path.join(playbook_dir, fn)
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    if not text.startswith('---'):
        continue
    end = text.find('\n---', 3)
    if end < 0:
        continue
    fm = text[3:end]

    # writes.files 块解析
    writes_files = []
    in_writes = False
    in_files = False
    pre_lines = []
    in_preconditions = False
    pre_top_inline = None
    for line in fm.split('\n'):
        # 顶级 key 切换
        m_top = re.match(r'^([A-Za-z0-9_-]+):(.*)$', line)
        if m_top:
            key = m_top.group(1)
            tail = m_top.group(2)
            in_writes = (key == 'writes')
            in_files = False
            if key == 'preconditions':
                in_preconditions = True
                # 行尾如 preconditions: [] 视为 inline
                pre_top_inline = tail.strip()
            else:
                in_preconditions = False
            continue

        if in_writes:
            if re.match(r'^\s+files:\s*$', line):
                in_files = True
                continue
            if re.match(r'^\s+files:\s*\[\]\s*$', line):
                in_files = False
                continue
            if in_files:
                m_item = re.match(r'^\s+-\s+(.+?)\s*$', line)
                if m_item:
                    writes_files.append(m_item.group(1).strip().strip('"').strip("'"))
                else:
                    if re.match(r'^\s+[A-Za-z0-9_-]+:', line):
                        in_files = False

        if in_preconditions:
            m_item = re.match(r'^\s+-\s+(.+?)\s*$', line)
            if m_item:
                pre_lines.append(m_item.group(1).strip())

    # 检查
    writes_profile = any('knowledge-base/profile.json' in w for w in writes_files)
    if writes_profile:
        # 必须有非空 preconditions
        empty = (pre_top_inline == '[]') or (pre_top_inline is None and not pre_lines) \
                or (pre_top_inline == '' and not pre_lines)
        if empty:
            violations.append(fn)

if violations:
    print("FAIL:" + ",".join(violations))
else:
    print("OK")
PY
)"
rc=$?

if [ "$rc" -ne 0 ]; then
  emit "fail" "python3 parser error: $result"
  exit 2
fi

case "$result" in
  FAIL:*)
    emit "fail" "playbooks writing profile.json without preconditions: ${result#FAIL:}"
    exit 2
    ;;
  OK)
    emit "pass" "all profile.json writers have non-empty preconditions"
    exit 0
    ;;
  *)
    emit "fail" "unexpected parser output: $result"
    exit 2
    ;;
esac
