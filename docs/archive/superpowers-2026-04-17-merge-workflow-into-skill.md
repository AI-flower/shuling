---
title: 薯灵 workflow 合并进 skill 实施计划
status: archived
moved_from: docs/superpowers/plans/2026-04-17-merge-workflow-into-skill.md
moved_at: 2026-04-23
original_date: 2026-04-17
archive_reason: completed
checkbox_count: 63
---

> **归档说明**（2026-04-23 v2.4.0 docs 重组）：
> 本文档已归档。原因：completed — workflow 双线已合并入 skill 主体，v2.1-v2.3 已完成收敛。
> 如需了解当前状态请参阅：`CHANGELOG.md` v2.1-v2.3 条目与根目录 `SKILL.md`。
>
> **Checkbox 状态 reconcile**：本 plan 含 63 个未勾 checkbox，2026-04-23 归档时统一判定"不再追踪"。已落地部分归入 v2.0-v2.3 实际发版（见 `CHANGELOG.md`），未落地部分若仍需要将另开新 plan。

---

# 薯灵 workflow 合并进 skill 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `workflow/xhs-automation/` 的"自动化定时 + NoteRx 诊断 + 知识库进化"能力收回到 skill 主体，删除双线，最终只剩"AI 助手 + SKILL.md + scripts/" 一条路。

**Architecture:**
- Skill-as-Brain：所有分析/决策都由 AI 助手在读 SKILL.md 后做，不再由 Python 脚本调 LLM 自我闭环。
- 脚本只做"手脚"：`scripts/fetch-metrics.sh`、`scripts/fetch-comments.sh`、`scripts/noterx-diagnose.sh` 三个新脚本封装外部数据获取与 DB 写入，分析全交给助手。
- 触发解耦：hermes cron 不再跑 Python，而是定时唤起 AI 助手让它读 SKILL.md 跑某段流程。

**Tech Stack:** bash, sqlite3, Python 3（仅 preflight + image），curl（NoteRx HTTP），AI 助手（hermes/claude code/codex）

---

## File Structure（合并后的目录）

```
shuling/
├── SKILL.md                          # 大脑剧本，第 3 节扩展为含 NoteRx 的每日复盘，第 4 节简化周回顾
├── install.sh                        # 删除所有 workflow 引用
├── README.md                         # 重写为单一架构
├── .gitignore                        # 不变
├── config/
│   └── runtime.env.example           # 新建（替代 workflow 那份）：MCP_URL + 可选 NOTERX_* + IMAGE_GEN_*
├── scripts/
│   ├── preflight.py                  # 不变
│   ├── db.sh                         # 扩展：加 note_diagnosis、generated_images 表 + 相关命令
│   ├── xhs.sh                        # 不变
│   ├── image.py                      # 不变
│   ├── screenshot.cjs                # 不变
│   ├── fetch-metrics.sh              # 新建：调 xhs.sh detail，提取互动数，写 post_metrics
│   ├── fetch-comments.sh             # 新建：调 xhs.sh detail，提取评论原文，过滤 spam，输出 JSON
│   └── noterx-diagnose.sh            # 新建：curl 调 noterx.muran.tech，写 note_diagnosis
├── data/
│   └── content-rules.md              # 不变
├── knowledge-base/                   # 运行时生成（gitignore 已屏蔽）
├── templates/
│   └── post.html                     # 不变
└── platform/
    ├── hermes.md                     # 修改：cron 用法改为唤起助手
    ├── claude-code.md                # 不变
    └── codex.md                      # 不变
```

**删除：** 整个 `workflow/xhs-automation/` 目录。

---

## 各 Stage 任务概览

- **Stage A（在 /tmp/shuling-src 远程副本上）**：Task 1-15 — 写代码、改文档、推 GitHub
- **Stage B（在 Mac 100.79.106.110）**：Task 16-18 — git pull、重装、hermes 端到端验证

---

### Task 1: 删除 workflow 目录

**Files:**
- Delete: `/tmp/shuling-src/workflow/`

- [ ] **Step 1: 物理删除 workflow 目录**

```bash
cd /tmp/shuling-src
rm -rf workflow/
```

- [ ] **Step 2: 验证已删除**

```bash
cd /tmp/shuling-src && ls workflow 2>&1
```

Expected: `ls: cannot access 'workflow': No such file or directory`

- [ ] **Step 3: git status 确认变更范围**

```bash
cd /tmp/shuling-src && git status --short | wc -l
```

Expected: 一堆 deleted 行，数量在 50 以内（workflow 下文件总数）

- [ ] **Step 4: 提交**

```bash
cd /tmp/shuling-src && git add -A && git commit -m "$(cat <<'EOF'
chore: 移除遗留 workflow 双线

workflow/xhs-automation/ 是早期独立后台脚本，与 skill 路线职责重叠
（自带 LLM 调用 + Telegram bot）。本次将其能力收回 skill 主体：
NoteRx 诊断、互动数据采集、评论分析等通过新增 scripts/ 工具实现，
分析逻辑全部交给 AI 助手按 SKILL.md 执行。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 扩展 db.sh —— 加 note_diagnosis 与 generated_images 表

**Files:**
- Modify: `/tmp/shuling-src/scripts/db.sh:60-122`（cmd_init 函数）
- Modify: `/tmp/shuling-src/scripts/db.sh:323-352`（dispatch + usage）

- [ ] **Step 1: 备份当前 db.sh**

```bash
cp /tmp/shuling-src/scripts/db.sh /tmp/shuling-src/scripts/db.sh.bak
```

- [ ] **Step 2: 在 cmd_init 的 SQL 末尾追加两张表**

打开 `/tmp/shuling-src/scripts/db.sh`，找到第 120 行附近 `comment_insights` 表定义之后、`"` 闭合之前，追加：

```sql
CREATE TABLE IF NOT EXISTS note_diagnosis (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER REFERENCES posts(id),
    diagnosed_at TEXT NOT NULL,
    source TEXT DEFAULT 'noterx-pre',
    overall_score REAL,
    grade TEXT,
    content_score REAL,
    visual_score REAL,
    growth_score REAL,
    user_reaction_score REAL,
    issues TEXT,
    suggestions TEXT,
    debate_summary TEXT,
    diagnosis_json TEXT
);

CREATE TABLE IF NOT EXISTS generated_images (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER REFERENCES posts(id),
    image_index INTEGER,
    prompt TEXT,
    image_path TEXT,
    gen_model TEXT,
    gen_strategy TEXT DEFAULT 'ai',
    gen_status TEXT DEFAULT 'pending',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

并把 echo 行从 `'{"ok": true, "tables": ["posts","post_metrics","user_choices","topic_candidates","comment_insights"]}'` 改成：

```bash
echo '{"ok": true, "tables": ["posts","post_metrics","user_choices","topic_candidates","comment_insights","note_diagnosis","generated_images"]}'
```

- [ ] **Step 3: 在 cmd_update_post_status 之后、`# ─── Main dispatch ───` 之前插入 cmd_add_diagnosis 函数**

```bash
cmd_add_diagnosis() {
    local json="$1"
    [ -z "$json" ] && { echo '{"error": "missing JSON argument"}' >&2; exit 1; }

    local post_id source overall grade c v g u issues suggestions
    post_id="$(json_val "$json" "post_id")"
    source="$(sql_escape "$(json_val "$json" "source")")"
    source="${source:-noterx-pre}"
    overall="$(json_val "$json" "overall_score")"
    grade="$(sql_escape "$(json_val "$json" "grade")")"
    c="$(json_val "$json" "content_score")"
    v="$(json_val "$json" "visual_score")"
    g="$(json_val "$json" "growth_score")"
    u="$(json_val "$json" "user_reaction_score")"
    issues="$(sql_escape "$(json_val "$json" "issues")")"
    suggestions="$(sql_escape "$(json_val "$json" "suggestions")")"

    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local new_id
    new_id="$(sql "
INSERT INTO note_diagnosis (post_id, diagnosed_at, source, overall_score, grade,
    content_score, visual_score, growth_score, user_reaction_score,
    issues, suggestions)
VALUES (${post_id:-0}, '$now', '$source', ${overall:-0}, '$grade',
    ${c:-0}, ${v:-0}, ${g:-0}, ${u:-0},
    '$issues', '$suggestions');
SELECT last_insert_rowid();
")"
    echo "{\"id\": $new_id}"
}

cmd_query_diagnosis() {
    local post_id=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --post-id) shift; post_id="$1"; shift ;;
            *) shift ;;
        esac
    done
    [ -z "$post_id" ] && { echo '{"error": "missing --post-id"}' >&2; exit 1; }
    sql_json "SELECT * FROM note_diagnosis WHERE post_id = $post_id ORDER BY diagnosed_at DESC LIMIT 1;"
}

cmd_query_undiagnosed() {
    local days=3
    while [ $# -gt 0 ]; do
        case "$1" in
            --days) shift; days="${1:-3}"; shift ;;
            *) shift ;;
        esac
    done
    sql_json "
SELECT p.id, p.date, p.slot, p.title, p.note_id
FROM posts p
LEFT JOIN note_diagnosis nd ON nd.post_id = p.id
WHERE p.status = 'published'
  AND p.note_id IS NOT NULL AND p.note_id != ''
  AND nd.id IS NULL
  AND p.date >= date('now', '-${days} days')
ORDER BY p.date DESC, p.id DESC;
"
}
```

- [ ] **Step 4: 在 case 分发表加入新命令**

把 `case "$cmd" in ... esac` 中加入：

```bash
    add-diagnosis)      cmd_add_diagnosis "$@" ;;
    query-diagnosis)    cmd_query_diagnosis "$@" ;;
    query-undiagnosed)  cmd_query_undiagnosed "$@" ;;
```

把 usage 帮助文本也对应加上 3 行：

```bash
        echo "  add-diagnosis '<json>'         Insert NoteRx diagnosis result"
        echo "  query-diagnosis --post-id N    Get latest diagnosis for a post"
        echo "  query-undiagnosed [--days N]   List published posts without diagnosis"
```

- [ ] **Step 5: 删除旧 db 重新初始化**

```bash
rm -f /tmp/shuling-src/data/xhs.db /tmp/shuling-src/data/xhs.db-shm /tmp/shuling-src/data/xhs.db-wal
bash /tmp/shuling-src/scripts/db.sh init
```

Expected:
```json
{"ok": true, "tables": ["posts","post_metrics","user_choices","topic_candidates","comment_insights","note_diagnosis","generated_images"]}
```

- [ ] **Step 6: 验证 schema**

```bash
sqlite3 /tmp/shuling-src/data/xhs.db ".tables"
```

Expected: `comment_insights  generated_images  note_diagnosis  post_metrics      posts             topic_candidates  user_choices`

```bash
sqlite3 /tmp/shuling-src/data/xhs.db ".schema note_diagnosis" | head -15
```

Expected: 看到 14 个字段（id, post_id, diagnosed_at, source, overall_score, grade, content_score, visual_score, growth_score, user_reaction_score, issues, suggestions, debate_summary, diagnosis_json）

- [ ] **Step 7: 端到端测试 add-diagnosis 命令**

```bash
bash /tmp/shuling-src/scripts/db.sh add-post '{"date":"2026-04-17","slot":"test","title":"测试","content":"X","tags":"[]","note_id":"test123","status":"published"}'
```

Expected: `{"id": 1}`

```bash
bash /tmp/shuling-src/scripts/db.sh add-diagnosis '{"post_id":1,"source":"noterx-pre","overall_score":78,"grade":"A","content_score":80,"visual_score":75,"growth_score":76,"user_reaction_score":82}'
```

Expected: `{"id": 1}`

```bash
bash /tmp/shuling-src/scripts/db.sh query-diagnosis --post-id 1
```

Expected: 返回包含 overall_score=78 的 JSON 行

```bash
bash /tmp/shuling-src/scripts/db.sh query-undiagnosed --days 7
```

Expected: `[]`（已诊断过）

- [ ] **Step 8: 清理测试数据 + 删备份**

```bash
rm -f /tmp/shuling-src/data/xhs.db /tmp/shuling-src/data/xhs.db-shm /tmp/shuling-src/data/xhs.db-wal /tmp/shuling-src/scripts/db.sh.bak
bash /tmp/shuling-src/scripts/db.sh init
```

- [ ] **Step 9: 提交**

```bash
cd /tmp/shuling-src && git add scripts/db.sh && git commit -m "$(cat <<'EOF'
feat(db): 加 note_diagnosis + generated_images 表与命令

新增表对应 NoteRx 诊断结果与图片生成历史。新增三个命令：
- add-diagnosis：写入诊断结果
- query-diagnosis：查某帖最新诊断
- query-undiagnosed：列出已发布但未诊断的帖子（供每日复盘批处理）

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 创建 scripts/fetch-metrics.sh

**Files:**
- Create: `/tmp/shuling-src/scripts/fetch-metrics.sh`

**职责：** 给定 post_id + note_id，调 `xhs.sh detail`，提取 likes/saves/comments/shares 四个数，写入 post_metrics 表。返回 JSON。

- [ ] **Step 1: 写脚本**

```bash
cat > /tmp/shuling-src/scripts/fetch-metrics.sh << 'SCRIPT_EOF'
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

# 用 python 解析互动数（兼容 JSON 嵌套与字符串数）
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

# 正则兜底：如果上面解析全是 0
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

# 输出供助手解读
echo "{\"post_id\":$POST_ID,\"note_id\":\"$NOTE_ID\",\"likes\":$LIKES,\"saves\":$SAVES,\"comments\":$COMMENTS,\"shares\":$SHARES}"
SCRIPT_EOF
chmod +x /tmp/shuling-src/scripts/fetch-metrics.sh
```

- [ ] **Step 2: dry-run 验证（无 MCP 时会失败但脚本结构对）**

```bash
bash /tmp/shuling-src/scripts/fetch-metrics.sh 2>&1 | head -3
```

Expected: `{"error": "usage: fetch-metrics.sh <post_id> <note_id> [xsec_token]"}`

- [ ] **Step 3: 提交**

```bash
cd /tmp/shuling-src && git add scripts/fetch-metrics.sh && git commit -m "$(cat <<'EOF'
feat(scripts): 新增 fetch-metrics.sh 拉互动数据并写 DB

封装 xhs.sh detail 调用 + 互动数解析（JSON 嵌套优先、正则兜底）+
post_metrics 表写入。供助手在每日复盘流程中批量调用。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 创建 scripts/fetch-comments.sh

**Files:**
- Create: `/tmp/shuling-src/scripts/fetch-comments.sh`

**职责：** 给定 note_id，调 `xhs.sh detail`，提取评论数组，过滤垃圾评论（纯 emoji、≤2 字、含"加微/私聊/免费领/http"），输出干净 JSON 数组。**不做 LLM 分析**——分析交给助手。

- [ ] **Step 1: 写脚本**

```bash
cat > /tmp/shuling-src/scripts/fetch-comments.sh << 'SCRIPT_EOF'
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

LIMIT="$LIMIT" python3 << PYEOF
import json, os, re, sys

raw = """$DETAIL"""
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
SCRIPT_EOF
chmod +x /tmp/shuling-src/scripts/fetch-comments.sh
```

- [ ] **Step 2: 验证脚本可执行**

```bash
bash /tmp/shuling-src/scripts/fetch-comments.sh 2>&1 | head -3
```

Expected: `{"error": "usage: fetch-comments.sh <note_id> [xsec_token] [--limit N]"}`

- [ ] **Step 3: 提交**

```bash
cd /tmp/shuling-src && git add scripts/fetch-comments.sh && git commit -m "$(cat <<'EOF'
feat(scripts): 新增 fetch-comments.sh 拉评论并过滤 spam

封装 xhs.sh detail + 评论数组提取 + 垃圾评论过滤
（纯 emoji / ≤2 字 / 引流广告关键词）。LLM 分析由助手负责，
脚本只做"取干净数据"这一物理活。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 创建 scripts/noterx-diagnose.sh

**Files:**
- Create: `/tmp/shuling-src/scripts/noterx-diagnose.sh`

**职责：** 给定 post_id + title + content + (可选 tags、category、image_count、--full)，curl 调 noterx.muran.tech 拿 5 维评分 + issues + suggestions，写入 note_diagnosis 表。返回 JSON 摘要。

**API 参考（自 workflow/.../noterx_diagnose.py）：**
- `POST /api/pre-score`：form data title/content/category/tags/image_count → 返回 `{total_score, dimensions:{content_quality,visual_quality,tag_strategy,engagement_potential}}`，超时 15s
- `POST /api/diagnose`：form data title/content/category/tags → 返回完整 `{overall_score, grade, radar_data, issues, suggestions, debate_summary}`，超时 150s
- 支持的 category：food, fashion, tech, travel, beauty, fitness, lifestyle, home（其他/未指定 → lifestyle）

- [ ] **Step 1: 写脚本**

```bash
cat > /tmp/shuling-src/scripts/noterx-diagnose.sh << 'SCRIPT_EOF'
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

# 1. pre-score 必跑
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

# 2. 解析 pre-score
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

# 3. 可选 full diagnose
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

# 4. test 模式不写 DB
if [ "$POST_ID" = "0" ]; then
    echo "$RESULT"
    exit 0
fi

# 5. 写 DB（issues/suggestions 序列化为 JSON 字符串）
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
SCRIPT_EOF
chmod +x /tmp/shuling-src/scripts/noterx-diagnose.sh
```

- [ ] **Step 2: 跑 --test 验证 NoteRx API 连通性**

```bash
bash /tmp/shuling-src/scripts/noterx-diagnose.sh --test 2>&1
```

Expected: 返回 JSON，含 `overall_score`、`grade`、5 维评分。如果 API 不可达，会返回 `{"error":"..."}`——记录现象但不阻塞，因为 NoteRx 服务可能临时不可用。

- [ ] **Step 3: 提交**

```bash
cd /tmp/shuling-src && git add scripts/noterx-diagnose.sh && git commit -m "$(cat <<'EOF'
feat(scripts): 新增 noterx-diagnose.sh 调外部诊断 API

curl 封装 noterx.muran.tech 的 /api/pre-score 与可选 /api/diagnose，
解析 5 维评分 + issues + suggestions，写入 note_diagnosis 表。
配置走 config/runtime.env（NOTERX_API_URL/TIMEOUT_*）。
--test 模式仅打印不写 DB，便于连通性检查。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: 创建 config/runtime.env.example

**Files:**
- Create: `/tmp/shuling-src/config/runtime.env.example`

- [ ] **Step 1: 写模板**

```bash
mkdir -p /tmp/shuling-src/config
cat > /tmp/shuling-src/config/runtime.env.example << 'EOF'
# 薯灵 skill 运行时配置
# 复制为 config/runtime.env 后按需填写
# 注意：本文件不配置 IM/通讯凭证（Telegram 等）—— 那是 hermes-agent 的职责

# ─── 小红书 MCP 服务地址 ──────────────────────────────────────
MCP_URL=http://localhost:18060/mcp

# ─── 图片生成（可选，不配置则走 HTML 截图降级）─────────────────
# IMAGE_GEN_PROVIDER=gemini
# IMAGE_GEN_API_KEY=
# IMAGE_GEN_MODEL=gemini-2.0-flash-preview-image-generation

# ─── NoteRx 诊断（可选，默认用 muran 公网地址）────────────────
# NOTERX_API_URL=https://noterx.muran.tech
# NOTERX_TIMEOUT_PRE=15
# NOTERX_TIMEOUT_FULL=150
EOF
```

- [ ] **Step 2: 验证文件存在**

```bash
ls -la /tmp/shuling-src/config/runtime.env.example
```

Expected: 文件存在，约 600+ 字节

- [ ] **Step 3: 提交**

```bash
cd /tmp/shuling-src && git add config/runtime.env.example && git commit -m "$(cat <<'EOF'
feat(config): 新增 runtime.env.example 替代 workflow 那份

放在 skill 根目录的 config/，包含 MCP_URL、可选 IMAGE_GEN_*、
可选 NOTERX_*。明确不放 Telegram/IM 凭证。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: 修改 install.sh 删除所有 workflow 引用

**Files:**
- Modify: `/tmp/shuling-src/install.sh:85-99`（rsync exclude）
- Modify: `/tmp/shuling-src/install.sh:151-168`（runtime.env 模板路径）

- [ ] **Step 1: 修 rsync 命令删 workflow exclude**

打开 `install.sh`，找到第 85-95 行的 rsync 块，**整体替换**：

```bash
    rsync -a --exclude=.git --exclude=.DS_Store --exclude=.idea \
        --exclude=skills --exclude=docs \
        --exclude=.session-recorder --exclude=*.md \
        --exclude=config/runtime.env --exclude=config/state.json \
        --exclude=knowledge-base/profile.json \
        --exclude=knowledge-base/preferences.json --exclude=knowledge-base/patterns.md \
        --exclude=data/xhs.db --exclude=data/xhs.db-shm --exclude=data/xhs.db-wal \
        "$SKILL_DIR/" "$target/"
```

（删除了 `--exclude=workflow`、整体 `--exclude=config` 改为只 exclude 用户运行时文件。这样 `config/runtime.env.example` 会被复制到 target。）

- [ ] **Step 2: 修 7.5 节 RUNTIME_ENV_TEMPLATE 路径**

把 `RUNTIME_ENV_TEMPLATE="$SKILL_DIR/workflow/xhs-automation/config/runtime.env.example"` 改为：

```bash
RUNTIME_ENV_TEMPLATE="$SKILL_DIR/config/runtime.env.example"
```

- [ ] **Step 3: 修 awk 缺单引号 bug（顺手）**

把第 30 行：
```bash
    info "Python $(python3 --version 2>&1 | awk {print })"
```
改为：
```bash
    info "Python $(python3 --version 2>&1 | awk '{print $2}')"
```

把第 37 行：
```bash
    info "sqlite3 $(sqlite3 --version | awk {print })"
```
改为：
```bash
    info "sqlite3 $(sqlite3 --version | awk '{print $1}')"
```

- [ ] **Step 4: 跑 install.sh 语法检查**

```bash
bash -n /tmp/shuling-src/install.sh && echo "OK"
```

Expected: `OK`

- [ ] **Step 5: 全文搜索仓库内是否还有 workflow 引用**

```bash
cd /tmp/shuling-src && grep -rln "workflow/xhs-automation\|workflow/" . --exclude-dir=.git --exclude-dir=docs 2>/dev/null
```

Expected: 空输出（docs 下的旧计划允许保留作为历史参考）

- [ ] **Step 6: 提交**

```bash
cd /tmp/shuling-src && git add install.sh && git commit -m "$(cat <<'EOF'
chore(install): 删 workflow 引用，runtime.env 模板移到 config/

- rsync exclude 列表移除 workflow，新增 config 子项细化（保留 example）
- RUNTIME_ENV_TEMPLATE 指向 config/runtime.env.example（根目录）
- 顺手修 awk 缺引号的 cosmetic bug

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: SKILL.md 第 3 节 — 重写为含 NoteRx 的每日复盘

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md:407-461`（第 3 节"每日复盘"全部）

- [ ] **Step 1: 用 Edit 替换第 3 节**

把 SKILL.md 第 3 节（从 `## 3. 每日复盘：数据采集 → 日报` 到下一个 `---` 之间的全部内容）整体替换为：

```markdown
## 3. 每日复盘：数据采集 → NoteRx 诊断 → 进化

每天晚上执行（建议 22:00 由 hermes cron 触发，或用户说"复盘一下"也立即跑）。

**目标**：拉今天发的所有帖子的真实数据 + 第三方诊断分数 → 你（大脑）综合判断 → **当晚立即更新** patterns/rules，让明天的创作变得更聪明。

### 步骤

1. **查询今日已发布的帖子**
   ```bash
   scripts/db.sh query-posts --today --status published
   ```
   返回 JSON 数组，每条含 `id, note_id, title, topic_type, title_pattern, content_style`。

2. **逐篇拉互动数据**
   对每个 `(post_id, note_id)`：
   ```bash
   scripts/fetch-metrics.sh <post_id> <note_id>
   ```
   脚本已写入 `post_metrics` 表，并把 `{likes, saves, comments, shares}` 回吐给你。

3. **逐篇拉评论原文（脚本已过滤垃圾评论）**
   ```bash
   scripts/fetch-comments.sh <note_id> --limit 30
   ```
   返回 `[{author, text, like_count}]`。**你自己读**评论，提炼：正面/负面/提问、用户内容需求（"能不能出一期 X"）、高频词。

4. **逐篇 NoteRx 诊断**
   先查是否已诊断过：
   ```bash
   scripts/db.sh query-diagnosis --post-id <id>
   ```
   返回空数组就跑：
   ```bash
   scripts/noterx-diagnose.sh <post_id> "<title>" \
       --content "<正文>" --tags "标签1,标签2" \
       --category tech --image-count 6
   ```
   返回 5 维评分 + grade（S/A/B/C/D）+ issues（仅 --full 时有）+ suggestions。脚本已写入 `note_diagnosis` 表。

   **--full 决策**：默认只跑 pre-score（< 50ms 零成本）。**只在帖子收藏率 ≥ 5% 或 ≤ 1%（极好极差两端）时**追加 `--full` 拿详细 issues，避免 token 浪费。

5. **综合分析（你来想）**
   把上面 3 份数据合在一起，对每篇帖子回答：
   - 收藏率 = saves / max(likes, 1)
   - 真实表现 vs NoteRx 预测分是否对齐？偏差大说明 NoteRx 在这个领域的校准需要修正
   - 评论里反复出现的痛点 → 是否值得变成新选题
   - NoteRx 给的 issues 里，哪些是 **结构性问题**（如"标题缺少数字钩子"），哪些是 **本帖特殊**？结构性问题应该回写到 patterns.md

6. **当晚更新知识库**（这是"每天进化"的核心，不要攒到周末）
   - **`knowledge-base/patterns.md`**：
     - 收藏率 ≥ 5% 的帖子用了什么标题/正文 pattern？还没记录就追加，confidence 从 experimental 起
     - 已存在 pattern 被验证有效（连续 3 次以上收藏率 ≥ 5%）→ confidence 升级（experimental → medium → high）
     - 已存在 pattern 连续 3 次 < 2% → 移到 `knowledge-base/anti-patterns.md`
     - patterns.md 活跃 ≤ 15 条，超出时淘汰 confidence 最低的
   - **`knowledge-base/preferences.json`**：
     - 表现好的 topic_type / content_style → weight + 0.1（上限 1.0）
     - 表现差的 → weight - 0.1（下限 0.0）
     - 重新计算 confidence_level（详见 4.1）
   - **`knowledge-base/evolution-log.md`**：追加一段，包含：日期 / 改了什么 / 为什么改 / 数据依据

7. **生成日报输出**

   日报格式（输出后由 hermes 决定如何送达用户）：
   ```
   📊 今日数据（2026-04-17）

   午间「标题A」: ❤️ 89  ⭐ 132  💬 15
       NoteRx: B 76 (内容 80 / 视觉 75 / 增长 70 / 反应 78)
   晚间「标题B」: ❤️ 203  ⭐ 47   💬 8
       NoteRx: A 82 (内容 85 / 视觉 80 / 增长 78 / 反应 84)

   💡 今日洞察
   - 「标题A」收藏率 148%，清单类内容继续验证有效
   - 「标题B」NoteRx 评分高但实际收藏率低，可能 NoteRx 校准在这个细分场景偏乐观
   - 评论里有 4 人问"怎么安装 X"，明天可以做一篇手把手教程

   🧬 知识库更新
   - patterns.md：「数字+痛点」标题 confidence experimental → medium
   - preferences.json：tech-tools weight 0.65 → 0.75

   📈 本周累计：发布 8 条 | 总赞 1.2k | 总收藏 890
   ```

   **不要在日报里包含"@用户"或"telegram://"等渠道字样**——hermes 自己负责送达。
```

- [ ] **Step 2: 验证替换无误**

```bash
grep -n "## 3\." /tmp/shuling-src/SKILL.md | head -3
grep -n "NoteRx 诊断" /tmp/shuling-src/SKILL.md | head -5
```

Expected: 看到第 3 节标题 + 多处 NoteRx 提及

- [ ] **Step 3: 提交**

```bash
cd /tmp/shuling-src && git add SKILL.md && git commit -m "$(cat <<'EOF'
feat(skill): 第 3 节重写为含 NoteRx 的每日复盘

新流程：拉数据 → 拉评论 → NoteRx 诊断 → 助手综合分析
→ 当晚立即改 patterns/rules（不攒到周末）→ 生成日报。
强调 --full 只在两端跑，节省 token。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: SKILL.md 第 4.3 — 改为周深度回顾

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md:526-585`（第 4.3 节）

- [ ] **Step 1: 用 Edit 替换 4.3 节**

把第 4.3 节（从 `### 4.3 周进化分析` 到第 4 节结束 `---` 之间）替换为：

```markdown
### 4.3 周深度回顾

**触发时机**：每周日的复盘流程中，作为日常复盘的"加餐"

**与每日复盘的区别**：每日复盘已经做了 patterns/rules 的实时调整。周回顾不再做硬调整，而是**抽离出一周的全景**给用户看：方向是否在收敛、有哪些反复出现的高频问题、要不要换打法。

**步骤**：

1. **读 evolution-log.md**：获取本周追加的所有变更
   ```bash
   tail -200 knowledge-base/evolution-log.md
   ```

2. **导出本周数据**
   ```bash
   scripts/db.sh query-posts --days 7
   ```
   对每篇帖子拉历史 metrics：
   ```bash
   scripts/db.sh query-metrics --post-id <id>
   ```

3. **跨日整合分析**（你自己做）
   - 哪种 topic_type + content_style 组合本周表现最稳定？
   - 哪些 pattern 已经被反复验证可以晋升 high？
   - 用户在评论区是否有积累的需求未满足？
   - NoteRx 评分与实际收藏率的相关性如何？是否存在"NoteRx 系统偏差"应该被你内化？

4. **写入周快照**：`knowledge-base/reviews/<YYYY-W##>.md`
   ```markdown
   # 2026-W17 周回顾

   ## 一句话总结
   本周发布 14 条，最稳定方向是 `tech-tools` + `清单体`。

   ## 收敛信号
   - 「数字 + 痛点」标题已连续 5 次收藏率 ≥ 5% → 升 high

   ## 待验证
   - 反差悬念体试了 2 次效果分化，下周再观察 1 次

   ## 用户需求积压
   - 8 条评论问"安装步骤"，下周必出一条手把手教程

   ## NoteRx 校准
   - tech 品类下 NoteRx 系统性偏低 ~5 分，明天起人为加权
   ```

5. **生成周报输出**：

   ```
   📈 本周成长报告（W17 / 2026-04-12 ~ 2026-04-18）

   发布 14 条 | 总赞 2.1k | 总收藏 1.5k | 粉丝 +47

   🏆 最佳：「5 个程序员必备的 AI 效率工具」收藏率 9.1%
      → 清单体 + 每个工具写了"替你省哪一步"
   📉 最差：「OpenClaw 是什么」收藏率 0.8%
      → 百科式开头，用户第一屏看不到"跟我有什么关系"

   🧬 你正在形成的风格（已写入 knowledge-base/）
   - 受众最吃"工具清单 + 场景化推荐"（连续 3 周验证）
   - "避坑"类标题点击率高但转化低
   - 你偏好选 AI 工具类 > 编程教程类

   🎯 下周建议
   - 继续清单体（已晋升 high confidence）
   - 出一条回应评论高频需求的手把手教程
   - 「反差悬念体」再试 1 次再决定保留/淘汰
   ```
```

- [ ] **Step 2: 验证替换正确**

```bash
grep -n "### 4\.3" /tmp/shuling-src/SKILL.md
grep -n "周深度回顾\|周进化分析" /tmp/shuling-src/SKILL.md
```

Expected: 4.3 节标题改为"周深度回顾"，"周进化分析"字样不再出现

- [ ] **Step 3: 提交**

```bash
cd /tmp/shuling-src && git add SKILL.md && git commit -m "$(cat <<'EOF'
refactor(skill): 4.3 周进化 → 周回顾

每日复盘已经实时改 patterns/rules，周日不再做硬调整，
而是抽离一周全景写入 reviews/<YYYY-W##>.md，输出给用户看
"方向收敛、待验证、需求积压、NoteRx 校准"四类信号。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: SKILL.md 第 6 节 — 加 3 个新脚本工具说明

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md:624-670`（第 6 节"工具参考"）

- [ ] **Step 1: 在第 6 节 "scripts/db.sh — 数据库操作" 之后插入 3 节新脚本说明**

打开 SKILL.md 找到 `### scripts/db.sh — 数据库操作` 那一节，在它结束（紧接着 `---` 之前）插入：

```markdown
### scripts/fetch-metrics.sh — 拉互动数据

```bash
scripts/fetch-metrics.sh <post_id> <note_id> [xsec_token]
```

调 `xhs.sh detail` 提取 likes/saves/comments/shares，写入 `post_metrics` 表（checkpoint='daily'）并输出 JSON。供每日复盘批量调用。

### scripts/fetch-comments.sh — 拉评论原文

```bash
scripts/fetch-comments.sh <note_id> [xsec_token] [--limit 50]
```

调 `xhs.sh detail` 提取评论数组，过滤垃圾评论（纯 emoji / ≤2 字 / 含"加微/私聊/免费领/http"），输出 `[{author, text, like_count}]` JSON 数组。**LLM 分析由你来做**，脚本只做物理过滤。

### scripts/noterx-diagnose.sh — NoteRx 第三方诊断

```bash
# 默认只跑 pre-score（< 50ms，零成本）
scripts/noterx-diagnose.sh <post_id> "<title>" \
    --content "<正文>" --tags "标签1,标签2" \
    --category tech --image-count 6

# 加 --full 跑完整 5-Agent 诊断（60-90s，仅在两端跑：极好或极差）
scripts/noterx-diagnose.sh <post_id> "<title>" --content "..." --full

# --test 模式：只测 API 连通性，不写 DB
scripts/noterx-diagnose.sh --test
```

调 `noterx.muran.tech` 拿 5 维评分 + grade + issues + suggestions，写入 `note_diagnosis` 表。环境变量：`NOTERX_API_URL`、`NOTERX_TIMEOUT_PRE`（默认 15s）、`NOTERX_TIMEOUT_FULL`（默认 150s）。

支持的 category：`tech`/`food`/`fashion`/`travel`/`beauty`/`fitness`/`lifestyle`/`home`，未指定走 `lifestyle`。

```

- [ ] **Step 2: 验证插入**

```bash
grep -n "fetch-metrics\|fetch-comments\|noterx-diagnose" /tmp/shuling-src/SKILL.md
```

Expected: 看到 3 个脚本在第 6 节有说明

- [ ] **Step 3: 提交**

```bash
cd /tmp/shuling-src && git add SKILL.md && git commit -m "$(cat <<'EOF'
docs(skill): 第 6 节加 fetch-metrics/fetch-comments/noterx-diagnose 用法

为助手提供完整调用参考，包括 --full 决策建议
（只在收藏率两端追加完整诊断）和 NoteRx category 映射。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: SKILL.md 第 7 节 — 更新表清单

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md:686-694`（SQLite 表清单）

- [ ] **Step 1: 替换表清单**

把第 7 节中 `### SQLite 表（data/xhs.db）` 下的表格替换为：

```markdown
| 表 | 用途 |
|----|------|
| `posts` | 帖子记录（标题/内容/标签/状态/类型/风格） |
| `post_metrics` | 互动数据时序（likes/saves/comments） |
| `user_choices` | 用户选择记录（用于偏好学习） |
| `topic_candidates` | 选题候选记录 |
| `comment_insights` | 评论分析结果（助手写入） |
| `note_diagnosis` | NoteRx 诊断分数与 issues |
| `generated_images` | 图片生成历史（model/path/status） |
```

- [ ] **Step 2: 验证**

```bash
grep "note_diagnosis\|generated_images" /tmp/shuling-src/SKILL.md
```

Expected: 表清单中出现两个新表

- [ ] **Step 3: 提交**

```bash
cd /tmp/shuling-src && git add SKILL.md && git commit -m "$(cat <<'EOF'
docs(skill): 第 7 节表清单加 note_diagnosis + generated_images

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: 修改 platform/hermes.md — cron 改为唤起助手

**Files:**
- Modify: `/tmp/shuling-src/platform/hermes.md:42-69`（Cron Job 配置）

- [ ] **Step 1: 替换 Cron Job 配置整段**

把"## Cron Job 配置"整节（从标题到下一个 `---`）替换为：

```markdown
## Cron Job 配置

> **重要原则**：hermes cron 不是"跑 Python 脚本"，而是"定时唤起 AI 助手让它读 SKILL.md 自己决定该做什么"。所有业务逻辑由 SKILL.md 0a 节的"业务路由"决定。

在 Hermes 中创建以下两个定时任务（都通过 `prompt` 唤起助手）：

### Job 1: 每日午间档发布（11:30）

```yaml
name: "薯灵-午间发布"
schedule: "30 11 * * *"
prompt: |
  使用 shuling skill。先跑 scripts/preflight.py 看 setup_completed
  是否为 true；为 true 直接进入今日午间档创作发布流程
  （选题 → 草稿 → 图片 → 发布），完成后输出业务结果。
deliver: "telegram:用户ID"
```

### Job 2: 每日晚间档发布（20:30）

```yaml
name: "薯灵-晚间发布"
schedule: "30 20 * * *"
prompt: |
  使用 shuling skill。先跑预检，进入今日晚间档创作发布流程。
deliver: "telegram:用户ID"
```

### Job 3: 每日复盘（22:00）

```yaml
name: "薯灵-每日复盘"
schedule: "0 22 * * *"
prompt: |
  使用 shuling skill 执行 SKILL.md 第 3 节"每日复盘"流程：
  拉今日所有已发帖子的互动数据 + 评论 + NoteRx 诊断，
  做综合分析，当晚立即更新 patterns.md / preferences.json /
  evolution-log.md，最后输出日报。
  如果今天是周日，按 SKILL.md 4.3 节再做一次"周深度回顾"
  并输出周报。
deliver: "telegram:用户ID"
```

> **注意**：cron 任务的 `prompt` 是给助手看的"任务说明"，不是给脚本的命令。助手会自己决定调哪些工具。如果某次 cron 触发后助手返回"setup_completed=false"，说明用户还没完成首次设置，跳过本次即可，不报警。
```

- [ ] **Step 2: 提交**

```bash
cd /tmp/shuling-src && git add platform/hermes.md && git commit -m "$(cat <<'EOF'
docs(hermes): cron 用法改为"唤起助手让它读 SKILL.md"

不再描述"如果是周日额外执行周进化"等假设代码内部细节，
改为给 prompt 让助手自己按 SKILL.md 0a 业务路由决策。
新增午间/晚间/复盘 3 个 cron 模板。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: 重写 README.md 删除两条线描述

**Files:**
- Modify: `/tmp/shuling-src/README.md:69-95`（架构图 + 文件结构）

- [ ] **Step 1: 替换"架构"小节的图**

打开 README.md，找到 `## 架构` 小节，把整个 ASCII 图（从 `## 架构` 到下一个 `---`）替换为：

```markdown
## 架构

```
┌─────────────────────────────────────────────────────┐
│              AI 助手（大脑 / Skill-as-Brain）         │
│                                                       │
│   读 SKILL.md → 业务路由 → 决策 → 调脚本 → 写知识库   │
└─┬─────────┬─────────┬─────────┬──────────┬──────────┘
  │         │         │         │          │
┌─▼──────┐┌─▼──────┐┌─▼─────┐┌─▼────────┐┌─▼─────────┐
│xhs.sh  ││db.sh   ││image  ││fetch-*   ││noterx-    │
│小红书  ││数据库  ││.py    ││.sh       ││diagnose.sh│
│MCP     ││SQLite  ││Gemini ││metrics + ││NoteRx API │
│        ││xhs.db  ││/HTML  ││comments  ││5 维评分    │
└────────┘└────────┘└───────┘└──────────┘└───────────┘

knowledge-base/                data/
├── profile.json               ├── xhs.db          ← 7 张表
├── preferences.json           └── content-rules.md
├── patterns.md
├── anti-patterns.md
├── evolution-log.md           templates/
└── reviews/<YYYY-W##>.md      └── post.html       ← HTML 截图模板
```

**只有一条路线**：智能体 → SKILL.md → scripts/。所有自动化（每日发布 + 每日复盘 + NoteRx 诊断 + 知识库进化）全部走这条路，由 hermes cron 定时唤起助手实现。
```

- [ ] **Step 2: 替换"文件结构"小节**

找到 `## 文件结构` 小节，把整个 tree 替换为：

```markdown
## 文件结构

```
shuling/
├── SKILL.md                  # 大脑剧本（核心）
├── install.sh                # 安装脚本
├── README.md                 # 本文件
├── config/
│   └── runtime.env.example   # 配置模板（MCP_URL / IMAGE_GEN_* / NOTERX_*）
├── scripts/
│   ├── preflight.py          # 环境预检
│   ├── db.sh                 # SQLite 增删改查
│   ├── xhs.sh                # 小红书 MCP 入口
│   ├── image.py              # Gemini 图片生成
│   ├── screenshot.cjs        # HTML → PNG 截图
│   ├── fetch-metrics.sh      # 拉互动数据写 DB
│   ├── fetch-comments.sh     # 拉评论原文 + 过滤 spam
│   └── noterx-diagnose.sh    # NoteRx 5 维诊断
├── data/
│   ├── xhs.db                # SQLite（7 张表，运行时生成）
│   └── content-rules.md      # 内容规则与平台限制
├── knowledge-base/           # 博主画像与偏好（运行时生成）
├── templates/
│   └── post.html             # 小红书风格 HTML 模板
└── platform/
    ├── hermes.md
    ├── claude-code.md
    └── codex.md
```
```

- [ ] **Step 3: 删除（如有）任何提及"workflow / 双线 / xhs-automation"的句子**

```bash
grep -n "workflow\|xhs-automation\|两条线\|双线" /tmp/shuling-src/README.md
```

Expected: 空。如果有匹配，用 Edit 删掉。

- [ ] **Step 4: 提交**

```bash
cd /tmp/shuling-src && git add README.md && git commit -m "$(cat <<'EOF'
docs(readme): 重写为单一架构

- 架构图加入 fetch-* 与 noterx-diagnose 节点
- 文件结构去掉 workflow，加入 config/ 与 3 个新脚本
- 明确"只有一条路线"原则

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: 全仓 grep 确认无 workflow 残留

- [ ] **Step 1: 全文 grep**

```bash
cd /tmp/shuling-src && grep -rln "workflow/xhs-automation\|workflow/" \
    . --exclude-dir=.git --exclude-dir=docs/superpowers/plans 2>/dev/null
```

Expected: 空输出。如有匹配，逐个用 Edit 修掉再 commit。

- [ ] **Step 2: 验证 SKILL.md 不再禁读 workflow（因为根本不存在了）**

可选：把 SKILL.md 第 25 行的核心原则 5 改成更简洁的：

打开 SKILL.md，把：
```
5. **不读 workflow 目录**：`workflow/xhs-automation/` 是另一个独立后台项目（不属于本 skill），其中的 .py 脚本与本 skill 行为无关。**禁止 grep / Read / 引用** 该目录下任何文件。本 skill 的所有路径都相对 skill 根目录（包含本 SKILL.md 的目录）。
```

改成：
```
5. **路径全部相对 skill 根目录**：所有脚本、配置、数据都在本 SKILL.md 同级目录或其子目录下，不要去任何"上级/兄弟"目录读写文件。
```

- [ ] **Step 3: 如有改动，提交**

```bash
cd /tmp/shuling-src && git add SKILL.md && git commit -m "$(cat <<'EOF'
chore(skill): 简化原则 5（workflow 已物理删除，无需禁读）

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)" 2>/dev/null || echo "no changes"
```

---

### Task 15: 推送所有改动到远端

- [ ] **Step 1: 查看本地 commit 列表**

```bash
cd /tmp/shuling-src && git log --oneline origin/main..HEAD
```

Expected: 看到 ~13 个新 commit

- [ ] **Step 2: 推送**

```bash
cd /tmp/shuling-src && git push origin main
```

Expected: `xxxxxxx..yyyyyyy  main -> main`

---

## Stage B：Mac 部署 + 验证

### Task 16: Mac 上 git pull + 重装

**前提：** Mac 100.79.106.110 已经 clone 了仓库到 `/Users/weiyong/Documents/10/shuling`，且 ssh 可达。

- [ ] **Step 1: ssh 进 Mac 拉最新代码**

```bash
ssh weiyong@100.79.106.110 'cd /Users/weiyong/Documents/10/shuling && git pull origin main'
```

Expected: 看到 13+ 个 commit 拉下来

- [ ] **Step 2: 跑 install.sh**

```bash
ssh weiyong@100.79.106.110 'export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && cd /Users/weiyong/Documents/10/shuling && yes "" | bash install.sh'
```

Expected:
- `[OK] Node.js v...`
- `[OK] sqlite3 ...`
- `[OK] Hermes → ~/.hermes/skills/social-media/shuling/`
- 数据库初始化成功（7 张表）
- `=== 安装完成 ===`

- [ ] **Step 3: 验证 hermes target 目录已无 workflow**

```bash
ssh weiyong@100.79.106.110 'ls ~/.hermes/skills/social-media/shuling/'
```

Expected: 看到 `SKILL.md scripts/ data/ config/ templates/ platform/ knowledge-base/`，**没有** `workflow/`

- [ ] **Step 4: 验证 schema 已升级**

```bash
ssh weiyong@100.79.106.110 'sqlite3 ~/.hermes/skills/social-media/shuling/data/xhs.db ".tables"'
```

Expected: `comment_insights generated_images note_diagnosis post_metrics posts topic_candidates user_choices`

---

### Task 17: 在 hermes 端到端验证

> 这一步需要在 Mac 的 hermes UI 中操作，无法纯命令行完成。

- [ ] **Step 1: 在 hermes 对话里说"复盘一下昨天的数据"**

预期助手会：
1. 跑 `python3 scripts/preflight.py`
2. 跑 `bash scripts/db.sh query-posts --today --status published`
3. 如果今天没发帖，明确告诉用户"今天还没发布任何帖子，没有数据可复盘"
4. 如果有，按第 3 节流程逐篇拉 metrics + comments + NoteRx
5. 输出日报

- [ ] **Step 2: 检查 hermes 日志确认调用链**

```bash
ssh weiyong@100.79.106.110 'tail -200 ~/.hermes/logs/$(ls -t ~/.hermes/logs/ | head -1) | grep -E "fetch-metrics|fetch-comments|noterx-diagnose|preflight"'
```

Expected: 看到 3 个新脚本中至少 1 个被调用过的痕迹

- [ ] **Step 3: 检查 evolution-log 是否被写入**

```bash
ssh weiyong@100.79.106.110 'cat ~/.hermes/skills/social-media/shuling/knowledge-base/evolution-log.md 2>/dev/null | tail -30'
```

Expected: 如果今天有帖子，看到一段日期戳的更新记录；没帖子则文件可能不存在（正常）

---

### Task 18: 配置 hermes cron job

- [ ] **Step 1: 在 hermes 中按 platform/hermes.md 创建 3 个 cron job**

参考 `platform/hermes.md` 第 "Cron Job 配置" 节，配置：
- "薯灵-午间发布" cron `30 11 * * *`
- "薯灵-晚间发布" cron `30 20 * * *`
- "薯灵-每日复盘" cron `0 22 * * *`

每个 job 的 `deliver` 字段填用户的 Telegram 用户 ID。

- [ ] **Step 2: 等待第二天验证至少 1 次复盘自动跑通**

观察次日 22:00 复盘 cron 是否触发，并送达预期日报。

---

## Self-Review

**1. Spec 覆盖检查**：

| 用户需求 | 对应 Task |
|---------|----------|
| 删除双线、只保留 skill | T1, T7, T13, T14 |
| 每日复盘（不是周日复盘） | T8（重写第 3 节），T12（cron 22:00） |
| NoteRx 集成 | T2（schema），T5（脚本），T8（流程），T10（参考） |
| 进化复盘当晚立即调整 patterns/rules | T8 step 6 |
| 周深度回顾不消失，但简化 | T9 |
| knowledge-base 路径统一到 shuling/ | T1（删 workflow）+ T13（README） |
| data/ 路径统一到 shuling/ | T1（删 workflow） |
| 选项递减保留 | SKILL.md 4.1 节未动，T8/T9 都未删除该机制 ✓ |
| 空白起步（不写迁移脚本） | 全计划未涉及数据迁移 ✓ |
| install.sh 同步精简 | T7 |
| platform/hermes.md 改为唤起助手 | T12 |
| README 重写 | T13 |

无遗漏。

**2. Placeholder 扫描**：所有 step 均有完整代码 / 完整命令 / 明确 expected。无 TBD / TODO / "implement later"。

**3. 类型/命名一致性**：
- `note_diagnosis` 表名在 T2 / T8 / T10 / T11 / T13 中保持一致 ✓
- `add-diagnosis` / `query-diagnosis` / `query-undiagnosed` 命令名在 T2 定义后，T8/T10 引用一致 ✓
- 脚本名 `fetch-metrics.sh` / `fetch-comments.sh` / `noterx-diagnose.sh` 在 T3-5 创建后，T8/T10/T13 引用一致 ✓
- `NOTERX_API_URL` / `NOTERX_TIMEOUT_*` 在 T5 / T6 / T10 中拼写一致 ✓

无冲突。

---

## 执行选择

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每个 task 派一个新 subagent 干净执行，task 间审核
2. **Inline 执行** — 在本会话里按顺序跑，关键检查点暂停

请告诉我用哪种方式继续。
