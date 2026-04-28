#!/usr/bin/env bash
# Usage: fetch-post-data.sh <post_id> <note_id> [xsec_token] [--limit N] [--no-db]
# 合并版：单次 detail 调用同时提取 metrics + comments
# 替代原 fetch-metrics.sh + fetch-comments.sh 两次独立调用，HTTP 流量减半
#
# 输出 JSON:
# {
#   "post_id": 123,
#   "note_id": "...",
#   "metrics": {"likes":0, "saves":0, "comments":0, "shares":0},
#   "comments": [{"author":"X","text":"Y","like_count":N}, ...]
# }

set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XHS="$SKILL_DIR/scripts/xhs.sh"
DB="$SKILL_DIR/scripts/db.sh"

POST_ID="${1:-}"
NOTE_ID="${2:-}"
XSEC=""
LIMIT=50
SKIP_DB=0

if [ -z "$POST_ID" ] || [ -z "$NOTE_ID" ]; then
    echo '{"error": "usage: fetch-post-data.sh <post_id> <note_id> [xsec_token] [--limit N] [--no-db]"}' >&2
    exit 1
fi

shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --limit)  shift; LIMIT="${1:-50}"; shift ;;
        --no-db)  SKIP_DB=1; shift ;;
        *)        if [ -z "$XSEC" ]; then XSEC="$1"; fi; shift ;;
    esac
done

# 单次 detail 调用
if [ -n "$XSEC" ]; then
    DETAIL=$(bash "$XHS" detail "$NOTE_ID" "$XSEC")
else
    DETAIL=$(bash "$XHS" detail "$NOTE_ID")
fi

# 一次 Python 同时提取 metrics + comments
RESULT=$(DETAIL="$DETAIL" LIMIT="$LIMIT" python3 << 'PYEOF'
import json, os, re, sys

raw = os.environ.get("DETAIL", "")
limit = int(os.environ.get("LIMIT", "50"))

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

def find_comments(d):
    if isinstance(d, dict):
        for k in ("comments", "comment_list"):
            if k in d and isinstance(d[k], list):
                return d[k]
        for v in d.values():
            r = find_comments(v)
            if r:
                return r
    elif isinstance(d, list):
        for v in d:
            r = find_comments(v)
            if r:
                return r
    return []

def to_int(v):
    try:
        return int(str(v).replace(",", "")) if v not in (None, "") else 0
    except (ValueError, TypeError):
        return 0

interact = find_interact(data) or {}
metrics = {
    "likes": to_int(interact.get("liked_count")),
    "saves": to_int(interact.get("collected_count") or interact.get("saved_count")),
    "comments": to_int(interact.get("comment_count")),
    "shares": to_int(interact.get("share_count")),
}

# 正则兜底（结构变化时）
if all(v == 0 for v in metrics.values()):
    for key, pat in [
        ("likes", r'"liked_count":\s*"?(\d+)"?'),
        ("saves", r'"collected_count":\s*"?(\d+)"?'),
        ("comments", r'"comment_count":\s*"?(\d+)"?'),
        ("shares", r'"share_count":\s*"?(\d+)"?'),
    ]:
        m = re.search(pat, raw)
        if m:
            metrics[key] = int(m.group(1))

SPAM_KEYWORDS = ["加微", "加V", "加v", "私聊", "免费领", "点击链接", "http", "扫码"]
EMOJI_ONLY = re.compile(r"^[\W_\d\s]*$", re.UNICODE)

def is_spam(text):
    t = (text or "").strip()
    if len(t) <= 2:
        return True
    if EMOJI_ONLY.match(t):
        return True
    return any(k in t for k in SPAM_KEYWORDS)

cleaned = []
for c in find_comments(data):
    if not isinstance(c, dict):
        continue
    text = c.get("content") or c.get("text") or ""
    if is_spam(text):
        continue
    author = ""
    if isinstance(c.get("user"), dict):
        author = c["user"].get("nickname") or c["user"].get("name") or ""
    author = author or c.get("nickname", "")
    cleaned.append({
        "author": author,
        "text": text,
        "like_count": int(c.get("liked_count") or c.get("like_count") or 0),
    })
    if len(cleaned) >= limit:
        break

print(json.dumps({"metrics": metrics, "comments": cleaned}, ensure_ascii=False))
PYEOF
)

# 写入 post_metrics 表
if [ "$SKIP_DB" = "0" ]; then
    METRICS_PAYLOAD=$(RESULT="$RESULT" POST_ID="$POST_ID" python3 <<'PYEOF'
import json, os
r = json.loads(os.environ["RESULT"])
m = dict(r["metrics"])
m["post_id"] = int(os.environ["POST_ID"])
m["checkpoint"] = "daily"
print(json.dumps(m, ensure_ascii=False))
PYEOF
)
    bash "$DB" add-metrics "$METRICS_PAYLOAD" >/dev/null
fi

# 输出合并结果
RESULT="$RESULT" POST_ID="$POST_ID" NOTE_ID="$NOTE_ID" python3 <<'PYEOF'
import json, os
r = json.loads(os.environ["RESULT"])
out = {
    "post_id": int(os.environ["POST_ID"]),
    "note_id": os.environ["NOTE_ID"],
    "metrics": r["metrics"],
    "comments": r["comments"],
}
print(json.dumps(out, ensure_ascii=False))
PYEOF
