#!/usr/bin/env bash
# build/check-package.sh — 验证 dist/ 包符合白名单
#
# 用法：bash build/check-package.sh [DIST_DIR]
#   默认 dist/shuling-agent-skill

set -euo pipefail

DIST="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dist/shuling-agent-skill}"

if [ ! -d "$DIST" ]; then
    echo '{"status":"fail","reason":"dist not found","dist":"'"$DIST"'"}'
    exit 1
fi

# 检查只含 3 个顶级条目（agents/ 在 v3.0 清理时已删，未来 v3.x 多平台时可恢复）
declare -a allowed=("SKILL.md" "VERSION" "agent")
errors=0

for entry in "$DIST"/*; do
    name="$(basename "$entry")"
    found=0
    for a in "${allowed[@]}"; do
        [ "$name" = "$a" ] && found=1
    done
    if [ "$found" = "0" ]; then
        echo "  unexpected top-level: $name" >&2
        errors=$((errors+1))
    fi
done

# 检查不含禁止文件
forbidden=$(find "$DIST" \( \
    -name '*.db' -o \
    -name 'runtime.env' -o \
    -name 'state.json' -o \
    -name '.layout-v3.done' -o \
    -name 'profile.json' -o \
    -name 'preferences.json' -o \
    -name '__pycache__' -o \
    -name '.DS_Store' \
\) 2>/dev/null | wc -l | tr -d ' ')

# 检查不含 inactive 顶级目录
for d in docs site marketing legacy ops build dist; do
    if [ -d "$DIST/$d" ]; then
        echo "  forbidden inactive dir: $d" >&2
        errors=$((errors+1))
    fi
done

if [ "$errors" -gt 0 ] || [ "$forbidden" -gt 0 ]; then
    echo "{\"status\":\"fail\",\"errors\":$errors,\"forbidden_files\":$forbidden}"
    exit 1
fi

echo "{\"status\":\"ok\",\"dist\":\"$DIST\",\"top_level_files\":$(ls -1 "$DIST" | wc -l | tr -d ' ')}"
exit 0
