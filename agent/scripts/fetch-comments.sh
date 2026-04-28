#!/usr/bin/env bash
# Usage: fetch-comments.sh <note_id> [xsec_token] [--limit N]
# 输出过滤后的评论 JSON 数组：[{"author":"X","text":"Y","like_count":N}]
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XHS="$SKILL_DIR/scripts/xhs.sh"

NOTE_ID="${1:-}"
XSEC=""
LIMIT=50

shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --limit) shift; LIMIT="${1:-50}"; shift ;;
        *) if [ -z "$XSEC" ]; then XSEC="$1"; fi; shift ;;
    esac
done

if [ -z "$NOTE_ID" ]; then
    echo '{"error": "usage: fetch-comments.sh <note_id> [xsec_token] [--limit N]"}' >&2
    exit 1
fi

if [ -n "$XSEC" ]; then
    DETAIL=$(bash "$XHS" detail "$NOTE_ID" "$XSEC")
else
    DETAIL=$(bash "$XHS" detail "$NOTE_ID")
fi

DETAIL="$DETAIL" LIMIT="$LIMIT" python3 << 'PYEOF'
import json, os, re, sys

raw = os.environ.get("DETAIL", "")
limit = int(os.environ.get("LIMIT", "50"))

try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("[]")
    sys.exit(0)

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

raw_comments = find_comments(data)

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
for c in raw_comments:
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

print(json.dumps(cleaned, ensure_ascii=False))
PYEOF
