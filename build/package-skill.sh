#!/usr/bin/env bash
# build/package-skill.sh — 打包 v3.0 skill 包到 dist/shuling-agent-skill/
#
# 白名单：只包含 SKILL.md / VERSION / agent/
# 排除：agent/data/*.db / agent/config/runtime.env / agent/knowledge-base/*.json|*.md
#       __pycache__ / *.bak.* / .DS_Store

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO/dist/shuling-agent-skill"

rm -rf "$DIST"
mkdir -p "$DIST"

rsync -a \
    --exclude '__pycache__' \
    --exclude '*.bak.*' \
    --exclude '.DS_Store' \
    --exclude 'agent/data/*.db' \
    --exclude 'agent/data/*.db-shm' \
    --exclude 'agent/data/*.db-wal' \
    --exclude 'agent/data/*.db-journal' \
    --exclude 'agent/data/.schema-degraded.lock' \
    --exclude 'agent/config/runtime.env' \
    --exclude 'agent/config/state.json' \
    --exclude 'agent/config/.layout-v3.done' \
    --exclude 'agent/knowledge-base/profile.json' \
    --exclude 'agent/knowledge-base/preferences.json' \
    --exclude 'agent/knowledge-base/patterns.md' \
    --exclude 'agent/knowledge-base/anti-patterns.md' \
    --exclude 'agent/knowledge-base/image-patterns.md' \
    --exclude 'agent/knowledge-base/image-anti-patterns.md' \
    --exclude 'agent/knowledge-base/evolution-log.md' \
    --exclude 'agent/knowledge-base/reviews' \
    --exclude 'agent/knowledge-base/audit-*' \
    "$REPO/SKILL.md" "$REPO/VERSION" "$REPO/agent" \
    "$DIST/"

echo "{\"status\":\"ok\",\"dist\":\"$DIST\",\"size\":\"$(du -sk "$DIST" | awk '{print $1}')k\"}"
