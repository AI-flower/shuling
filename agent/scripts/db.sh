#!/usr/bin/env bash
set -e

# ─── v3.0+ 路径单一来源（_paths.sh + _common.sh）────────────────────
# 详见 docs/adr/0001-stateful-creator-agent.md §第 9 条 路径单一来源
_DB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_DB_SCRIPT_DIR/_paths.sh" ] && . "$_DB_SCRIPT_DIR/_paths.sh"
[ -f "$_DB_SCRIPT_DIR/_common.sh" ] && . "$_DB_SCRIPT_DIR/_common.sh"

# ─── Auto-detect paths ───────────────────────────────────────────────
# v2.4.2: 支持 SHULING_DB env var override, 允许调用方（install.sh / _guard.sh）
# 明确指定操作哪个 DB, 避免在 target install 路径上 db.sh 误写源仓库 DB.
# v3.0+: 优先用 _paths.sh 提供的 SHULING_AGENT_ROOT / SHULING_DB_PATH。
SKILL_DIR="${SHULING_AGENT_ROOT:-$(cd "$_DB_SCRIPT_DIR/.." && pwd)}"
if [ -n "${SHULING_DB:-}" ]; then
    DB_PATH="$SHULING_DB"
    DB_DIR="$(dirname "$DB_PATH")"
elif [ -n "${SHULING_DB_PATH:-}" ]; then
    DB_PATH="$SHULING_DB_PATH"
    DB_DIR="$(dirname "$DB_PATH")"
else
    DB_DIR="$SKILL_DIR/data"
    DB_PATH="$DB_DIR/xhs.db"
fi

# ─── Helpers ──────────────────────────────────────────────────────────

ensure_db_dir() {
    mkdir -p "$DB_DIR"
}

sql() {
    sqlite3 "$DB_PATH" "$@"
}

# JSON output: prefer sqlite3 -json, fallback to csv-to-json
sql_json() {
    local query="$1"
    if sqlite3 "$DB_PATH" -json "SELECT 1" >/dev/null 2>&1; then
        sqlite3 "$DB_PATH" -json "$query"
    else
        # Fallback: csv+header → python json
        local csv
        csv="$(sqlite3 "$DB_PATH" -csv -header "$query")"
        if [ -z "$csv" ]; then
            echo "[]"
        else
            echo "$csv" | python3 -c "
import csv, json, sys
reader = csv.DictReader(sys.stdin)
print(json.dumps(list(reader), ensure_ascii=False))
"
        fi
    fi
}

# Parse JSON field — jq first, python3 fallback
json_val() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r ".$key // empty"
    else
        python3 -c "import json,sys; d=json.loads(sys.stdin.read()); v=d.get('$key',''); print('' if v is None else v)" <<< "$json"
    fi
}

# Escape single quotes for SQL strings
sql_escape() {
    echo "${1//\'/\'\'}"
}

# ─── Commands ─────────────────────────────────────────────────────────

cmd_init() {
    ensure_db_dir
    sql "PRAGMA journal_mode=WAL;" >/dev/null
    sql "
CREATE TABLE IF NOT EXISTS posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    slot TEXT NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    tags TEXT,
    note_id TEXT,
    topic_type TEXT,
    title_pattern TEXT,
    content_style TEXT,
    status TEXT DEFAULT 'draft',
    published_at TEXT,
    source TEXT DEFAULT 'shuling',          -- v2.2.0: shuling|imported|manual
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_posts_source ON posts(source);
CREATE INDEX IF NOT EXISTS idx_posts_note_id ON posts(note_id);

CREATE TABLE IF NOT EXISTS post_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER REFERENCES posts(id),
    checked_at TEXT NOT NULL,
    checkpoint TEXT DEFAULT 'daily',
    likes INTEGER DEFAULT 0,
    saves INTEGER DEFAULT 0,
    comments INTEGER DEFAULT 0,
    shares INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS user_choices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    choice_type TEXT NOT NULL,
    offered_count INTEGER,
    chosen_index INTEGER,
    chosen_label TEXT,
    skipped_labels TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS topic_candidates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    source TEXT,
    title TEXT,
    score REAL,
    xhs_competition INTEGER,
    selected BOOLEAN DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS comment_insights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER REFERENCES posts(id),
    total_comments INTEGER DEFAULT 0,
    positive_count INTEGER DEFAULT 0,
    negative_count INTEGER DEFAULT 0,
    question_count INTEGER DEFAULT 0,
    top_questions TEXT,
    top_praise TEXT,
    content_requests TEXT,
    analyzed_at TEXT DEFAULT CURRENT_TIMESTAMP
);

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

CREATE TABLE IF NOT EXISTS request_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    called_at TEXT NOT NULL,
    tool TEXT NOT NULL,
    args_preview TEXT,
    status TEXT NOT NULL,
    latency_ms INTEGER,
    error_hint TEXT,
    session_tag TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_request_log_called ON request_log(called_at);
CREATE INDEX IF NOT EXISTS idx_request_log_tool ON request_log(tool, called_at);
CREATE INDEX IF NOT EXISTS idx_request_log_status ON request_log(status);

-- v2.2.0: 账号历史快照（给老博主接入 + audit-report 纵向趋势用）
CREATE TABLE IF NOT EXISTS historical_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    snapshotted_at TEXT NOT NULL,
    followers INTEGER,
    total_likes INTEGER,
    total_posts INTEGER,
    imported_posts_count INTEGER,
    earliest_post_at TEXT,
    latest_post_at TEXT,
    meta_json TEXT
);
CREATE INDEX IF NOT EXISTS idx_hstats_snapshotted_at ON historical_stats(snapshotted_at DESC);

-- v2.2.1: migration tracking (also ensured by migrations/_guard.sh)
CREATE TABLE IF NOT EXISTS __migrations (
    version TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"
    echo '{"ok": true, "tables": ["posts","post_metrics","user_choices","topic_candidates","comment_insights","note_diagnosis","generated_images","request_log","historical_stats","__migrations"]}'
}

cmd_add_post() {
    local json="$1"
    [ -z "$json" ] && { echo '{"error": "missing JSON argument"}' >&2; exit 1; }

    local date slot title content tags note_id topic_type title_pattern content_style status source published_at
    date="$(sql_escape "$(json_val "$json" "date")")"
    slot="$(sql_escape "$(json_val "$json" "slot")")"
    title="$(sql_escape "$(json_val "$json" "title")")"
    content="$(sql_escape "$(json_val "$json" "content")")"
    tags="$(sql_escape "$(json_val "$json" "tags")")"
    note_id="$(sql_escape "$(json_val "$json" "note_id")")"
    topic_type="$(sql_escape "$(json_val "$json" "topic_type")")"
    title_pattern="$(sql_escape "$(json_val "$json" "title_pattern")")"
    content_style="$(sql_escape "$(json_val "$json" "content_style")")"
    status="$(json_val "$json" "status")"
    status="${status:-draft}"
    status="$(sql_escape "$status")"
    source="$(json_val "$json" "source")"
    source="${source:-shuling}"
    source="$(sql_escape "$source")"
    published_at="$(sql_escape "$(json_val "$json" "published_at")")"

    # 对 imported source 且带 note_id 的行做幂等 upsert（note_id 唯一）
    if [ "$source" = "imported" ] && [ -n "$note_id" ]; then
        local existing_id
        existing_id="$(sql "SELECT id FROM posts WHERE note_id='$note_id' AND source='imported' LIMIT 1;")"
        if [ -n "$existing_id" ]; then
            sql "
UPDATE posts SET
    title='$title', content='$content', tags='$tags',
    topic_type='$topic_type', title_pattern='$title_pattern', content_style='$content_style',
    status='$status', published_at='$published_at'
WHERE id=$existing_id;
"
            echo "{\"id\": $existing_id, \"mode\": \"updated\"}"
            return 0
        fi
    fi

    local new_id
    new_id="$(sql "
INSERT INTO posts (date, slot, title, content, tags, note_id, topic_type, title_pattern, content_style, status, published_at, source)
VALUES ('$date','$slot','$title','$content','$tags','$note_id','$topic_type','$title_pattern','$content_style','$status','$published_at','$source');
SELECT last_insert_rowid();
")"
    echo "{\"id\": $new_id, \"mode\": \"inserted\"}"
}

cmd_add_metrics() {
    local json="$1"
    [ -z "$json" ] && { echo '{"error": "missing JSON argument"}' >&2; exit 1; }

    local post_id likes saves comments shares checkpoint checked_at
    post_id="$(json_val "$json" "post_id")"
    likes="$(json_val "$json" "likes")"
    saves="$(json_val "$json" "saves")"
    comments="$(json_val "$json" "comments")"
    shares="$(json_val "$json" "shares")"
    checkpoint="$(json_val "$json" "checkpoint")"
    checkpoint="${checkpoint:-daily}"
    checkpoint="$(sql_escape "$checkpoint")"
    checked_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local new_id
    new_id="$(sql "
INSERT INTO post_metrics (post_id, checked_at, checkpoint, likes, saves, comments, shares)
VALUES (${post_id:-0},'$checked_at','$checkpoint',${likes:-0},${saves:-0},${comments:-0},${shares:-0});
SELECT last_insert_rowid();
")"
    echo "{\"id\": $new_id}"
}

cmd_log_choice() {
    local json="$1"
    [ -z "$json" ] && { echo '{"error": "missing JSON argument"}' >&2; exit 1; }

    local choice_type offered_count chosen_index chosen_label skipped_labels
    choice_type="$(sql_escape "$(json_val "$json" "choice_type")")"
    offered_count="$(json_val "$json" "offered_count")"
    chosen_index="$(json_val "$json" "chosen_index")"
    chosen_label="$(sql_escape "$(json_val "$json" "chosen_label")")"
    skipped_labels="$(sql_escape "$(json_val "$json" "skipped_labels")")"

    local new_id
    new_id="$(sql "
INSERT INTO user_choices (choice_type, offered_count, chosen_index, chosen_label, skipped_labels)
VALUES ('$choice_type',${offered_count:-0},${chosen_index:-0},'$chosen_label','$skipped_labels');
SELECT last_insert_rowid();
")"
    echo "{\"id\": $new_id}"
}

cmd_query_posts() {
    local -a clauses=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --today)
                clauses+=("date = date('now')")
                shift
                ;;
            --days)
                shift
                local n="${1:-7}"
                clauses+=("date >= date('now', '-${n} days')")
                shift
                ;;
            --status)
                shift
                clauses+=("status = '$(sql_escape "$1")'")
                shift
                ;;
            --source)
                shift
                clauses+=("source = '$(sql_escape "$1")'")
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    local where=""
    if [ ${#clauses[@]} -gt 0 ]; then
        where="WHERE $(IFS=' AND '; echo "${clauses[*]}")"
    fi
    sql_json "SELECT * FROM posts $where ORDER BY created_at DESC;"
}

# v2.2.0: 给已有帖补分类字段（AI 分类 imported 帖子后回写）
cmd_update_post_meta() {
    local json="$1"
    [ -z "$json" ] && { echo '{"error": "missing JSON argument"}' >&2; exit 1; }

    local id topic_type title_pattern content_style
    id="$(json_val "$json" "id")"
    topic_type="$(sql_escape "$(json_val "$json" "topic_type")")"
    title_pattern="$(sql_escape "$(json_val "$json" "title_pattern")")"
    content_style="$(sql_escape "$(json_val "$json" "content_style")")"

    [ -z "$id" ] && { echo '{"error": "id required"}' >&2; exit 1; }

    sql "UPDATE posts SET
        topic_type = COALESCE(NULLIF('$topic_type',''), topic_type),
        title_pattern = COALESCE(NULLIF('$title_pattern',''), title_pattern),
        content_style = COALESCE(NULLIF('$content_style',''), content_style)
        WHERE id = $id;"
    echo "{\"ok\": true, \"id\": $id}"
}

# v2.2.0: 写一条账号快照
cmd_add_historical_stat() {
    local json="$1"
    [ -z "$json" ] && { echo '{"error": "missing JSON argument"}' >&2; exit 1; }

    local snapshotted_at followers total_likes total_posts imported_posts_count earliest_post_at latest_post_at meta_json
    snapshotted_at="$(json_val "$json" "snapshotted_at")"
    snapshotted_at="${snapshotted_at:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
    snapshotted_at="$(sql_escape "$snapshotted_at")"
    followers="$(json_val "$json" "followers")"
    followers="${followers:-0}"
    total_likes="$(json_val "$json" "total_likes")"
    total_likes="${total_likes:-0}"
    total_posts="$(json_val "$json" "total_posts")"
    total_posts="${total_posts:-0}"
    imported_posts_count="$(json_val "$json" "imported_posts_count")"
    imported_posts_count="${imported_posts_count:-0}"
    earliest_post_at="$(sql_escape "$(json_val "$json" "earliest_post_at")")"
    latest_post_at="$(sql_escape "$(json_val "$json" "latest_post_at")")"
    meta_json="$(sql_escape "$(json_val "$json" "meta_json")")"

    local new_id
    new_id="$(sql "
INSERT INTO historical_stats (snapshotted_at, followers, total_likes, total_posts, imported_posts_count, earliest_post_at, latest_post_at, meta_json)
VALUES ('$snapshotted_at', $followers, $total_likes, $total_posts, $imported_posts_count, '$earliest_post_at', '$latest_post_at', '$meta_json');
SELECT last_insert_rowid();
")"
    echo "{\"id\": $new_id}"
}

cmd_query_historical_stats() {
    local limit=30
    while [ $# -gt 0 ]; do
        case "$1" in
            --limit) shift; limit="${1:-30}"; shift ;;
            *) shift ;;
        esac
    done
    sql_json "SELECT * FROM historical_stats ORDER BY snapshotted_at DESC LIMIT $limit;"
}

cmd_query_metrics() {
    local post_id=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --post-id)
                shift
                post_id="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    [ -z "$post_id" ] && { echo '{"error": "missing --post-id"}' >&2; exit 1; }
    sql_json "SELECT * FROM post_metrics WHERE post_id = $post_id ORDER BY checked_at DESC;"
}

cmd_query_preferences() {
    # Aggregate chosen vs skipped from user_choices
    # chosen_label → chosen count; skipped_labels (comma-separated) → skipped count per label
    DB_PATH="$DB_PATH" python3 << 'PYEOF'
import sqlite3, json, os

db_path = os.environ["DB_PATH"]
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

rows = cur.execute("SELECT choice_type, chosen_label, skipped_labels FROM user_choices").fetchall()
total = len(rows)

topic_chosen = {}
topic_skipped = {}
style_chosen = {}
style_skipped = {}

for row in rows:
    ctype = row["choice_type"] or ""
    chosen = row["chosen_label"] or ""
    skipped_raw = row["skipped_labels"] or ""
    skipped_list = [s.strip() for s in skipped_raw.split(",") if s.strip()]

    if "topic" in ctype.lower():
        bucket_c, bucket_s = topic_chosen, topic_skipped
    elif "style" in ctype.lower():
        bucket_c, bucket_s = style_chosen, style_skipped
    else:
        bucket_c, bucket_s = topic_chosen, topic_skipped

    if chosen:
        bucket_c[chosen] = bucket_c.get(chosen, 0) + 1
    for s in skipped_list:
        bucket_s[s] = bucket_s.get(s, 0) + 1

def build_prefs(chosen_map, skipped_map):
    all_labels = set(chosen_map) | set(skipped_map)
    result = {}
    for label in sorted(all_labels):
        c = chosen_map.get(label, 0)
        s = skipped_map.get(label, 0)
        w = round(c / (c + s), 2) if (c + s) > 0 else 0.0
        result[label] = {"chosen": c, "skipped": s, "weight": w}
    return result

output = {
    "total_choices": total,
    "topic_preferences": build_prefs(topic_chosen, topic_skipped),
    "style_preferences": build_prefs(style_chosen, style_skipped),
}
print(json.dumps(output, ensure_ascii=False, indent=2))
conn.close()
PYEOF
}

cmd_update_post_status() {
    local id="$1" status="$2" note_id="$3"
    [ -z "$id" ] || [ -z "$status" ] && { echo '{"error": "usage: update-post-status <id> <status> [note_id]"}' >&2; exit 1; }

    status="$(sql_escape "$status")"

    if [ -n "$note_id" ]; then
        note_id="$(sql_escape "$note_id")"
        if [ "$status" = "published" ]; then
            sql "UPDATE posts SET status='$status', note_id='$note_id', published_at=datetime('now') WHERE id=$id;"
        else
            sql "UPDATE posts SET status='$status', note_id='$note_id' WHERE id=$id;"
        fi
    else
        if [ "$status" = "published" ]; then
            sql "UPDATE posts SET status='$status', published_at=datetime('now') WHERE id=$id;"
        else
            sql "UPDATE posts SET status='$status' WHERE id=$id;"
        fi
    fi
    echo "{\"ok\": true, \"id\": $id, \"status\": \"$status\"}"
}

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


cmd_add_request_log() {
    local json="$1"
    [ -z "$json" ] && { echo '{"error": "missing JSON argument"}' >&2; exit 1; }

    local tool status latency_ms args_preview error_hint session_tag called_at
    tool="$(sql_escape "$(json_val "$json" "tool")")"
    status="$(sql_escape "$(json_val "$json" "status")")"
    latency_ms="$(json_val "$json" "latency_ms")"
    args_preview="$(sql_escape "$(json_val "$json" "args_preview")")"
    error_hint="$(sql_escape "$(json_val "$json" "error_hint")")"
    session_tag="$(sql_escape "$(json_val "$json" "session_tag")")"
    called_at="$(json_val "$json" "called_at")"
    [ -z "$called_at" ] && called_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    called_at="$(sql_escape "$called_at")"

    sql "
INSERT INTO request_log (called_at, tool, args_preview, status, latency_ms, error_hint, session_tag)
VALUES ('$called_at','$tool','$args_preview','$status',${latency_ms:-NULL},'$error_hint','$session_tag');
" >/dev/null
    echo '{"ok": true}'
}

cmd_query_request_log() {
    local days=1 tool="" status="" limit=100 summary=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --days)    shift; days="${1:-1}"; shift ;;
            --tool)    shift; tool="${1:-}"; shift ;;
            --status)  shift; status="${1:-}"; shift ;;
            --limit)   shift; limit="${1:-100}"; shift ;;
            --summary) summary=1; shift ;;
            *) shift ;;
        esac
    done

    local where="WHERE called_at >= datetime('now', '-${days} days')"
    [ -n "$tool" ]   && where="$where AND tool = '$(sql_escape "$tool")'"
    [ -n "$status" ] && where="$where AND status = '$(sql_escape "$status")'"

    if [ "$summary" = "1" ]; then
        sql_json "
SELECT tool,
       status,
       COUNT(*) AS n,
       ROUND(AVG(latency_ms), 0) AS avg_ms,
       MAX(latency_ms) AS max_ms
FROM request_log
$where
GROUP BY tool, status
ORDER BY tool, status;
"
    else
        sql_json "
SELECT id, called_at, tool, status, latency_ms,
       substr(args_preview, 1, 60) AS args_preview,
       substr(error_hint, 1, 80)   AS error_hint,
       session_tag
FROM request_log
$where
ORDER BY id DESC
LIMIT $limit;
"
    fi
}

# ─── v3.0+ Runtime self-healing ───────────────────────────────────────
# ensure-runtime-layout: copy-first 把 v2 旧路径数据迁到 v3 agent/ 路径
# ensure-schema: 检查 __migrations 表 + 自动应用未应用的 migration
# 详见 docs/plans/v3-playbook-split-feasibility.md + ADR-0001 §第 12 条 降级路径强制

cmd_ensure_runtime_layout() {
    local mode="run"
    local fmt="text"
    local verbose=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) mode="dry"; shift ;;
            --json) fmt="json"; shift ;;
            --verbose) verbose=1; shift ;;
            *) shift ;;
        esac
    done

    local marker="${SHULING_LAYOUT_MARKER:-$SKILL_DIR/config/.layout-v3.done}"
    local agent_root="${SHULING_AGENT_ROOT:-$SKILL_DIR}"
    local skill_root="${SHULING_SKILL_ROOT:-$(cd "$agent_root/.." && pwd)}"

    # 已完成则幂等返回
    if [ -f "$marker" ]; then
        if [ "$fmt" = "json" ]; then
            emit_json status=ok action=skip reason=marker_exists marker="$marker"
        else
            [ "$verbose" = "1" ] && echo "✓ layout-v3 already applied (marker: $marker)"
        fi
        return 0
    fi

    # v2 → v3 路径映射表
    declare -a v2_paths v3_paths
    v2_paths=(
        "$skill_root/data/xhs.db"
        "$skill_root/config/runtime.env"
        "$skill_root/data/xhs.db-wal"
        "$skill_root/data/xhs.db-shm"
        "$skill_root/data/xhs.db-journal"
    )
    v3_paths=(
        "$agent_root/data/xhs.db"
        "$agent_root/config/runtime.env"
        "$agent_root/data/xhs.db-wal"
        "$agent_root/data/xhs.db-shm"
        "$agent_root/data/xhs.db-journal"
    )

    local copied=0 skipped=0 not_found=0 would_copy=0
    declare -a actions

    # 同步 agent/knowledge-base/ 子目录文件（不覆盖新文件）
    if [ -d "$skill_root/knowledge-base" ]; then
        if [ "$mode" != "dry" ]; then
            mkdir -p "$agent_root/knowledge-base" 2>/dev/null || {
                log_error "cannot mkdir $agent_root/knowledge-base"
                exit "${EXIT_PERM:-11}"
            }
        fi
        # 拷贝 KB 文件 .json/.md 但跳过 .gitkeep；不覆盖
        while IFS= read -r kbf; do
            local rel="${kbf#$skill_root/knowledge-base/}"
            local newpath="$agent_root/knowledge-base/$rel"
            if [ ! -e "$newpath" ]; then
                actions+=("kb-copy: $rel")
                if [ "$mode" != "dry" ]; then
                    mkdir -p "$(dirname "$newpath")" && cp -p "$kbf" "$newpath" && copied=$((copied+1))
                fi
            else
                skipped=$((skipped+1))
            fi
        done < <(find "$skill_root/knowledge-base" -type f \( -name '*.json' -o -name '*.md' \) ! -name '.gitkeep' 2>/dev/null)
    fi

    # 创建 v3 目录骨架
    if [ "$mode" != "dry" ]; then
        mkdir -p "$agent_root/data" "$agent_root/config" "$agent_root/knowledge-base" 2>/dev/null || {
            log_error "cannot create v3 directories under $agent_root"
            exit "${EXIT_PERM:-11}"
        }
    fi

    # 主路径映射 copy-first
    for i in "${!v2_paths[@]}"; do
        local v2p="${v2_paths[$i]}"
        local v3p="${v3_paths[$i]}"
        if [ ! -e "$v2p" ]; then
            not_found=$((not_found+1))
            continue
        fi
        if [ -e "$v3p" ]; then
            actions+=("skip-exists: $(basename $v3p) (v3 path populated)")
            skipped=$((skipped+1))
            continue
        fi
        actions+=("copy: $v2p → $v3p")
        if [ "$mode" != "dry" ]; then
            cp -p "$v2p" "$v3p" || {
                log_error "copy failed: $v2p → $v3p"
                exit "${EXIT_FS:-10}"
            }
            copied=$((copied+1))
        else
            would_copy=$((would_copy+1))
        fi
    done

    # 写 marker
    if [ "$mode" != "dry" ]; then
        local now
        now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        cat > "$marker" <<EOF
{
  "completed_at": "$now",
  "schema_version": "3.0.0",
  "v2_paths_kept": true,
  "v2_skill_root": "$skill_root",
  "v3_agent_root": "$agent_root",
  "copied": $copied,
  "skipped": $skipped,
  "not_found_v2": $not_found
}
EOF
    fi

    if [ "$fmt" = "json" ]; then
        emit_json status=ok mode="$mode" copied="$copied" would_copy="$would_copy" skipped="$skipped" not_found_v2="$not_found" marker="$marker"
    else
        if [ "$verbose" = "1" ] || [ "$mode" = "dry" ]; then
            for a in "${actions[@]}"; do echo "  $a"; done
        fi
        if [ "$mode" = "dry" ]; then
            echo "ensure-runtime-layout: would_copy=$would_copy skipped=$skipped not_found_v2=$not_found mode=dry"
        else
            echo "ensure-runtime-layout: copied=$copied skipped=$skipped not_found_v2=$not_found"
            echo "marker written: $marker"
        fi
    fi
    return 0
}

cmd_ensure_schema() {
    local mode="run"
    local fmt="text"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) mode="dry"; shift ;;
            --json) fmt="json"; shift ;;
            *) shift ;;
        esac
    done

    # v3.0+: 单进程内只调一次（性能优化）
    if [ "${_SHULING_SCHEMA_OK:-0}" = "1" ] && [ "$mode" != "dry" ]; then
        [ "$fmt" = "json" ] && emit_json status=ok action=skip reason=already_checked_in_process
        return 0
    fi

    local degraded_lock="${SHULING_SCHEMA_DEGRADED_LOCK:-$DB_DIR/.schema-degraded.lock}"
    local mig_dir="${SHULING_MIGRATIONS_DB_DIR:-$SKILL_DIR/migrations/db}"
    [ ! -d "$mig_dir" ] && mig_dir="$SKILL_DIR/migrations"

    # 检测 DB 是否存在
    if [ ! -f "$DB_PATH" ]; then
        if [ "$mode" = "dry" ]; then
            [ "$fmt" = "json" ] && emit_json status=ok action=would_init db="$DB_PATH" || echo "would-init: $DB_PATH"
            return 0
        fi
        cmd_init >/dev/null 2>&1
    fi

    # 确保 __migrations 表存在
    sql "CREATE TABLE IF NOT EXISTS __migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')));" 2>/dev/null

    # 计算未应用 migration
    declare -a pending
    if [ -d "$mig_dir" ]; then
        while IFS= read -r mig; do
            # migration 文件名 v2.1.1.sh → 检查表里 version 字段（既支持带 v 也支持不带）
            local stripped="$(basename "$mig" .sh | sed 's/^v//')"
            local count
            count="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM __migrations WHERE version='$stripped' OR version='v$stripped';" 2>/dev/null || echo 0)"
            [ "$count" = "0" ] && pending+=("$mig")
        done < <(find "$mig_dir" -maxdepth 1 -type f -name 'v*.sh' 2>/dev/null | sort)
    fi

    if [ ${#pending[@]} -eq 0 ]; then
        export _SHULING_SCHEMA_OK=1
        if [ "$fmt" = "json" ]; then
            emit_json status=ok action=up_to_date pending=0
        else
            echo "ensure-schema: up to date (0 pending)"
        fi
        return 0
    fi

    if [ "$mode" = "dry" ]; then
        if [ "$fmt" = "json" ]; then
            local plist=""
            for m in "${pending[@]}"; do plist="${plist}$(basename $m .sh),"; done
            emit_json status=ok action=would_apply pending="${#pending[@]}" migrations="${plist%,}"
        else
            echo "ensure-schema: would apply ${#pending[@]} migrations:"
            for m in "${pending[@]}"; do echo "  $(basename $m .sh)"; done
        fi
        return 0
    fi

    # 实际应用 migration
    local applied=0 failed=0
    for m in "${pending[@]}"; do
        if env SHULING_DB="$DB_PATH" SKILL_DIR="$SKILL_DIR" bash "$m" >/dev/null 2>&1; then
            applied=$((applied+1))
        else
            failed=$((failed+1))
            log_warn "migration failed: $(basename $m)"
        fi
    done

    # 失败则进入降级模式（schema-degraded lock）
    if [ $failed -gt 0 ]; then
        touch "$degraded_lock"
        if [ "$fmt" = "json" ]; then
            emit_json status=degraded applied="$applied" failed="$failed" lock="$degraded_lock"
        else
            log_warn "ensure-schema: $failed migration(s) failed; entering read-only degraded mode"
            echo "lock written: $degraded_lock"
        fi
        return "${EXIT_AUTOFIX:-1}"
    fi

    export _SHULING_SCHEMA_OK=1
    if [ "$fmt" = "json" ]; then
        emit_json status=ok applied="$applied" failed=0
    else
        echo "ensure-schema: applied $applied migration(s)"
    fi
}

# ─── Main dispatch ────────────────────────────────────────────────────

cmd="${1:-}"
shift || true

case "$cmd" in
    init)               cmd_init ;;
    ensure-runtime-layout) cmd_ensure_runtime_layout "$@" ;;
    ensure-schema)         cmd_ensure_schema "$@" ;;
    add-post)           cmd_add_post "$@" ;;
    add-metrics)        cmd_add_metrics "$@" ;;
    log-choice)         cmd_log_choice "$@" ;;
    query-posts)        cmd_query_posts "$@" ;;
    query-metrics)      cmd_query_metrics "$@" ;;
    query-preferences)  cmd_query_preferences ;;
    update-post-status) cmd_update_post_status "$@" ;;
    add-diagnosis)      cmd_add_diagnosis "$@" ;;
    query-diagnosis)    cmd_query_diagnosis "$@" ;;
    query-undiagnosed)  cmd_query_undiagnosed "$@" ;;
    add-request-log)    cmd_add_request_log "$@" ;;
    query-request-log)  cmd_query_request_log "$@" ;;
    add-historical-stat)   cmd_add_historical_stat "$@" ;;
    query-historical-stats) cmd_query_historical_stats "$@" ;;
    update-post-meta)   cmd_update_post_meta "$@" ;;
    *)
        echo "Usage: db.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init                           Create all tables"
        echo "  ensure-runtime-layout [--dry-run] [--json] [--verbose]"
        echo "                                 v3.0+: copy-first migrate v2 user data to agent/"
        echo "  ensure-schema [--dry-run] [--json]"
        echo "                                 v3.0+: auto-apply pending migrations to current DB"
        echo "  add-post '<json>'              Insert/upsert a post (upsert iff source=imported & note_id given)"
        echo "  add-metrics '<json>'           Insert metrics"
        echo "  log-choice '<json>'            Log a user choice"
        echo "  query-posts [--today|--days N|--status S|--source S]"
        echo "  query-metrics --post-id N"
        echo "  query-preferences              Aggregate preference weights"
        echo "  update-post-status <id> <status> [note_id]"
        echo "  update-post-meta '<json>'      Update topic_type/title_pattern/content_style by id"
        echo "  add-diagnosis '<json>'         Insert NoteRx diagnosis result"
        echo "  query-diagnosis --post-id N    Get latest diagnosis for a post"
        echo "  query-undiagnosed [--days N]   List published posts without diagnosis"
        echo "  add-request-log '<json>'       Record one MCP call"
        echo "  query-request-log [--days N --tool T --status S --limit N --summary]"
        echo "  add-historical-stat '<json>'   Snapshot account stats (for audit trend)"
        echo "  query-historical-stats [--limit N]"
        exit 1
        ;;
esac
