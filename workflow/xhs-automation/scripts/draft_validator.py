"""XHS 自动化系统 - 草稿验证 Agent：三维度评估草稿质量并排名"""
import json
import os
import re
import subprocess
import random
import sys
import time
from datetime import datetime, date

sys.path.insert(0, os.path.dirname(__file__))
import db


def resolve_mcp_script(script_name):
    candidates = [
        os.environ.get(f"XHS_{script_name.upper().replace('.', '_').replace('-', '_')}"),
        os.path.expanduser(f"~/.agents/skills/xiaohongshu/scripts/{script_name}"),
        os.path.expanduser(f"~/.claude/skills/xiaohongshu/scripts/{script_name}"),
        os.path.expanduser(f"~/.codex/skills/xiaohongshu/scripts/{script_name}"),
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return path
    return os.path.expanduser(f"~/.agents/skills/xiaohongshu/scripts/{script_name}")


MCP_CALL = resolve_mcp_script("mcp-call.sh")


# ---------------------------------------------------------------------------
# 维度 1：平台数据验证
# ---------------------------------------------------------------------------

def extract_keywords(title):
    """从标题中提取 2-3 个搜索关键词"""
    # 去掉 emoji
    title = re.sub(r'[\U00010000-\U0010ffff]', '', title)
    # 去掉标点符号
    title = re.sub(r'[^\w\s\u4e00-\u9fff]', ' ', title)
    # 去掉数字开头的模式词（"3步"、"5个"、"10分钟"等）
    title = re.sub(r'\d+[\u6b65\u4e2a\u5206\u949f\u5929\u79d2\u5c0f\u65f6\u5468\u6708\u5e74\u79cd\u5927\u62db\u70b9\u53e5\u6b3e]', '', title)
    # 去掉常见停用词
    stop_words = {'的', '了', '是', '在', '我', '有', '和', '就', '不', '人', '都',
                  '一', '一个', '上', '也', '很', '到', '说', '要', '去', '你', '会',
                  '着', '没有', '看', '好', '自己', '这', '他', '她', '什么', '这个',
                  '那个', '但是', '可以', '还是', '这样', '那样', '怎么', '为什么',
                  '如何', '必看', '超', '真的', '太', '最', '居然', '竟然', '原来',
                  '分享', '推荐', '整理', '合集', '盘点', '总结'}
    # 分词：按空格和中文字符边界分割
    tokens = re.findall(r'[\u4e00-\u9fff]{2,}|[a-zA-Z]{2,}', title)
    keywords = [t for t in tokens if t.lower() not in stop_words and len(t) >= 2]
    # 返回前 3 个关键词
    return keywords[:3]


def parse_search_result(stdout):
    """解析 MCP search_feeds 返回结果"""
    if not stdout or not stdout.strip():
        return {"note_count": 0, "avg_likes": 0, "avg_saves": 0}

    # 尝试 JSON 解析
    try:
        data = json.loads(stdout.strip())
        if isinstance(data, dict):
            items = data.get("items") or data.get("feeds") or data.get("notes") or data.get("data", [])
        elif isinstance(data, list):
            items = data
        else:
            items = []
    except (json.JSONDecodeError, ValueError):
        # JSON 解析失败，尝试正则提取
        items = []
        likes_matches = re.findall(r'(?:likes?|liked_count|like_count)["\s:]+(\d+)', stdout)
        saves_matches = re.findall(r'(?:saves?|collected_count|collect_count)["\s:]+(\d+)', stdout)
        count_match = re.search(r'(?:total|count|note_count)["\s:]+(\d+)', stdout)

        note_count = int(count_match.group(1)) if count_match else 0
        avg_likes = sum(int(x) for x in likes_matches) / max(len(likes_matches), 1)
        avg_saves = sum(int(x) for x in saves_matches) / max(len(saves_matches), 1)

        return {
            "note_count": note_count or len(likes_matches),
            "avg_likes": round(avg_likes, 1),
            "avg_saves": round(avg_saves, 1)
        }

    if not items:
        return {"note_count": 0, "avg_likes": 0, "avg_saves": 0}

    total_likes = 0
    total_saves = 0
    for item in items:
        if isinstance(item, dict):
            total_likes += int(item.get("likes", 0) or item.get("liked_count", 0)
                               or item.get("like_count", 0))
            total_saves += int(item.get("saves", 0) or item.get("collected_count", 0)
                               or item.get("collect_count", 0))

    n = len(items)
    return {
        "note_count": n,
        "avg_likes": round(total_likes / n, 1) if n else 0,
        "avg_saves": round(total_saves / n, 1) if n else 0
    }


def calculate_blue_ocean(search_data):
    """蓝海指数 = 需求热度 / 供给量"""
    supply = search_data.get("note_count", 1) or 1
    demand = search_data.get("avg_likes", 0) + search_data.get("avg_saves", 0) * 2
    return round(demand / supply, 2)


def search_xhs(keyword, cache):
    """调用 MCP 搜索，带缓存和去重"""
    # 先查 DB 缓存
    cached = db.get_keyword_cache(keyword)
    if cached:
        return {
            "note_count": cached.get("note_count", 0),
            "avg_likes": cached.get("avg_likes", 0),
            "avg_saves": cached.get("avg_saves", 0)
        }
    # 再查内存缓存
    if keyword in cache:
        return cache[keyword]

    # 随机延迟 2-5 秒，避免触发限流
    time.sleep(random.uniform(2, 5))

    try:
        result = subprocess.run(
            [MCP_CALL, "search_feeds", json.dumps({"keyword": keyword, "limit": 10})],
            capture_output=True, text=True, timeout=30,
            cwd=os.path.expanduser("~/.xiaohongshu")
        )
        parsed = parse_search_result(result.stdout)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        parsed = {"note_count": 0, "avg_likes": 0, "avg_saves": 0}

    # 写入 DB 缓存
    blue_ocean = calculate_blue_ocean(parsed)
    db.add_keyword_tracking(
        keyword,
        parsed.get("note_count", 0),
        parsed.get("avg_likes", 0),
        parsed.get("avg_saves", 0),
        blue_ocean
    )
    cache[keyword] = parsed
    return parsed


def score_platform(draft, cache):
    """平台数据评分 0-100"""
    keywords = extract_keywords(draft["title"])
    if not keywords:
        return 50  # 无法评估时给中间分

    scores = []
    for kw in keywords:
        data = search_xhs(kw, cache)
        boi = calculate_blue_ocean(data)
        if boi >= 5:
            scores.append(random.randint(90, 100))
        elif boi >= 2:
            scores.append(random.randint(60, 75))
        elif boi >= 0.5:
            scores.append(random.randint(40, 60))
        else:
            scores.append(random.randint(10, 30))

    return round(sum(scores) / len(scores))


# ---------------------------------------------------------------------------
# 维度 2：内容质量评估
# ---------------------------------------------------------------------------

def parse_quality_scores(stdout):
    """解析 Claude 返回的质量评分 JSON"""
    if not stdout or not stdout.strip():
        return {}

    text = stdout.strip()

    # 尝试直接 JSON 解析
    try:
        arr = json.loads(text)
        if isinstance(arr, list):
            return _normalize_quality_array(arr)
    except (json.JSONDecodeError, ValueError):
        pass

    # 尝试提取 JSON 代码块
    json_match = re.search(r'```(?:json)?\s*(\[[\s\S]*?\])\s*```', text)
    if json_match:
        try:
            arr = json.loads(json_match.group(1))
            if isinstance(arr, list):
                return _normalize_quality_array(arr)
        except (json.JSONDecodeError, ValueError):
            pass

    # 尝试提取裸 JSON 数组
    arr_match = re.search(r'(\[\s*\{[\s\S]*?\}\s*\])', text)
    if arr_match:
        try:
            arr = json.loads(arr_match.group(1))
            if isinstance(arr, list):
                return _normalize_quality_array(arr)
        except (json.JSONDecodeError, ValueError):
            pass

    return {}


def _normalize_quality_array(arr):
    """将 Claude 返回的评分数组标准化为 {draft_id: scores} 映射"""
    result = {}
    for item in arr:
        if not isinstance(item, dict):
            continue
        draft_id = item.get("draft_id", "")
        sub_scores = []
        for key in ("title_score", "completeness_score", "compliance_score",
                     "format_score", "cta_score"):
            val = item.get(key)
            if val is not None:
                try:
                    sub_scores.append(float(val))
                except (ValueError, TypeError):
                    pass

        # 加权平均：标题25%，完整性30%，合规20%，格式15%，CTA10%
        weights = [0.25, 0.30, 0.20, 0.15, 0.10]
        if len(sub_scores) == 5:
            avg = sum(s * w for s, w in zip(sub_scores, weights))
        elif sub_scores:
            avg = sum(sub_scores) / len(sub_scores)
        else:
            avg = 50

        result[draft_id] = {
            "avg_score": round(avg, 1),
            "title_score": item.get("title_score", 50),
            "completeness_score": item.get("completeness_score", 50),
            "compliance_score": item.get("compliance_score", 100),
            "format_score": item.get("format_score", 50),
            "cta_score": item.get("cta_score", 50),
            "highlights": item.get("highlights", ""),
            "risks": item.get("risks", "")
        }
    return result


def score_quality_batch(drafts):
    """用 Claude 批量评分所有草稿"""
    claude_bin = os.environ.get("XHS_CLAUDE_BIN", "claude")

    drafts_text = ""
    for i, d in enumerate(drafts):
        drafts_text += f"\n--- 草稿 {i + 1} (ID: {d['draft_id']}) ---\n"
        drafts_text += f"标题：{d['title']}\n"
        drafts_text += f"正文（前300字）：{d['content'][:300]}\n"
        tags = d.get('tags', [])
        if isinstance(tags, str):
            try:
                tags = json.loads(tags)
            except (json.JSONDecodeError, ValueError):
                tags = [tags]
        drafts_text += f"标签：{', '.join(tags) if tags else '无'}\n"
        drafts_text += f"格式：{d.get('suggested_format', 'unknown')}\n"

    prompt = f"""你是小红书内容质量评审专家。请对以下 {len(drafts)} 份草稿进行评分。

{drafts_text}

对每份草稿评估以下维度（0-100分）：
1. title_score: 标题吸引力（爆款模式、≤20字、含关键词）
2. completeness_score: 内容完整性（结构清晰、信息密度、有操作步骤）
3. compliance_score: 合规性（100分起步，违禁词/提及其他平台则扣分）
4. format_score: 格式匹配度
5. cta_score: CTA有效性

请严格按 JSON 数组格式返回（不要加 markdown 标记）：
[
  {{"draft_id": "xxx", "title_score": 85, "completeness_score": 80, "compliance_score": 100, "format_score": 75, "cta_score": 70, "highlights": "亮点", "risks": "风险"}},
  ...
]"""

    try:
        result = subprocess.run(
            [claude_bin, "--dangerously-skip-permissions", "--print", "-p", prompt],
            capture_output=True, text=True, timeout=180
        )
        return parse_quality_scores(result.stdout)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        # Claude 调用失败，返回所有草稿的默认中间分
        return {d["draft_id"]: {"avg_score": 50, "highlights": "", "risks": "质量评估失败"} for d in drafts}


# ---------------------------------------------------------------------------
# 维度 3：历史对标
# ---------------------------------------------------------------------------

def score_history(draft):
    """基于历史数据评分"""
    history = db.get_history_performance(days=30)
    if not history:
        return 50  # 无历史数据给中间分

    # 找到与当前 draft 相同 angle+style 的历史表现
    for h in history:
        if h["angle"] == draft.get("angle") and h["style"] == draft.get("style"):
            avg_all = sum(r["avg_likes"] + r["avg_saves"] * 2 for r in history) / len(history)
            this_combo = h["avg_likes"] + h["avg_saves"] * 2
            ratio = this_combo / avg_all if avg_all > 0 else 1.0
            return min(100, max(0, int(50 * ratio + 25)))

    return 50  # 新组合给中间分


# ---------------------------------------------------------------------------
# 冷启动权重自适应
# ---------------------------------------------------------------------------

def get_weights():
    """根据发布帖子数自适应调整权重"""
    count = db.get_published_post_count()
    if count <= 5:
        return 0.50, 0.50, 0.00
    elif count <= 19:
        return 0.45, 0.40, 0.15
    else:
        return 0.40, 0.35, 0.25


# ---------------------------------------------------------------------------
# 总结生成
# ---------------------------------------------------------------------------

def generate_overall_insight(rankings, w1, w2, w3, post_count):
    """生成本次评估的中文总结"""
    if not rankings:
        return "本次无草稿参与评估。"

    total = len(rankings)
    best = rankings[0]
    worst = rankings[-1]

    # 冷启动提示
    if post_count <= 5:
        phase = "冷启动期（≤5篇），历史数据权重为0，主要依赖平台数据和内容质量评估"
    elif post_count <= 19:
        phase = "成长期（6-19篇），历史对标开始生效但权重较低"
    else:
        phase = "成熟期（≥20篇），三维度完整生效"

    # 分数分布
    scores = [r["total_score"] for r in rankings]
    avg_score = round(sum(scores) / len(scores), 1)
    spread = round(max(scores) - min(scores), 1)

    lines = [
        f"本次共评估 {total} 份草稿，当前处于{phase}。",
        f"权重分配：平台数据 {int(w1*100)}% / 内容质量 {int(w2*100)}% / 历史对标 {int(w3*100)}%。",
        f"平均得分 {avg_score}，分差 {spread}。",
        f"推荐首选：「{best['title']}」（{best['total_score']}分）",
    ]

    if best.get("highlights"):
        lines.append(f"  亮点：{best['highlights']}")
    if worst.get("risks") and total > 1:
        lines.append(f"末位「{worst['title']}」（{worst['total_score']}分）风险：{worst['risks']}")

    # 平台数据洞察
    high_platform = [r for r in rankings if r["platform_score"] >= 70]
    if high_platform:
        lines.append(f"平台数据优势草稿：{len(high_platform)} 篇（蓝海关键词匹配度高）")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 主函数
# ---------------------------------------------------------------------------

def validate_drafts(drafts, date_str=None):
    """验证所有草稿，返回排名列表"""
    date_str = date_str or date.today().isoformat()
    w1, w2, w3 = get_weights()
    search_cache = {}  # 内存搜索缓存

    # 批量内容质量评分
    quality_scores = score_quality_batch(drafts)

    rankings = []
    for draft in drafts:
        p_score = score_platform(draft, search_cache)
        q_data = quality_scores.get(draft["draft_id"], {})
        q_score = q_data.get("avg_score", 50)
        h_score = score_history(draft)

        total = round(p_score * w1 + q_score * w2 + h_score * w3, 1)

        # 写入 DB
        if "db_id" in draft:
            db.add_draft_score(draft["db_id"], p_score, q_score, h_score, total,
                               q_data.get("highlights", ""), q_data.get("risks", ""))

        rankings.append({
            "draft_id": draft["draft_id"],
            "db_id": draft.get("db_id"),
            "total_score": total,
            "platform_score": p_score,
            "quality_score": q_score,
            "history_score": h_score,
            "highlights": q_data.get("highlights", ""),
            "risks": q_data.get("risks", ""),
            "title": draft["title"]
        })

    rankings.sort(key=lambda x: x["total_score"], reverse=True)
    for i, r in enumerate(rankings):
        r["rank"] = i + 1

    post_count = db.get_published_post_count()
    overall_insight = generate_overall_insight(rankings, w1, w2, w3, post_count)

    return {
        "evaluated_at": datetime.now().isoformat(),
        "total_drafts": len(rankings),
        "weights": {"platform": w1, "quality": w2, "history": w3},
        "cold_start": post_count < 20,
        "post_count": post_count,
        "rankings": rankings,
        "overall_insight": overall_insight
    }


# ---------------------------------------------------------------------------
# CLI 入口
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    db.init_db()
    db.migrate_db()

    today = date.today().isoformat()

    # 从命令行参数获取日期和 slot
    date_arg = sys.argv[1] if len(sys.argv) > 1 else today
    slot_arg = sys.argv[2] if len(sys.argv) > 2 else None

    # 从 DB 加载草稿
    if slot_arg:
        raw_drafts = db.get_drafts_by_date_slot(date_arg, slot_arg)
    else:
        # 尝试所有 slot
        raw_drafts = []
        for slot in ("morning", "noon", "evening", "slot1", "slot2", "slot3"):
            raw_drafts.extend(db.get_drafts_by_date_slot(date_arg, slot))

    if not raw_drafts:
        print(f"[validator] {date_arg} 没有找到草稿，跳过验证")
        sys.exit(0)

    # 转换为验证所需格式
    drafts = []
    for r in raw_drafts:
        tags = r.get("tags")
        if isinstance(tags, str):
            try:
                tags = json.loads(tags)
            except (json.JSONDecodeError, ValueError):
                tags = [tags] if tags else []

        drafts.append({
            "draft_id": r["draft_id"],
            "db_id": r["id"],
            "title": r["title"],
            "content": r["content"],
            "tags": tags or [],
            "angle": r.get("angle", ""),
            "style": r.get("style", ""),
            "suggested_format": r.get("suggested_format", "image_text"),
        })

    print(f"[validator] 开始验证 {len(drafts)} 份草稿 (日期: {date_arg})")
    result = validate_drafts(drafts, date_arg)

    print(f"\n{'='*60}")
    print(f"评估完成 - {result['total_drafts']} 份草稿")
    print(f"权重: 平台 {result['weights']['platform']*100:.0f}% / "
          f"质量 {result['weights']['quality']*100:.0f}% / "
          f"历史 {result['weights']['history']*100:.0f}%")
    print(f"冷启动: {'是' if result['cold_start'] else '否'} (已发布 {result['post_count']} 篇)")
    print(f"{'='*60}")

    for r in result["rankings"]:
        print(f"\n#{r['rank']} [{r['total_score']}分] {r['title']}")
        print(f"   平台={r['platform_score']} 质量={r['quality_score']} 历史={r['history_score']}")
        if r["highlights"]:
            print(f"   亮点: {r['highlights']}")
        if r["risks"]:
            print(f"   风险: {r['risks']}")

    print(f"\n--- 总结 ---\n{result['overall_insight']}")
