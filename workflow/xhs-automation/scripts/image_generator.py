"""XHS 自动化系统 - AI 图片生成模块（零依赖）

支持四种策略：
  - cover_ai: 封面 AI 生成 + 内容页 HTML 截图（推荐默认）
  - ai: 全部 AI 生成
  - html: 全部 HTML 截图（Playwright）
  - auto: 等同 cover_ai（向后兼容）

支持两种 AI 图片后端（IMAGE_GEN_PROVIDER）：
  - openai: OpenAI 兼容 API（gpt-image-1 等）
  - gemini: Google Gemini API（Nano Banana Pro 等，零 SDK 依赖）
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
    provider = os.environ.get("IMAGE_GEN_PROVIDER", "openai").strip().lower()

    # 根据 provider 设置默认 model
    default_model = {
        "openai": "gpt-image-1",
        "gemini": "gemini-2.0-flash-preview-image-generation",
    }.get(provider, "gpt-image-1")

    return {
        "provider": provider,
        "api_key": os.environ.get("IMAGE_GEN_API_KEY", "").strip(),
        "base_url": os.environ.get("IMAGE_GEN_BASE_URL", "https://api.openai.com/v1").rstrip("/"),
        "model": os.environ.get("IMAGE_GEN_MODEL", default_model),
        "size": os.environ.get("IMAGE_GEN_SIZE", "1024x1024"),
        "aspect_ratio": os.environ.get("IMAGE_GEN_ASPECT_RATIO", "3:4"),
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

def _parse_image_prompts(raw):
    """解析 image_prompts，兼容新格式（dict）和旧格式（list/str）。

    Returns:
        (visual_style: str, prompts: list[str])
    """
    if isinstance(raw, str):
        try:
            raw = json.loads(raw) if raw else []
        except (json.JSONDecodeError, ValueError):
            return ("", [raw] if raw else [])

    if isinstance(raw, dict):
        visual_style = raw.get("visual_style", "")
        prompts = raw.get("prompts", [])
        if isinstance(prompts, str):
            prompts = [prompts] if prompts else []
        return (visual_style, prompts)

    if isinstance(raw, list):
        return ("", raw)

    return ("", [])


def enhance_image_prompt(raw_prompt, brand_style="", visual_style="", page_index=0):
    """增强 prompt：合并品牌风格 + 帖子视觉风格 + 小红书适配 + 页码上下文

    优先级：raw_prompt（内容描述）> visual_style（本帖风格）> brand_style（品牌风格）
    """
    parts = [raw_prompt.strip()]

    # 帖子级风格（来自 Claude 针对本帖生成的视觉描述）
    if visual_style:
        parts.append(visual_style)

    # 品牌级风格（来自 IMAGE_BRAND_STYLE 环境变量）
    if brand_style:
        parts.append(brand_style)
    elif not visual_style:
        # 两者都没有时才用兜底
        parts.append("clean modern style, soft pastel colors, minimalist, no text overlay")

    # 页码上下文
    if page_index == 0:
        parts.append("eye-catching cover image, vibrant and inviting, hero illustration")
    elif page_index >= 4:
        parts.append("summary visual, warm and encouraging tone")

    parts.append("high quality, vibrant colors, 3:4 aspect ratio, no text in image")
    return ", ".join(parts)


# ---------------------------------------------------------------------------
# 策略推荐
# ---------------------------------------------------------------------------

def recommend_image_strategy(draft):
    """根据内容类型推荐图片策略

    策略说明：
    - html: 全部走 HTML 截图（无 API Key 时强制）
    - ai: 全部走 AI 生成
    - cover_ai: 封面走 AI，内容页走 HTML 截图（推荐默认）
    - auto: 等同 cover_ai（向后兼容）
    """
    config = get_image_config()

    if not config["api_key"]:
        return "html"

    fmt = draft.get("suggested_format", "image_text")

    # image_text 格式（主流）：封面 AI + 内容截图，兼顾吸引力和信息密度
    if fmt == "image_text":
        return "cover_ai"

    # 纯图片格式：全部 AI
    if fmt == "image_only":
        return "ai"

    return "cover_ai"


# ---------------------------------------------------------------------------
# AI 图片生成 — 路由
# ---------------------------------------------------------------------------

async def generate_image_ai(semaphore, prompt, output_path, config):
    """通过 AI API 生成单张图片（自动路由 OpenAI / Gemini）"""
    provider = config.get("provider", "openai")
    if provider == "gemini":
        return await _generate_image_gemini(semaphore, prompt, output_path, config)
    else:
        return await _generate_image_openai(semaphore, prompt, output_path, config)


# ---------------------------------------------------------------------------
# OpenAI 兼容 API 后端
# ---------------------------------------------------------------------------

async def _generate_image_openai(semaphore, prompt, output_path, config):
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
            raise RuntimeError(f"OpenAI API error {e.code}: {body}")

        image_data = data.get("data", [{}])[0]

        if "b64_json" in image_data:
            img_bytes = base64.b64decode(image_data["b64_json"])
        elif "url" in image_data:
            img_resp = await loop.run_in_executor(
                None, lambda: urllib.request.urlopen(image_data["url"], timeout=60))
            img_bytes = img_resp.read()
        else:
            raise ValueError("OpenAI response contains neither b64_json nor url")

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(img_bytes)
        return output_path


# ---------------------------------------------------------------------------
# Google Gemini API 后端（零 SDK 依赖，直接 REST 调用）
# ---------------------------------------------------------------------------

GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta"


async def _generate_image_gemini(semaphore, prompt, output_path, config):
    """通过 Google Gemini API 生成单张图片

    使用 generateContent 端点 + responseModalities=IMAGE，
    支持 Nano Banana Pro / Nano Banana 2 等 Gemini 图像生成模型。
    """
    async with semaphore:
        model = config["model"]
        api_key = config["api_key"]
        aspect_ratio = config.get("aspect_ratio", "3:4")

        url = f"{GEMINI_API_BASE}/models/{model}:generateContent?key={api_key}"

        payload = json.dumps({
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
            },
        }).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=payload,
            headers={"Content-Type": "application/json"},
        )

        loop = asyncio.get_event_loop()
        try:
            resp = await loop.run_in_executor(
                None, lambda: urllib.request.urlopen(req, timeout=180))
            data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")[:500]
            raise RuntimeError(f"Gemini API error {e.code}: {body}")

        # 从 candidates 中提取图片
        candidates = data.get("candidates", [])
        if not candidates:
            # 检查是否有 promptFeedback 被拒
            feedback = data.get("promptFeedback", {})
            block_reason = feedback.get("blockReason", "")
            if block_reason:
                raise RuntimeError(f"Gemini 拒绝生成: {block_reason}")
            raise RuntimeError(f"Gemini 返回空 candidates: {json.dumps(data)[:300]}")

        parts = candidates[0].get("content", {}).get("parts", [])
        for part in parts:
            inline_data = part.get("inlineData")
            if inline_data and inline_data.get("data"):
                img_bytes = base64.b64decode(inline_data["data"])
                os.makedirs(os.path.dirname(output_path), exist_ok=True)
                with open(output_path, "wb") as f:
                    f.write(img_bytes)
                return output_path

        raise RuntimeError(
            f"Gemini 响应中无图片数据, parts={json.dumps(parts)[:200]}"
        )


async def _generate_image_gemini_with_ref(semaphore, prompt, output_path, config,
                                          reference_image_path=None):
    """Gemini 生图 + 参考图（保持风格一致性）

    将参考图作为 contents 的一部分传入，Gemini 会参考其风格生成新图。
    适用于 cover_ai 策略：先生成封面，后续页面以封面为参考。
    """
    async with semaphore:
        model = config["model"]
        api_key = config["api_key"]

        url = f"{GEMINI_API_BASE}/models/{model}:generateContent?key={api_key}"

        content_parts = []

        # 如果有参考图，先放参考图
        if reference_image_path and os.path.exists(reference_image_path):
            with open(reference_image_path, "rb") as f:
                ref_bytes = f.read()
            ref_b64 = base64.b64encode(ref_bytes).decode("utf-8")
            # 判断 MIME 类型
            mime = "image/png" if reference_image_path.endswith(".png") else "image/jpeg"
            content_parts.append({
                "inlineData": {"mimeType": mime, "data": ref_b64}
            })
            content_parts.append({
                "text": f"参考上面这张图的视觉风格和配色，生成以下内容的插画：{prompt}"
            })
        else:
            content_parts.append({"text": prompt})

        payload = json.dumps({
            "contents": [{"parts": content_parts}],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
            },
        }).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=payload,
            headers={"Content-Type": "application/json"},
        )

        loop = asyncio.get_event_loop()
        try:
            resp = await loop.run_in_executor(
                None, lambda: urllib.request.urlopen(req, timeout=180))
            data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")[:500]
            raise RuntimeError(f"Gemini API error {e.code}: {body}")

        candidates = data.get("candidates", [])
        if not candidates:
            feedback = data.get("promptFeedback", {})
            block_reason = feedback.get("blockReason", "")
            if block_reason:
                raise RuntimeError(f"Gemini 拒绝生成: {block_reason}")
            raise RuntimeError(f"Gemini 返回空 candidates: {json.dumps(data)[:300]}")

        parts = candidates[0].get("content", {}).get("parts", [])
        for part in parts:
            inline_data = part.get("inlineData")
            if inline_data and inline_data.get("data"):
                img_bytes = base64.b64decode(inline_data["data"])
                os.makedirs(os.path.dirname(output_path), exist_ok=True)
                with open(output_path, "wb") as f:
                    f.write(img_bytes)
                return output_path

        raise RuntimeError(
            f"Gemini 响应中无图片数据, parts={json.dumps(parts)[:200]}"
        )


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

    provider = config["provider"]
    use_gemini_ref = (provider == "gemini")

    # 确定策略
    strategy = draft.get("image_strategy", "auto")
    if strategy == "auto":
        strategy = recommend_image_strategy(draft)

    # 解析 prompts（兼容新格式 dict 和旧格式 list）
    visual_style, prompts = _parse_image_prompts(draft.get("image_prompts", []))

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
    model_name = config["model"] if strategy in ("ai", "cover_ai") else "screenshot"
    db_ids = []
    for i, prompt in enumerate(prompts):
        img_id = db.add_generated_image(
            post_id, i + 1, prompt,
            gen_model=model_name,
            gen_strategy=strategy,
        )
        db_ids.append(img_id)

    if strategy == "cover_ai" and config["api_key"] and len(prompts) > 0:
        # cover_ai 策略：封面（index 0）走 AI，其余走 HTML 截图
        results = [{"index": i + 1, "path": None, "status": "pending"} for i in range(len(prompts))]

        # AI 生成封面
        cover_prompt = prompts[0]
        cover_path = os.path.join(output_dir, f"page-1.png")
        enhanced = enhance_image_prompt(
            cover_prompt, config["brand_style"], visual_style, page_index=0
        )
        try:
            path = await generate_image_ai(semaphore, enhanced, cover_path, config)
            db.update_image_status(db_ids[0], "done", path)
            results[0] = {"index": 1, "path": path, "status": "done"}
            print(f"  [{provider.upper()}] page-1.png 封面生成成功")
        except Exception as e:
            print(f"  [{provider.upper()}] page-1.png 封面失败: {e}，将降级截图", file=sys.stderr)

        # 内容页走 HTML 截图
        html_path = os.path.join(output_dir, "post.html")
        if not os.path.exists(html_path):
            post_dir = draft.get("post_dir", output_dir)
            html_path = os.path.join(post_dir, "post.html")

        screenshot_paths = generate_image_html(html_path, output_dir)
        if screenshot_paths:
            print(f"  [截图] 成功生成 {len(screenshot_paths)} 张")

        # 内容页使用截图结果（跳过封面 index 0 如果 AI 成功）
        for idx in range(1, len(prompts)):
            if idx < len(screenshot_paths) and os.path.exists(screenshot_paths[idx]):
                db.update_image_status(db_ids[idx], "done", screenshot_paths[idx])
                results[idx] = {"index": idx + 1, "path": screenshot_paths[idx], "status": "done"}
            else:
                db.update_image_status(db_ids[idx], "failed")
                results[idx] = {"index": idx + 1, "path": None, "status": "failed",
                                "error": "screenshot not available for this page"}

        # 封面 AI 失败时，用截图兜底
        if results[0]["status"] != "done" and screenshot_paths and os.path.exists(screenshot_paths[0]):
            db.update_image_status(db_ids[0], "done", screenshot_paths[0])
            results[0] = {"index": 1, "path": screenshot_paths[0], "status": "done"}

        return results

    elif strategy in ("ai", "auto") and config["api_key"]:
        # 全 AI 生成：Gemini 时利用参考图保持风格一致
        cover_path_for_ref = None

        async def _gen_one(idx, prompt):
            nonlocal cover_path_for_ref
            img_path = os.path.join(output_dir, f"page-{idx + 1}.png")
            enhanced = enhance_image_prompt(prompt, config["brand_style"], visual_style, page_index=idx)
            try:
                if use_gemini_ref and idx > 0 and cover_path_for_ref:
                    # Gemini：后续页面以封面为参考图，保持风格一致
                    path = await _generate_image_gemini_with_ref(
                        semaphore, enhanced, img_path, config,
                        reference_image_path=cover_path_for_ref,
                    )
                else:
                    path = await generate_image_ai(semaphore, enhanced, img_path, config)

                # 封面生成成功后记录路径，供后续页面参考
                if idx == 0:
                    cover_path_for_ref = path

                db.update_image_status(db_ids[idx], "done", path)
                print(f"  [{provider.upper()}] page-{idx + 1}.png 生成成功")
                return {"index": idx + 1, "path": path, "status": "done"}
            except Exception as e:
                print(f"  [{provider.upper()}] page-{idx + 1}.png 失败: {e}", file=sys.stderr)
                return {"index": idx + 1, "path": None, "status": "failed", "error": str(e)}

        if use_gemini_ref and len(prompts) > 1:
            # Gemini 参考图模式：先生成封面，再并行生成后续页面
            cover_result = await _gen_one(0, prompts[0])
            results = [cover_result]

            if cover_result["status"] == "done":
                # 封面成功，后续页面并行生成（带参考图）
                tasks = [_gen_one(i, p) for i, p in enumerate(prompts) if i > 0]
                rest = await asyncio.gather(*tasks)
                results.extend(rest)
            else:
                # 封面失败，后续页面不带参考图并行生成
                tasks = [_gen_one(i, p) for i, p in enumerate(prompts) if i > 0]
                rest = await asyncio.gather(*tasks)
                results.extend(rest)
        else:
            # OpenAI 或单图：全部并行
            tasks = [_gen_one(i, p) for i, p in enumerate(prompts)]
            results = await asyncio.gather(*tasks)

        results = sorted(results, key=lambda r: r["index"])

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

    enhanced = enhance_image_prompt(prompt, config["brand_style"], visual_style="", page_index=page_index - 1)
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
        print("  strategy: auto (默认) / ai / html / cover_ai")
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
    provider = config["provider"]
    print(f"[image_gen] 帖子 #{post_id}「{post['title']}」生成 {len(prompts)} 张图片")
    print(f"  策略: {cli_strategy}, Provider: {provider}, API: {'可用' if config['api_key'] else '未配置'}")
    if provider == "gemini":
        print(f"  Gemini 模型: {config['model']}, 宽高比: {config['aspect_ratio']}")

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
