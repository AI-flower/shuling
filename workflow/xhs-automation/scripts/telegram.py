"""XHS 自动化系统 - Telegram 通知模块（零依赖）"""
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import config_loader

config_loader.load_runtime_env()

BOT_TOKEN = os.environ.get("XHS_TELEGRAM_BOT_TOKEN", "").strip()
CHAT_ID = os.environ.get("XHS_TELEGRAM_CHAT_ID", "").strip()


def _api_url(method):
    return f"https://api.telegram.org/bot{BOT_TOKEN}/{method}"


def _is_configured():
    if BOT_TOKEN and CHAT_ID:
        return True
    print("Telegram config missing: set XHS_TELEGRAM_BOT_TOKEN and XHS_TELEGRAM_CHAT_ID", file=sys.stderr)
    return False


def send(text, parse_mode="HTML"):
    """发送 Telegram 消息"""
    if not _is_configured():
        return False
    data = json.dumps({
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": parse_mode
    }).encode()
    req = urllib.request.Request(_api_url("sendMessage"), data=data, headers={"Content-Type": "application/json"})
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        result = json.loads(resp.read())
        return result.get("ok", False)
    except Exception as e:
        print(f"Telegram send failed: {e}", file=sys.stderr)
        return False


def send_daily_review(date_str, posts_data, trend_data=None, follower_count=None, insights=None, tomorrow_plan=None):
    """发送格式化的每日复盘"""
    lines = [f"📊 <b>XHS 每日复盘</b> ({date_str})", ""]

    # 今日数据
    lines.append("📈 <b>今日数据</b>")
    for p in posts_data:
        lines.append(f"  {p['slot']}: 「{p['title']}」")
        lines.append(f"    ❤️ {p.get('likes', 0)}  ⭐ {p.get('saves', 0)}  💬 {p.get('comments', 0)}")
    lines.append("")

    # 累计趋势
    if follower_count is not None:
        lines.append(f"👥 <b>粉丝</b>: {follower_count}")

    if trend_data:
        total_l = sum(t.get("total_likes", 0) for t in trend_data)
        total_s = sum(t.get("total_saves", 0) for t in trend_data)
        lines.append(f"📊 近{len(trend_data)}天: 总赞 {total_l} | 总收藏 {total_s}")
    lines.append("")

    # 洞察
    if insights:
        lines.append(f"💡 <b>洞察</b>: {insights}")
        lines.append("")

    # 明日计划
    if tomorrow_plan:
        lines.append("📅 <b>明日计划</b>:")
        for item in tomorrow_plan:
            lines.append(f"  • {item}")

    return send("\n".join(lines))


def send_photo(photo_path, caption="", parse_mode="HTML"):
    """发送图片到 Telegram（multipart/form-data，零依赖）"""
    if not _is_configured():
        return False
    import os
    import uuid
    boundary = uuid.uuid4().hex
    url = _api_url("sendPhoto")

    with open(photo_path, "rb") as f:
        file_data = f.read()

    filename = os.path.basename(photo_path)
    parts = []

    # chat_id
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n{CHAT_ID}")
    # caption
    if caption:
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n{caption}")
    # parse_mode
    if parse_mode:
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"parse_mode\"\r\n\r\n{parse_mode}")
    # photo file
    file_header = f"--{boundary}\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"{filename}\"\r\nContent-Type: image/png\r\n\r\n"

    body = "\r\n".join(parts).encode() + b"\r\n" + file_header.encode() + file_data + f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}"
    })
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        result = json.loads(resp.read())
        return result.get("ok", False)
    except Exception as e:
        print(f"Telegram send_photo failed: {e}", file=sys.stderr)
        return False


def send_media_group(photo_paths, caption="", parse_mode="HTML"):
    """发送多张图片为相册（media group）"""
    if not _is_configured():
        return False
    import os
    import uuid
    boundary = uuid.uuid4().hex
    url = _api_url("sendMediaGroup")

    media = []
    file_parts = []
    for i, path in enumerate(photo_paths):
        attach_name = f"photo{i}"
        item = {"type": "photo", "media": f"attach://{attach_name}"}
        if i == 0 and caption:
            item["caption"] = caption
            if parse_mode:
                item["parse_mode"] = parse_mode
        media.append(item)
        file_parts.append((attach_name, path))

    parts_bytes = b""
    # chat_id
    parts_bytes += f"--{boundary}\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n{CHAT_ID}\r\n".encode()
    # media json
    media_json = json.dumps(media, ensure_ascii=False)
    parts_bytes += f"--{boundary}\r\nContent-Disposition: form-data; name=\"media\"\r\n\r\n{media_json}\r\n".encode()
    # files
    for attach_name, path in file_parts:
        filename = os.path.basename(path)
        with open(path, "rb") as f:
            file_data = f.read()
        parts_bytes += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{attach_name}\"; filename=\"{filename}\"\r\nContent-Type: image/png\r\n\r\n".encode()
        parts_bytes += file_data + b"\r\n"

    parts_bytes += f"--{boundary}--\r\n".encode()

    req = urllib.request.Request(url, data=parts_bytes, headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}"
    })
    try:
        resp = urllib.request.urlopen(req, timeout=60)
        result = json.loads(resp.read())
        return result.get("ok", False)
    except Exception as e:
        print(f"Telegram send_media_group failed: {e}", file=sys.stderr)
        return False


def send_publish_confirm(title, slot, scheduled_at=None):
    """发送发布确认"""
    time_info = f"定时 {scheduled_at}" if scheduled_at else "立即发布"
    return send(f"✅ <b>帖子已提交</b>\n\n📝 {title}\n⏰ {slot} | {time_info}")


def send_error(context, error_msg):
    """发送错误告警"""
    return send(f"🚨 <b>XHS 自动化错误</b>\n\n📍 {context}\n❌ {error_msg}")


def send_draft_report(rankings_data, date_str, slot):
    """发送草稿报告总览（Top 3）"""
    r = rankings_data
    top3 = r["rankings"][:3]

    slot_label = "午间档" if slot == "noon" else "晚间档"
    lines = [f"📊 推文草稿报告 | {date_str} {slot_label}\n"]
    lines.append(f"共生成 {r['total_drafts']} 份草稿，验证评估完成\n")

    if r.get("cold_start"):
        lines.append(f"📊 数据积累中（已发布 {r.get('post_count', 0)} 篇），评分精度将持续提升\n")

    lines.append("🏆 Top 3 推荐：")
    medals = ["1️⃣", "2️⃣", "3️⃣"]
    for i, item in enumerate(top3):
        angle_map = {"recommend": "推荐", "tutorial": "教程", "compare": "评测", "story": "故事"}
        style_map = {"professional": "专业", "casual": "口语", "suspense": "悬念"}
        tag = f"[{angle_map.get(item.get('angle',''), '?')}+{style_map.get(item.get('style',''), '?')}]"
        lines.append(f"{medals[i]} {tag} {item['total_score']}分 — \"{item['title']}\"")
        if item.get("highlights"):
            lines.append(f"   💡 {item['highlights']}")

    lines.append(f"\n📈 {r.get('overall_insight', '')}")
    lines.append(f"\n回复数字 1-{r['total_drafts']} 查看详情")
    lines.append("回复 \"选N\" 确认选择")
    lines.append("回复 \"更多\" 查看全部草稿")

    timeout = int(os.environ.get("DRAFT_SELECT_TIMEOUT", "110"))
    lines.append(f"\n⏰ {timeout}分钟后自动使用 #1")

    return send("\n".join(lines))


def send_draft_detail(draft, score_data):
    """发送单份草稿详情"""
    angle_map = {"recommend": "推荐", "tutorial": "教程", "compare": "评测", "story": "故事"}
    style_map = {"professional": "专业", "casual": "口语", "suspense": "悬念"}

    lines = [f"📝 草稿详情 | {angle_map.get(draft.get('angle',''),'?')}+{style_map.get(draft.get('style',''),'?')}\n"]
    lines.append(f"标题：{draft['title']}\n")
    content_preview = draft.get("content", "")[:200]
    lines.append(f"正文预览：\n\"{content_preview}...\"\n")

    tags = draft.get("tags", [])
    if isinstance(tags, str):
        tags = json.loads(tags) if tags else []
    lines.append(f"标签：{' '.join(tags)}")
    lines.append(f"格式：{draft.get('suggested_format', '?')}")

    if score_data:
        lines.append(f"\n评分明细：")
        lines.append(f"  平台数据 {score_data.get('platform_score', '?')}/100")
        lines.append(f"  内容质量 {score_data.get('quality_score', '?')}/100")
        lines.append(f"  历史对标 {score_data.get('history_score', '?')}/100")
        lines.append(f"  综合评分 {score_data.get('total_score', '?')}/100")

    lines.append(f"\n回复 \"选{draft.get('rank', '?')}\" 确认选择")
    return send("\n".join(lines))


def send_image_review(image_paths, draft_title):
    """发送图片审核（相册 + 操作指引）"""
    if len(image_paths) > 1:
        send_media_group([p for p in image_paths if p and os.path.exists(p)])
    elif image_paths and os.path.exists(image_paths[0]):
        send_photo(image_paths[0])

    lines = [f"🎨 图片已生成 | \"{draft_title}\""]
    lines.append(f"共 {len(image_paths)} 张图片")
    lines.append("")
    lines.append("回复 \"确认\" → 进入发布")
    lines.append("回复 \"重新生成\" → 全部重新生成")
    lines.append("回复 \"重新生成N\" → 重新生成第N张")
    lines.append("回复 \"取消\" → 取消发布")
    timeout = int(os.environ.get("IMAGE_REVIEW_TIMEOUT", "30"))
    lines.append(f"\n⏰ {timeout}分钟后自动确认")
    return send("\n".join(lines))


def send_all_drafts_summary(rankings):
    """发送全部草稿摘要（回复"更多"时）"""
    lines = ["📋 全部草稿摘要\n"]
    angle_map = {"recommend": "推荐", "tutorial": "教程", "compare": "评测", "story": "故事"}
    style_map = {"professional": "专业", "casual": "口语", "suspense": "悬念"}
    for item in rankings:
        tag = f"[{angle_map.get(item.get('angle',''), '?')}+{style_map.get(item.get('style',''), '?')}]"
        lines.append(f"#{item['rank']} {tag} {item['total_score']}分 — \"{item['title']}\"")
    lines.append(f"\n回复 \"选N\" 确认选择")
    return send("\n".join(lines))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        send(" ".join(sys.argv[1:]), parse_mode="")
    else:
        send("🧪 XHS 自动化系统 Telegram 通知测试成功！")
        print("Test message sent.")
