#!/usr/bin/env bash
# Migration for v2.1.3 "Friendly Onboarding" —— 无 DB 迁移
# 新增内容全部在文档与脚本层:
#   - install.sh 支持 --check / --dry-run / --yes / --target
#   - scripts/preflight.py 支持 --human / --json
#   - docs/mcp-setup.md 重写（一键安装 + cookie 图文指引）
#   - schemas/ 新增 state/profile/preferences JSON Schema
#   - SKILL.md 新增 §0b 识别平台 + 写入前校验 schema
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/migrations/_guard.sh"

if already_applied "2.1.3"; then
    echo '{"status":"skipped","reason":"already_applied","version":"2.1.3"}'
    exit 0
fi

mark_applied "2.1.3"
echo '{"status":"ok","reason":"no_schema_change","version":"2.1.3"}'
