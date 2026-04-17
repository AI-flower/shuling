#!/usr/bin/env bash
# Usage: noterx-diagnose.sh <post_id> <title> [--content TEXT] [--tags "a,b,c"]
#                          [--category tech|food|...] [--image-count N] [--full]
# 调 NoteRx API 评分并写 note_diagnosis 表，输出 JSON 摘要
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DB="$SKILL_DIR/scripts/db.sh"
RUNTIME_ENV="$SKILL_DIR/config/runtime.env"
[ -f "$RUNTIME_ENV" ] && set -a && . "$RUNTIME_ENV" && set +a || true

NOTERX_API_URL="${NOTERX_API_URL:-https://noterx.muran.tech}"
NOTERX_TIMEOUT_PRE="${NOTERX_TIMEOUT_PRE:-15}"
NOTERX_TIMEOUT_FULL="${NOTERX_TIMEOUT_FULL:-150}"

POST_ID="${1:-}"
TITLE="${2:-}"
CONTENT=""
TAGS=""
CATEGORY="lifestyle"
IMAGE_COUNT=0
FULL=0

shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do
    case "$1" in
        --content)     shift; CONTENT="${1:-}"; shift ;;
        --tags)        shift; TAGS="${1:-}"; shift ;;
        --category)    shift; CATEGORY="${1:-lifestyle}"; shift ;;
        --image-count) shift; IMAGE_COUNT="${1:-0}"; shift ;;
        --full)        FULL=1; shift ;;
        --test)        POST_ID="0"; TITLE="测试标题"; CONTENT="测试内容"; CATEGORY="tech"; shift ;;
        *) shift ;;
    esac
done

if [ -z "$POST_ID" ] || [ -z "$TITLE" ]; then
    echo '{"error": "usage: noterx-diagnose.sh <post_id> <title> [--content T] [--tags a,b] [--category tech] [--image-count N] [--full]"}' >&2
    exit 1
fi

PRE_RESPONSE=$(curl -s --max-time "$NOTERX_TIMEOUT_PRE" \
    -X POST "$NOTERX_API_URL/api/pre-score" \
    --data-urlencode "title=$TITLE" \
    --data-urlencode "content=$CONTENT" \
    --data-urlencode "category=$CATEGORY" \
    --data-urlencode "tags=$TAGS" \
    --data-urlencode "image_count=$IMAGE_COUNT" 2>&1) || {
    echo "{\"error\": \"NoteRx pre-score 调用失败: $PRE_RESPONSE\"}" >&2
    exit 2
}

RESULT=$(PRE_RESPONSE="$PRE_RESPONSE" python3 << 'PYEOF'
import json, os, sys
raw = os.environ["PRE_RESPONSE"]
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print(json.dumps({"error": "pre-score 返回非 JSON", "raw": raw[:200]}))
    sys.exit(0)

total = data.get("total_score", 0)
dims = data.get("dimensions", {}) or {}

def grade(s):
    if s >= 90: return "S"
    if s >= 75: return "A"
    if s >= 60: return "B"
    if s >= 40: return "C"
    return "D"

print(json.dumps({
    "source": "noterx-pre",
    "overall_score": total,
    "grade": grade(total),
    "content_score": dims.get("content_quality", 0),
    "visual_score": dims.get("visual_quality", 0),
    "growth_score": dims.get("tag_strategy", 0),
    "user_reaction_score": dims.get("engagement_potential", 0),
    "issues": [],
    "suggestions": [],
}, ensure_ascii=False))
PYEOF
)

if [ "$FULL" = "1" ]; then
    FULL_RESPONSE=$(curl -s --max-time "$NOTERX_TIMEOUT_FULL" \
        -X POST "$NOTERX_API_URL/api/diagnose" \
        --data-urlencode "title=$TITLE" \
        --data-urlencode "content=$CONTENT" \
        --data-urlencode "category=$CATEGORY" \
        --data-urlencode "tags=$TAGS" 2>&1) || FULL_RESPONSE=""

    if [ -n "$FULL_RESPONSE" ]; then
        RESULT=$(RESULT="$RESULT" FULL_RESPONSE="$FULL_RESPONSE" python3 << 'PYEOF'
import json, os, sys
pre = json.loads(os.environ["RESULT"])
try:
    diag = json.loads(os.environ["FULL_RESPONSE"])
except json.JSONDecodeError:
    print(json.dumps(pre, ensure_ascii=False))
    sys.exit(0)

radar = diag.get("radar_data", {}) or {}
issues = []
for it in diag.get("issues", []) or []:
    if isinstance(it, dict):
        d = it.get("description", "")
        a = it.get("from_agent", "")
        if d:
            issues.append(f"[{a}] {d}".strip() if a else d)
    elif isinstance(it, str):
        issues.append(it)

suggestions = []
for sg in diag.get("suggestions", []) or []:
    if isinstance(sg, dict):
        d = sg.get("description", "")
        imp = sg.get("expected_impact", "")
        if d:
            suggestions.append(f"{d}（预期: {imp}）" if imp else d)
    elif isinstance(sg, str):
        suggestions.append(sg)

merged = {
    "source": "noterx-full",
    "overall_score": diag.get("overall_score", pre["overall_score"]),
    "grade": diag.get("grade", pre["grade"]),
    "content_score": radar.get("content", pre["content_score"]),
    "visual_score": radar.get("visual", pre["visual_score"]),
    "growth_score": radar.get("growth", pre["growth_score"]),
    "user_reaction_score": radar.get("user_reaction", pre["user_reaction_score"]),
    "issues": issues,
    "suggestions": suggestions,
    "debate_summary": diag.get("debate_summary", ""),
}
print(json.dumps(merged, ensure_ascii=False))
PYEOF
)
    fi
fi

if [ "$POST_ID" = "0" ]; then
    echo "$RESULT"
    exit 0
fi

DB_PAYLOAD=$(RESULT="$RESULT" POST_ID="$POST_ID" python3 << 'PYEOF'
import json, os
r = json.loads(os.environ["RESULT"])
print(json.dumps({
    "post_id": int(os.environ["POST_ID"]),
    "source": r["source"],
    "overall_score": r["overall_score"],
    "grade": r["grade"],
    "content_score": r["content_score"],
    "visual_score": r["visual_score"],
    "growth_score": r["growth_score"],
    "user_reaction_score": r["user_reaction_score"],
    "issues": json.dumps(r.get("issues", []), ensure_ascii=False),
    "suggestions": json.dumps(r.get("suggestions", []), ensure_ascii=False),
}, ensure_ascii=False))
PYEOF
)

bash "$DB" add-diagnosis "$DB_PAYLOAD" >/dev/null
echo "$RESULT"
