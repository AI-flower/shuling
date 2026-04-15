"""XHS 自动化系统 - 发送草稿预览到 Telegram 供确认"""
import json
import os
import sys
import glob
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(__file__))
import telegram

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
POSTS_DIR = os.path.join(BASE_DIR, "posts")


def send_preview(date_str=None):
    """发送次日草稿的预览到 Telegram（晚上 21:30 发送，预览明天的内容）"""
    if date_str is None:
        date_str = (date.today() + timedelta(days=1)).isoformat()

    print(f"=== 发送 {date_str} 草稿预览 ===\n")

    # 查找当天帖子目录
    post_dirs = sorted(glob.glob(os.path.join(POSTS_DIR, f"{date_str}-post*")))
    if not post_dirs:
        telegram.send(f"⚠️ {date_str} 没有找到待发布的帖子草稿")
        print("没有找到帖子目录")
        return False

    # 发送总览消息
    telegram.send(
        f"📋 <b>XHS 发布计划 — {date_str}</b>\n\n"
        f"共 {len(post_dirs)} 篇帖子待确认\n"
        f"请查看以下预览，回复 ✅ 确认发布"
    )

    for i, post_dir in enumerate(post_dirs, 1):
        meta_path = os.path.join(post_dir, "meta.json")
        if not os.path.exists(meta_path):
            print(f"  跳过 {post_dir}（无 meta.json）")
            continue

        with open(meta_path, "r") as f:
            meta = json.load(f)

        title = meta.get("title", "无标题")
        content = meta.get("content", "")
        tags = meta.get("tags", [])
        schedule_at = meta.get("schedule_at", "未设定")
        slot = "noon" if "post1" in post_dir else "evening"

        # 构造文字信息
        slot_label = "🌞 午间" if slot == "noon" else "🌙 晚间"
        tags_str = " ".join(f"#{t}" for t in tags) if tags else ""

        caption = (
            f"{slot_label} 帖子 {i}/{len(post_dirs)}\n\n"
            f"📝 <b>{title}</b>\n"
            f"⏰ 定时: {schedule_at}\n\n"
            f"{content[:300]}{'...' if len(content) > 300 else ''}\n\n"
            f"🏷 {tags_str}"
        )

        # 收集图片
        images = sorted(glob.glob(os.path.join(post_dir, "page-*.png")))

        if images:
            print(f"  发送帖子 {i}: 「{title}」({len(images)} 张图)")
            if len(images) == 1:
                telegram.send_photo(images[0], caption=caption)
            else:
                # 先发相册（最多10张），第一张带 caption
                telegram.send_media_group(images[:10], caption=caption)
        else:
            print(f"  发送帖子 {i}: 「{title}」（无图片，仅文字）")
            telegram.send(caption)

    # 发送确认提示
    telegram.send(
        "👆 以上为今日全部待发布内容\n\n"
        "✅ 回复「确认」→ 按计划发布\n"
        "❌ 回复「取消」→ 暂停发布\n"
        "📝 回复修改意见 → 我来调整"
    )

    print(f"\n✅ 已发送 {len(post_dirs)} 篇帖子预览到 Telegram")
    return True


if __name__ == "__main__":
    date_str = sys.argv[1] if len(sys.argv) > 1 else None
    send_preview(date_str)
