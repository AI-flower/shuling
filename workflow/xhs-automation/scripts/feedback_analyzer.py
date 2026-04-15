"""XHS 自动化系统 - 反馈驱动创作：评论采集与分析"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(__file__))
import db


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


def is_spam_comment(text):
    """过滤垃圾评论：纯emoji、太短、引流广告"""
    if len(text.strip()) <= 2:
        return True
    spam_patterns = ["加微", "加V", "私聊", "免费领", "点击链接", "http"]
    return any(p in text for p in spam_patterns)


def collect_comments(note_id):
    """通过 MCP 采集帖子评论列表"""
    if not note_id:
        print("  note_id 为空，跳过采集", file=sys.stderr)
        return []

    try:
        result = subprocess.run(
            [MCP_CALL, "get_feed_detail", json.dumps({"feed_id": note_id, "xsec_token": ""})],
            capture_output=True, text=True, timeout=30,
            cwd=os.path.expanduser("~/.xiaohongshu")
        )
        if result.returncode != 0:
            print(f"  采集 {note_id} 评论失败: {result.stderr}", file=sys.stderr)
            return []

        output = result.stdout

        # 尝试 JSON 解析
        try:
            data = json.loads(output)
            comments_raw = []

            # MCP 返回格式：可能在 comments 字段或 note_card.comments
            if isinstance(data, dict):
                comments_raw = (
                    data.get("comments", [])
                    or data.get("note_card", {}).get("comments", [])
                )

            comments = []
            for c in comments_raw:
                text = c.get("content", c.get("text", ""))
                if text and not is_spam_comment(text):
                    comments.append({
                        "user": c.get("user_info", {}).get("nickname", c.get("nickname", "匿名")),
                        "text": text,
                    })
            return comments

        except (json.JSONDecodeError, ValueError):
            pass

        # 正则回退：提取评论文本
        comments = []
        for m in re.finditer(r'"content":\s*"([^"]+)"', output):
            text = m.group(1)
            if text and not is_spam_comment(text):
                comments.append({"user": "用户", "text": text})
        return comments

    except Exception as e:
        print(f"  采集评论异常: {e}", file=sys.stderr)
        return []


def analyze_comments(post_id, comments):
    """用 Claude CLI 分析评论并写入 DB"""
    if not comments:
        print(f"  帖子 {post_id} 无有效评论，跳过分析")
        db.add_comment_analysis(post_id, total_comments=0)
        return None

    # 拼接评论列表
    comment_text = "\n".join(
        f"- {c['user']}: {c['text']}" for c in comments
    )

    prompt = f"""你是小红书运营数据分析师。以下是一篇帖子收到的 {len(comments)} 条用户评论：

{comment_text}

请分析这些评论，返回严格 JSON（不要 markdown 代码块，不要额外文字）：
{{
  "total_comments": {len(comments)},
  "positive_count": <正面评论数>,
  "negative_count": <负面评论数>,
  "question_count": <提问类评论数>,
  "top_questions": ["最常见的问题1", "问题2"],
  "top_praise": ["用户称赞的点1", "点2"],
  "top_complaints": ["用户吐槽的点1"],
  "content_requests": ["用户希望看到的内容1"],
  "ai_summary": "一句话综合分析用户反馈倾向和创作启示"
}}"""

    claude_bin = os.environ.get("XHS_CLAUDE_BIN", "claude")
    try:
        result = subprocess.run(
            [claude_bin, "--dangerously-skip-permissions", "--print", "-p", prompt],
            capture_output=True, text=True, timeout=180
        )
        if result.returncode != 0:
            print(f"  Claude 分析失败: {result.stderr}", file=sys.stderr)
            return None

        response = result.stdout.strip()

        # 清理可能的 markdown 代码块包裹
        if response.startswith("```"):
            response = re.sub(r"^```(?:json)?\s*", "", response)
            response = re.sub(r"\s*```$", "", response)

        analysis = json.loads(response)

    except json.JSONDecodeError as e:
        print(f"  Claude 返回非 JSON: {e}", file=sys.stderr)
        print(f"  原始输出: {result.stdout[:500]}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  Claude 调用异常: {e}", file=sys.stderr)
        return None

    # 写入 DB
    db.add_comment_analysis(
        post_id=post_id,
        total_comments=analysis.get("total_comments", len(comments)),
        positive_count=analysis.get("positive_count", 0),
        negative_count=analysis.get("negative_count", 0),
        question_count=analysis.get("question_count", 0),
        top_questions=analysis.get("top_questions"),
        top_praise=analysis.get("top_praise"),
        top_complaints=analysis.get("top_complaints"),
        content_requests=analysis.get("content_requests"),
        ai_summary=analysis.get("ai_summary"),
    )

    print(f"  分析完成: +{analysis.get('positive_count', 0)} "
          f"-{analysis.get('negative_count', 0)} "
          f"?{analysis.get('question_count', 0)}")
    return analysis


def analyze_post(post_id, note_id):
    """一键分析一篇帖子：采集评论 + AI 分析 + 写入 DB"""
    print(f"分析帖子 post_id={post_id} note_id={note_id}")
    comments = collect_comments(note_id)
    print(f"  采集到 {len(comments)} 条有效评论")
    return analyze_comments(post_id, comments)


def backfill_analysis(days=3):
    """补充分析最近未分析的帖子"""
    db.init_db()
    posts = db.get_unanalyzed_posts(days=days)

    if not posts:
        print(f"最近 {days} 天没有未分析的帖子")
        return

    print(f"=== 补充分析 {len(posts)} 篇帖子 ===\n")
    for p in posts:
        print(f"[{p['date']}] {p['title']}")
        if not p.get("xhs_note_id"):
            print("  跳过: 无 note_id")
            continue
        analyze_post(p["id"], p["xhs_note_id"])
        print()


def get_feedback_for_prompt():
    """返回格式化的反馈文本，可直接注入创作 prompt"""
    db.init_db()
    feedbacks = db.get_latest_feedback(limit=3)

    if not feedbacks:
        return ""

    lines = ["## 近期用户反馈洞察\n"]
    for fb in feedbacks:
        title = fb.get("title", "未知帖子")
        summary = fb.get("ai_summary", "")
        questions = json.loads(fb["top_questions"]) if fb.get("top_questions") else []
        requests = json.loads(fb["content_requests"]) if fb.get("content_requests") else []
        praise = json.loads(fb["top_praise"]) if fb.get("top_praise") else []

        lines.append(f"### 「{title}」")
        if summary:
            lines.append(f"综合: {summary}")
        if praise:
            lines.append(f"好评: {', '.join(praise)}")
        if questions:
            lines.append(f"高频提问: {', '.join(questions)}")
        if requests:
            lines.append(f"用户想看: {', '.join(requests)}")
        lines.append("")

    return "\n".join(lines)


if __name__ == "__main__":
    backfill_analysis()
