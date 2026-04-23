#!/usr/bin/env bash
# v2.3.0 upgrade hook: 把 ~/.hermes/cron/jobs.json 里 "HTML 截图" 替换成 "Gemini 生图"
# 幂等：文件不存在 skip / 语义层无匹配 skip / 有则备份后替换
# target_path 仅用于日志，实际改 ~/.hermes/cron/jobs.json

set -e

TARGET_PATH="${1:-}"
if [ -z "$TARGET_PATH" ] || [ ! -d "$TARGET_PATH" ]; then
    echo '{"status":"failed","detail":"target_path required or not a directory"}'
    exit 1
fi

JOBS_FILE="$HOME/.hermes/cron/jobs.json"

if [ ! -f "$JOBS_FILE" ]; then
    echo "{\"status\":\"skipped\",\"reason\":\"no hermes jobs.json at $JOBS_FILE\",\"target\":\"$TARGET_PATH\"}"
    exit 0
fi

# 校验 JSON
if ! jq empty "$JOBS_FILE" >/dev/null 2>&1; then
    echo "{\"status\":\"failed\",\"detail\":\"jobs.json is not valid JSON, refusing to touch\",\"target\":\"$TARGET_PATH\"}"
    exit 1
fi

# ─── 用 python 探测（解析 JSON 后在字符串值里查，避免 unicode 转义与 grep 的反斜杠陷阱）
has_match=$(python3 - "$JOBS_FILE" << 'PY_EOF'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)

def walk(x):
    if isinstance(x, dict):
        for v in x.values():
            if walk(v):
                return True
    elif isinstance(x, list):
        for v in x:
            if walk(v):
                return True
    elif isinstance(x, str):
        if 'HTML 截图' in x or 'HTML截图' in x:
            return True
    return False

print('yes' if walk(data) else 'no')
PY_EOF
)

if [ "$has_match" != "yes" ]; then
    echo "{\"status\":\"skipped\",\"reason\":\"no 'HTML 截图' occurrence in jobs.json\",\"target\":\"$TARGET_PATH\"}"
    exit 0
fi

# ─── 备份 ─────────────────────────────────────────────────
TS=$(date +%Y%m%d-%H%M%S)
BACKUP="${JOBS_FILE}.bak-v2.3.0-${TS}"
cp "$JOBS_FILE" "$BACKUP"

# ─── 解析 → 替换 → 写回（保持源文件原 ensure_ascii 风格：探测一下）
TMP="${JOBS_FILE}.tmp.$$"

python3 - "$JOBS_FILE" "$TMP" << 'PY_EOF'
import json, sys
src, dst = sys.argv[1], sys.argv[2]

# 探测原文件是否使用 ensure_ascii（unicode 转义）
with open(src, 'r', encoding='utf-8') as f:
    raw = f.read()
# 如果原文件里有 "\u" 序列（典型 ensure_ascii=True 输出），写回也用同样格式
use_ensure_ascii = '\\u' in raw

data = json.loads(raw)

def walk(x):
    if isinstance(x, dict):
        return {k: walk(v) for k, v in x.items()}
    if isinstance(x, list):
        return [walk(v) for v in x]
    if isinstance(x, str):
        return (x
                .replace('HTML 截图', 'Gemini 生图')
                .replace('HTML截图', 'Gemini 生图'))
    return x

with open(dst, 'w', encoding='utf-8') as f:
    json.dump(walk(data), f, ensure_ascii=use_ensure_ascii, indent=2)
PY_EOF

# ─── 校验新文件仍是 JSON ───────────────────────────────────
if ! jq empty "$TMP" >/dev/null 2>&1; then
    rm -f "$TMP"
    echo "{\"status\":\"failed\",\"detail\":\"rewrite produced invalid JSON, backup kept at $BACKUP\",\"target\":\"$TARGET_PATH\"}"
    exit 1
fi

# ─── 再次用 python 验证已无残留 ───────────────────────────
still=$(python3 - "$TMP" << 'PY_EOF'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)

def walk(x):
    if isinstance(x, dict):
        for v in x.values():
            if walk(v):
                return True
    elif isinstance(x, list):
        for v in x:
            if walk(v):
                return True
    elif isinstance(x, str):
        if 'HTML 截图' in x or 'HTML截图' in x:
            return True
    return False

print('yes' if walk(data) else 'no')
PY_EOF
)

if [ "$still" = "yes" ]; then
    rm -f "$TMP"
    echo "{\"status\":\"failed\",\"detail\":\"replacement incomplete, backup kept at $BACKUP\",\"target\":\"$TARGET_PATH\"}"
    exit 1
fi

mv "$TMP" "$JOBS_FILE"

echo "{\"status\":\"ok\",\"detail\":\"replaced 'HTML 截图' -> 'Gemini 生图' in jobs.json, backup: $BACKUP\",\"target\":\"$TARGET_PATH\"}"
