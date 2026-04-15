"""统一 LLM 调用接口 - 根据 runtime.env 中的 LLM_PROVIDER 路由。"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import config_loader

config_loader.load_runtime_env()


def call_llm(prompt, system=None, max_tokens=4096):
    """调用配置的 LLM，返回文本响应。失败返回 None。"""
    provider = os.environ.get("LLM_PROVIDER", "claude")
    api_key = os.environ.get("LLM_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN", "")
    base_url = os.environ.get("LLM_BASE_URL") or None
    model = os.environ.get("LLM_MODEL", "claude-sonnet-4-20250514")

    if not api_key:
        print("LLM_API_KEY 未配置，跳过 LLM 调用", file=sys.stderr)
        return None

    try:
        if provider == "claude":
            return _call_anthropic(prompt, system, max_tokens, api_key, base_url, model)
        else:
            return _call_openai(prompt, system, max_tokens, api_key, base_url, model)
    except Exception as e:
        print(f"LLM 调用失败 ({provider}): {e}", file=sys.stderr)
        return None


def _call_anthropic(prompt, system, max_tokens, api_key, base_url, model):
    from anthropic import Anthropic
    client = Anthropic(api_key=api_key, base_url=base_url) if base_url else Anthropic(api_key=api_key)
    kwargs = {"model": model, "max_tokens": max_tokens, "messages": [{"role": "user", "content": prompt}]}
    if system:
        kwargs["system"] = system
    resp = client.messages.create(**kwargs)
    return resp.content[0].text


def _call_openai(prompt, system, max_tokens, api_key, base_url, model):
    from openai import OpenAI
    client = OpenAI(api_key=api_key, base_url=base_url) if base_url else OpenAI(api_key=api_key)
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    resp = client.chat.completions.create(model=model, max_tokens=max_tokens, messages=messages)
    return resp.choices[0].message.content
