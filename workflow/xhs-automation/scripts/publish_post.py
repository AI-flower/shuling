"""XHS 自动化系统 - 发布编排：读取 draft → 调 publish.sh → 更新状态"""
import json
import os
import subprocess
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(__file__))
import db
import telegram

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
PUBLISH_SH = os.path.join(BASE_DIR, "publish.sh")


def _import_post_from_dir(date_str, slot, post_dir):
    """从文件系统导入帖子到 DB（fallback）"""
    meta_path = os.path.join(post_dir, "meta.json")
    if not os.path.exists(meta_path):
        return None
    import glob
    if not glob.glob(os.path.join(post_dir, "page-*.png")):
        return None
    try:
        meta = json.load(open(meta_path))
        post_id = db.add_post(
            date_str=date_str,
            slot=slot,
            post_dir=os.path.abspath(post_dir),
            title=meta.get("title", ""),
            content=meta.get("content", ""),
            tags=meta.get("tags", []),
            post_type="tool_recommend" if slot == "noon" else "skill_tip",
            scheduled_at=meta.get("schedule_at"),
        )
        print(f"  [fallback] 从文件系统导入: {post_dir} → post_id={post_id}")
        return post_id
    except Exception as e:
        print(f"  [fallback] 导入失败: {e}", file=sys.stderr)
        return None


def publish_slot(date_str, slot):
    """发布指定日期+时段的 draft 帖子"""
    db.init_db()

    drafts = db.get_draft_posts(date_str, slot)
    if not drafts:
        # Fallback：从文件系统扫描
        slot_num = "1" if slot == "noon" else "2"
        fallback_dir = os.path.join(BASE_DIR, "posts", f"{date_str}-post{slot_num}")
        if os.path.isdir(fallback_dir):
            print(f"DB 无记录，尝试从文件系统导入: {fallback_dir}")
            post_id = _import_post_from_dir(date_str, slot, fallback_dir)
            if post_id:
                drafts = db.get_draft_posts(date_str, slot)

    if not drafts:
        print(f"没有找到 {date_str} {slot} 的 draft 帖子")
        return False

    post = drafts[0]  # 取最新的 draft
    post_dir = post["post_dir"]

    # 验证目录和文件存在
    meta_path = os.path.join(post_dir, "meta.json")
    if not os.path.exists(meta_path):
        msg = f"meta.json 不存在: {meta_path}"
        print(msg, file=sys.stderr)
        telegram.send_error("publish_post", msg)
        return False

    # 检查是否有图片
    import glob
    images = sorted(glob.glob(os.path.join(post_dir, "page-*.png")))
    if not images:
        msg = f"没有找到 page-*.png: {post_dir}"
        print(msg, file=sys.stderr)
        telegram.send_error("publish_post", msg)
        return False

    print(f"发布 {date_str} {slot}: 「{post['title']}」")
    print(f"  目录: {post_dir}")
    print(f"  图片: {len(images)} 张")

    # 调用 publish.sh
    try:
        result = subprocess.run(
            ["bash", PUBLISH_SH, post_dir],
            capture_output=True, text=True, timeout=120
        )
        print(result.stdout)
        if result.returncode != 0:
            error_text = (result.stderr or result.stdout).strip()
            msg = f"publish.sh 失败: {error_text}"
            print(msg, file=sys.stderr)
            telegram.send_error("publish_post", msg)
            # 平台业务失败时保留 draft，方便修正后重试；脚本级失败再记 failed
            if result.returncode >= 3:
                db.update_post_status(post["id"], "failed")
            return False

        # 从输出中尝试提取 note_id
        note_id = None
        for line in result.stdout.split("\n"):
            if "note_id" in line.lower() or "id" in line:
                import re
                match = re.search(r'"(?:note_id|id)":\s*"([^"]+)"', line)
                if match:
                    note_id = match.group(1)
                    break

        # 更新状态
        status = "scheduled" if post.get("scheduled_at") else "published"
        db.update_post_status(post["id"], status, note_id)

        # 读取 meta 获取 scheduled_at
        meta = json.load(open(meta_path))
        scheduled_at = meta.get("schedule_at")

        # 发送 Telegram 确认
        telegram.send_publish_confirm(post["title"], slot, scheduled_at)

        print(f"✅ 发布成功！状态: {status}")
        return True

    except subprocess.TimeoutExpired:
        msg = "publish.sh 执行超时（120s）"
        print(msg, file=sys.stderr)
        telegram.send_error("publish_post", msg)
        return False
    except Exception as e:
        msg = f"发布异常: {e}"
        print(msg, file=sys.stderr)
        telegram.send_error("publish_post", msg)
        return False


def publish_by_dir(post_dir):
    """直接通过目录发布（不查 DB）"""
    meta_path = os.path.join(post_dir, "meta.json")
    if not os.path.exists(meta_path):
        print(f"meta.json 不存在: {meta_path}", file=sys.stderr)
        return False

    print(f"直接发布: {post_dir}")
    try:
        result = subprocess.run(
            ["bash", PUBLISH_SH, post_dir],
            capture_output=True, text=True, timeout=120
        )
        print(result.stdout)
        if result.returncode != 0:
            print(f"失败: {(result.stderr or result.stdout).strip()}", file=sys.stderr)
            return False

        meta = json.load(open(meta_path))
        telegram.send_publish_confirm(
            meta["title"], "manual",
            meta.get("schedule_at")
        )
        print("✅ 发布成功！")
        return True
    except Exception as e:
        print(f"异常: {e}", file=sys.stderr)
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法:")
        print(f"  {sys.argv[0]} <date> <slot>     # 从 DB 查 draft 发布")
        print(f"  {sys.argv[0]} <post_dir>         # 直接发布目录")
        print(f"")
        print(f"  slot: noon | evening")
        print(f"  例: {sys.argv[0]} 2026-03-13 noon")
        print(f"  例: {sys.argv[0]} posts/2026-03-13-post1/")
        sys.exit(1)

    if len(sys.argv) == 3:
        publish_slot(sys.argv[1], sys.argv[2])
    else:
        arg = sys.argv[1]
        if os.path.isdir(arg):
            publish_by_dir(arg)
        else:
            # 默认 noon
            publish_slot(arg, "noon")
