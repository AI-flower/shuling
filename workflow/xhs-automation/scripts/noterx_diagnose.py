"""NoteRx API 集成 - 调用 noterx.muran.tech 诊断已发布帖子"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import db

try:
    import requests
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "-q"])
    import requests

NOTERX_BASE = os.environ.get("NOTERX_API_URL", "https://noterx.muran.tech")
NOTERX_TIMEOUT_PRE = int(os.environ.get("NOTERX_TIMEOUT_PRE", "15"))
NOTERX_TIMEOUT_FULL = int(os.environ.get("NOTERX_TIMEOUT_FULL", "150"))

# 品类映射：我们的帖子 → NoteRx 支持的 category
# NoteRx 支持: food, fashion, tech, travel, beauty, fitness, lifestyle, home
CATEGORY_MAP = {
    "tech": "tech",
    "ai": "tech",
    "科技": "tech",
    "编程": "tech",
    "开发": "tech",
    "工具": "tech",
}
DEFAULT_CATEGORY = "tech"


def _map_category(our_category):
    """将我们的品类映射到 NoteRx 支持的品类"""
    if not our_category:
        return DEFAULT_CATEGORY
    key = our_category.lower().strip()
    return CATEGORY_MAP.get(key, DEFAULT_CATEGORY)


def pre_score(title, content="", category="tech", tags=None, image_count=0):
    """
    调用 NoteRx /api/pre-score（即时评分，<50ms，零 LLM 成本）。
    返回 dict 或 None（失败时）。
    """
    url = f"{NOTERX_BASE}/api/pre-score"
    tag_str = ",".join(tags) if tags else ""
    try:
        resp = requests.post(url, data={
            "title": title,
            "content": content,
            "category": _map_category(category),
            "tags": tag_str,
            "image_count": image_count,
        }, timeout=NOTERX_TIMEOUT_PRE)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        print(f"  NoteRx pre-score 失败: {e}", file=sys.stderr)
        return None


def full_diagnose(title, content="", category="tech", tags=None):
    """
    调用 NoteRx /api/diagnose（完整 5-Agent 诊断，60-90s）。
    返回 dict 或 None（失败时）。
    """
    url = f"{NOTERX_BASE}/api/diagnose"
    tag_str = ",".join(tags) if tags else ""
    try:
        resp = requests.post(url, data={
            "title": title,
            "content": content,
            "category": _map_category(category),
            "tags": tag_str,
        }, timeout=NOTERX_TIMEOUT_FULL)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        print(f"  NoteRx full-diagnose 失败: {e}", file=sys.stderr)
        return None


def diagnose_post(post_id, title, content="", tags=None, category="tech",
                  full=False, image_count=0):
    """
    诊断一篇帖子并写入 DB。
    full=False: 只调 pre-score（快速，零成本）
    full=True:  调完整诊断（60-90s，消耗对方 LLM tokens）
    返回诊断结果 dict 或 None。
    """
    tag_list = []
    if tags:
        if isinstance(tags, str):
            try:
                tag_list = json.loads(tags)
            except (json.JSONDecodeError, TypeError):
                tag_list = [t.strip() for t in tags.split(",") if t.strip()]
        elif isinstance(tags, list):
            tag_list = tags

    # 1. 始终调 pre-score
    pre = pre_score(title, content, category, tag_list, image_count=image_count)
    if not pre:
        print(f"  帖子 {post_id} pre-score 失败，跳过诊断")
        return None

    result = {
        "source": "noterx-pre",
        "overall_score": pre.get("total_score", 0),
        "grade": _score_to_grade(pre.get("total_score", 0)),
        "content_score": pre.get("dimensions", {}).get("content_quality", 0),
        "visual_score": pre.get("dimensions", {}).get("visual_quality", 0),
        "growth_score": pre.get("dimensions", {}).get("tag_strategy", 0),
        "user_reaction_score": pre.get("dimensions", {}).get("engagement_potential", 0),
        "issues": [],
        "suggestions": [],
        "debate_summary": "",
        "pre_score_raw": pre,
    }

    # 2. 可选：完整诊断
    if full:
        print(f"  调用 NoteRx 完整诊断（预计 60-90s）...")
        t0 = time.time()
        diag = full_diagnose(title, content, category, tag_list)
        elapsed = time.time() - t0
        if diag:
            result["source"] = "noterx-full"
            result["overall_score"] = diag.get("overall_score", result["overall_score"])
            result["grade"] = diag.get("grade", result["grade"])
            radar = diag.get("radar_data", {})
            result["content_score"] = radar.get("content", result["content_score"])
            result["visual_score"] = radar.get("visual", result["visual_score"])
            result["growth_score"] = radar.get("growth", result["growth_score"])
            result["user_reaction_score"] = radar.get("user_reaction", result["user_reaction_score"])
            result["issues"] = _extract_issues(diag)
            result["suggestions"] = _extract_suggestions(diag)
            result["debate_summary"] = diag.get("debate_summary", "")
            result["full_diag_raw"] = diag
            print(f"  完整诊断完成 ({elapsed:.1f}s): {result['grade']} {result['overall_score']}分")
        else:
            print(f"  完整诊断失败 ({elapsed:.1f}s)，使用 pre-score 结果")

    # 3. 写入 DB
    diagnosis_json = result.get("full_diag_raw") or result.get("pre_score_raw")
    db.add_diagnosis(
        post_id=post_id,
        source=result["source"],
        overall_score=result["overall_score"],
        grade=result["grade"],
        content_score=result["content_score"],
        visual_score=result["visual_score"],
        growth_score=result["growth_score"],
        user_reaction_score=result["user_reaction_score"],
        issues=result["issues"],
        suggestions=result["suggestions"],
        debate_summary=result["debate_summary"],
        diagnosis_json=diagnosis_json,
    )

    return result


def _extract_issues(diag):
    """从完整诊断结果提取 issues 列表（字符串）"""
    issues = []
    for iss in diag.get("issues", []):
        if isinstance(iss, dict):
            desc = iss.get("description", "")
            agent = iss.get("from_agent", "")
            if desc:
                prefix = f"[{agent}]" if agent else ""
                issues.append(f"{prefix} {desc}".strip())
        elif isinstance(iss, str):
            issues.append(iss)
    return issues


def _extract_suggestions(diag):
    """从完整诊断结果提取 suggestions 列表（字符串）"""
    suggestions = []
    for sug in diag.get("suggestions", []):
        if isinstance(sug, dict):
            desc = sug.get("description", "")
            impact = sug.get("expected_impact", "")
            if desc:
                text = desc
                if impact:
                    text += f"（预期: {impact}）"
                suggestions.append(text)
        elif isinstance(sug, str):
            suggestions.append(sug)
    return suggestions


def _score_to_grade(score):
    if score >= 90:
        return "S"
    if score >= 75:
        return "A"
    if score >= 60:
        return "B"
    if score >= 40:
        return "C"
    return "D"


# ---- CLI 入口：手动诊断/补诊 ----

def backfill_diagnosis(days=3, full=False):
    """补充诊断最近未诊断的帖子"""
    db.init_db()
    db.migrate_db()
    posts = db.get_undiagnosed_posts(days=days)
    if not posts:
        print(f"最近 {days} 天没有未诊断的帖子")
        return

    print(f"=== 补充诊断 {len(posts)} 篇帖子 (full={full}) ===\n")
    for p in posts:
        print(f"[{p['date']}] {p['title']}")
        tags = p.get("tags")
        images = db.get_post_images(p["id"])
        img_count = len(images) if images else 0
        diagnose_post(p["id"], p["title"], p.get("content", ""), tags, full=full, image_count=img_count)
        print()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="NoteRx 诊断集成")
    parser.add_argument("--days", type=int, default=3, help="补诊最近 N 天")
    parser.add_argument("--full", action="store_true", help="使用完整诊断（慢，60-90s/篇）")
    parser.add_argument("--test", action="store_true", help="测试 API 连通性")
    args = parser.parse_args()

    if args.test:
        print("测试 NoteRx API 连通性...")
        result = pre_score("测试标题", "测试内容", "tech", ["测试"])
        if result:
            print(f"  pre-score OK: {result.get('total_score')}分")
        else:
            print("  pre-score FAILED")
            sys.exit(1)
        print("API 连通性测试通过")
    else:
        backfill_diagnosis(days=args.days, full=args.full)
