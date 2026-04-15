"""XHS 自动化系统 - AI 图片生成模块（零依赖）

支持三种策略：
  - ai: OpenAI 兼容 API 生成
  - html: HTML 截图降级（Playwright）
  - auto: AI 优先，失败自动降级为截图
"""
import base64
import glob
import json
import os
import shutil
import subprocess
import sys
import asyncio
import urllib.request
from datetime import datetime

sys.path.insert(0, os.path.dirname(__file__))
import config_loader
import db

config_loader.load_runtime_env()

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
POSTS_DIR = os.path.join(BASE_DIR, "posts")


def get_image_config():
    return {
        "api_key": os.environ.get("IMAGE_GEN_API_KEY", "").strip(),
        "base_url": os.environ.get("IMAGE_GEN_BASE_URL", "https://api.openai.com/v1").rstrip("/"),
        "model": os.environ.get("IMAGE_GEN_MODEL", "gpt-image-1"),
        "size": os.environ.get("IMAGE_GEN_SIZE", "1024x1024"),
        "style": os.environ.get("IMAGE_GEN_STYLE", "vivid"),
        "brand_style": os.environ.get("IMAGE_BRAND_STYLE", "").strip(),
        "concurrency": int(os.environ.get("DRAFT_CONCURRENCY", "3")),
    }


def _find_executable(name, candidates=None):
    candidates = candidates or []
    for candidate in candidates:
        if not candidate:
            continue
        expanded = os.path.expanduser(candidate)
        if os.path.exists(expanded) and os.access(expanded, os.X_OK):
            return expanded
    found = shutil.which(name)
    return found


def _resolve_screenshot_js():
    env_override = os.environ.get("XHS_SCREENSHOT_JS")
    candidates = [
        env_override,
        os.path.expanduser("~/.claude/skills/xhs-content-generator/scripts/screenshot.cjs"),
        os.path.expanduser("~/.agents/skills/xhs-content-generator/scripts/screenshot.cjs"),
        os.path.expanduser("~/.codex/skills/xhs-content-generator/scripts/screenshot.cjs"),
    ]
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    return os.path.expanduser("~/.claude/skills/xhs-content-generator/scripts/screenshot.cjs")


SCREENSHOT_JS = _resolve_screenshot_js()
NODE_BIN = _find_executable("node", [
    os.environ.get("XHS_NODE_BIN"),
    "~/.nvm/versions/node/v24.14.0/bin/node",
    "/opt/homebrew/bin/node",
    "/usr/local/bin/node",
])


# ---------------------------------------------------------------------------
# Prompt 增强
# ---------------------------------------------------------------------------

def enhance_image_prompt(raw_prompt, brand_style="", page_index=0):
    """增强 prompt：追加品牌风格 + 小红书适配 + 页码上下文"""
    parts = [raw_prompt.strip()]

    if brand_style:
        parts.append(brand_style)
    else:
        parts.append("clean modern style, soft pastel colors, minimalist, no text overlay")

    # 页码上下文
    if page_index == 0:
        parts.append("eye-catching cover image, vibrant and inviting")
    elif page_index >= 4:
        parts.append("summary visual, warm and encouraging tone")

    parts.append("high quality, vibrant colors, 3:4 aspect ratio")
    return ", ".join(parts)


# ---------------------------------------------------------------------------
# 策略推荐
# ---------------------------------------------------------------------------

def recommend_image_strategy(draft):
    """根据内容类型推荐图片策略"""
    fmt = draft.get("suggested_format", "image_text")
    config = get_image_config()

    if not config["api_key"]:
        return "html"  # 未配置 API Key，强制截图

    if fmt == "image_text":
        return "ai"
    if fmt == "image_only" and draft.get("angle") == "tutorial":
        return "html"  # 教程类内容截图效果更好
    return "ai"


# ---------------------------------------------------------------------------
# AI 图片生成（OpenAI 兼容 API）
# ---------------------------------------------------------------------------

async def generate_image_ai(semaphore, prompt, output_path, config):
    """通过 OpenAI 兼容 API 生成单张图片"""
    async with semaphore:
        payload = json.dumps({
            "model": config["model"],
            "prompt": prompt,
            "n": 1,
            "size": config["size"],
            "response_format": "b64_json",
        }).encode("utf-8")

        req = urllib.request.Request(
            f"{config['base_url']}/images/generations",
            data=payload,
            headers={
                "Authorization": f"Bearer {config['api_key']}",
                "Content-Type": "application/json",
            },
        )

        loop = asyncio.get_event_loop()
        try:
            resp = await loop.run_in_executor(
                None, lambda: urllib.request.urlopen(req, timeout=120))
            data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")[:300]
            raise RuntimeError(f"API error {e.code}: {body}")

        image_data = data.get("data", [{}])[0]

        if "b64_json" in image_data:
            img_bytes = base64.b64decode(image_data["b64_json"])
        elif "url" in image_data:
            img_resp = await loop.run_in_executor(
                None, lambda: urllib.request.urlopen(image_data["url"], timeout=60))
            img_bytes = img_resp.read()
        else:
            raise ValueError("API response contains neither b64_json nor url")

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(img_bytes)
        return output_path


# ---------------------------------------------------------------------------
# HTML 截图降级
# ---------------------------------------------------------------------------

def generate_image_html(html_path, output_dir):
    """HTML 截图降级（调用 screenshot.cjs），返回图片路径列表"""
    if not html_path or not os.path.exists(html_path):
        print(f"[image_gen] HTML 文件不存在: {html_path}", file=sys.stderr)
        return []

    if not SCREENSHOT_JS or not os.path.exists(SCREENSHOT_JS):
        print(f"[image_gen] 截图脚本不存在: {SCREENSHOT_JS}", file=sys.stderr)
        return []

    if not NODE_BIN:
        print("[image_gen] node 未找到", file=sys.stderr)
        return []

    try:
        env = {**os.environ, "PATH": os.path.dirname(NODE_BIN) + ":" + os.environ.get("PATH", "")}
        node_path = os.environ.get("XHS_NODE_PATH") or os.environ.get("NODE_PATH")
        if node_path:
            env["NODE_PATH"] = node_path

        result = subprocess.run(
            [NODE_BIN, SCREENSHOT_JS, html_path, output_dir],
            capture_output=True, text=True, timeout=60, env=env,
        )
        if result.returncode != 0:
            print(f"[image_gen] 截图失败: {result.stderr}", file=sys.stderr)
            return []

        pngs = sorted(glob.glob(os.path.join(output_dir, "*.png")))
        renamed = []
        for i, png in enumerate(pngs, 1):
            new_name = os.path.join(output_dir, f"page-{i}.png")
            if png != new_name:
                os.rename(png, new_name)
            renamed.append(new_name)

        return renamed

    except subprocess.TimeoutExpired:
        print("[image_gen] 截图超时", file=sys.stderr)
        return []
    except Exception as e:
        print(f"[image_gen] 截图异常: {e}", file=sys.stderr)
        return []


# ---------------------------------------------------------------------------
# 主生成流程（并行 AI + 截图降级）
# ---------------------------------------------------------------------------

async def generate_images(draft, post_id, output_dir):
    """
    为选中草稿生成所有图片。

    Args:
        draft: 草稿 dict（需含 image_prompts / key_points / image_strategy）
        post_id: 帖子 DB ID
        output_dir: 输出目录

    Returns:
        [{"index": N, "path": str|None, "status": str, "error": str?}, ...]
    """
    os.makedirs(output_dir, exist_ok=True)
    config = get_image_config()

    # 确定策略
    strategy = draft.get("image_strategy", "auto")
    if strategy == "auto":
        strategy = recommend_image_strategy(draft)

    # 解析 prompts
    prompts = draft.get("image_prompts", [])
    if isinstance(prompts, str):
        try:
            prompts = json.loads(prompts) if prompts else []
        except (json.JSONDecodeError, ValueError):
            prompts = [prompts] if prompts else []

    # 如果没有 prompts，从 key_points 构造
    if not prompts:
        kps = draft.get("key_points", [])
        if isinstance(kps, str):
            try:
                kps = json.loads(kps) if kps else []
            except (json.JSONDecodeError, ValueError):
                kps = [kps] if kps else []
        prompts = [f"illustration for: {kp}" for kp in kps] if kps else []

    if not prompts:
        prompts = [f"illustration for: {draft.get('title', 'content')}"]

    semaphore = asyncio.Semaphore(config["concurrency"])
    results = []
    ai_failed = []

    # 注册到 DB + AI 并行生成
    db_ids = []
    for i, prompt in enumerate(prompts):
        img_id = db.add_generated_image(
            post_id, i + 1, prompt,
            gen_model=config["model"] if strategy == "ai" else "screenshot",
            gen_strategy=strategy,
        )
        db_ids.append(img_id)

    if strategy in ("ai", "auto") and config["api_key"]:
        # 并行 AI 生成
        async def _gen_one(idx, prompt):
            img_path = os.path.join(output_dir, f"page-{idx + 1}.png")
            enhanced = enhance_image_prompt(prompt, config["brand_style"], page_index=idx)
            try:
                path = await generate_image_ai(semaphore, enhanced, img_path, config)
                db.update_image_status(db_ids[idx], "done", path)
                print(f"  [AI] page-{idx + 1}.png 生成成功")
                return {"index": idx + 1, "path": path, "status": "done"}
            except Exception as e:
                print(f"  [AI] page-{idx + 1}.png 失败: {e}", file=sys.stderr)
                return {"index": idx + 1, "path": None, "status": "failed", "error": str(e)}

        tasks = [_gen_one(i, p) for i, p in enumerate(prompts)]
        results = await asyncio.gather(*tasks)

        # 收集失败的索引
        ai_failed = [r["index"] - 1 for r in results if r["status"] == "failed"]
    else:
        # 不走 AI，全部标记为待截图
        ai_failed = list(range(len(prompts)))
        results = [{"index": i + 1, "path": None, "status": "pending"} for i in range(len(prompts))]

    # 截图降级：对 AI 失败 / 非 AI 策略的图片
    if ai_failed and strategy in ("html", "auto"):
        html_path = os.path.join(output_dir, "post.html")
        # 也尝试从帖子目录找
        if not os.path.exists(html_path):
            post_dir = draft.get("post_dir", output_dir)
            html_path = os.path.join(post_dir, "post.html")

        screenshot_paths = generate_image_html(html_path, output_dir)
        if screenshot_paths:
            print(f"  [截图] 成功生成 {len(screenshot_paths)} 张")

        for idx in ai_failed:
            if idx < len(screenshot_paths) and os.path.exists(screenshot_paths[idx]):
                db.update_image_status(db_ids[idx], "done", screenshot_paths[idx])
                results[idx] = {"index": idx + 1, "path": screenshot_paths[idx], "status": "done"}
            else:
                db.update_image_status(db_ids[idx], "failed")
                if results[idx]["status"] != "failed":
                    results[idx] = {"index": idx + 1, "path": None, "status": "failed",
                                    "error": "screenshot fallback unavailable"}

    return results


# ---------------------------------------------------------------------------
# 重新生成指定图片
# ---------------------------------------------------------------------------

async def regenerate_image(post_id, page_index, new_prompt=None):
    """重新生成指定页码的图片，返回路径或 None"""
    config = get_image_config()
    if not config["api_key"]:
        return None

    images = db.get_post_images(post_id)
    target = None
    for img in images:
        if img["image_index"] == page_index:
            target = img
            break

    if not target:
        print(f"[image_gen] post_id={post_id} 未找到 page_index={page_index}", file=sys.stderr)
        return None

    prompt = new_prompt or target["prompt"]
    output_path = target.get("image_path")
    if not output_path:
        output_path = os.path.join(POSTS_DIR, f"regen-{post_id}-{page_index}.png")

    enhanced = enhance_image_prompt(prompt, config["brand_style"], page_index=page_index - 1)
    semaphore = asyncio.Semaphore(1)

    try:
        path = await generate_image_ai(semaphore, enhanced, output_path, config)
        # 更新旧记录 + 新增记录
        db.update_image_status(target["id"], "done", path)
        if new_prompt:
            db.add_generated_image(
                post_id, page_index, new_prompt,
                image_path=path, gen_model=config["model"],
                gen_strategy="ai", gen_status="done",
            )
        return path
    except Exception as e:
        print(f"[image_gen] 重新生成失败: {e}", file=sys.stderr)
        db.update_image_status(target["id"], "failed")
        return None


# ---------------------------------------------------------------------------
# 同步入口
# ---------------------------------------------------------------------------

def run(draft, post_id, output_dir):
    """同步入口，供其他模块调用"""
    return asyncio.run(generate_images(draft, post_id, output_dir))


def run_regenerate(post_id, page_index, new_prompt=None):
    """同步重新生成入口"""
    return asyncio.run(regenerate_image(post_id, page_index, new_prompt))


# ---------------------------------------------------------------------------
# CLI 入口
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    from datetime import date
    db.init_db()

    if len(sys.argv) < 2:
        print("用法: python image_generator.py <post_id> [strategy]")
        print("  strategy: auto (默认) / ai / html")
        sys.exit(1)

    post_id = int(sys.argv[1])
    cli_strategy = sys.argv[2] if len(sys.argv) > 2 else "auto"

    # 从 DB 读取帖子
    all_posts = db.get_posts_by_date(date.today().isoformat())
    post = None
    for p in all_posts:
        if p["id"] == post_id:
            post = p
            break

    if not post:
        print(f"[image_gen] 未找到 post_id={post_id}")
        sys.exit(1)

    post_dir = post["post_dir"]
    images = db.get_post_images(post_id)
    if images:
        prompts = [img["prompt"] for img in images]
    else:
        prompts = [
            f"Cover illustration for: {post['title']}",
            f"Content illustration for: {post['title']}",
            f"Summary illustration for: {post['title']}",
        ]

    config = get_image_config()
    print(f"[image_gen] 帖子 #{post_id}「{post['title']}」生成 {len(prompts)} 张图片")
    print(f"  策略: {cli_strategy}, AI API: {'可用' if config['api_key'] else '未配置'}")

    draft_like = {
        "title": post["title"],
        "image_prompts": prompts,
        "image_strategy": cli_strategy,
        "post_dir": post_dir,
    }
    results = run(draft_like, post_id, post_dir)
    done = [r for r in results if r["status"] == "done"]
    print(f"\n完成: {len(done)}/{len(results)} 张图片生成成功")
    for r in results:
        status_icon = "OK" if r["status"] == "done" else "FAIL"
        print(f"  [{status_icon}] page-{r['index']}.png {r.get('path', '')}")
