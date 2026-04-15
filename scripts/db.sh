#!/usr/bin/env bash
set -e

# ─── Auto-detect paths ───────────────────────────────────────────────
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DB_DIR="$SKILL_DIR/data"
DB_PATH="$DB_DIR/xhs.db"

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
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

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
"
    echo '{"ok": true, "tables": ["posts","post_metrics","user_choices","topic_candidates","comment_insights"]}'
}

cmd_add_post() {
    local json="$1"
    [ -z "$json" ] && { echo '{"error": "missing JSON argument"}' >&2; exit 1; }

    local date slot title content tags note_id topic_type title_pattern content_style status
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

    local new_id
    new_id="$(sql "
INSERT INTO posts (date, slot, title, content, tags, note_id, topic_type, title_pattern, content_style, status)
VALUES ('$date','$slot','$title','$content','$tags','$note_id','$topic_type','$title_pattern','$content_style','$status');
SELECT last_insert_rowid();
")"
    echo "{\"id\": $new_id}"
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
    local where=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --today)
                where="WHERE date = date('now')"
                shift
                ;;
            --days)
                shift
                local n="${1:-7}"
                where="WHERE date >= date('now', '-${n} days')"
                shift
                ;;
            --status)
                shift
                local st
                st="$(sql_escape "$1")"
                where="WHERE status = '$st'"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    sql_json "SELECT * FROM posts $where ORDER BY created_at DESC;"
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

# ─── Main dispatch ────────────────────────────────────────────────────

cmd="${1:-}"
shift || true

case "$cmd" in
    init)               cmd_init ;;
    add-post)           cmd_add_post "$@" ;;
    add-metrics)        cmd_add_metrics "$@" ;;
    log-choice)         cmd_log_choice "$@" ;;
    query-posts)        cmd_query_posts "$@" ;;
    query-metrics)      cmd_query_metrics "$@" ;;
    query-preferences)  cmd_query_preferences ;;
    update-post-status) cmd_update_post_status "$@" ;;
    *)
        echo "Usage: db.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init                           Create all tables"
        echo "  add-post '<json>'              Insert a post"
        echo "  add-metrics '<json>'           Insert metrics"
        echo "  log-choice '<json>'            Log a user choice"
        echo "  query-posts [--today|--days N|--status S]"
        echo "  query-metrics --post-id N"
        echo "  query-preferences              Aggregate preference weights"
        echo "  update-post-status <id> <status> [note_id]"
        exit 1
        ;;
esac
