"""XHS 自动化系统 - 晚间复盘：拉互动数据 + Telegram 日报"""
import json
import os
import subprocess
import sys
import re
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(__file__))
import db
import telegram
import feedback_analyzer

BASE_DIR = os.path.dirname(os.path.dirname(__file__))


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

    if success:
        db.mark_review_sent(date_str)
        print("✅ Telegram 日报发送成功！")
    else:
        print("❌ Telegram 日报发送失败")

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


if __name__ == "__main__":
    date_str = sys.argv[1] if len(sys.argv) > 1 else None
    run_review(date_str)
