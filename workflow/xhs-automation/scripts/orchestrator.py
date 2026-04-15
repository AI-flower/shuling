"""XHS 自动化系统 - 总编排入口

串联全流程：加载选题 -> 生成草稿 -> 验证评估 -> Telegram 推送报告
-> 轮询等待博主选择 -> 生成图片 -> 推送审图 -> 等待确认 -> 写入 DB 发布。

包含完整降级逻辑：
  - 草稿失败 -> 旧流程 (create_content)
  - 验证失败 -> 跳过评分
  - 图片失败 -> HTML 截图
  - 超时 -> 自动选 #1
"""
import argparse
import asyncio
import json
import logging
import os
import sys
import time
from datetime import date, datetime

sys.path.insert(0, os.path.dirname(__file__))
import config_loader
import db
import telegram

config_loader.load_runtime_env()

LOG = logging.getLogger(__name__)

# 超时配置（分钟）
DRAFT_SELECT_TIMEOUT = int(os.environ.get("DRAFT_SELECT_TIMEOUT", "110"))    # 110 min
IMAGE_REVIEW_TIMEOUT = int(os.environ.get("IMAGE_REVIEW_TIMEOUT", "30"))     # 30 min
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "30"))                   # 30s

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, "data")
POSTS_DIR = os.path.join(BASE_DIR, "posts")


# ---------------------------------------------------------------------------
# 选题加载
# ---------------------------------------------------------------------------

def load_candidate(date_str, slot):
    """从 research.py 的输出加载候选"""
    path = os.path.join(DATA_DIR, f"candidates-{date_str}.json")
    if not os.path.exists(path):
        LOG.warning("候选文件不存在: %s", path)
        return None
    with open(path) as f:
        data = json.load(f)

    # 兼容两种格式: data["selected"] 或 data["candidates"] + selected 标记
    selected = data.get("selected", [])
    if not selected:
        selected = [c for c in data.get("candidates", []) if c.get("selected")]

    slot_idx = 0 if slot == "noon" else 1
    if len(selected) > slot_idx:
        return selected[slot_idx]
    return selected[0] if selected else None


# ---------------------------------------------------------------------------
# 降级工具
# ---------------------------------------------------------------------------

def fallback_old_flow(date_str, slot, candidate):
    """降级到现有 create_content.py 旧流程"""
    try:
        import create_content
        result = create_content.create_post(candidate, date_str, slot, 1)
        if result:
            LOG.info("旧流程降级成功: post_id=%s", result["post_id"])
            return result
    except Exception as e:
        LOG.error("旧流程降级也失败: %s", e)
    return None


def fallback_html_images(draft_data, post_dir):
    """降级为 HTML 截图"""
    try:
        import create_content
        html = create_content.generate_html_fallback(
            {"repo": "", "description": draft_data.get("title", ""), "stars": 0, "topics": []},
            "noon"
        )
        html_path = os.path.join(post_dir, "post.html")
        with open(html_path, "w", encoding="utf-8") as f:
            f.write(html)
        images = create_content.take_screenshots(html_path, post_dir)
        return images
    except Exception as e:
        LOG.error("HTML 截图降级失败: %s", e)
        return []


def build_fallback_validation(drafts):
    """验证失败时的回退：按生成顺序排列，无评分"""
    rankings = []
    for i, d in enumerate(drafts):
        rankings.append({
            "rank": i + 1,
            "draft_id": d["draft_id"],
            "db_id": d.get("db_id"),
            "total_score": 0,
            "platform_score": 0,
            "quality_score": 0,
            "history_score": 0,
            "highlights": "评分不可用",
            "risks": "",
            "title": d["title"],
            "angle": d.get("angle"),
            "style": d.get("style"),
        })
    return {
        "rankings": rankings,
        "total_drafts": len(rankings),
        "overall_insight": "验证服务不可用，按生成顺序排列",
        "cold_start": False,
    }


def select_auto(validation):
    """自动选择排名第一的草稿"""
    return validation["rankings"][0]


def write_meta_json(post_dir, draft, image_paths, date_str, slot):
    """写入 meta.json 兼容现有发布流程"""
    os.makedirs(post_dir, exist_ok=True)
    tags = draft.get("tags", [])
    if isinstance(tags, str):
        try:
            tags = json.loads(tags)
        except (json.JSONDecodeError, ValueError):
            tags = [tags] if tags else []

    meta = {
        "title": draft["title"],
        "content": draft["content"],
        "tags": tags,
        "images": [os.path.abspath(p) for p in image_paths if p],
        "is_original": True,
        "format": draft.get("suggested_format", "image_text"),
    }
    with open(os.path.join(post_dir, "meta.json"), "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)


# ---------------------------------------------------------------------------
# 单 slot 完整流程
# ---------------------------------------------------------------------------

async def run_slot(date_str, slot):
    """单槽位完整流程"""
    print(f"[{slot}] 开始处理 {date_str}")

    # 检查是否已有帖子
    existing = db.get_posts_by_date(date_str, slot)
    active = [p for p in existing if p["status"] in ("scheduled", "published")]
    if active:
        LOG.info("跳过 %s: 已有活跃帖子 (post_id=%s)", slot, active[0]["id"])
        return active[0]["id"]

    # 1. 加载选题
    candidate = load_candidate(date_str, slot)
    if not candidate:
        print(f"[{slot}] 无候选选题，跳过")
        return None

    repo = candidate.get("repo", "未知项目")
    LOG.info("[%s] 选题: %s", slot, repo)

    # 2. 生成草稿（降级：全部失败 -> 旧流程）
    import draft_generator
    try:
        drafts = await draft_generator.generate_drafts(candidate, slot, date_str)
    except Exception as e:
        print(f"[{slot}] 草稿生成异常: {e}，降级旧流程")
        result = fallback_old_flow(date_str, slot, candidate)
        if result:
            telegram.send(f"[{slot}] 旧流程降级完成\n标题: {result['title']}")
        return result["post_id"] if result else None

    if not drafts:
        print(f"[{slot}] 草稿全部失败，降级旧流程")
        result = fallback_old_flow(date_str, slot, candidate)
        if result:
            telegram.send(f"[{slot}] 旧流程降级完成\n标题: {result['title']}")
        return result["post_id"] if result else None

    # 3. 验证评估（降级：失败 -> 跳过评分直接推送）
    import draft_validator
    try:
        validation = draft_validator.validate_drafts(drafts, date_str)
    except Exception as e:
        print(f"[{slot}] 验证失败: {e}，跳过评分")
        validation = build_fallback_validation(drafts)

    # 4. Telegram 推送报告（降级：不可用 -> 自动选 #1）
    try:
        report_time = time.time()
        _send_draft_report(validation, date_str, slot)
    except Exception as e:
        print(f"[{slot}] Telegram 不可用: {e}，自动模式")
        selected = select_auto(validation)
        await finish_slot(selected, candidate, date_str, slot)
        return selected.get("db_id")

    # 5. 轮询等待博主选择
    timeout_min = DRAFT_SELECT_TIMEOUT
    remind_at = report_time + (timeout_min - 30) * 60
    reminded = False

    selected = None
    try:
        import telegram_listener
    except ImportError:
        LOG.warning("telegram_listener 未就绪，自动选择 #1")
        selected = select_auto(validation)
        telegram.send(f"已自动选择 #{selected['rank']}: 「{selected['title']}」")
        await finish_slot(selected, candidate, date_str, slot)
        return selected.get("db_id")

    while True:
        reply = telegram_listener.poll_for_reply(
            os.environ.get("XHS_TELEGRAM_CHAT_ID"),
            after_timestamp=int(report_time),
            timeout_minutes=min(timeout_min, 30),
            poll_interval=POLL_INTERVAL
        )

        if reply is None:
            # 发 30 分钟提醒
            if not reminded and time.time() >= remind_at:
                telegram.send("还有30分钟自动选择 #1\n回复 \"选N\" 选择其他")
                reminded = True
            # 检查总超时
            if time.time() >= report_time + timeout_min * 60:
                selected = select_auto(validation)
                telegram.send(
                    f"已超时，自动选择 #{selected['rank']}: 「{selected['title']}」"
                )
                break
            continue

        action = reply.get("action", "")

        if action == "select":
            idx = reply.get("value", 1) - 1
            if 0 <= idx < len(validation["rankings"]):
                selected = validation["rankings"][idx]
                break
            else:
                telegram.send(f"序号无效，共 {len(validation['rankings'])} 份草稿")

        elif action == "detail":
            idx = reply.get("value", 1) - 1
            if 0 <= idx < len(validation["rankings"]):
                draft_data = db.get_draft_by_id(validation["rankings"][idx].get("db_id"))
                if draft_data:
                    _send_draft_detail(draft_data, validation["rankings"][idx])

        elif action == "more":
            _send_all_drafts_summary(validation["rankings"])

        elif action == "skip":
            print(f"[{slot}] 博主选择跳过")
            return None

        elif action == "auto_mode":
            selected = select_auto(validation)
            break

    if not selected:
        return None

    # 6. 生成图片 + 审图 + 确认 -> 发布
    await finish_slot(selected, candidate, date_str, slot)
    return selected.get("db_id")


# ---------------------------------------------------------------------------
# 选中草稿后：生图 -> 审图 -> 写入 DB
# ---------------------------------------------------------------------------

async def finish_slot(selected, candidate, date_str, slot):
    """选中草稿后完成后续流程"""
    draft_data = db.get_draft_by_id(selected.get("db_id"))
    if not draft_data:
        LOG.error("无法加载草稿 db_id=%s", selected.get("db_id"))
        return

    db.mark_draft_selected(selected["db_id"])

    # 创建 post 目录
    post_dir = os.path.join(POSTS_DIR, f"{date_str}-{slot}")
    image_dir = os.path.join(post_dir, "images")

    # 创建 post 记录
    tags = draft_data.get("tags", [])
    if isinstance(tags, str):
        try:
            tags = json.loads(tags)
        except (json.JSONDecodeError, ValueError):
            tags = [tags] if tags else []

    post_id = db.add_post(
        date_str=date_str,
        slot=slot,
        post_dir=os.path.abspath(post_dir),
        title=draft_data["title"],
        content=draft_data["content"],
        tags=tags,
        post_type=draft_data.get("suggested_format", "image_text"),
        github_repo=candidate.get("repo"),
        github_stars=candidate.get("stars"),
    )

    # 生成图片（降级：失败 -> HTML 截图）
    import image_generator
    try:
        images = await image_generator.generate_images(draft_data, post_id, image_dir)
        image_paths = [img["path"] for img in images
                       if img.get("path") and img.get("status") == "success"]
    except Exception as e:
        print(f"[{slot}] 图片生成失败: {e}，降级 HTML 截图")
        image_paths = fallback_html_images(draft_data, post_dir)

    if not image_paths:
        image_paths = fallback_html_images(draft_data, post_dir)

    # 推送审图（降级：Telegram 不可用 -> 自动确认）
    cancelled = False
    try:
        import telegram_listener
        _send_image_review(image_paths, draft_data["title"])
        review_time = time.time()

        reply = telegram_listener.poll_for_reply(
            os.environ.get("XHS_TELEGRAM_CHAT_ID"),
            after_timestamp=int(review_time),
            timeout_minutes=IMAGE_REVIEW_TIMEOUT,
            poll_interval=POLL_INTERVAL
        )

        if reply and reply.get("action") == "cancel":
            cancelled = True
        elif reply and reply.get("action") == "regenerate_all":
            try:
                images = await image_generator.generate_images(draft_data, post_id, image_dir)
                image_paths = [img["path"] for img in images if img.get("path")]
            except Exception:
                pass  # 重新生成失败，使用原有图片
    except ImportError:
        LOG.warning("telegram_listener 未就绪，自动确认审图")
        _send_image_review(image_paths, draft_data["title"])
    except Exception:
        pass  # Telegram 不可用，自动确认

    if cancelled:
        print(f"[{slot}] 博主取消，跳过发布")
        return

    # 写入 meta.json（兼容现有发布流程）
    write_meta_json(post_dir, draft_data, image_paths, date_str, slot)

    # 更新 DB 状态
    db.update_post_status(post_id, "scheduled")

    telegram.send(
        f"[{slot}] 帖子已进入发布队列\n"
        f"标题: {draft_data['title']}\n"
        f"角度: {draft_data.get('angle', '?')} / "
        f"风格: {draft_data.get('style', '?')}\n"
        f"图片: {len(image_paths)} 张"
    )
    print(f"[{slot}] 完成: \"{draft_data['title']}\" -> {post_dir}")


# ---------------------------------------------------------------------------
# Telegram 消息格式化
# ---------------------------------------------------------------------------

def _send_draft_report(validation, date_str, slot):
    """发送草稿排名报告"""
    rankings = validation.get("rankings", [])
    lines = [f"<b>[{slot}] 草稿报告</b> ({date_str})\n"]

    for r in rankings:
        score = f" [{r['total_score']}分]" if r.get("total_score") else ""
        lines.append(f"#{r['rank']}{score} 「{r['title']}」")
        lines.append(f"   角度: {r.get('angle', '?')} / 风格: {r.get('style', '?')}")
        if r.get("highlights"):
            lines.append(f"   亮点: {r['highlights'][:80]}")

    insight = validation.get("overall_insight", "")
    if insight:
        lines.append(f"\n<b>评估总结:</b>\n{insight[:300]}")

    lines.append(f"\n回复 <b>选N</b> 选择第N份 (如: 选1)")
    lines.append(f"回复 <b>更多</b> 查看所有草稿摘要")
    lines.append(f"回复 <b>详情N</b> 查看第N份完整内容")
    lines.append(f"回复 <b>自动</b> 自动选择第1名")
    lines.append(f"回复 <b>跳过</b> 不发这个 slot")
    lines.append(f"\n{DRAFT_SELECT_TIMEOUT} 分钟内未回复将自动选择 #1")

    telegram.send("\n".join(lines))


def _send_draft_detail(draft_data, ranking):
    """发送单份草稿的完整详情"""
    content = draft_data.get("content", "")
    if len(content) > 800:
        content = content[:797] + "..."

    tags = draft_data.get("tags", "")
    if isinstance(tags, str):
        try:
            tags = json.loads(tags)
        except (json.JSONDecodeError, ValueError):
            tags = [tags] if tags else []
    tag_str = " ".join(tags) if tags else ""

    telegram.send(
        f"<b>#{ranking['rank']} 「{draft_data['title']}」</b>\n"
        f"角度: {draft_data.get('angle', '?')} / 风格: {draft_data.get('style', '?')}\n"
        f"得分: {ranking.get('total_score', 'N/A')} "
        f"(平台={ranking.get('platform_score', '?')} "
        f"质量={ranking.get('quality_score', '?')} "
        f"历史={ranking.get('history_score', '?')})\n\n"
        f"{content}\n\n"
        f"{tag_str}"
    )


def _send_all_drafts_summary(rankings):
    """发送所有草稿的简要摘要"""
    lines = ["<b>所有草稿摘要:</b>\n"]
    for r in rankings:
        lines.append(
            f"#{r['rank']} [{r.get('total_score', 0)}分] 「{r['title']}」"
            f"\n   {r.get('angle', '?')}-{r.get('style', '?')}"
        )
        if r.get("highlights"):
            lines.append(f"   亮点: {r['highlights'][:60]}")
        if r.get("risks"):
            lines.append(f"   风险: {r['risks'][:60]}")
    lines.append("\n回复 <b>详情N</b> 查看第N份完整内容")
    telegram.send("\n".join(lines))


def _send_image_review(image_paths, title):
    """发送图片审核消息"""
    if isinstance(image_paths, list) and len(image_paths) > 1:
        str_paths = [str(p) for p in image_paths if p]
        if str_paths:
            telegram.send_media_group(str_paths, caption=f"[审图] 「{title}」")
    elif isinstance(image_paths, list) and len(image_paths) == 1:
        telegram.send_photo(str(image_paths[0]), caption=f"[审图] 「{title}」")

    telegram.send(
        f"图片审核 ({len(image_paths)} 张):\n"
        f"回复 <b>确认</b> 通过并发布\n"
        f"回复 <b>取消</b> 取消发布\n"
        f"回复 <b>重新生成</b> 重新生成所有图片\n"
        f"{IMAGE_REVIEW_TIMEOUT} 分钟内未回复将自动确认"
    )


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------

async def run(date_str=None, slots=None):
    """执行完整编排流程"""
    date_str = date_str or date.today().isoformat()
    slots = slots or ["noon", "evening"]

    db.init_db()
    db.migrate_db()

    LOG.info("=== XHS 总编排开始 %s (slots: %s) ===", date_str, slots)
    telegram.send(f"<b>XHS 自动化启动</b> ({date_str})\nSlots: {', '.join(slots)}")

    results = {}
    for slot in slots:
        try:
            post_id = await run_slot(date_str, slot)
            results[slot] = post_id
        except Exception as e:
            LOG.error("Slot %s 异常: %s", slot, e, exc_info=True)
            telegram.send_error(f"[{slot}] 编排异常", str(e)[:200])
            results[slot] = None

    # 汇总报告
    summary_lines = [f"<b>XHS 编排完成</b> ({date_str})\n"]
    for s, pid in results.items():
        status = f"post_id={pid}" if pid else "跳过/失败"
        summary_lines.append(f"  {s}: {status}")
    telegram.send("\n".join(summary_lines))

    LOG.info("=== 总编排结束 ===")
    return results


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s"
    )
    parser = argparse.ArgumentParser(description="XHS 总编排入口")
    parser.add_argument("--date", default=date.today().isoformat(),
                        help="日期 (YYYY-MM-DD)")
    parser.add_argument("--slot", default=None, choices=["noon", "evening"],
                        help="指定单个 slot，默认两个都跑")
    args = parser.parse_args()

    slots = [args.slot] if args.slot else ["noon", "evening"]
    asyncio.run(run(args.date, slots))
