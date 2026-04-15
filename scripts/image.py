#!/usr/bin/env python3
"""Gemini AI image generation script.

Usage:
    python3 scripts/image.py --check              Check if API key is configured
    python3 scripts/image.py --set-key "KEY"       Save API key to data/.env
    python3 scripts/image.py "prompt" output.png   Generate image from prompt

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


def get_data_dir():
    """Return the absolute path to the data/ directory (script/../data/)."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(script_dir), "data")


def get_env_file():
    """Return the absolute path to data/.env."""
    return os.path.join(get_data_dir(), ".env")


def load_env_file():
    """Load key=value pairs from data/.env into a dict."""
    env_path = get_env_file()
    env_vars = {}
    if os.path.isfile(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, value = line.partition("=")
                    env_vars[key.strip()] = value.strip()
    return env_vars


def get_api_key():
    """Resolve API key with priority: env var > data/.env file."""
    key = os.environ.get("IMAGE_GEN_API_KEY", "").strip()
    if key:
        return key
    env_vars = load_env_file()
    return env_vars.get("IMAGE_GEN_API_KEY", "").strip() or None


def get_model():
    """Resolve model name with priority: env var > default."""
    model = os.environ.get("IMAGE_GEN_MODEL", "").strip()
    return model or "gemini-2.0-flash-preview-image-generation"


# ── --check ──────────────────────────────────────────────────────────────────

def cmd_check():
    """Check whether an API key is configured. Exit 0 or 2."""
    key = get_api_key()
    if key:
        print("[image] API key is configured.", file=sys.stderr)
        sys.exit(0)
    else:
        print("[image] API key is NOT configured. "
              "Use --set-key or export IMAGE_GEN_API_KEY.", file=sys.stderr)
        sys.exit(2)


# ── --set-key ────────────────────────────────────────────────────────────────

def cmd_set_key(api_key):
    """Write the API key into data/.env."""
    data_dir = get_data_dir()
    os.makedirs(data_dir, exist_ok=True)
    env_path = get_env_file()

    lines = []
    if os.path.isfile(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

    # Update or append IMAGE_GEN_API_KEY
    key_found = False
    provider_found = False
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if re.match(r"^IMAGE_GEN_API_KEY\s*=", stripped):
            new_lines.append(f"IMAGE_GEN_API_KEY={api_key}\n")
            key_found = True
        elif re.match(r"^IMAGE_GEN_PROVIDER\s*=", stripped):
            new_lines.append("IMAGE_GEN_PROVIDER=gemini\n")
            provider_found = True
        else:
            new_lines.append(line)

    if not key_found:
        new_lines.append(f"IMAGE_GEN_API_KEY={api_key}\n")
    if not provider_found:
        new_lines.append("IMAGE_GEN_PROVIDER=gemini\n")

    with open(env_path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    print(f"[image] API key saved to {env_path}", file=sys.stderr)
    sys.exit(0)


# ── generate ─────────────────────────────────────────────────────────────────

def cmd_generate(prompt, output_path):
    """Call Gemini API and save the generated image."""
    api_key = get_api_key()
    if not api_key:
        print("[image] ERROR: API key is not configured. "
              "Use --set-key or export IMAGE_GEN_API_KEY.", file=sys.stderr)
        sys.exit(2)

    model = get_model()
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={api_key}"
    )

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    print(f"[image] Generating image with model: {model}", file=sys.stderr)
    print(f"[image] Prompt: {prompt}", file=sys.stderr)

    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"[image] ERROR: HTTP {e.code} — {err_body}", file=sys.stderr)
        sys.exit(3)
    except urllib.error.URLError as e:
        print(f"[image] ERROR: Network error — {e.reason}", file=sys.stderr)
        sys.exit(3)
    except Exception as e:
        print(f"[image] ERROR: {e}", file=sys.stderr)
        sys.exit(3)

    # Extract base64 image data from response
    try:
        candidates = body.get("candidates", [])
        if not candidates:
            print("[image] ERROR: No candidates in response.", file=sys.stderr)
            print(f"[image] Response: {json.dumps(body, indent=2)}", file=sys.stderr)
            sys.exit(3)

        parts = candidates[0].get("content", {}).get("parts", [])
        image_data = None
        for part in parts:
            if "inlineData" in part:
                image_data = part["inlineData"].get("data")
                break

        if not image_data:
            print("[image] ERROR: No image data in response.", file=sys.stderr)
            print(f"[image] Response: {json.dumps(body, indent=2)}", file=sys.stderr)
            sys.exit(3)
    except (KeyError, IndexError, TypeError) as e:
        print(f"[image] ERROR: Failed to parse response — {e}", file=sys.stderr)
        print(f"[image] Response: {json.dumps(body, indent=2)}", file=sys.stderr)
        sys.exit(3)

    # Ensure output directory exists
    output_dir = os.path.dirname(os.path.abspath(output_path))
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    # Write image file
    with open(output_path, "wb") as f:
        f.write(base64.b64decode(image_data))

    abs_path = os.path.abspath(output_path)
    print(f"[image] Image saved to {abs_path}", file=sys.stderr)
    # stdout: only the file path for programmatic consumption
    print(abs_path)
    sys.exit(0)


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]

    if not args:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(1)

    if args[0] == "--check":
        cmd_check()
    elif args[0] == "--set-key":
        if len(args) < 2:
            print("[image] ERROR: --set-key requires an API key argument.",
                  file=sys.stderr)
            sys.exit(1)
        cmd_set_key(args[1])
    else:
        if len(args) < 2:
            print("[image] ERROR: Usage: image.py \"prompt\" /output/path.png",
                  file=sys.stderr)
            sys.exit(1)
        cmd_generate(args[0], args[1])


if __name__ == "__main__":
    main()
