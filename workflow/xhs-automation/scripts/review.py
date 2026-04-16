"""XHS 自动化系统 - 晚间复盘：拉互动数据 + Telegram 日报"""
import json
import os
import subprocess
import sys
import re
import glob
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(__file__))
import db
import llm
import telegram
import feedback_analyzer
import noterx_diagnose

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
KNOWLEDGE_BASE_DIR = os.path.join(BASE_DIR, "knowledge-base")
REVIEWS_DIR = os.path.join(KNOWLEDGE_BASE_DIR, "reviews")


def resolve_mcp_script(script_name):
    """兼容不同 skill 安装路径。"""
    candidates = [
        os.environ.get(f"XHS_{script_name.upper().replace('.', '_')}"),
        os.path.expanduser(f"~/.agents/skills/xiaohongshu/scripts/{script_name}"),
        os.path.expanduser(f"~/.claude/skills/xiaohongshu/scripts/{script_name}"),
        os.path.expanduser(f"~/.codex/skills/xiaohongshu/scripts/{script_name}"),
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return path
    return os.path.expanduser(f"~/.agents/skills/xiaohongshu/scripts/{script_name}")


MCP_CALL = resolve_mcp_script("mcp-call.sh")


def get_note_metrics(note_id):
    """通过 MCP get_feed_detail 获取帖子互动数据"""
    if not note_id:
        return None
    try:
        result = subprocess.run(
            [MCP_CALL, "get_feed_detail", json.dumps({"feed_id": note_id, "xsec_token": ""})],
            capture_output=True, text=True, timeout=30,
            cwd=os.path.expanduser("~/.xiaohongshu")
        )
        if result.returncode != 0:
            print(f"  获取 {note_id} 数据失败: {result.stderr}", file=sys.stderr)
            return None

        output = result.stdout
        # 尝试解析 JSON
        try:
            data = json.loads(output)
            # MCP 返回格式可能多样
            if isinstance(data, dict):
                interact = data.get("interact_info", data.get("note_card", {}).get("interact_info", {}))
                if not interact and "liked_count" in str(data):
                    # 可能在顶层
                    interact = data
                return {
                    "likes": int(interact.get("liked_count", 0)),
                    "saves": int(interact.get("collected_count", interact.get("saved_count", 0))),
                    "comments": int(interact.get("comment_count", 0)),
                    "shares": int(interact.get("share_count", 0))
                }
        except (json.JSONDecodeError, ValueError):
            pass

        # 正则回退
        metrics = {}
        for key, patterns in {
            "likes": [r'"liked_count":\s*"?(\d+)"?', r'赞\s*[:：]\s*(\d+)', r'❤️?\s*(\d+)'],
            "saves": [r'"collected_count":\s*"?(\d+)"?', r'收藏\s*[:：]\s*(\d+)', r'⭐\s*(\d+)'],
            "comments": [r'"comment_count":\s*"?(\d+)"?', r'评论\s*[:：]\s*(\d+)', r'💬\s*(\d+)'],
            "shares": [r'"share_count":\s*"?(\d+)"?'],
        }.items():
            for pat in patterns:
                m = re.search(pat, output)
                if m:
                    metrics[key] = int(m.group(1))
                    break
            if key not in metrics:
                metrics[key] = 0

        return metrics if any(v > 0 for v in metrics.values()) else None

    except Exception as e:
        print(f"  获取指标异常: {e}", file=sys.stderr)
        return None


def get_user_followers():
    """获取当前账号粉丝数"""
    try:
        result = subprocess.run(
            [MCP_CALL, "check_login_status"],
            capture_output=True, text=True, timeout=15,
            cwd=os.path.expanduser("~/.xiaohongshu")
        )
        output = result.stdout
        # 尝试提取粉丝数
        m = re.search(r'"fans":\s*"?(\d+)"?', output)
        if m:
            return int(m.group(1))
        m = re.search(r'粉丝\s*[:：]\s*(\d+)', output)
        if m:
            return int(m.group(1))
    except Exception as e:
        print(f"获取粉丝数失败: {e}", file=sys.stderr)
    return None


def run_review(date_str=None):
    """执行晚间复盘"""
    if date_str is None:
        date_str = date.today().isoformat()

    db.init_db()
    db.migrate_db()
    print(f"=== XHS 晚间复盘 {date_str} ===\n")

    # 1. 获取今日帖子
    posts = db.get_posts_by_date(date_str)
    if not posts:
        print("今日没有帖子记录")
        telegram.send(f"📊 {date_str} 复盘：今日无帖子记录")
        return

    # 2. 拉取每篇帖子的互动数据
    posts_data = []
    total_likes = 0
    total_saves = 0
    total_comments = 0
    best_post = None
    best_score = 0

    for p in posts:
        print(f"📝 「{p['title']}」({p['slot']})")
        metrics = None

        # 尝试从 MCP 获取实时数据
        if p.get("xhs_note_id"):
            print(f"  拉取 note_id={p['xhs_note_id']} 的数据...")
            metrics = get_note_metrics(p["xhs_note_id"])

        if metrics:
            print(f"  ❤️ {metrics['likes']}  ⭐ {metrics['saves']}  💬 {metrics['comments']}")
            # 存入数据库
            db.add_metrics(p["id"], **metrics)
        else:
            # 尝试从 DB 读取已有数据
            existing = db.get_latest_metrics(p["id"])
            if existing:
                metrics = {
                    "likes": existing["likes"],
                    "saves": existing["saves"],
                    "comments": existing["comments"],
                    "shares": existing.get("shares", 0)
                }
                print(f"  (缓存数据) ❤️ {metrics['likes']}  ⭐ {metrics['saves']}  💬 {metrics['comments']}")
            else:
                metrics = {"likes": 0, "saves": 0, "comments": 0, "shares": 0}
                print("  ⚠️ 无法获取互动数据")

        total_likes += metrics["likes"]
        total_saves += metrics["saves"]
        total_comments += metrics["comments"]

        # 计算综合分 = 点赞 + 收藏*2 + 评论*3
        score = metrics["likes"] + metrics["saves"] * 2 + metrics["comments"] * 3
        if score > best_score:
            best_score = score
            best_post = p

        posts_data.append({
            "slot": p["slot"],
            "title": p["title"],
            **metrics
        })

    # 3. 获取粉丝数
    print("\n👥 获取粉丝数...")
    follower_count = get_user_followers()
    if follower_count is not None:
        print(f"  粉丝: {follower_count}")

    # 4. 获取趋势数据
    trend = db.get_trend(7)

    # 5. 生成洞察
    insights = generate_insights(posts_data, trend, follower_count)

    # 6. 保存复盘到 DB
    db.add_review(
        date_str=date_str,
        total_likes=total_likes,
        total_saves=total_saves,
        total_comments=total_comments,
        follower_count=follower_count,
        best_post_id=best_post["id"] if best_post else None,
        insights=insights
    )

    # 7. 生成明日计划建议
    tomorrow_plan = suggest_tomorrow(posts_data, trend)

    # 8. 反馈分析：对当天已发布的帖子采集评论并分析
    print("\n💬 分析评论反馈...")
    comment_insights = []
    for p in posts:
        if p.get("status") == "published" and p.get("xhs_note_id"):
            try:
                analysis = feedback_analyzer.analyze_post(p["id"], p["xhs_note_id"])
                if analysis and analysis.get("ai_summary"):
                    comment_insights.append({
                        "title": p["title"],
                        "summary": analysis["ai_summary"],
                    })
            except Exception as e:
                print(f"  反馈分析「{p['title']}」失败: {e}", file=sys.stderr)


    # 8.5 NoteRx 诊断：对已发布帖子进行多维度评分
    print("\n🏥 NoteRx 诊断分析...")
    diagnosis_results = []
    use_full_diagnose = os.environ.get("NOTERX_FULL_DIAGNOSE", "").lower() in ("1", "true", "yes")
    for p in posts:
        if p.get("status") != "published":
            continue
        # 跳过已诊断的
        existing = db.get_latest_diagnosis(p["id"])
        if existing:
            diagnosis_results.append({
                "title": p["title"],
                "score": existing["overall_score"],
                "grade": existing["grade"],
                "content": existing["content_score"],
                "visual": existing["visual_score"],
                "growth": existing["growth_score"],
                "cached": True,
            })
            print(f"  「{p['title'][:15]}」已有诊断: {existing['grade']} {existing['overall_score']}分")
            continue
        try:
            result = noterx_diagnose.diagnose_post(
                post_id=p["id"],
                title=p["title"],
                content=p.get("content", ""),
                tags=p.get("tags"),
                full=use_full_diagnose,
            )
            if result:
                diagnosis_results.append({
                    "title": p["title"],
                    "score": result["overall_score"],
                    "grade": result["grade"],
                    "content": result["content_score"],
                    "visual": result["visual_score"],
                    "growth": result["growth_score"],
                    "issues": result.get("issues", [])[:3],
                    "cached": False,
                })
                print(f"  「{p['title'][:15]}」: {result['grade']} {result['overall_score']}分")
        except Exception as e:
            print(f"  「{p['title'][:15]}」诊断失败: {e}", file=sys.stderr)

    # 9. 发送 Telegram 日报
    print("\n📤 发送 Telegram 日报...")
    success = telegram.send_daily_review(
        date_str=date_str,
        posts_data=posts_data,
        trend_data=trend,
        follower_count=follower_count,
        insights=insights,
        tomorrow_plan=tomorrow_plan
    )

    # 追加评论洞察摘要
    if comment_insights:
        ci_lines = ["💬 <b>评论洞察</b>"]
        for ci in comment_insights:
            ci_lines.append(f"  「{ci['title'][:15]}」: {ci['summary']}")
        telegram.send("\n".join(ci_lines))

    # 追加 NoteRx 诊断摘要
    if diagnosis_results:
        diag_lines = ["🏥 <b>NoteRx 诊断</b>"]
        for dr in diagnosis_results:
            cached_tag = " (缓存)" if dr.get("cached") else ""
            diag_lines.append(
                f"  「{dr['title'][:15]}」{dr['grade']} {dr['score']}分{cached_tag}"
                f"  内容{dr.get('content', 0):.0f} 视觉{dr.get('visual', 0):.0f} 增长{dr.get('growth', 0):.0f}"
            )
            for iss in dr.get("issues", [])[:2]:
                diag_lines.append(f"    ⚠️ {iss[:60]}")
        telegram.send("\n".join(diag_lines))

    if success:
        db.mark_review_sent(date_str)
        print("✅ Telegram 日报发送成功！")
    else:
        print("❌ Telegram 日报发送失败")

    # 10. 更新知识库阶段
    print("\n🧠 更新知识库状态...")
    try:
        update_knowledge_phase()
    except Exception as e:
        print(f"  知识库阶段更新失败: {e}", file=sys.stderr)

    # 11. 周日触发进化分析
    try:
        weekly_evolution(date_str)
    except Exception as e:
        print(f"  周进化分析失败: {e}", file=sys.stderr)

    return posts_data


def generate_insights(posts_data, trend, follower_count):
    """基于数据生成简要洞察"""
    insights = []

    if not posts_data:
        return "今日无数据"

    # 找出表现最好和最差的帖子
    sorted_posts = sorted(posts_data, key=lambda x: x.get("likes", 0) + x.get("saves", 0) * 2, reverse=True)
    if len(sorted_posts) >= 2:
        best = sorted_posts[0]
        worst = sorted_posts[-1]
        if best.get("likes", 0) > worst.get("likes", 0) * 2:
            insights.append(f"「{best['title'][:10]}...」表现明显优于其他帖子")

    # 收藏率分析
    total_likes = sum(p.get("likes", 0) for p in posts_data)
    total_saves = sum(p.get("saves", 0) for p in posts_data)
    if total_likes > 0:
        save_rate = total_saves / total_likes
        if save_rate > 0.5:
            insights.append("收藏率高于50%，内容实用性强")
        elif save_rate < 0.2:
            insights.append("收藏率偏低，可增加干货内容提升收藏")

    # 趋势对比
    if trend and len(trend) >= 2:
        yesterday = trend[0] if trend[0]["date"] != date.today().isoformat() else (trend[1] if len(trend) > 1 else None)
        if yesterday:
            likes_change = total_likes - yesterday.get("total_likes", 0)
            if likes_change > 0:
                insights.append(f"点赞较昨日增加 {likes_change}")
            elif likes_change < 0:
                insights.append(f"点赞较昨日减少 {abs(likes_change)}，需调整内容策略")

    return "；".join(insights) if insights else "数据积累中，持续观察"


def suggest_tomorrow(posts_data, trend):
    """基于今日数据建议明日内容方向"""
    suggestions = []

    # 分析哪类帖子表现好
    total_saves = sum(p.get("saves", 0) for p in posts_data)
    total_likes = sum(p.get("likes", 0) for p in posts_data)

    if total_saves > total_likes:
        suggestions.append("继续产出干货工具推荐类内容（收藏率高）")
    else:
        suggestions.append("尝试更有趣味性的标题和内容提升互动")

    suggestions.append("从 GitHub trending 挑选今日热门 AI 项目")
    suggestions.append("保持 noon(12:00) + evening(21:00) 双发节奏")

    return suggestions


def update_knowledge_phase():
    """更新 knowledge-base/README.md 中的帖子计数和阶段"""
    readme_path = os.path.join(KNOWLEDGE_BASE_DIR, "README.md")
    if not os.path.exists(readme_path):
        return

    post_count = db.get_published_post_count()
    if post_count < 10:
        phase = "cold-start"
    elif post_count < 30:
        phase = "growth"
    else:
        phase = "mature"

    try:
        content = open(readme_path, "r", encoding="utf-8").read()
        new_line = f"当前: {phase}（{post_count} 篇）"
        content = re.sub(r"当前: .+", new_line, content)
        with open(readme_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  知识库阶段: {phase}（{post_count} 篇）")
    except Exception as e:
        print(f"  更新知识库阶段失败: {e}", file=sys.stderr)


def export_week_data(date_str):
    """导出本周数据为 Markdown，供进化分析使用"""
    today = date.fromisoformat(date_str)
    week_start = today - timedelta(days=today.weekday())
    week_end = week_start + timedelta(days=6)
    week_id = today.strftime("%Y-W%W")

    posts = db.get_posts_between_dates(week_start.isoformat(), week_end.isoformat())
    if not posts:
        return None, None

    lines = [f"# {week_id} 周数据（{week_start} - {week_end}）\n"]
    total_likes = total_saves = total_comments = 0
    best_post = None
    best_save_rate = 0

    post_sections = []
    for i, p in enumerate(posts, 1):
        metrics_list = db.get_all_metrics_for_post(p["id"])
        latest = metrics_list[-1] if metrics_list else {"likes": 0, "saves": 0, "comments": 0, "shares": 0}
        total_likes += latest.get("likes", 0)
        total_saves += latest.get("saves", 0)
        total_comments += latest.get("comments", 0)

        curve_parts = []
        for m in metrics_list:
            cp = m.get("checkpoint", "review")
            curve_parts.append(f"{cp}({m['likes']}/{m['saves']}/{m['comments']})")
        curve = " → ".join(curve_parts) if curve_parts else "无数据"

        save_rate = (latest["saves"] / max(latest["likes"], 1)) * 100
        if save_rate > best_save_rate:
            best_save_rate = save_rate
            best_post = p

        predicted = db.get_draft_score_for_post(p["id"])
        predicted_str = f"{predicted:.0f}" if predicted else "无"

        section = f"""### #{i:02d} | {p['date']} {p['slot']}
- 标题: "{p['title']}"
- 角度: {p.get('angle', '无')} | 风格: {p.get('style', '无')}
- 预测分: {predicted_str}
- 实际: 👍{latest['likes']} ⭐{latest['saves']} 💬{latest['comments']}
- 增长曲线: {curve}
- 收藏率: {save_rate:.1f}%"""
        post_sections.append(section)

    follower = get_user_followers()
    lines.append("## 总览")
    lines.append(f"- 发布: {len(posts)} 篇 | 总点赞: {total_likes} | 总收藏: {total_saves} | 总评论: {total_comments}")
    if follower:
        lines.append(f"- 粉丝: {follower}")
    if best_post:
        lines.append(f"- 最佳帖子: #{posts.index(best_post)+1:02d} 收藏率 {best_save_rate:.1f}%")
    lines.append("\n## 逐篇数据\n")
    lines.extend(post_sections)

    content = "\n".join(lines)
    os.makedirs(REVIEWS_DIR, exist_ok=True)
    review_path = os.path.join(REVIEWS_DIR, f"{week_id}.md")
    with open(review_path, "w", encoding="utf-8") as f:
        f.write(content)

    return week_id, content


EVOLUTION_PROMPT = """你是小红书内容运营分析师。分析以下周数据，输出进化建议。

## 本周数据
{week_data}

## 当前 Pattern 库
{patterns_content}

## 当前规则
{rules_content}

## 任务
1. 表现好的帖子（收藏率 > 5%）用了什么共性？提炼为 pattern
2. 表现差的帖子（收藏率 < 2%）有什么共性？标记需要避免的模式
3. 已有 pattern 中，被使用且效果好的 → confidence 升级
4. 已有 pattern 连续表现差的 → 建议标记 deprecated
5. 根据数据调整 angle_weights 和 style_weights
6. 预测分 vs 实际收藏率的偏差分析

## 输出格式
严格输出 JSON，不要其他文字：
{{
  "new_patterns": [
    {{"id": "P0X-简短id", "name": "模式名", "template": "模板", "example": "示例", "applicable": "适用场景", "confidence": "low"}}
  ],
  "pattern_updates": [
    {{"id": "P01", "action": "upgrade|downgrade|deprecate", "reason": "原因", "new_confidence": "medium|high|deprecated"}}
  ],
  "rules_update": {{
    "angle_weights": {{"pain-point": 0.35, "tutorial": 0.35, "discovery": 0.30}},
    "style_weights": {{"casual-sharing": 0.40, "step-by-step": 0.35, "comparison": 0.25}},
    "preferred_patterns": ["P01", "P02"]
  }},
  "weekly_summary": "本周关键发现（1-2 句话）",
  "calibration_note": "评分校准观察"
}}"""


def weekly_evolution(date_str):
    """周日运行：导出数据 → LLM 分析 → 程序化更新知识库"""
    today = date.fromisoformat(date_str)
    if today.weekday() != 6:
        return

    if not os.path.exists(os.path.join(KNOWLEDGE_BASE_DIR, "README.md")):
        print("  知识库未初始化，跳过进化分析")
        return

    print("\n🧬 周进化分析...")

    week_id, week_data = export_week_data(date_str)
    if not week_data:
        print("  本周无数据，跳过")
        return

    post_count = db.get_published_post_count()
    if post_count < 3:
        print(f"  帖子总数 {post_count} < 3，跳过进化（样本不足）")
        return

    patterns_path = os.path.join(KNOWLEDGE_BASE_DIR, "patterns.md")
    rules_path = os.path.join(KNOWLEDGE_BASE_DIR, "rules.json")
    patterns_content = ""
    rules_content = "{}"
    if os.path.exists(patterns_path):
        patterns_content = open(patterns_path, "r", encoding="utf-8").read()
    if os.path.exists(rules_path):
        rules_content = open(rules_path, "r", encoding="utf-8").read()

    prompt = EVOLUTION_PROMPT.format(
        week_data=week_data,
        patterns_content=patterns_content or "（空，尚无 pattern）",
        rules_content=rules_content
    )
    response = llm.call_llm(prompt, system="你是小红书数据分析专家，只输出 JSON。")
    if not response:
        print("  LLM 调用失败，跳过进化")
        return

    try:
        json_text = response.strip()
        if "```json" in json_text:
            json_text = json_text.split("```json")[1].split("```")[0]
        elif "```" in json_text:
            json_text = json_text.split("```")[1].split("```")[0]
        result = json.loads(json_text)
    except (json.JSONDecodeError, IndexError) as e:
        print(f"  LLM 返回的 JSON 解析失败: {e}", file=sys.stderr)
        return

    _apply_pattern_updates(patterns_path, patterns_content, result)
    _apply_rules_updates(rules_path, rules_content, result)
    _update_readme_summary(result, week_id)
    _cleanup_old_reviews(keep=4)

    print("  ✅ 周进化分析完成")


def _apply_pattern_updates(patterns_path, current_content, result):
    """根据 LLM 分析结果更新 patterns.md"""
    lines = current_content.split("\n") if current_content else []

    for update in result.get("pattern_updates", []):
        pid = update["id"]
        action = update["action"]
        new_conf = update.get("new_confidence", "")
        for i, line in enumerate(lines):
            if line.startswith(f"### {pid} "):
                if action == "deprecate":
                    lines[i] = line.replace(f"### {pid}", f"### ~~{pid}~~ [DEPRECATED]")
                else:
                    lines[i] = re.sub(r"confidence: \w+", f"confidence: {new_conf}", line)
                break

    for np in result.get("new_patterns", []):
        lines.append(f"\n### {np['id']} | {np['name']} | confidence: {np.get('confidence', 'low')} | source: self-data")
        lines.append(f"- **模板**: {np.get('template', '')}")
        lines.append(f"- **示例**: \"{np.get('example', '')}\"")
        lines.append(f"- **适用**: {np.get('applicable', '')}")
        lines.append(f"- **来源**: 自己数据提炼")
        lines.append(f"- **自己数据**: 首次发现")
        lines.append(f"- **使用次数**: 0 | **平均收藏率**: 待统计")

    content = "\n".join(lines)
    active_count = content.count("\n### ") - content.count("[DEPRECATED]")
    content = re.sub(r"活跃数: \d+", f"活跃数: {max(active_count, 0)}", content)
    content = re.sub(r"最后更新: .+?\|", f"最后更新: {date.today().isoformat()} |", content)

    with open(patterns_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  patterns.md 已更新（活跃 {active_count} 条）")


def _apply_rules_updates(rules_path, current_content, result):
    """根据 LLM 分析结果更新 rules.json"""
    try:
        rules = json.loads(current_content) if current_content.strip() else {}
    except json.JSONDecodeError:
        rules = {}

    rules_update = result.get("rules_update", {})
    if rules_update.get("angle_weights"):
        rules["angle_weights"] = rules_update["angle_weights"]
    if rules_update.get("style_weights"):
        rules["style_weights"] = rules_update["style_weights"]
    if rules_update.get("preferred_patterns"):
        rules.setdefault("title", {})["preferred_patterns"] = rules_update["preferred_patterns"]

    rules["version"] = date.today().strftime("%Y-W%W")
    rules["post_count"] = db.get_published_post_count()
    pc = rules["post_count"]
    rules["phase"] = "cold-start" if pc < 10 else ("growth" if pc < 30 else "mature")

    with open(rules_path, "w", encoding="utf-8") as f:
        json.dump(rules, f, ensure_ascii=False, indent=2)
    print(f"  rules.json 已更新（phase={rules['phase']}）")


def _update_readme_summary(result, week_id):
    """更新 README.md 中的摘要区块"""
    readme_path = os.path.join(KNOWLEDGE_BASE_DIR, "README.md")
    if not os.path.exists(readme_path):
        return

    content = open(readme_path, "r", encoding="utf-8").read()

    preferred = result.get("rules_update", {}).get("preferred_patterns", [])
    if preferred:
        top_text = ", ".join(preferred[:5])
        content = re.sub(
            r"(## 当前生效的 Top Pattern\n).*?(\n## )",
            f"\\1{top_text}\n\n\\2",
            content, flags=re.DOTALL
        )

    summary = result.get("weekly_summary", "")
    calibration = result.get("calibration_note", "")
    findings = summary
    if calibration:
        findings += f"\n评分校准: {calibration}"
    content = re.sub(
        r"(## 本周关键发现\n).*?(\n## )",
        f"\\1{findings}\n\n\\2",
        content, flags=re.DOTALL
    )

    reviews = sorted(glob.glob(os.path.join(REVIEWS_DIR, "*.md")), reverse=True)[:4]
    review_links = "\n".join(f"- [{os.path.basename(r)}](reviews/{os.path.basename(r)})" for r in reviews)
    content = re.sub(
        r"(## 近期复盘\n).*$",
        f"\\1{review_links}\n",
        content, flags=re.DOTALL
    )

    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(content)


def _cleanup_old_reviews(keep=4):
    """保留最近 N 周的复盘文件"""
    if not os.path.exists(REVIEWS_DIR):
        return
    files = sorted(glob.glob(os.path.join(REVIEWS_DIR, "*.md")), reverse=True)
    for old in files[keep:]:
        os.remove(old)
        print(f"  清理旧复盘: {os.path.basename(old)}")


if __name__ == "__main__":
    date_str = sys.argv[1] if len(sys.argv) > 1 else None
    run_review(date_str)
