"""XHS 自动化系统 - SQLite 数据库模块"""
import sqlite3
import json
import os
from datetime import datetime, date

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "xhs.db")


def get_conn():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db():
    conn = get_conn()
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        slot TEXT NOT NULL,
        post_dir TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        tags TEXT,
        post_type TEXT NOT NULL,
        github_repo TEXT,
        github_stars INTEGER,
        xhs_note_id TEXT,
        scheduled_at TEXT,
        published_at TEXT,
        status TEXT DEFAULT 'draft',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS post_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id INTEGER REFERENCES posts(id),
        checked_at TEXT NOT NULL,
        likes INTEGER DEFAULT 0,
        saves INTEGER DEFAULT 0,
        comments INTEGER DEFAULT 0,
        shares INTEGER DEFAULT 0,
        checkpoint TEXT DEFAULT 'review'
    );

    CREATE TABLE IF NOT EXISTS topics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        github_repo TEXT,
        topic_keyword TEXT,
        xhs_competition INTEGER DEFAULT 0,
        selected BOOLEAN DEFAULT 0,
        reason TEXT
    );

    CREATE TABLE IF NOT EXISTS daily_reviews (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        total_likes INTEGER DEFAULT 0,
        total_saves INTEGER DEFAULT 0,
        total_comments INTEGER DEFAULT 0,
        follower_count INTEGER,
        best_post_id INTEGER REFERENCES posts(id),
        insights TEXT,
        telegram_sent BOOLEAN DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        slot TEXT NOT NULL,
        draft_id TEXT NOT NULL,
        angle TEXT NOT NULL,
        style TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        tags TEXT,
        suggested_format TEXT,
        image_prompts TEXT,
        key_points TEXT,
        image_strategy TEXT DEFAULT 'auto',
        selected BOOLEAN DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS draft_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        draft_row_id INTEGER REFERENCES drafts(id),
        platform_score REAL,
        quality_score REAL,
        history_score REAL,
        total_score REAL,
        highlights TEXT,
        risks TEXT,
        evaluated_at TEXT
    );

    CREATE TABLE IF NOT EXISTS comment_analysis (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id INTEGER REFERENCES posts(id),
        analyzed_at TEXT NOT NULL,
        total_comments INTEGER DEFAULT 0,
        positive_count INTEGER DEFAULT 0,
        negative_count INTEGER DEFAULT 0,
        question_count INTEGER DEFAULT 0,
        top_questions TEXT,
        top_praise TEXT,
        top_complaints TEXT,
        content_requests TEXT,
        ai_summary TEXT
    );

    CREATE TABLE IF NOT EXISTS keyword_tracking (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        keyword TEXT NOT NULL,
        checked_at TEXT NOT NULL,
        note_count INTEGER,
        avg_likes REAL,
        avg_saves REAL,
        blue_ocean_index REAL,
        trend_direction TEXT
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

    CREATE TABLE IF NOT EXISTS note_diagnosis (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id INTEGER REFERENCES posts(id),
        diagnosed_at TEXT NOT NULL,
        source TEXT DEFAULT 'noterx',
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
    """)
    conn.commit()
    conn.close()


# ---- Posts ----

def add_post(date_str, slot, post_dir, title, content, tags, post_type,
             github_repo=None, github_stars=None, scheduled_at=None,
             angle=None, style=None, pattern_used=None):
    conn = get_conn()
    existing = conn.execute(
        "SELECT id FROM posts WHERE date=? AND slot=? AND post_dir=? ORDER BY id DESC LIMIT 1",
        (date_str, slot, post_dir)
    ).fetchone()
    if existing:
        post_id = existing["id"]
        conn.close()
        return post_id

    cur = conn.execute(
        """INSERT INTO posts (date, slot, post_dir, title, content, tags, post_type,
           github_repo, github_stars, scheduled_at, status, angle, style, pattern_used)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft', ?, ?, ?)""",
        (date_str, slot, post_dir, title, content, json.dumps(tags, ensure_ascii=False),
         post_type, github_repo, github_stars, scheduled_at, angle, style, pattern_used)
    )
    conn.commit()
    post_id = cur.lastrowid
    conn.close()
    return post_id


def update_post_status(post_id, status, xhs_note_id=None):
    conn = get_conn()
    if xhs_note_id:
        conn.execute("UPDATE posts SET status=?, xhs_note_id=?, published_at=? WHERE id=?",
                      (status, xhs_note_id, datetime.now().isoformat(), post_id))
    else:
        conn.execute("UPDATE posts SET status=? WHERE id=?", (status, post_id))
    conn.commit()
    conn.close()


def get_posts_by_date(date_str, slot=None):
    conn = get_conn()
    if slot:
        rows = conn.execute("SELECT * FROM posts WHERE date=? AND slot=?", (date_str, slot)).fetchall()
    else:
        rows = conn.execute("SELECT * FROM posts WHERE date=?", (date_str,)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_draft_posts(date_str, slot):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM posts WHERE date=? AND slot=? AND status='draft'",
        (date_str, slot)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---- Metrics ----

def add_metrics(post_id, likes=0, saves=0, comments=0, shares=0, checkpoint="review"):
    conn = get_conn()
    conn.execute(
        "INSERT INTO post_metrics (post_id, checked_at, likes, saves, comments, shares, checkpoint) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (post_id, datetime.now().isoformat(), likes, saves, comments, shares, checkpoint)
    )
    conn.commit()
    conn.close()


def get_latest_metrics(post_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM post_metrics WHERE post_id=? ORDER BY checked_at DESC LIMIT 1",
        (post_id,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


# ---- Topics ----

def add_topic(date_str, github_repo=None, topic_keyword=None, xhs_competition=0, selected=False, reason=None):
    conn = get_conn()
    conn.execute(
        "INSERT INTO topics (date, github_repo, topic_keyword, xhs_competition, selected, reason) VALUES (?, ?, ?, ?, ?, ?)",
        (date_str, github_repo, topic_keyword, xhs_competition, selected, reason)
    )
    conn.commit()
    conn.close()


def is_topic_used(github_repo):
    conn = get_conn()
    row = conn.execute(
        "SELECT COUNT(*) as cnt FROM posts WHERE github_repo=? AND status IN ('scheduled','published')",
        (github_repo,)
    ).fetchone()
    conn.close()
    return row["cnt"] > 0


# ---- Reviews ----

def add_review(date_str, total_likes, total_saves, total_comments, follower_count=None, best_post_id=None, insights=None):
    conn = get_conn()
    conn.execute(
        """INSERT OR REPLACE INTO daily_reviews
           (date, total_likes, total_saves, total_comments, follower_count, best_post_id, insights, telegram_sent)
           VALUES (?, ?, ?, ?, ?, ?, ?, 0)""",
        (date_str, total_likes, total_saves, total_comments, follower_count, best_post_id, insights)
    )
    conn.commit()
    conn.close()


def mark_review_sent(date_str):
    conn = get_conn()
    conn.execute("UPDATE daily_reviews SET telegram_sent=1 WHERE date=?", (date_str,))
    conn.commit()
    conn.close()


def get_trend(days=7):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM daily_reviews ORDER BY date DESC LIMIT ?", (days,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


## ---- Schema Migration ----

def migrate_db():
    """为 posts 表添加 angle/style 字段（如果不存在）"""
    conn = get_conn()
    cursor = conn.execute("PRAGMA table_info(posts)")
    columns = {row["name"] for row in cursor.fetchall()}
    if "angle" not in columns:
        conn.execute("ALTER TABLE posts ADD COLUMN angle TEXT")
    if "style" not in columns:
        conn.execute("ALTER TABLE posts ADD COLUMN style TEXT")
    # post_metrics: checkpoint 字段
    cursor = conn.execute("PRAGMA table_info(post_metrics)")
    pm_columns = {row["name"] for row in cursor.fetchall()}
    if "checkpoint" not in pm_columns:
        conn.execute("ALTER TABLE post_metrics ADD COLUMN checkpoint TEXT DEFAULT 'review'")
    # posts: pattern_used 字段
    cursor = conn.execute("PRAGMA table_info(posts)")
    posts_columns = {row["name"] for row in cursor.fetchall()}
    if "pattern_used" not in posts_columns:
        conn.execute("ALTER TABLE posts ADD COLUMN pattern_used TEXT")
    # note_diagnosis table (NoteRx integration)
    try:
        conn.execute("SELECT 1 FROM note_diagnosis LIMIT 1")
    except sqlite3.OperationalError:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS note_diagnosis (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                post_id INTEGER REFERENCES posts(id),
                diagnosed_at TEXT NOT NULL,
                source TEXT DEFAULT 'noterx',
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
            )
        """)
    conn.commit()
    conn.close()


# ---- Drafts ----

def add_draft(date_str, slot, draft_id, angle, style, title, content,
              tags=None, suggested_format="image_text", image_prompts=None,
              key_points=None, image_strategy="auto"):
    conn = get_conn()
    cur = conn.execute(
        """INSERT INTO drafts (date, slot, draft_id, angle, style, title, content,
           tags, suggested_format, image_prompts, key_points, image_strategy)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (date_str, slot, draft_id, angle, style, title, content,
         json.dumps(tags, ensure_ascii=False) if tags else None,
         suggested_format,
         json.dumps(image_prompts, ensure_ascii=False) if image_prompts else None,
         json.dumps(key_points, ensure_ascii=False) if key_points else None,
         image_strategy)
    )
    conn.commit()
    row_id = cur.lastrowid
    conn.close()
    return row_id


def mark_draft_selected(draft_row_id):
    conn = get_conn()
    conn.execute("UPDATE drafts SET selected=1 WHERE id=?", (draft_row_id,))
    conn.commit()
    conn.close()


def get_drafts_by_date_slot(date_str, slot):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM drafts WHERE date=? AND slot=? ORDER BY id",
        (date_str, slot)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_draft_by_id(draft_row_id):
    conn = get_conn()
    row = conn.execute("SELECT * FROM drafts WHERE id=?", (draft_row_id,)).fetchone()
    conn.close()
    return dict(row) if row else None


def get_history_performance(days=30):
    """获取历史 angle/style 组合的平均互动率，用于历史对标"""
    conn = get_conn()
    rows = conn.execute("""
        SELECT p.angle, p.style, COUNT(*) as cnt,
               AVG(m.likes) as avg_likes, AVG(m.saves) as avg_saves,
               AVG(m.comments) as avg_comments
        FROM posts p
        JOIN post_metrics m ON m.post_id = p.id
        WHERE p.angle IS NOT NULL AND p.published_at IS NOT NULL
          AND p.date >= date('now', ?)
        GROUP BY p.angle, p.style
    """, (f"-{days} days",)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_published_post_count():
    """获取已发布帖子总数，用于冷启动权重判断"""
    conn = get_conn()
    row = conn.execute(
        "SELECT COUNT(*) as cnt FROM posts WHERE status='published'"
    ).fetchone()
    conn.close()
    return row["cnt"] if row else 0


def get_recent_angles(days=7):
    """获取最近 N 天使用过的角度，用于多样性选择"""
    conn = get_conn()
    rows = conn.execute(
        "SELECT DISTINCT angle FROM drafts WHERE selected=1 AND date >= date('now', ?)",
        (f"-{days} days",)
    ).fetchall()
    conn.close()
    return [r["angle"] for r in rows]


# ---- Draft Scores ----

def add_draft_score(draft_row_id, platform_score, quality_score, history_score,
                    total_score, highlights="", risks=""):
    conn = get_conn()
    conn.execute(
        """INSERT INTO draft_scores (draft_row_id, platform_score, quality_score,
           history_score, total_score, highlights, risks, evaluated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (draft_row_id, platform_score, quality_score, history_score,
         total_score, highlights, risks, datetime.now().isoformat())
    )
    conn.commit()
    conn.close()


def get_draft_rankings(date_str, slot):
    """获取指定日期槽位的草稿排名"""
    conn = get_conn()
    rows = conn.execute("""
        SELECT d.*, s.platform_score, s.quality_score, s.history_score,
               s.total_score, s.highlights, s.risks
        FROM drafts d
        LEFT JOIN draft_scores s ON s.draft_row_id = d.id
        WHERE d.date=? AND d.slot=?
        ORDER BY s.total_score DESC NULLS LAST, d.id
    """, (date_str, slot)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---- Comment Analysis ----

def add_comment_analysis(post_id, total_comments=0, positive_count=0,
                         negative_count=0, question_count=0,
                         top_questions=None, top_praise=None,
                         top_complaints=None, content_requests=None,
                         ai_summary=None):
    conn = get_conn()
    conn.execute(
        """INSERT INTO comment_analysis (post_id, analyzed_at, total_comments,
           positive_count, negative_count, question_count,
           top_questions, top_praise, top_complaints, content_requests, ai_summary)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (post_id, datetime.now().isoformat(), total_comments,
         positive_count, negative_count, question_count,
         json.dumps(top_questions, ensure_ascii=False) if top_questions else None,
         json.dumps(top_praise, ensure_ascii=False) if top_praise else None,
         json.dumps(top_complaints, ensure_ascii=False) if top_complaints else None,
         json.dumps(content_requests, ensure_ascii=False) if content_requests else None,
         ai_summary)
    )
    conn.commit()
    conn.close()


def get_latest_feedback(limit=3):
    """获取最近 N 篇帖子的评论分析，用于反馈注入"""
    conn = get_conn()
    rows = conn.execute(
        """SELECT ca.*, p.title, p.angle, p.style FROM comment_analysis ca
           JOIN posts p ON p.id = ca.post_id
           ORDER BY ca.analyzed_at DESC LIMIT ?""",
        (limit,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_unanalyzed_posts(days=3):
    """获取最近 N 天内已发布但未做评论分析的帖子"""
    conn = get_conn()
    rows = conn.execute("""
        SELECT p.* FROM posts p
        LEFT JOIN comment_analysis ca ON ca.post_id = p.id
        WHERE p.status = 'published' AND ca.id IS NULL
          AND p.date >= date('now', ?)
    """, (f"-{days} days",)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---- Note Diagnosis (NoteRx) ----

def add_diagnosis(post_id, source="noterx", overall_score=0, grade="",
                  content_score=0, visual_score=0, growth_score=0,
                  user_reaction_score=0, issues=None, suggestions=None,
                  debate_summary="", diagnosis_json=None):
    conn = get_conn()
    conn.execute(
        """INSERT INTO note_diagnosis (post_id, diagnosed_at, source,
           overall_score, grade, content_score, visual_score,
           growth_score, user_reaction_score, issues, suggestions,
           debate_summary, diagnosis_json)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (post_id, datetime.now().isoformat(), source,
         overall_score, grade, content_score, visual_score,
         growth_score, user_reaction_score,
         json.dumps(issues, ensure_ascii=False) if issues else None,
         json.dumps(suggestions, ensure_ascii=False) if suggestions else None,
         debate_summary,
         json.dumps(diagnosis_json, ensure_ascii=False) if diagnosis_json else None)
    )
    conn.commit()
    conn.close()


def get_latest_diagnosis(post_id):
    """获取某篇帖子最新一次诊断"""
    conn = get_conn()
    row = conn.execute(
        """SELECT * FROM note_diagnosis WHERE post_id = ?
           ORDER BY diagnosed_at DESC LIMIT 1""",
        (post_id,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def get_recent_diagnoses(limit=5):
    """获取最近 N 次诊断结果（用于反馈注入）"""
    conn = get_conn()
    rows = conn.execute(
        """SELECT nd.*, p.title, p.angle, p.style, p.slot
           FROM note_diagnosis nd
           JOIN posts p ON p.id = nd.post_id
           ORDER BY nd.diagnosed_at DESC LIMIT ?""",
        (limit,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_undiagnosed_posts(days=3):
    """获取最近 N 天已发布但未诊断的帖子"""
    conn = get_conn()
    rows = conn.execute("""
        SELECT p.* FROM posts p
        LEFT JOIN note_diagnosis nd ON nd.post_id = p.id
        WHERE p.status = 'published' AND nd.id IS NULL
          AND p.date >= date('now', ?)
    """, (f"-{days} days",)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---- Keyword Tracking ----

def add_keyword_tracking(keyword, note_count=0, avg_likes=0.0, avg_saves=0.0,
                         blue_ocean_index=0.0, trend_direction="stable"):
    conn = get_conn()
    conn.execute(
        """INSERT INTO keyword_tracking (keyword, checked_at, note_count,
           avg_likes, avg_saves, blue_ocean_index, trend_direction)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (keyword, datetime.now().isoformat(), note_count,
         avg_likes, avg_saves, blue_ocean_index, trend_direction)
    )
    conn.commit()
    conn.close()


def get_keyword_cache(keyword, max_age_hours=24):
    """获取关键词缓存（同一天不重复搜索）"""
    conn = get_conn()
    row = conn.execute(
        """SELECT * FROM keyword_tracking
           WHERE keyword=? AND checked_at >= datetime('now', ?)
           ORDER BY checked_at DESC LIMIT 1""",
        (keyword, f"-{max_age_hours} hours")
    ).fetchone()
    conn.close()
    return dict(row) if row else None


# ---- Generated Images ----

def add_generated_image(post_id, image_index, prompt, image_path=None,
                        gen_model=None, gen_strategy="ai", gen_status="pending"):
    conn = get_conn()
    cur = conn.execute(
        """INSERT INTO generated_images (post_id, image_index, prompt, image_path,
           gen_model, gen_strategy, gen_status)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (post_id, image_index, prompt, image_path, gen_model, gen_strategy, gen_status)
    )
    conn.commit()
    row_id = cur.lastrowid
    conn.close()
    return row_id


def update_image_status(image_id, gen_status, image_path=None):
    conn = get_conn()
    if image_path:
        conn.execute("UPDATE generated_images SET gen_status=?, image_path=? WHERE id=?",
                      (gen_status, image_path, image_id))
    else:
        conn.execute("UPDATE generated_images SET gen_status=? WHERE id=?",
                      (gen_status, image_id))
    conn.commit()
    conn.close()


def get_post_images(post_id):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM generated_images WHERE post_id=? ORDER BY image_index",
        (post_id,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def has_metric_at_checkpoint(post_id, checkpoint):
    """检查是否已采集该时间点的数据"""
    conn = get_conn()
    row = conn.execute(
        "SELECT COUNT(*) as cnt FROM post_metrics WHERE post_id=? AND checkpoint=?",
        (post_id, checkpoint)
    ).fetchone()
    conn.close()
    return row["cnt"] > 0


def get_published_posts_with_notes():
    """获取所有已发布且有 note_id 的帖子"""
    conn = get_conn()
    rows = conn.execute(
        "SELECT id, xhs_note_id, published_at FROM posts WHERE status='published' AND xhs_note_id IS NOT NULL"
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_posts_between_dates(start_date, end_date):
    """获取日期范围内的帖子，用于周复盘导出"""
    conn = get_conn()
    rows = conn.execute("""
        SELECT p.id, p.date, p.slot, p.title, p.angle, p.style, p.github_repo,
               p.github_stars, p.status, p.xhs_note_id
        FROM posts p
        WHERE p.date >= ? AND p.date <= ? AND p.status = 'published'
        ORDER BY p.date, p.slot
    """, (start_date, end_date)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_all_metrics_for_post(post_id):
    """获取帖子的所有 checkpoint 指标，用于增长曲线"""
    conn = get_conn()
    rows = conn.execute(
        "SELECT checkpoint, likes, saves, comments, shares, checked_at FROM post_metrics WHERE post_id=? ORDER BY checked_at",
        (post_id,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_draft_score_for_post(post_id):
    """获取帖子对应的草稿预测分"""
    conn = get_conn()
    row = conn.execute("""
        SELECT ds.total_score FROM draft_scores ds
        JOIN drafts d ON d.id = ds.draft_row_id
        JOIN posts p ON p.date = d.date AND p.slot = d.slot
        WHERE p.id = ? AND d.selected = 1
        ORDER BY ds.total_score DESC LIMIT 1
    """, (post_id,)).fetchone()
    conn.close()
    return row["total_score"] if row else None


# 初始化
if __name__ == "__main__":
    init_db()
    migrate_db()
    print(f"Database initialized at {DB_PATH}")
