#!/usr/bin/env bash
# ops/verify/checks/28-playbook-graph-no-cycle.sh — playbook 调用图无环
# severity: error
#
# 解析每个 playbook frontmatter 的 calls.playbooks 字段，构造有向图，DFS 检测环。
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="28-playbook-graph-no-cycle"
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
import os, re, sys, json

playbook_dir = sys.argv[1]
graph = {}

for fn in sorted(os.listdir(playbook_dir)):
    if not re.match(r'^[0-9][0-9].*\.md$', fn):
        continue
    path = os.path.join(playbook_dir, fn)
    try:
        with open(path, 'r', encoding='utf-8') as f:
            text = f.read()
    except Exception as e:
        print("READERR:" + fn + ":" + str(e))
        sys.exit(2)
    if not text.startswith('---'):
        continue
    end = text.find('\n---', 3)
    if end < 0:
        continue
    fm = text[3:end]

    # 找 calls: 块下的 playbooks: 数组
    targets = []
    in_calls = False
    in_playbooks = False
    for line in fm.split('\n'):
        if re.match(r'^calls:\s*$', line):
            in_calls = True
            in_playbooks = False
            continue
        if in_calls:
            # 退出 calls 的条件：非缩进的下一个顶级 key
            if re.match(r'^[A-Za-z0-9_-]+:', line):
                in_calls = False
                in_playbooks = False
                continue
            if re.match(r'^\s+playbooks:\s*$', line):
                in_playbooks = True
                continue
            if in_playbooks:
                m = re.match(r'^\s+-\s+(.+?)\s*$', line)
                if m:
                    t = m.group(1).strip().strip('"').strip("'")
                    targets.append(t)
                else:
                    # 子段结束
                    if re.match(r'^\s+[A-Za-z0-9_-]+:', line):
                        in_playbooks = False
    graph[fn] = targets

# DFS 检测环
WHITE, GRAY, BLACK = 0, 1, 2
state = {n: WHITE for n in graph}
cycle_path = []

def dfs(node, stack):
    state[node] = GRAY
    stack.append(node)
    for nb in graph.get(node, []):
        # 解析为 graph 的 key（可能写成 "04-publish-flow.md" 或 "agent/playbook/04-..."）
        target = os.path.basename(nb)
        if target not in graph:
            continue
        if state[target] == GRAY:
            # cycle
            idx = stack.index(target)
            return stack[idx:] + [target]
        if state[target] == WHITE:
            r = dfs(target, stack)
            if r:
                return r
    stack.pop()
    state[node] = BLACK
    return None

for n in list(graph.keys()):
    if state[n] == WHITE:
        c = dfs(n, [])
        if c:
            print("CYCLE:" + " -> ".join(c))
            sys.exit(0)

print("OK:" + str(len(graph)))
PY
)"
rc=$?

if [ "$rc" -ne 0 ]; then
  emit "fail" "python3 parser error: $result"
  exit 2
fi

case "$result" in
  CYCLE:*)
    emit "fail" "playbook call graph has cycle: ${result#CYCLE:}"
    exit 2
    ;;
  OK:*)
    n="${result#OK:}"
    emit "pass" "playbook call graph (${n} nodes) is acyclic"
    exit 0
    ;;
  *)
    emit "fail" "unexpected parser output: $result"
    exit 2
    ;;
esac
