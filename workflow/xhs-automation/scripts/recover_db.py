"""从文件系统扫描 posts/ 目录，把缺失的记录补录到 DB"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import db

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
POSTS_DIR = os.path.join(BASE_DIR, "posts")


def recover():
    db.init_db()
    post_dirs = sorted(glob.glob(os.path.join(POSTS_DIR, "????-??-??-post*")))
    imported = 0
    skipped = 0

    for post_dir in post_dirs:
        name = os.path.basename(post_dir)  # e.g. 2026-03-14-post1
        parts = name.rsplit("-post", 1)
        if len(parts) != 2:
            continue
        date_str, num = parts[0], parts[1]
        slot = "noon" if num == "1" else "evening"

        meta_path = os.path.join(post_dir, "meta.json")
        if not os.path.exists(meta_path):
            print(f"  跳过（无 meta.json）: {name}")
            continue

        images = sorted(glob.glob(os.path.join(post_dir, "page-*.png")))
        if not images:
            print(f"  跳过（无图片）: {name}")
            continue

        # 检查 DB 是否已有记录
        existing = db.get_posts_by_date(date_str, slot)
        if existing:
            skipped += 1
            continue

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
            print(f"  ✅ 导入: {name} → post_id={post_id} 「{meta.get('title', '')}」")
            imported += 1
        except Exception as e:
            print(f"  ❌ 导入失败 {name}: {e}")

    print(f"\n完成：新导入 {imported} 条，已有记录跳过 {skipped} 条")


if __name__ == "__main__":
    recover()
