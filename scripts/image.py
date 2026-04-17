#!/usr/bin/env python3
"""AI image generation script with multi-protocol support.

支持两种协议（通过 IMAGE_GEN_PROTOCOL 切换）：
  - gemini-native（默认）：Google 官方 / 透明代理 Gemini
      鉴权：?key=xxx
      端点：{BASE_URL}/v1beta/models/{model}:generateContent
  - openai-chat：OpenAI 兼容代理（newapi/oneapi 等）
      鉴权：Authorization: Bearer xxx
      端点：{BASE_URL}/v1/chat/completions
      payload：{messages, modalities:["text","image"]}
      响应：从 message.images 或 message.content 中抓 base64

Usage:
    python3 scripts/image.py --check
    python3 scripts/image.py --set-key "KEY"
    python3 scripts/image.py "prompt" output.png

Exit codes:
    0 - Success
    2 - API key not configured
    3 - Generation failed
"""

import base64
import json
import os
import re
import sys
import urllib.request
import urllib.error


# ── 路径 / 配置加载 ──────────────────────────────────────────────────────────

def _skill_dir():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(script_dir)


def get_data_dir():
    return os.path.join(_skill_dir(), "data")


def get_env_files():
    """按优先级返回配置文件路径列表（先到先得）。"""
    return [
        os.path.join(_skill_dir(), "config", "runtime.env"),
        os.path.join(get_data_dir(), ".env"),
    ]


def load_env():
    """合并所有 env 文件，先出现的优先。"""
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


def get_protocol():
    return (_resolve("IMAGE_GEN_PROTOCOL") or "gemini-native").lower()


def get_base_url():
    url = _resolve("IMAGE_GEN_BASE_URL")
    if url:
        return url.rstrip("/")
    if get_protocol() == "openai-chat":
        return ""
    return "https://generativelanguage.googleapis.com"


def get_model():
    m = _resolve("IMAGE_GEN_MODEL")
    if m:
        return m
    if get_protocol() == "openai-chat":
        return "gemini-2.5-flash-image"
    return "gemini-2.0-flash-preview-image-generation"


# ── --check ──────────────────────────────────────────────────────────────────

def cmd_check():
    key = get_api_key()
    proto = get_protocol()
    if not key:
        print("[image] API key NOT configured. Use --set-key or export IMAGE_GEN_API_KEY.",
              file=sys.stderr)
        sys.exit(2)
    if proto == "openai-chat" and not get_base_url():
        print("[image] openai-chat 模式必须配置 IMAGE_GEN_BASE_URL", file=sys.stderr)
        sys.exit(2)
    print(f"[image] OK — protocol={proto} model={get_model()} base_url={get_base_url() or '(default)'}",
          file=sys.stderr)
    sys.exit(0)


# ── --set-key ────────────────────────────────────────────────────────────────

def cmd_set_key(api_key):
    """写入 config/runtime.env（优先），不存在则创建。"""
    cfg_dir = os.path.join(_skill_dir(), "config")
    os.makedirs(cfg_dir, exist_ok=True)
    env_path = os.path.join(cfg_dir, "runtime.env")

    lines = []
    if os.path.isfile(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

    found = False
    new_lines = []
    for line in lines:
        if re.match(r"^IMAGE_GEN_API_KEY\s*=", line.strip()):
            new_lines.append(f"IMAGE_GEN_API_KEY={api_key}\n")
            found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"IMAGE_GEN_API_KEY={api_key}\n")

    with open(env_path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)
    print(f"[image] API key saved to {env_path}", file=sys.stderr)
    sys.exit(0)


# ── 协议 1: gemini-native ────────────────────────────────────────────────────

def _gen_gemini_native(prompt, output_path):
    api_key = get_api_key()
    base = get_base_url()
    model = get_model()
    url = f"{base}/v1beta/models/{model}:generateContent?key={api_key}"

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }
    body = _http_post(url, payload, headers={"Content-Type": "application/json"})

    candidates = body.get("candidates", [])
    if not candidates:
        _fail_with_response("No candidates in response", body)

    parts = candidates[0].get("content", {}).get("parts", [])
    image_data = None
    for p in parts:
        if "inlineData" in p:
            image_data = p["inlineData"].get("data")
            break
    if not image_data:
        _fail_with_response("No image data in response", body)

    _save_b64(image_data, output_path)


# ── 协议 2: openai-chat ──────────────────────────────────────────────────────

def _gen_openai_chat(prompt, output_path):
    api_key = get_api_key()
    base = get_base_url()
    model = get_model()
    if not base:
        print("[image] ERROR: openai-chat 模式必须配置 IMAGE_GEN_BASE_URL", file=sys.stderr)
        sys.exit(2)

    url = f"{base}/v1/chat/completions"
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
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

    # 1. 优先 message.images（部分代理直接给结构化）
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

    # 2. 从 message.content 里 regex 抓 markdown / data url
    content = msg.get("content", "") or ""
    if isinstance(content, list):
        # 部分代理把 content 拆成 parts 数组
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


def cmd_generate(prompt, output_path):
    api_key = get_api_key()
    if not api_key:
        print("[image] ERROR: API key is not configured.", file=sys.stderr)
        sys.exit(2)
    proto = get_protocol()
    print(f"[image] protocol={proto} model={get_model()}", file=sys.stderr)
    print(f"[image] prompt={prompt[:80]}...", file=sys.stderr)
    if proto == "openai-chat":
        _gen_openai_chat(prompt, output_path)
    else:
        _gen_gemini_native(prompt, output_path)


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    arg = sys.argv[1]
    if arg == "--check":
        cmd_check()
    elif arg == "--set-key":
        if len(sys.argv) < 3:
            print("ERROR: --set-key requires KEY argument", file=sys.stderr)
            sys.exit(1)
        cmd_set_key(sys.argv[2])
    else:
        if len(sys.argv) < 3:
            print("ERROR: usage: image.py <prompt> <output_path>", file=sys.stderr)
            sys.exit(1)
        cmd_generate(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
