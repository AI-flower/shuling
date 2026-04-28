#!/usr/bin/env bash
# Usage: fetch-metrics.sh <post_id> <note_id> [xsec_token]
# 调 xhs.sh detail，提取互动数据，写入 post_metrics 表，输出 JSON
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XHS="$SKILL_DIR/scripts/xhs.sh"
DB="$SKILL_DIR/scripts/db.sh"

POST_ID="${1:-}"
NOTE_ID="${2:-}"
XSEC="${3:-}"

if [ -z "$POST_ID" ] || [ -z "$NOTE_ID" ]; then
    echo '{"error": "usage: fetch-metrics.sh <post_id> <note_id> [xsec_token]"}' >&2
    exit 1
fi

if [ -n "$XSEC" ]; then
    DETAIL=$(bash "$XHS" detail "$NOTE_ID" "$XSEC")
else
    DETAIL=$(bash "$XHS" detail "$NOTE_ID")
fi

METRICS=$(echo "$DETAIL" | python3 << 'PYEOF'
import json, sys, re

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    data = {}

def find_interact(d):
    if isinstance(d, dict):
        if any(k in d for k in ("liked_count", "collected_count", "comment_count")):
            return d
        for v in d.values():
            r = find_interact(v)
            if r:
                return r
    elif isinstance(d, list):
        for v in d:
            r = find_interact(v)
            if r:
                return r
    return None

interact = find_interact(data) or {}

def to_int(v):
    try:
        return int(str(v).replace(",", "")) if v not in (None, "") else 0
    except (ValueError, TypeError):
        return 0

result = {
    "likes": to_int(interact.get("liked_count")),
    "saves": to_int(interact.get("collected_count") or interact.get("saved_count")),
    "comments": to_int(interact.get("comment_count")),
    "shares": to_int(interact.get("share_count")),
}

if all(v == 0 for v in result.values()):
    for key, pat in [
        ("likes", r'"liked_count":\s*"?(\d+)"?'),
        ("saves", r'"collected_count":\s*"?(\d+)"?'),
        ("comments", r'"comment_count":\s*"?(\d+)"?'),
        ("shares", r'"share_count":\s*"?(\d+)"?'),
    ]:
        m = re.search(pat, raw)
        if m:
            result[key] = int(m.group(1))

print(json.dumps(result, ensure_ascii=False))
PYEOF
)

LIKES=$(echo "$METRICS" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("likes",0))')
SAVES=$(echo "$METRICS" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("saves",0))')
COMMENTS=$(echo "$METRICS" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("comments",0))')
SHARES=$(echo "$METRICS" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("shares",0))')

bash "$DB" add-metrics "{\"post_id\":$POST_ID,\"likes\":$LIKES,\"saves\":$SAVES,\"comments\":$COMMENTS,\"shares\":$SHARES,\"checkpoint\":\"daily\"}" >/dev/null

echo "{\"post_id\":$POST_ID,\"note_id\":\"$NOTE_ID\",\"likes\":$LIKES,\"saves\":$SAVES,\"comments\":$COMMENTS,\"shares\":$SHARES}"
