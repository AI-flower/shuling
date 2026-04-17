#!/usr/bin/env python3
"""Gemini AI 图片生成脚本（供 Hermes Bot 直接调用）

用法:
    python3 gemini-generate-image.py <prompt> <output_path>
    python3 gemini-generate-image.py --check   # 仅检查 API Key 是否已配置

退出码:
    0 = 成功
    2 = API Key 未配置（需要用户提供）
    3 = 生成失败
"""
import base64
import json
import os
import sys
import urllib.request
import urllib.error

def load_runtime_env():
    env_path = os.path.expanduser("~/xhs-automation/config/runtime.env")
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, val = line.partition("=")
                    os.environ.setdefault(key.strip(), val.strip())

def check_api_key():
    """检查 Gemini API Key，未配置时打印提示并退出"""
    load_runtime_env()
    api_key = os.environ.get("IMAGE_GEN_API_KEY", "").strip()
    provider = os.environ.get("IMAGE_GEN_PROVIDER", "gemini").strip().lower()

    if provider != "gemini":
        print(f"当前 IMAGE_GEN_PROVIDER={provider}，已强制切换为 gemini")

    if not api_key:
        print("ERROR: 需要 Gemini API Key 才能生成图片！")
        print("")
        print("请向用户索要 Gemini API Key：")
        print("  获取地址: https://aistudio.google.com/api-keys")
        print("  （免费额度即可使用）")
        print("")
        print("拿到 Key 后，运行以下命令配置：")
        print("  sed -i '' 's|^IMAGE_GEN_API_KEY=.*|IMAGE_GEN_API_KEY=用户提供的Key|' ~/xhs-automation/config/runtime.env")
        sys.exit(2)

    print(f"Gemini API Key 已配置 ({api_key[:8]}...)")
    return api_key

def generate_image(prompt, output_path):
    """调用 Gemini API 生成图片"""
    api_key = check_api_key()
    model = os.environ.get("IMAGE_GEN_MODEL", "gemini-2.0-flash-preview-image-generation")

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"

    payload = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})

    print(f"正在调用 Gemini 生成图片...")
    print(f"  模型: {model}")
    print(f"  Prompt: {prompt[:80]}...")

    try:
        resp = urllib.request.urlopen(req, timeout=180)
        data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:500]
        print(f"Gemini API 错误 {e.code}: {body}", file=sys.stderr)
        sys.exit(3)
    except Exception as e:
        print(f"请求失败: {e}", file=sys.stderr)
        sys.exit(3)

    # 检查 block
    if "error" in data:
        print(f"Gemini 错误: {data['error'].get('message', str(data['error']))}", file=sys.stderr)
        sys.exit(3)

    candidates = data.get("candidates", [])
    if not candidates:
        feedback = data.get("promptFeedback", {})
        reason = feedback.get("blockReason", "")
        if reason:
            print(f"Gemini 拒绝生成: {reason}", file=sys.stderr)
        else:
            print(f"Gemini 返回空结果: {json.dumps(data)[:300]}", file=sys.stderr)
        sys.exit(3)

    parts = candidates[0].get("content", {}).get("parts", [])
    for part in parts:
        inline = part.get("inlineData")
        if inline and inline.get("data"):
            img_bytes = base64.b64decode(inline["data"])
            os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
            with open(output_path, "wb") as f:
                f.write(img_bytes)
            print(f"成功: {len(img_bytes)} bytes -> {output_path}")
            return output_path

    print(f"响应中无图片数据: {json.dumps(parts)[:200]}", file=sys.stderr)
    sys.exit(3)

def set_api_key(key):
    """将用户提供的 API Key 写入 runtime.env"""
    env_path = os.path.expanduser("~/xhs-automation/config/runtime.env")
    if not os.path.exists(env_path):
        print(f"配置文件不存在: {env_path}", file=sys.stderr)
        sys.exit(1)

    with open(env_path, "r") as f:
        content = f.read()

    # 替换或追加
    if "IMAGE_GEN_API_KEY=" in content:
        lines = content.split("\n")
        new_lines = []
        for line in lines:
            if line.strip().startswith("IMAGE_GEN_API_KEY="):
                new_lines.append(f"IMAGE_GEN_API_KEY={key}")
            else:
                new_lines.append(line)
        content = "\n".join(new_lines)
    else:
        content += f"\nIMAGE_GEN_API_KEY={key}\n"

    # 确保 provider 是 gemini
    if "IMAGE_GEN_PROVIDER=" in content:
        lines = content.split("\n")
        new_lines = []
        for line in lines:
            if line.strip().startswith("IMAGE_GEN_PROVIDER="):
                new_lines.append("IMAGE_GEN_PROVIDER=gemini")
            else:
                new_lines.append(line)
        content = "\n".join(new_lines)

    with open(env_path, "w") as f:
        f.write(content)

    print(f"已配置 Gemini API Key 到 {env_path}")
    print(f"  IMAGE_GEN_PROVIDER=gemini")
    print(f"  IMAGE_GEN_API_KEY={key[:8]}...")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法:")
        print("  python3 gemini-generate-image.py <prompt> <output_path>   # 生成图片")
        print("  python3 gemini-generate-image.py --check                  # 检查 API Key")
        print("  python3 gemini-generate-image.py --set-key <API_KEY>      # 配置 API Key")
        sys.exit(1)

    if sys.argv[1] == "--check":
        check_api_key()
    elif sys.argv[1] == "--set-key":
        if len(sys.argv) < 3:
            print("用法: python3 gemini-generate-image.py --set-key <API_KEY>")
            sys.exit(1)
        set_api_key(sys.argv[2])
    else:
        if len(sys.argv) < 3:
            print("用法: python3 gemini-generate-image.py <prompt> <output_path>")
            sys.exit(1)
        generate_image(sys.argv[1], sys.argv[2])
