#!/usr/bin/env python3
"""AI image generation script with multi-provider support + 中文模板.

支持三种协议（通过 IMAGE_GEN_PROTOCOL 切换）：
  - gemini-native（默认）：Google 官方 / 透明代理 Gemini 3 Pro
  - openai-images：OpenAI 官方 /v1/images/generations + /v1/images/edits（gpt-image-2）
  - openai-chat：OpenAI 兼容代理（newapi/oneapi 等）走 chat completion

支持两种 CLI 模式：
  - 结构化模式（推荐，RedInk 范式）：加载 agent/prompts/image_prompt.txt 中文模板
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
    python3 agent/scripts/image.py --check
    python3 agent/scripts/image.py --set-key "KEY" [--provider gemini|openai|openai-chat]

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
import secrets
import sys
import urllib.request
import urllib.error


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


def get_api_key():
    return _resolve("IMAGE_GEN_API_KEY") or None


# Provider 别名映射（让用户写 --provider gemini / openai 也能识别）
_PROVIDER_ALIAS = {
    "gemini": "gemini-native",
    "google": "gemini-native",
    "gemini-native": "gemini-native",
    "openai": "openai-images",
    "openai-images": "openai-images",
    "openai-chat": "openai-chat",
    "chat": "openai-chat",
}


def normalize_protocol(value):
    """把用户输入归一到三个标准协议名之一。未识别值原样返回（让 check 报错）。"""
    return _PROVIDER_ALIAS.get((value or "").strip().lower(), value)


def get_protocol():
    raw = _resolve("IMAGE_GEN_PROTOCOL") or "gemini-native"
    return normalize_protocol(raw).lower()


def get_base_url():
    url = _resolve("IMAGE_GEN_BASE_URL")
    if url:
        return url.rstrip("/")
    proto = get_protocol()
    if proto == "openai-images":
        return "https://api.openai.com"
    if proto == "openai-chat":
        return ""  # 必须用户配置
    return "https://generativelanguage.googleapis.com"


def get_model():
    m = _resolve("IMAGE_GEN_MODEL")
    if m:
        return m
    proto = get_protocol()
    if proto == "openai-images":
        return "gpt-image-2"
    if proto == "openai-chat":
        return ""  # 必须用户配置
    return "gemini-3-pro-image-preview"


def get_image_size():
    """竖版 3:4 默认；可通过 IMAGE_GEN_SIZE 覆盖（仅 openai-images 用到）"""
    return _resolve("IMAGE_GEN_SIZE") or "1024x1536"


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
    key = get_api_key()
    proto = get_protocol()
    if not key:
        print("[image] API key NOT configured. Use --set-key or export IMAGE_GEN_API_KEY.",
              file=sys.stderr)
        sys.exit(2)
    if proto not in ("gemini-native", "openai-images", "openai-chat"):
        print(f"[image] Unknown protocol: {proto!r} (expected gemini-native / openai-images / openai-chat)",
              file=sys.stderr)
        sys.exit(2)
    if proto == "openai-chat" and not get_base_url():
        print("[image] openai-chat 模式必须配置 IMAGE_GEN_BASE_URL", file=sys.stderr)
        sys.exit(2)
    tpl_state = "loaded" if load_prompt_template() is not None else "MISSING"
    base_url = get_base_url() or "(default)"
    print(
        f"[image] OK — protocol={proto} model={get_model()} base_url={base_url} template={tpl_state}",
        file=sys.stderr,
    )
    sys.exit(0)


# ── --set-key（可选 --provider）──────────────────────────────────────────────

def cmd_set_key(api_key, provider=None):
    cfg_dir = os.path.join(_skill_dir(), "config")
    os.makedirs(cfg_dir, exist_ok=True)
    env_path = os.path.join(cfg_dir, "runtime.env")

    lines = []
    if os.path.isfile(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

    # 计算要写入的 KV 对（按 provider 决定）
    target_proto = normalize_protocol(provider) if provider else None
    target_model = None
    if target_proto == "gemini-native":
        target_model = "gemini-3-pro-image-preview"
    elif target_proto == "openai-images":
        target_model = "gpt-image-2"
    # openai-chat 不写默认模型（用户需自配）

    updates = {"IMAGE_GEN_API_KEY": api_key}
    if target_proto:
        updates["IMAGE_GEN_PROTOCOL"] = target_proto
    if target_model:
        updates["IMAGE_GEN_MODEL"] = target_model

    # 切到 openai-chat 时，旧的 IMAGE_GEN_MODEL（前次 provider 的默认值）必须清除，
    # 否则会把 gpt-image-2 / gemini-3-pro-image-preview 错误地传给代理。
    keys_to_remove = set()
    if target_proto == "openai-chat":
        keys_to_remove.add("IMAGE_GEN_MODEL")

    new_lines = []
    seen = set()
    for line in lines:
        stripped = line.strip()
        matched = False
        # 先看是否要删
        for kr in keys_to_remove:
            if re.match(rf"^{re.escape(kr)}\s*=", stripped):
                # 删除（不写入 new_lines）
                matched = True
                break
        if matched:
            continue
        # 再看是否要替换
        for k in updates:
            if re.match(rf"^{re.escape(k)}\s*=", stripped):
                new_lines.append(f"{k}={updates[k]}\n")
                seen.add(k)
                matched = True
                break
        if not matched:
            new_lines.append(line)

    for k, v in updates.items():
        if k not in seen:
            if new_lines and not new_lines[-1].endswith("\n"):
                new_lines.append("\n")
            new_lines.append(f"{k}={v}\n")

    with open(env_path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    if target_proto:
        print(f"[image] saved to {env_path} (provider={target_proto}, model={target_model or '(default)'})",
              file=sys.stderr)
    else:
        print(f"[image] API key saved to {env_path} (provider unchanged)", file=sys.stderr)
    sys.exit(0)


# ── 参考图增强说明（RedInk 4 要素：配色/排版/字体/装饰元素） ────────────────

REF_ENHANCE_HEAD = (
    "请参考上面这张图片的视觉风格（包括配色、排版风格、字体风格、装饰元素风格），"
    "生成一张风格一致的新图片。\n\n新图片的内容要求：\n"
)

REF_ENHANCE_TAIL = (
    "\n\n重要：\n"
    "1. 必须保持与参考图相同的视觉风格和设计语言\n"
    "2. 配色方案要与参考图协调一致\n"
    "3. 排版和装饰元素的风格要统一\n"
    "4. 但内容要按照新的要求来生成"
)


# ── 协议 1: gemini-native（REST，含参考图支持） ──────────────────────────────

def _gen_gemini_native(prompt, output_path, reference_paths=None):
    api_key = get_api_key()
    base = get_base_url()
    model = get_model()
    url = f"{base}/v1beta/models/{model}:generateContent?key={api_key}"

    parts = []
    if reference_paths:
        ref_bytes = _load_reference_image(reference_paths[0])
        ref_b64 = base64.b64encode(ref_bytes).decode("ascii")
        parts.append({
            "inlineData": {
                "mimeType": "image/png",
                "data": ref_b64,
            }
        })
        enhanced = REF_ENHANCE_HEAD + prompt + REF_ENHANCE_TAIL
        parts.append({"text": enhanced})
        print("[image] reference: 1 image attached (gemini-native)", file=sys.stderr)
    else:
        parts.append({"text": prompt})

    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "temperature": 1.0,
            "topP": 0.95,
            "responseModalities": ["IMAGE"],
        },
    }
    body = _http_post(url, payload, headers={"Content-Type": "application/json"})

    candidates = body.get("candidates", [])
    if not candidates:
        _fail_with_response("No candidates in response", body)

    out_parts = candidates[0].get("content", {}).get("parts", [])
    image_data = None
    for p in out_parts:
        if "inlineData" in p:
            image_data = p["inlineData"].get("data")
            break
        if "inline_data" in p:
            image_data = p["inline_data"].get("data")
            break
    if not image_data:
        _fail_with_response("No image data in response", body)

    _save_b64(image_data, output_path)


# ── 协议 2: openai-images（gpt-image-2 / dall-e-3）──────────────────────────

def _gen_openai_images(prompt, output_path, reference_paths=None):
    """OpenAI 官方图像生成接口。
    无参考图：POST /v1/images/generations（JSON body）
    有参考图：POST /v1/images/edits（multipart/form-data）
    """
    if reference_paths:
        return _gen_openai_images_edit(prompt, output_path, reference_paths)
    return _gen_openai_images_create(prompt, output_path)


def _gen_openai_images_create(prompt, output_path):
    api_key = get_api_key()
    base = get_base_url()
    model = get_model()
    url = f"{base}/v1/images/generations"

    payload = {
        "model": model,
        "prompt": prompt,
        "size": get_image_size(),
        "n": 1,
        # gpt-image-2 默认返回 b64_json；dall-e-3 也支持
        "response_format": "b64_json",
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    body = _http_post(url, payload, headers=headers)

    data = body.get("data", [])
    if not data:
        _fail_with_response("No data in response", body)

    first = data[0]
    if "b64_json" in first and first["b64_json"]:
        _save_b64(first["b64_json"], output_path)
        return
    if "url" in first and first["url"]:
        _save_url(first["url"], output_path)
        return
    _fail_with_response("No image data in OpenAI response", body)


def _gen_openai_images_edit(prompt, output_path, reference_paths):
    """gpt-image-2 image-to-image：/v1/images/edits multipart."""
    api_key = get_api_key()
    base = get_base_url()
    model = get_model()
    url = f"{base}/v1/images/edits"

    enhanced = REF_ENHANCE_HEAD + prompt + REF_ENHANCE_TAIL

    fields = {
        "model": model,
        "prompt": enhanced,
        "size": get_image_size(),
        "n": "1",
        "response_format": "b64_json",
    }
    files = []
    for i, p in enumerate(reference_paths):
        fields_name = "image[]" if len(reference_paths) > 1 else "image"
        files.append((fields_name, p))

    body_bytes, boundary = _build_multipart(fields, files)
    print(f"[image] reference: {len(reference_paths)} image(s) attached (openai-images edit)",
          file=sys.stderr)

    headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Authorization": f"Bearer {api_key}",
        "Content-Length": str(len(body_bytes)),
    }
    body = _http_post_raw(url, body_bytes, headers=headers)

    data = body.get("data", [])
    if not data:
        _fail_with_response("No data in OpenAI edits response", body)

    first = data[0]
    if "b64_json" in first and first["b64_json"]:
        _save_b64(first["b64_json"], output_path)
        return
    if "url" in first and first["url"]:
        _save_url(first["url"], output_path)
        return
    _fail_with_response("No image data in OpenAI edits response", body)


# ── 协议 3: openai-chat（兼容代理） ──────────────────────────────────────────

def _gen_openai_chat(prompt, output_path, reference_paths=None):
    api_key = get_api_key()
    base = get_base_url()
    model = get_model()
    if not base:
        print("[image] ERROR: openai-chat 模式必须配置 IMAGE_GEN_BASE_URL", file=sys.stderr)
        sys.exit(2)

    user_content = prompt
    if reference_paths:
        ref_bytes_list = [_load_reference_image(p) for p in reference_paths]
        n = len(ref_bytes_list)
        enhanced = (
            f"请参考提供的 {n} 张图片的视觉风格（配色、排版风格、字体风格、装饰元素风格），生成一张风格一致的新图片。\n"
            f"\n新图片的内容要求：{prompt}\n"
            "\n重要：\n"
            "1. 必须保持与参考图相同的视觉风格和设计语言\n"
            "2. 配色方案要与参考图协调一致\n"
            "3. 排版和装饰元素的风格要统一\n"
            "4. 但内容要按照新的要求来生成"
        )
        content_parts = [{"type": "text", "text": enhanced}]
        for ref_bytes in ref_bytes_list:
            b64 = base64.b64encode(ref_bytes).decode("ascii")
            content_parts.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{b64}"},
            })
        user_content = content_parts
        print(f"[image] reference: {n} image(s) attached (openai-chat)", file=sys.stderr)

    url = f"{base}/v1/chat/completions"
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": user_content}],
        "modalities": ["text", "image"],
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    body = _http_post(url, payload, headers=headers)

    choices = body.get("choices", [])
    if not choices:
        _fail_with_response("No choices in response", body)
    msg = choices[0].get("message", {}) or {}

    if "images" in msg and msg["images"]:
        first = msg["images"][0]
        url_or_data = (first.get("image_url") or {}).get("url") or first.get("url") or ""
        if url_or_data:
            if url_or_data.startswith("data:"):
                m = re.match(r"data:image/[a-z+]+;base64,(.+)", url_or_data)
                if m:
                    _save_b64(m.group(1), output_path)
                    return
            elif url_or_data.startswith("http"):
                _save_url(url_or_data, output_path)
                return

    content = msg.get("content", "") or ""
    if isinstance(content, list):
        for p in content:
            if isinstance(p, dict):
                if p.get("type") == "image_url":
                    iu = (p.get("image_url") or {}).get("url", "")
                    if iu.startswith("data:"):
                        m = re.match(r"data:image/[a-z+]+;base64,(.+)", iu)
                        if m:
                            _save_b64(m.group(1), output_path)
                            return
                    elif iu.startswith("http"):
                        _save_url(iu, output_path)
                        return
        content = json.dumps(content, ensure_ascii=False)

    m = re.search(r"data:image/[a-z+]+;base64,([A-Za-z0-9+/=\s]+?)(?:[)\s\"]|$)", content)
    if m:
        b64 = re.sub(r"\s+", "", m.group(1))
        _save_b64(b64, output_path)
        return

    m = re.search(r"!\[[^\]]*\]\((https?://[^)]+)\)", content)
    if m:
        _save_url(m.group(1), output_path)
        return

    _fail_with_response("响应中未找到图片数据（content 内无 data:image 或 http URL）", body)


# ── helpers ──────────────────────────────────────────────────────────────────

def _build_multipart(fields, files):
    """Build multipart/form-data body with stdlib only.
    fields: dict of {name: str_value}
    files:  list of (field_name, file_path) tuples
    returns: (body_bytes, boundary_str)
    """
    boundary = "----shulingboundary" + secrets.token_hex(16)
    body = b""
    for k, v in fields.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{k}"\r\n\r\n'.encode()
        body += str(v).encode("utf-8") + b"\r\n"
    for fieldname, filepath in files:
        with open(filepath, "rb") as f:
            data = f.read()
        ctype, _ = mimetypes.guess_type(filepath)
        if not ctype:
            ctype = "image/png"
        fname = os.path.basename(filepath)
        body += f"--{boundary}\r\n".encode()
        body += (f'Content-Disposition: form-data; name="{fieldname}"; '
                 f'filename="{fname}"\r\n').encode()
        body += f"Content-Type: {ctype}\r\n\r\n".encode()
        body += data + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return body, boundary


def _load_reference_image(path, max_kb=200):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) <= max_kb * 1024:
        return data
    try:
        from PIL import Image
        from io import BytesIO
        img = Image.open(BytesIO(data))
        if img.mode in ("RGBA", "LA", "P"):
            img = img.convert("RGB")
        buf = BytesIO()
        for q in range(85, 25, -10):
            buf.seek(0); buf.truncate(0)
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
    return _http_post_raw(url, data, headers=headers)


def _http_post_raw(url, raw_body, headers):
    req = urllib.request.Request(url, data=raw_body, headers=headers, method="POST")
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


def cmd_generate(prompt, output_path, reference_paths=None):
    api_key = get_api_key()
    if not api_key:
        print("[image] ERROR: API key is not configured.", file=sys.stderr)
        sys.exit(2)
    proto = get_protocol()
    print(f"[image] protocol={proto} model={get_model()}", file=sys.stderr)
    preview = prompt[:100].replace("\n", " ")
    print(f"[image] prompt={preview}... ({len(prompt)} chars)", file=sys.stderr)
    if proto == "openai-images":
        _gen_openai_images(prompt, output_path, reference_paths=reference_paths)
    elif proto == "openai-chat":
        _gen_openai_chat(prompt, output_path, reference_paths=reference_paths)
    elif proto == "gemini-native":
        _gen_gemini_native(prompt, output_path, reference_paths=reference_paths)
    else:
        print(f"[image] ERROR: unknown protocol {proto!r}", file=sys.stderr)
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
        api_key = sys.argv[2]
        provider = None
        # 解析可选 --provider
        if len(sys.argv) >= 5 and sys.argv[3] == "--provider":
            provider = sys.argv[4]
        cmd_set_key(api_key, provider=provider)
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
            page_type = sys.argv[i + 1]; i += 2
        elif a == "--page-content":
            page_content = sys.argv[i + 1]; i += 2
        elif a == "--outline-file":
            outline_file = sys.argv[i + 1]; i += 2
        elif a == "--topic":
            topic = sys.argv[i + 1]; i += 2
        elif a == "--output":
            output = sys.argv[i + 1]; i += 2
        elif a == "--reference":
            references.append(sys.argv[i + 1]); i += 2
        elif a == "--short":
            use_short = True; i += 1
        else:
            positional.append(a); i += 1

    # 结构化模式：走中文模板
    if page_type is not None or page_content is not None or output is not None:
        if not output:
            print("ERROR: structured mode requires --output", file=sys.stderr); sys.exit(1)
        if not page_content:
            print("ERROR: structured mode requires --page-content", file=sys.stderr); sys.exit(1)
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
