#!/usr/bin/env bash
# build/check-version-sync.sh — 验证 SKILL.md frontmatter version == VERSION
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ver_file="$(grep -m1 '^version:' "$REPO/VERSION" | awk -F'"' '{print $2}' | tr -d ' ')"
ver_skill="$(grep -m1 '^version:' "$REPO/SKILL.md" | awk -F: '{print $2}' | tr -d ' ')"

if [ "$ver_file" = "$ver_skill" ]; then
    echo "{\"status\":\"ok\",\"version\":\"$ver_file\"}"
    exit 0
else
    echo "{\"status\":\"fail\",\"version_file\":\"$ver_file\",\"version_skill\":\"$ver_skill\"}"
    exit 1
fi
