#!/usr/bin/env python3
"""AI image generation script with fixed Gemini Native or OpenAI-compatible provider.

真实生成只使用首次配置时选定的图片接口。
`IMAGE_GEN_PROTOCOL` 必须在首次配置时明确选择一种：
  - gemini-native / gemini（Gemini 原生图片接口）
  - openai-images / openai-image / openai（OpenAI 兼容图片接口）

支持两种 CLI 模式：
  - 结构化模式（推荐，RedInk 范式）：加载 prompts/image_prompt.txt 中文模板
      --page-type 封面|内容|总结
      --page-content "该页完整原文（含 配图建议 那一行）"
      --outline-file /tmp/xhs-post/outline.txt   # 整篇大纲原文
      --topic "用户原始主题"
      --output /tmp/xhs-post/page-1.png
      [--reference /tmp/xhs-post/page-1.png]     # 封面回流
      [--short]                                   # 用 image_prompt_short.txt

  - 兼容模式（旧，直接给 prompt 文本）：
      image.py "<prompt>" <output_path> [--reference path]

控制命令：
    python3 scripts/image.py --check
    python3 scripts/image.py --set-key "KEY"

Exit codes:
    0 - Success
    2 - API key not configured
    3 - Generation failed
"""

import base64
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


GEMINI_DEFAULT_MODEL = "gemini-2.5-flash-image"
GEMINI_DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
OPENAI_DEFAULT_MODEL = "gpt-image-2"
OPENAI_DEFAULT_BASE_URL = "https://api.gjs.ink"


# ── 路径 / 配置加载 ──────────────────────────────────────────────────────────

def _skill_dir():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(script_dir)


def get_data_dir():
    return os.path.join(_skill_dir(), "data")


def get_prompts_dir():
    return os.path.join(_skill_dir(), "prompts")


def get_env_files():
    return [
        os.path.join(_skill_dir(), "config", "runtime.env"),
        os.path.join(get_data_dir(), ".env"),
    ]


def load_env():
    env_vars = {}
    for path in get_env_files():
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, _, v = line.partition("=")
                    env_vars.setdefault(k.strip(), v.strip())
    return env_vars


def _resolve(name, default=""):
    v = os.environ.get(name, "").strip()
    if v:
        return v
    return load_env().get(name, "").strip() or default


def get_protocol():
    return (_resolve("IMAGE_GEN_PROTOCOL") or "").lower()


def get_effective_protocol():
    proto = get_protocol()
    if proto in ("", "auto"):
        return ""
    if proto in ("gemini-native", "gemini", "google-gemini", "google"):
        return "gemini-native"
    if proto in ("openai-images", "openai-image", "openai"):
        return "openai-images"
    if proto == "openai-chat":
        print(f"[image] WARN: protocol={proto} 已兼容映射为 openai-images", file=sys.stderr)
        return "openai-images"
    return proto


def get_api_key(protocol=None):
    proto = protocol or get_effective_protocol()
    if proto == "gemini-native":
        return _resolve("GEMINI_API_KEY") or None
    return (
        _resolve("IMAGE_GEN_API_KEY")
        or _resolve("OPENAI_API_KEY")
        or None
    )


def get_base_url(protocol=None):
    proto = protocol or get_effective_protocol()
    if proto == "gemini-native":
        url = _resolve("GEMINI_BASE_URL") or _resolve("IMAGE_GEN_GEMINI_BASE_URL")
        return url.rstrip("/") if url else GEMINI_DEFAULT_BASE_URL
    url = _resolve("IMAGE_GEN_BASE_URL") or _resolve("OPENAI_BASE_URL")
    return url.rstrip("/") if url else OPENAI_DEFAULT_BASE_URL


def get_model(protocol=None):
    proto = protocol or get_effective_protocol()
    if proto == "gemini-native":
        m = (
            _resolve("GEMINI_IMAGE_MODEL")
            or _resolve("IMAGE_GEN_GEMINI_MODEL")
        )
        if m:
            return m
        legacy = _resolve("IMAGE_GEN_MODEL")
        if legacy.startswith("gemini-"):
            return legacy
        return GEMINI_DEFAULT_MODEL
    m = (
        _resolve("OPENAI_IMAGE_MODEL")
        or _resolve("IMAGE_GEN_OPENAI_MODEL")
    )
    if m:
        return m
    legacy = _resolve("IMAGE_GEN_MODEL")
    if legacy and not legacy.startswith("gemini-"):
        return legacy
    return OPENAI_DEFAULT_MODEL


def get_size():
    return _resolve("IMAGE_GEN_SIZE") or "1024x1536"


def get_quality():
    return (_resolve("IMAGE_GEN_QUALITY") or "high").lower()


def get_aspect_ratio():
    return (
        _resolve("IMAGE_GEN_ASPECT_RATIO")
        or _resolve("GEMINI_ASPECT_RATIO")
        or "3:4"
    )


def get_gemini_image_size(model=None):
    configured = (
        _resolve("GEMINI_IMAGE_SIZE")
        or _resolve("IMAGE_GEN_GEMINI_IMAGE_SIZE")
        or _resolve("IMAGE_GEN_IMAGE_SIZE")
    )
    if configured:
        return configured
    model_name = model or get_model("gemini-native")
    if model_name.startswith("gemini-3"):
        return "1K"
    return ""


# ── 模板加载 ─────────────────────────────────────────────────────────────────

def load_prompt_template(short=False):
    filename = "image_prompt_short.txt" if short else "image_prompt.txt"
    path = os.path.join(get_prompts_dir(), filename)
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def render_prompt(page_type, page_content, full_outline="", user_topic="", short=False):
    tpl = load_prompt_template(short=short)
    if tpl is None:
        return (
            "生成小红书风格竖版 3:4 图片。\n"
            f"页面类型：{page_type}\n"
            f"页面内容：\n{page_content}"
        )
    return tpl.format(
        page_type=page_type or "内容",
        page_content=page_content or "",
        full_outline=full_outline or "（未提供）",
        user_topic=user_topic or "（未提供）",
    )


# ── --check ──────────────────────────────────────────────────────────────────

def cmd_check():
    proto = get_effective_protocol()
    if not proto:
        print("[image] IMAGE_GEN_PROTOCOL not configured. Choose gemini-native or openai-images first.", file=sys.stderr)
        sys.exit(2)
    key = get_api_key(proto)
    if not key:
        key_hint = "GEMINI_API_KEY" if proto == "gemini-native" else "IMAGE_GEN_API_KEY/OPENAI_API_KEY"
        print(f"[image] API key NOT configured. Use --set-key or export {key_hint}.", file=sys.stderr)
        sys.exit(2)
    if proto not in ("gemini-native", "openai-images"):
        print(f"[image] unsupported protocol: {proto}", file=sys.stderr)
        sys.exit(2)
    tpl_state = "loaded" if load_prompt_template() is not None else "MISSING"
    if proto == "gemini-native":
        detail = f"aspect_ratio={get_aspect_ratio()} image_size={get_gemini_image_size(get_model(proto))}"
    else:
        detail = f"size={get_size()} quality={get_quality()}"
    print(
        f"[image] OK — protocol={proto} model={get_model(proto)} base_url={get_base_url(proto)} "
        f"{detail} template={tpl_state}",
        file=sys.stderr,
    )
    sys.exit(0)


# ── --set-key ────────────────────────────────────────────────────────────────

def _set_env_value(path, key, value):
    lines = []
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()

    found = False
    new_lines = []
    for line in lines:
        if re.match(rf"^{re.escape(key)}\s*=", line.strip()):
            new_lines.append(f"{key}={value}\n")
            found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"{key}={value}\n")

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)


def cmd_set_key(api_key):
    cfg_dir = os.path.join(_skill_dir(), "config")
    os.makedirs(cfg_dir, exist_ok=True)
    env_path = os.path.join(cfg_dir, "runtime.env")
    proto = get_effective_protocol()
    if not proto:
        print("[image] ERROR: set IMAGE_GEN_PROTOCOL=gemini-native or openai-images before --set-key", file=sys.stderr)
        sys.exit(2)
    key_name = "GEMINI_API_KEY" if proto == "gemini-native" else "IMAGE_GEN_API_KEY"
    _set_env_value(env_path, key_name, api_key)
    print(f"[image] API key saved to {env_path} as {key_name}", file=sys.stderr)
    sys.exit(0)


# ── 参考图增强说明（RedInk 4 要素：配色/排版/字体/装饰元素） ────────────────

REF_ENHANCE_HEAD = (
    "请参考提供的参考图视觉风格（包括配色、排版风格、字体风格、装饰元素风格），"
    "生成一张风格一致的新图片。\n\n新图片的内容要求：\n"
)

REF_ENHANCE_TAIL = (
    "\n\n重要：\n"
    "1. 必须保持与参考图相同的视觉风格和设计语言\n"
    "2. 配色方案要与参考图协调一致\n"
    "3. 排版和装饰元素的风格要统一\n"
    "4. 但内容要按照新的要求来生成"
)


# ── OpenAI-compatible images API（gpt-image-2）───────────────────────────────

def _gen_openai_images(prompt, output_path, reference_paths=None):
    api_key = get_api_key("openai-images")
    model = get_model("openai-images")
    payload = {
        "model": model,
        "prompt": prompt,
        "size": get_size(),
        "quality": get_quality(),
        "output_format": "png",
    }
    endpoint = "/v1/images/generations"

    if reference_paths:
        payload["prompt"] = REF_ENHANCE_HEAD + prompt + REF_ENHANCE_TAIL
        payload["image"] = [_ref_input(p) for p in reference_paths]
        endpoint = "/v1/images/edits"
        print(f"[image] reference: {len(reference_paths)} image(s) attached (openai-images)",
              file=sys.stderr)

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    body = _http_post(f"{get_base_url('openai-images')}{endpoint}", payload, headers=headers)
    _save_openai_image(body, output_path)


# ── Gemini native generateContent image API ─────────────────────────────────

def _gemini_part_from_reference(path):
    ref_bytes = _load_reference_image(path)
    mime = _guess_mime(path, ref_bytes)
    return {
        "inline_data": {
            "mime_type": mime,
            "data": base64.b64encode(ref_bytes).decode("ascii"),
        }
    }


def _gen_gemini_native(prompt, output_path, reference_paths=None):
    api_key = get_api_key("gemini-native")
    model = get_model("gemini-native")
    parts = []
    if reference_paths:
        parts.extend(_gemini_part_from_reference(path) for path in reference_paths)
        prompt = REF_ENHANCE_HEAD + prompt + REF_ENHANCE_TAIL
        print(f"[image] reference: {len(reference_paths)} image(s) attached (gemini-native)",
              file=sys.stderr)
    parts.append({"text": prompt})

    generation_config = {
        "responseModalities": ["IMAGE"],
        "imageConfig": {"aspectRatio": get_aspect_ratio()},
    }
    image_size = get_gemini_image_size(model)
    if image_size:
        generation_config["imageConfig"]["imageSize"] = image_size

    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": generation_config,
    }
    headers = {
        "Content-Type": "application/json",
        "x-goog-api-key": api_key,
    }
    endpoint_model = urllib.parse.quote(model, safe="")
    body = _http_post(
        f"{get_base_url('gemini-native')}/models/{endpoint_model}:generateContent",
        payload,
        headers=headers,
    )
    _save_gemini_image(body, output_path)


# ── helpers ──────────────────────────────────────────────────────────────────

def _ref_input(path):
    ref_bytes = _load_reference_image(path)
    mime = _guess_mime(path, ref_bytes)
    b64 = base64.b64encode(ref_bytes).decode("ascii")
    return f"data:{mime};base64,{b64}"


def _guess_mime(path, data):
    mime, _ = mimetypes.guess_type(path)
    if mime and mime.startswith("image/"):
        return mime
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8"):
        return "image/jpeg"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return "image/gif"
    return "image/png"


def _load_reference_image(path, max_kb=200):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) <= max_kb * 1024:
        return data
    try:
        from io import BytesIO
        from PIL import Image

        img = Image.open(BytesIO(data))
        if img.mode in ("RGBA", "LA", "P"):
            img = img.convert("RGB")
        buf = BytesIO()
        for q in range(85, 25, -10):
            buf.seek(0)
            buf.truncate(0)
            img.save(buf, format="JPEG", quality=q, optimize=True)
            if buf.tell() <= max_kb * 1024:
                break
        compressed = buf.getvalue()
        print(f"[image] reference compressed: {len(data)} -> {len(compressed)} bytes",
              file=sys.stderr)
        return compressed
    except ImportError:
        print(f"[image] WARN: Pillow not installed, sending uncompressed reference ({len(data)} bytes)",
              file=sys.stderr)
        return data


def _http_post(url, payload, headers):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"[image] ERROR: HTTP {e.code} — {err_body[:500]}", file=sys.stderr)
        sys.exit(3)
    except urllib.error.URLError as e:
        print(f"[image] ERROR: Network error — {e.reason}", file=sys.stderr)
        sys.exit(3)
    except Exception as e:
        print(f"[image] ERROR: {e}", file=sys.stderr)
        sys.exit(3)


def _save_b64(b64_data, output_path):
    output_dir = os.path.dirname(os.path.abspath(output_path))
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(base64.b64decode(b64_data))
    print(f"[image] saved {os.path.abspath(output_path)} ({os.path.getsize(output_path)} bytes)",
          file=sys.stderr)


def _save_url(url, output_path):
    output_dir = os.path.dirname(os.path.abspath(output_path))
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    try:
        with urllib.request.urlopen(url, timeout=120) as resp:
            with open(output_path, "wb") as f:
                f.write(resp.read())
        print(f"[image] downloaded {os.path.abspath(output_path)}", file=sys.stderr)
    except Exception as e:
        print(f"[image] ERROR downloading {url}: {e}", file=sys.stderr)
        sys.exit(3)


def _fail_with_response(msg, body):
    print(f"[image] ERROR: {msg}", file=sys.stderr)
    snippet = json.dumps(body, ensure_ascii=False)[:500]
    print(f"[image] Response (preview): {snippet}", file=sys.stderr)
    sys.exit(3)


def _save_openai_image(body, output_path):
    data = body.get("data", [])
    if data:
        first = data[0] or {}
        if first.get("b64_json"):
            _save_b64(first["b64_json"], output_path)
            return
        if first.get("url"):
            _save_url(first["url"], output_path)
            return

    text = json.dumps(body, ensure_ascii=False)
    match = re.search(r'"b64_json"\s*:\s*"([^"]+)"', text)
    if match:
        _save_b64(match.group(1), output_path)
        return
    match = re.search(r'"url"\s*:\s*"(https?://[^"]+)"', text)
    if match:
        _save_url(match.group(1), output_path)
        return

    _fail_with_response("响应中未找到图片数据（data[].b64_json / url 均缺失）", body)


def _save_gemini_image(body, output_path):
    for candidate in body.get("candidates", []) or []:
        content = candidate.get("content") or {}
        for part in content.get("parts", []) or []:
            inline_data = part.get("inlineData") or part.get("inline_data")
            if inline_data and inline_data.get("data"):
                _save_b64(inline_data["data"], output_path)
                return

    text = json.dumps(body, ensure_ascii=False)
    match = re.search(r'"(?:inlineData|inline_data)"\s*:\s*\{[^{}]*"data"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"', text)
    if match:
        _save_b64(match.group(1), output_path)
        return

    _fail_with_response("Gemini 响应中未找到图片数据（candidates[].content.parts[].inlineData.data 缺失）", body)


def cmd_generate(prompt, output_path, reference_paths=None):
    proto = get_effective_protocol()
    if not proto:
        print("[image] ERROR: IMAGE_GEN_PROTOCOL is not configured. Choose gemini-native or openai-images first.", file=sys.stderr)
        sys.exit(2)
    api_key = get_api_key(proto)
    if not api_key:
        print("[image] ERROR: API key is not configured.", file=sys.stderr)
        sys.exit(2)
    print(f"[image] protocol={proto} model={get_model(proto)}", file=sys.stderr)
    preview = prompt[:100].replace("\n", " ")
    print(f"[image] prompt={preview}... ({len(prompt)} chars)", file=sys.stderr)
    if proto == "gemini-native":
        _gen_gemini_native(prompt, output_path, reference_paths=reference_paths)
        return
    if proto == "openai-images":
        _gen_openai_images(prompt, output_path, reference_paths=reference_paths)
        return
    else:
        print(f"[image] ERROR: unsupported protocol: {proto}", file=sys.stderr)
        sys.exit(2)


# ── main ─────────────────────────────────────────────────────────────────────

def _read_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    arg = sys.argv[1]
    if arg == "--check":
        cmd_check()
        return
    if arg == "--set-key":
        if len(sys.argv) < 3:
            print("ERROR: --set-key requires KEY argument", file=sys.stderr)
            sys.exit(1)
        cmd_set_key(sys.argv[2])
        return

    page_type = None
    page_content = None
    outline_file = None
    topic = None
    output = None
    references = []
    use_short = False
    positional = []

    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--page-type":
            page_type = sys.argv[i + 1]
            i += 2
        elif a == "--page-content":
            page_content = sys.argv[i + 1]
            i += 2
        elif a == "--outline-file":
            outline_file = sys.argv[i + 1]
            i += 2
        elif a == "--topic":
            topic = sys.argv[i + 1]
            i += 2
        elif a == "--output":
            output = sys.argv[i + 1]
            i += 2
        elif a == "--reference":
            references.append(sys.argv[i + 1])
            i += 2
        elif a == "--short":
            use_short = True
            i += 1
        else:
            positional.append(a)
            i += 1

    # 结构化模式：走中文模板
    if page_type is not None or page_content is not None or output is not None:
        if not output:
            print("ERROR: structured mode requires --output", file=sys.stderr)
            sys.exit(1)
        if not page_content:
            print("ERROR: structured mode requires --page-content", file=sys.stderr)
            sys.exit(1)
        full_outline = ""
        if outline_file and os.path.isfile(outline_file):
            full_outline = _read_file(outline_file)
        prompt = render_prompt(
            page_type=page_type or "内容",
            page_content=page_content,
            full_outline=full_outline,
            user_topic=topic or "",
            short=use_short,
        )
        cmd_generate(prompt, output, reference_paths=references or None)
        return

    # 兼容模式：旧的 image.py <prompt> <output>
    if len(positional) < 2:
        print(
            "ERROR: usage:\n"
            "  structured: image.py --page-type TYPE --page-content TEXT --output PATH "
            "[--outline-file F] [--topic T] [--reference P] [--short]\n"
            "  legacy:     image.py <prompt> <output_path> [--reference path]...",
            file=sys.stderr,
        )
        sys.exit(1)
    cmd_generate(positional[0], positional[1], reference_paths=references or None)


if __name__ == "__main__":
    main()
