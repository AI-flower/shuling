#!/usr/bin/env python3
"""内容质量与 AI 托管感检查 — v3.0+

供 03-daily-flow.md 在生成 meta.json 前调用：分析最近 N 篇已发布帖
+ 当前待发草稿，检测 8 项"AI 托管感"信号（标题/正文/标签/emoji 模板化、
高频 AI 味词、图片页结构与清单体过度集中）。

设计原则：
  - 纯 stdlib（不引入新 pip 依赖）
  - 不调 LLM API（这是规则引擎，不是 AI 检测）
  - 8 项检测各自独立函数，易于单测
  - DB 缺失/为空 → score=100, warnings=[]，不报错
  - JSON 输出与 agent/schemas/content-qa-report.schema.json 对齐

用法：
  python3 agent/scripts/content-qa.py                              # 默认 human 表格
  python3 agent/scripts/content-qa.py --json                       # 单行 JSON
  python3 agent/scripts/content-qa.py --draft /tmp/xhs-post/meta.json
  python3 agent/scripts/content-qa.py --last-n 30 --threshold 70

退出码：
  0  score >= threshold（默认 70）
  1  score < threshold（auto-fixable / 提示重写）
  2  DB 不存在或参数错误（need-user / 配置问题）
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import math
import os
import re
import sqlite3
import sys
from collections import Counter
from pathlib import Path

# ─── 路径推导（与 db.sh 保持一致）──────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
AGENT_ROOT_DEFAULT = SCRIPT_DIR.parent


def _resolve_db_path(cli_db: str | None) -> Path:
    if cli_db:
        return Path(cli_db).expanduser().resolve()
    env_db = os.environ.get("SHULING_DB")
    if env_db:
        return Path(env_db).expanduser().resolve()
    env_root = os.environ.get("SHULING_AGENT_ROOT")
    if env_root:
        return (Path(env_root).expanduser().resolve() / "data" / "xhs.db")
    return AGENT_ROOT_DEFAULT / "data" / "xhs.db"


# ─── 高频 AI 味词汇表（hardcoded，便于后续维护）────────────────────
_AI_FLAVORED_WORDS: list[str] = [
    "赋能",
    "闭环",
    "抓手",
    "维度",
    "人设",
    "生态",
    "流量密码",
    "出圈",
    "接住",
    "超有用",
    "干货满满",
    "保姆级",
    "yyds",
    "绝绝子",
    "拿捏",
    "破防",
    "氛围感",
    "高级感",
    "整活",
    "通透",
    "顶配",
    "天花板",
    "复盘",
    "强势",
    "深度种草",
    "亲测有效",
    "宝藏",
    "进阶",
    "心智",
    "颗粒度",
    "对齐",
    "链路",
    "打法",
]


# ─── emoji 检测（粗粒度，覆盖常见 unicode block）───────────────────
_EMOJI_RE = re.compile(
    "["
    "\U0001F300-\U0001F5FF"  # 各种符号 & 象形
    "\U0001F600-\U0001F64F"  # 表情
    "\U0001F680-\U0001F6FF"  # 交通 & 地图
    "\U0001F700-\U0001F77F"  # 炼金
    "\U0001F780-\U0001F7FF"  # 几何
    "\U0001F800-\U0001F8FF"
    "\U0001F900-\U0001F9FF"  # 补充符号 & 象形
    "\U0001FA00-\U0001FA6F"
    "\U0001FA70-\U0001FAFF"
    "\U00002600-\U000026FF"  # 杂项符号
    "\U00002700-\U000027BF"  # 装饰符号
    "\U0001F1E0-\U0001F1FF"  # 国旗
    "]+",
    flags=re.UNICODE,
)


# ─── 文本相似度：trigram Jaccard ───────────────────────────────────
def _trigrams(s: str) -> set[tuple[str, str, str]]:
    s = (s or "").strip()
    if len(s) < 3:
        # 短串退化为 1-gram，避免 zip 空集
        return {(c, "", "") for c in s}
    return set(zip(s, s[1:], s[2:]))


def _jaccard(a: set, b: set) -> float:
    if not a and not b:
        return 1.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0


# ─── 数据加载 ─────────────────────────────────────────────────────
def _load_recent_posts(db_path: Path, last_n: int) -> list[dict]:
    """读最近 N 篇 published 帖（按 created_at desc）。表/库不存在返回 []。"""
    if not db_path.exists():
        return []
    try:
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        # 检查 posts 表是否存在
        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='posts'"
        )
        if not cur.fetchone():
            conn.close()
            return []
        cur.execute(
            """
            SELECT id, date, title, content, tags, topic_type,
                   title_pattern, content_style, status, created_at
            FROM posts
            WHERE status IN ('published','draft')
            ORDER BY datetime(created_at) DESC
            LIMIT ?
            """,
            (last_n,),
        )
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        return rows
    except sqlite3.DatabaseError:
        return []


def _load_recent_image_strategies(db_path: Path, last_n: int) -> list[str]:
    """读最近 N 篇的 generated_images.gen_strategy（按 post 聚合）。"""
    if not db_path.exists():
        return []
    try:
        conn = sqlite3.connect(str(db_path))
        cur = conn.cursor()
        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='generated_images'"
        )
        if not cur.fetchone():
            conn.close()
            return []
        # 每篇取 strategy 多数派（简化：第一条）
        cur.execute(
            """
            SELECT post_id, gen_strategy
            FROM generated_images
            WHERE gen_strategy IS NOT NULL AND gen_strategy != ''
            ORDER BY post_id DESC
            LIMIT ?
            """,
            (last_n * 5,),  # 一篇通常 ≤6 页
        )
        seen: dict[int, str] = {}
        for pid, strat in cur.fetchall():
            if pid not in seen:
                seen[pid] = strat
        conn.close()
        # 按 post_id desc 取最近 last_n
        ordered = [seen[k] for k in sorted(seen.keys(), reverse=True)][:last_n]
        return ordered
    except sqlite3.DatabaseError:
        return []


def _load_draft(draft_path: Path | None) -> dict | None:
    if not draft_path:
        return None
    if not draft_path.exists():
        return None
    try:
        return json.loads(draft_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


# ─── 8 项检查 ─────────────────────────────────────────────────────
# 每项返回 list[dict]：
#   {check, severity (info|warn|error), message, samples?, deduction}

JACCARD_TITLE_THRESHOLD = 0.6
JACCARD_OPENING_THRESHOLD = 0.6
PATTERN_RUN_LIMIT = 5
LIST_STYLE_RUN_LIMIT = 4
EMOJI_DENSE_LIMIT = 6
TAG_REPEAT_LIMIT = 5  # 最近 10 篇内 ≥5 篇用相同 5+ tag 组合
IMAGE_STRATEGY_RUN_LIMIT = 5
OPENING_LEN = 30


def check_title_similarity(posts: list[dict]) -> list[dict]:
    """1. 最近 30 篇标题两两 Jaccard >= 0.6 算重复。"""
    out: list[dict] = []
    titles = [(p.get("id"), (p.get("title") or "").strip()) for p in posts if p.get("title")]
    if len(titles) < 2:
        return out
    grams = [(pid, t, _trigrams(t)) for pid, t in titles]
    dup_pairs: list[tuple[str, str]] = []
    flagged: set = set()
    for i in range(len(grams)):
        for j in range(i + 1, len(grams)):
            sim = _jaccard(grams[i][2], grams[j][2])
            if sim >= JACCARD_TITLE_THRESHOLD:
                dup_pairs.append((grams[i][1], grams[j][1]))
                flagged.add(grams[i][0])
                flagged.add(grams[j][0])
    if dup_pairs:
        out.append(
            {
                "check": "title_similarity",
                "severity": "warn" if len(dup_pairs) < 5 else "error",
                "message": f"最近 {len(titles)} 篇里有 {len(flagged)} 篇标题 trigram Jaccard >= {JACCARD_TITLE_THRESHOLD}",
                "samples": [{"a": a, "b": b} for a, b in dup_pairs[:3]],
                "deduction": 25 if len(dup_pairs) >= 5 else 10,
            }
        )
    return out


def check_title_pattern_run(posts: list[dict]) -> list[dict]:
    """2. 同一 title_pattern 连续 ≥ 5 次。posts 已按 created_at desc。"""
    out: list[dict] = []
    patterns = [(p.get("id"), p.get("title_pattern") or "") for p in posts]
    run_pat = ""
    run_len = 0
    max_run = 0
    max_pat = ""
    for _, pat in patterns:
        if pat and pat == run_pat:
            run_len += 1
        else:
            run_pat = pat
            run_len = 1 if pat else 0
        if run_len > max_run and run_pat:
            max_run = run_len
            max_pat = run_pat
    if max_run >= PATTERN_RUN_LIMIT:
        out.append(
            {
                "check": "title_pattern_run",
                "severity": "warn",
                "message": f"标题模板「{max_pat}」连续 {max_run} 次（阈值 {PATTERN_RUN_LIMIT}）",
                "samples": [{"pattern": max_pat, "run_length": max_run}],
                "deduction": 10,
            }
        )
    return out


def check_opening_repeat(posts: list[dict]) -> list[dict]:
    """3. 正文开头 30 字相互 Jaccard >= 0.6。"""
    out: list[dict] = []
    openings = [
        (p.get("id"), (p.get("content") or "").strip()[:OPENING_LEN])
        for p in posts
        if p.get("content")
    ]
    openings = [(i, o) for i, o in openings if len(o) >= 10]
    if len(openings) < 2:
        return out
    grams = [(i, o, _trigrams(o)) for i, o in openings]
    flagged: set = set()
    pair_examples = []
    for i in range(len(grams)):
        for j in range(i + 1, len(grams)):
            sim = _jaccard(grams[i][2], grams[j][2])
            if sim >= JACCARD_OPENING_THRESHOLD:
                flagged.add(grams[i][0])
                flagged.add(grams[j][0])
                if len(pair_examples) < 3:
                    pair_examples.append({"a": grams[i][1], "b": grams[j][1]})
    if flagged:
        out.append(
            {
                "check": "opening_repeat",
                "severity": "warn" if len(flagged) < 6 else "error",
                "message": f"最近 {len(openings)} 篇里有 {len(flagged)} 篇正文前 {OPENING_LEN} 字高相似",
                "samples": pair_examples,
                "deduction": 25 if len(flagged) >= 6 else 10,
            }
        )
    return out


def _parse_tags(raw) -> list[str]:
    if not raw:
        return []
    if isinstance(raw, list):
        return [str(t).strip() for t in raw if str(t).strip()]
    s = str(raw).strip()
    if not s:
        return []
    # 试 JSON 数组
    if s.startswith("["):
        try:
            arr = json.loads(s)
            if isinstance(arr, list):
                return [str(t).strip() for t in arr if str(t).strip()]
        except json.JSONDecodeError:
            pass
    # 退化 split
    return [t.strip() for t in re.split(r"[,，;；\s]+", s) if t.strip()]


def check_tag_combo_repeat(posts: list[dict]) -> list[dict]:
    """4. 最近 10 篇用相同 5+ 标签组合 (frozenset 出现 ≥ 2 次)。"""
    out: list[dict] = []
    recent10 = posts[:10]
    combos: list[frozenset] = []
    for p in recent10:
        tags = _parse_tags(p.get("tags"))
        if len(tags) >= TAG_REPEAT_LIMIT:
            combos.append(frozenset(tags))
    if not combos:
        return out
    counter = Counter(combos)
    repeats = [(c, n) for c, n in counter.items() if n >= 2]
    if repeats:
        worst = max(repeats, key=lambda x: x[1])
        out.append(
            {
                "check": "tag_combo_repeat",
                "severity": "warn",
                "message": f"最近 10 篇里有同一组 {len(worst[0])} 个标签出现 {worst[1]} 次",
                "samples": [{"tags": sorted(worst[0]), "count": worst[1]}],
                "deduction": 10,
            }
        )
    return out


def _count_emoji(text: str) -> int:
    if not text:
        return 0
    return sum(len(m.group(0)) for m in _EMOJI_RE.finditer(text))


def check_emoji_density(posts: list[dict], draft: dict | None) -> list[dict]:
    """5. 单页 emoji 数 ≥ 6。检查最近帖 + 草稿。"""
    out: list[dict] = []
    samples: list[dict] = []
    items: list[tuple[str, str]] = []
    for p in posts[:10]:
        body = (p.get("title") or "") + "\n" + (p.get("content") or "")
        items.append((f"post#{p.get('id')}", body))
    if draft:
        body = str(draft.get("title", "")) + "\n" + str(draft.get("content", ""))
        items.append(("draft", body))
    over = []
    for label, body in items:
        n = _count_emoji(body)
        if n >= EMOJI_DENSE_LIMIT:
            over.append({"target": label, "emoji_count": n})
    if over:
        samples = over[:3]
        sev = "error" if any(s["emoji_count"] >= EMOJI_DENSE_LIMIT * 2 for s in over) else "warn"
        out.append(
            {
                "check": "emoji_density",
                "severity": sev,
                "message": f"{len(over)} 处 emoji 数 >= {EMOJI_DENSE_LIMIT}",
                "samples": samples,
                "deduction": 15 if sev == "warn" else 25,
            }
        )
    return out


def check_ai_flavored_words(posts: list[dict], draft: dict | None) -> list[dict]:
    """6. 高频 AI 味词汇命中。最近 10 篇命中率 >= 30% 报 warn；草稿命中也独立 warn。"""
    out: list[dict] = []
    word_set = _AI_FLAVORED_WORDS
    hits_per_post = 0
    sample_words: Counter = Counter()
    for p in posts[:10]:
        body = (p.get("title") or "") + " " + (p.get("content") or "")
        post_hits = [w for w in word_set if w in body]
        if post_hits:
            hits_per_post += 1
            for w in post_hits:
                sample_words[w] += 1
    total_recent = min(10, len(posts))
    if total_recent and hits_per_post / total_recent >= 0.3:
        top = sample_words.most_common(5)
        out.append(
            {
                "check": "ai_flavored_words",
                "severity": "warn",
                "message": f"最近 {total_recent} 篇里 {hits_per_post} 篇出现 AI 味词汇",
                "samples": [{"word": w, "count": n} for w, n in top],
                "deduction": 10,
            }
        )
    if draft:
        body = str(draft.get("title", "")) + " " + str(draft.get("content", ""))
        draft_hits = [w for w in word_set if w in body]
        if len(draft_hits) >= 2:
            out.append(
                {
                    "check": "ai_flavored_words_draft",
                    "severity": "warn",
                    "message": f"草稿命中 {len(draft_hits)} 个 AI 味词汇",
                    "samples": [{"word": w} for w in draft_hits[:5]],
                    "deduction": 10,
                }
            )
    return out


def check_image_strategy_run(strategies: list[str]) -> list[dict]:
    """7. 同一 generated_images.gen_strategy 连续 ≥ 5 篇。"""
    out: list[dict] = []
    if not strategies:
        return out
    run_s = ""
    run_len = 0
    max_run = 0
    max_s = ""
    for s in strategies:
        if s and s == run_s:
            run_len += 1
        else:
            run_s = s
            run_len = 1 if s else 0
        if run_len > max_run and run_s:
            max_run = run_len
            max_s = run_s
    if max_run >= IMAGE_STRATEGY_RUN_LIMIT:
        out.append(
            {
                "check": "image_strategy_run",
                "severity": "warn",
                "message": f"图片生成策略「{max_s}」连续 {max_run} 篇（阈值 {IMAGE_STRATEGY_RUN_LIMIT}）",
                "samples": [{"strategy": max_s, "run_length": max_run}],
                "deduction": 10,
            }
        )
    return out


def check_list_style_run(posts: list[dict]) -> list[dict]:
    """8. 连续多篇清单体（content_style='清单' 或 title_pattern='数字清单'）≥ 4 次。"""
    out: list[dict] = []
    run_len = 0
    max_run = 0
    for p in posts:
        cs = p.get("content_style") or ""
        tp = p.get("title_pattern") or ""
        is_list = ("清单" in cs) or ("数字清单" in tp) or ("列表" in cs)
        if is_list:
            run_len += 1
        else:
            run_len = 0
        if run_len > max_run:
            max_run = run_len
    if max_run >= LIST_STYLE_RUN_LIMIT:
        out.append(
            {
                "check": "list_style_run",
                "severity": "warn",
                "message": f"连续 {max_run} 篇清单体（阈值 {LIST_STYLE_RUN_LIMIT}）",
                "samples": [{"run_length": max_run}],
                "deduction": 10,
            }
        )
    return out


# ─── 主聚合 ───────────────────────────────────────────────────────
def run_all_checks(
    posts: list[dict], strategies: list[str], draft: dict | None
) -> list[dict]:
    warnings: list[dict] = []
    warnings.extend(check_title_similarity(posts))
    warnings.extend(check_title_pattern_run(posts))
    warnings.extend(check_opening_repeat(posts))
    warnings.extend(check_tag_combo_repeat(posts))
    warnings.extend(check_emoji_density(posts, draft))
    warnings.extend(check_ai_flavored_words(posts, draft))
    warnings.extend(check_image_strategy_run(strategies))
    warnings.extend(check_list_style_run(posts))
    # 草稿独立标题/开头检查 — 与历史比较
    if draft and posts:
        d_title = str(draft.get("title") or "").strip()
        d_open = str(draft.get("content") or "").strip()[:OPENING_LEN]
        if d_title:
            d_grams = _trigrams(d_title)
            for p in posts:
                t = (p.get("title") or "").strip()
                if t and _jaccard(d_grams, _trigrams(t)) >= JACCARD_TITLE_THRESHOLD:
                    warnings.append(
                        {
                            "check": "draft_title_similar_to_history",
                            "severity": "warn",
                            "message": "草稿标题与历史帖高相似",
                            "samples": [{"draft": d_title, "history": t}],
                            "deduction": 15,
                        }
                    )
                    break
        if d_open and len(d_open) >= 10:
            d_grams = _trigrams(d_open)
            for p in posts:
                o = (p.get("content") or "").strip()[:OPENING_LEN]
                if o and len(o) >= 10 and _jaccard(d_grams, _trigrams(o)) >= JACCARD_OPENING_THRESHOLD:
                    warnings.append(
                        {
                            "check": "draft_opening_similar_to_history",
                            "severity": "warn",
                            "message": "草稿正文开头与历史帖高相似",
                            "samples": [{"draft": d_open, "history": o}],
                            "deduction": 15,
                        }
                    )
                    break
    return warnings


def compute_score(warnings: list[dict]) -> int:
    score = 100
    for w in warnings:
        score -= int(w.get("deduction", 5))
    return max(0, min(100, score))


def build_report(
    posts: list[dict],
    strategies: list[str],
    draft: dict | None,
    target_post_id: int | None,
) -> dict:
    warnings = run_all_checks(posts, strategies, draft)
    score = compute_score(warnings)
    return {
        "ok": score >= 70,
        "score": score,
        "warnings": [
            {
                "check": w["check"],
                "severity": w["severity"],
                "message": w["message"],
                "samples": w.get("samples", []),
            }
            for w in warnings
        ],
        "checked_at": _dt.date.today().isoformat(),
        "target_post_id": target_post_id,
        "sample_size": {
            "recent_posts": len(posts),
            "image_strategies": len(strategies),
            "draft_present": draft is not None,
        },
    }


# ─── 输出渲染 ─────────────────────────────────────────────────────
_COLOR_RESET = "\033[0m"
_COLOR_GREEN = "\033[32m"
_COLOR_YELLOW = "\033[33m"
_COLOR_RED = "\033[31m"
_COLOR_BOLD = "\033[1m"


def _maybe_color(s: str, color: str) -> str:
    if not sys.stdout.isatty():
        return s
    return f"{color}{s}{_COLOR_RESET}"


def render_human(report: dict, threshold: int) -> None:
    score = report["score"]
    if score >= threshold:
        score_str = _maybe_color(f"{score}/100 OK", _COLOR_GREEN)
    elif score >= 50:
        score_str = _maybe_color(f"{score}/100 WARN", _COLOR_YELLOW)
    else:
        score_str = _maybe_color(f"{score}/100 FAIL", _COLOR_RED)

    print(_maybe_color("━━━ content-qa 报告 ━━━", _COLOR_BOLD))
    print(f"score:        {score_str}   threshold: {threshold}")
    print(f"checked_at:   {report['checked_at']}")
    ss = report["sample_size"]
    print(
        f"sample_size:  recent_posts={ss['recent_posts']}  "
        f"image_strategies={ss['image_strategies']}  "
        f"draft={'yes' if ss['draft_present'] else 'no'}"
    )
    warns = report["warnings"]
    if not warns:
        print(_maybe_color("OK 无 AI 托管感信号。", _COLOR_GREEN))
        return
    print()
    print(_maybe_color(f"warnings ({len(warns)}):", _COLOR_BOLD))
    for w in warns:
        sev = w["severity"]
        if sev == "error":
            tag = _maybe_color("[ERR ]", _COLOR_RED)
        elif sev == "warn":
            tag = _maybe_color("[WARN]", _COLOR_YELLOW)
        else:
            tag = "[INFO]"
        print(f"  {tag} {w['check']}: {w['message']}")
        for s in (w.get("samples") or [])[:2]:
            preview = json.dumps(s, ensure_ascii=False)
            if len(preview) > 120:
                preview = preview[:117] + "..."
            print(f"        {preview}")


# ─── CLI ─────────────────────────────────────────────────────────
def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="内容质量与 AI 托管感检查（v3.0+）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "退出码: 0=score>=threshold / 1=score<threshold / 2=参数或 DB 错误\n"
            "环境变量: SHULING_DB（DB 路径）, SHULING_AGENT_ROOT（agent/ 根）\n"
        ),
    )
    parser.add_argument("--db", help="xhs.db 路径（覆盖 env / 默认推导）")
    parser.add_argument("--draft", help="待检查草稿 meta.json 路径")
    parser.add_argument("--last-n", type=int, default=30, help="分析最近 N 篇（默认 30）")
    parser.add_argument("--threshold", type=int, default=70, help="score 阈值（默认 70）")
    out_group = parser.add_mutually_exclusive_group()
    out_group.add_argument("--json", action="store_true", help="输出单行 JSON")
    out_group.add_argument("--human", action="store_true", help="输出彩色表格（默认）")
    args = parser.parse_args(argv)

    if args.last_n < 1 or args.last_n > 1000:
        print(
            json.dumps(
                {"ok": False, "error": "invalid --last-n (1..1000)"},
                ensure_ascii=False,
            )
        )
        return 2

    db_path = _resolve_db_path(args.db)
    draft_path = Path(args.draft).expanduser().resolve() if args.draft else None

    # 草稿明确指定但读不到 → exit 2
    if args.draft and (not draft_path or not draft_path.exists()):
        msg = {
            "ok": False,
            "error": "draft_not_found",
            "message": f"draft not found: {args.draft}",
        }
        print(json.dumps(msg, ensure_ascii=False))
        return 2

    posts = _load_recent_posts(db_path, args.last_n)
    strategies = _load_recent_image_strategies(db_path, args.last_n)
    draft = _load_draft(draft_path)

    target_post_id = None
    if draft:
        try:
            tp = draft.get("post_id") or draft.get("id")
            if tp is not None:
                target_post_id = int(tp)
        except (TypeError, ValueError):
            target_post_id = None

    # DB 不存在或没有任何历史 → 直接 100 分
    if not posts and not draft:
        report = {
            "ok": True,
            "score": 100,
            "warnings": [],
            "checked_at": _dt.date.today().isoformat(),
            "target_post_id": None,
            "sample_size": {
                "recent_posts": 0,
                "image_strategies": 0,
                "draft_present": False,
            },
            "note": "no history yet",
        }
    else:
        report = build_report(posts, strategies, draft, target_post_id)

    if args.json:
        print(json.dumps(report, ensure_ascii=False))
    else:
        render_human(report, args.threshold)

    return 0 if report["score"] >= args.threshold else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
