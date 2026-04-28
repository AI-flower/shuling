#!/usr/bin/env bash
# ops/verify/checks/40-no-cookie-in-docs-or-logs.sh — 文档 / playbook / README 不含真实 cookie 或 API key
# severity: error
set -uo pipefail

CHECK_NAME="40-no-cookie-in-docs-or-logs"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

# 扫描范围
scan_dirs=("$ROOT/docs" "$ROOT/agent/playbook")
scan_files=("$ROOT/README.md" "$ROOT/UPGRADE.md" "$ROOT/CHANGELOG.md")

# 放行文件（占位符文件）
allowlist_files=(
    "$ROOT/agent/config/runtime.env.example"
)

# 收集要扫描的文件
declare -a files_to_scan=()
for d in "${scan_dirs[@]}"; do
    if [ -d "$d" ]; then
        while IFS= read -r f; do
            [ -f "$f" ] && files_to_scan+=("$f")
        done < <(find "$d" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) 2>/dev/null)
    fi
done
for f in "${scan_files[@]}"; do
    [ -f "$f" ] && files_to_scan+=("$f")
done

if [ ${#files_to_scan[@]} -eq 0 ]; then
    emit "pass" "no files to scan"
    exit 0
fi

# 真实 secret 检测模式（长度够长才算真实）
# 用 python3 做检测以便精确控制长度
violations=()
for f in "${files_to_scan[@]}"; do
    # 跳过放行文件
    skip=0
    for allow in "${allowlist_files[@]}"; do
        [ "$f" = "$allow" ] && skip=1 && break
    done
    [ "$skip" = "1" ] && continue

    result=$(python3 - "$f" << 'PYEOF'
import re, sys

path = sys.argv[1]
try:
    with open(path, errors='replace') as fh:
        content = fh.read()
except Exception:
    sys.exit(0)

# 放行占位符
placeholder = re.compile(r'x{10,}|your[_-]?api[_-]?key|<your[_\-]key>|your-api-key-here|PLACEHOLDER', re.IGNORECASE)

patterns = [
    (r'web_session=([A-Za-z0-9%_\-\.]{40,})', 40),
    (r'xsec_token=([A-Za-z0-9%_\-\.]{40,})', 40),
    (r'\ba1=([A-Za-z0-9%_\-\.]{40,})', 40),
    (r'webId=([A-Za-z0-9%_\-\.]{30,})', 30),
    (r'Cookie:\s*([^\n]{80,})', 80),
    (r'(sk-[A-Za-z0-9]{30,})', 30),
    (r'(AIza[A-Za-z0-9_\-]{30,})', 30),
]

hits = []
for pat, minlen in patterns:
    for m in re.finditer(pat, content):
        val = m.group(1) if m.lastindex else m.group(0)
        if len(val) >= minlen and not placeholder.search(val):
            hits.append(f"{pat[:30]}… at char {m.start()}")

if hits:
    print('\n'.join(hits[:3]))
PYEOF
)
    if [ -n "$result" ]; then
        rel="${f#$ROOT/}"
        violations+=("${rel}: ${result}")
    fi
done

if [ ${#violations[@]} -gt 0 ]; then
    msg="potential secrets in docs: ${violations[*]}"
    emit "fail" "${msg:0:400}"
    exit 2
fi

emit "pass" "no real cookies or API keys found in docs/playbook/README"
exit 0
