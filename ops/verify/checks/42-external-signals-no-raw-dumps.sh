#!/usr/bin/env bash
# ops/verify/checks/42-external-signals-no-raw-dumps.sh — external-signals JSON 不含原始转储字段且 ≤50KB
# severity: error
set -uo pipefail

CHECK_NAME="42-external-signals-no-raw-dumps"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

signals_dir="$ROOT/agent/knowledge-base/external-signals"

if [ ! -d "$signals_dir" ]; then
    # 目录不存在 — 合理（运行时创建），pass
    emit "pass" "external-signals directory not found (expected for clean install)"
    exit 0
fi

# 收集 JSON 文件
declare -a json_files=()
while IFS= read -r f; do
    [ -f "$f" ] && json_files+=("$f")
done < <(find "$signals_dir" -maxdepth 2 -name "*.json" 2>/dev/null)

if [ ${#json_files[@]} -eq 0 ]; then
    emit "pass" "external-signals contain no raw dumps (directory empty)"
    exit 0
fi

for f in "${json_files[@]}"; do
    # 文件大小检查
    size=$(wc -c < "$f" 2>/dev/null || echo 0)
    if [ "$size" -gt 51200 ]; then
        rel="${f#$ROOT/}"
        emit "fail" "external-signals file too large (${size} bytes > 50KB): ${rel}"
        exit 2
    fi

    # 禁止字段检查
    result=$(python3 - "$f" << 'PYEOF'
import json, sys

path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception as e:
    print(f"PARSE_ERROR: {e}")
    sys.exit(1)

banned = {'full_body', 'raw_comments', 'full_comments', 'raw_post_body', 'note_body', 'raw_html'}

def walk(obj, depth=0):
    if depth > 20:
        return
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in banned:
                print(f"BANNED_FIELD: {k}")
                return
            walk(v, depth + 1)
    elif isinstance(obj, list):
        for x in obj:
            walk(x, depth + 1)

walk(data)
PYEOF
)
    check_rc=$?
    if [ "$check_rc" -ne 0 ] || echo "$result" | grep -q "^BANNED_FIELD:\|^PARSE_ERROR:"; then
        rel="${f#$ROOT/}"
        emit "fail" "banned field or parse error in ${rel}: ${result:0:200}"
        exit 2
    fi
done

emit "pass" "external-signals contain no raw dumps (${#json_files[@]} files checked)"
exit 0
