#!/usr/bin/env python3
"""
环境预检工具 — 供智能体安装 skill 时调用。
输出 JSON，告诉智能体哪些依赖就绪、哪些需要用户配合。

用法：python3 scripts/preflight.py
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SKILL_DIR / "scripts"
DATA_DIR = SKILL_DIR / "data"
KB_DIR = SKILL_DIR / "knowledge-base"
CONFIG_DIR = SKILL_DIR / "config"
STATE_FILE = CONFIG_DIR / "state.json"
RUNTIME_ENV = CONFIG_DIR / "runtime.env"


def load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except Exception:
            return {}
    return {}


def update_state(**kwargs) -> None:
    state = load_state()
    state.update(kwargs)
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2))


def find_node():
    """优先 PATH，其次 ~/.nvm 常见路径。"""
    node = shutil.which("node")
    if node:
        return node
    nvm_dir = Path.home() / ".nvm" / "versions" / "node"
    if nvm_dir.exists():
        versions = sorted(nvm_dir.iterdir())
        if versions:
            cand = versions[-1] / "bin" / "node"
            if cand.exists():
                return str(cand)
    return None


def check_python():
    return {
        "name": "Python 3",
        "status": "ok",
        "version": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "action": None,
    }


def check_node():
    node = find_node()
    if not node:
        return {
            "name": "Node.js",
            "status": "missing",
            "detail": "截图功能需要 Node.js（已尝试 PATH 与 ~/.nvm 常见路径）",
            "action": "auto_install",
            "install_hint": "brew install node（macOS）或 apt install nodejs（Linux）",
        }
    try:
        ver = subprocess.check_output([node, "-v"], text=True, timeout=5).strip()
    except Exception:
        ver = "unknown"
    return {"name": "Node.js", "status": "ok", "version": ver, "detail": node, "action": None}


def check_sqlite():
    s = shutil.which("sqlite3")
    if not s:
        return {
            "name": "sqlite3",
            "status": "missing",
            "action": "auto_install",
            "install_hint": "brew install sqlite（macOS）或 apt install sqlite3（Linux）",
        }
    return {"name": "sqlite3", "status": "ok", "action": None}


def check_playwright():
    node = find_node()
    if not node:
        return {
            "name": "Playwright",
            "status": "skip",
            "detail": "Node.js 未安装，无法检查 Playwright",
            "action": None,
        }
    env = os.environ.copy()
    env["PATH"] = f"{Path(node).parent}:{env.get('PATH', '')}"
    try:
        result = subprocess.run(
            ["npx", "playwright", "--version"],
            capture_output=True, text=True, timeout=15, env=env,
        )
        if result.returncode == 0:
            return {"name": "Playwright", "status": "ok", "version": result.stdout.strip(), "action": None}
    except Exception:
        pass
    return {
        "name": "Playwright",
        "status": "missing",
        "detail": "HTML 截图功能需要 Playwright",
        "action": "auto_install",
        "install_cmd": "npx playwright install chromium",
    }


def check_mcp():
    """检查 xiaohongshu-mcp 是否可用。已知曾就绪过则放宽：超时不视为失败。"""
    xhs_sh = SCRIPTS_DIR / "xhs.sh"
    if not xhs_sh.exists():
        return {
            "name": "xiaohongshu-mcp",
            "status": "missing",
            "detail": "xhs.sh 脚本未找到",
            "action": "ask_user",
            "ask": "xiaohongshu-mcp 服务未安装。这是小红书操作的核心依赖。\n安装指南见 docs/mcp-setup.md\n安装完成后告诉我，我来验证。",
        }

    state = load_state()
    previously_ok = state.get("mcp_configured") is True

    try:
        result = subprocess.run(
            ["bash", str(xhs_sh), "status"],
            capture_output=True, text=True, timeout=30,
        )
        output = result.stdout + result.stderr
        out_lower = output.lower()
        login_hit = any(kw in out_lower for kw in ("login", "ok", "success", "logged"))
        zh_hit = any(kw in output for kw in ("已登录", "登录成功", "在线"))
        if result.returncode == 0 and (login_hit or zh_hit):
            update_state(mcp_configured=True)
            return {"name": "xiaohongshu-mcp", "status": "ok", "detail": "MCP 服务运行中", "action": None}
        if any(kw in out_lower for kw in ("connect", "refused", "error")):
            return {
                "name": "xiaohongshu-mcp",
                "status": "not_running",
                "detail": "MCP 服务未启动或无法连接",
                "action": "ask_user",
                "ask": "xiaohongshu-mcp 服务未运行。需要先启动 MCP 服务并确保小红书已登录。",
            }
    except subprocess.TimeoutExpired:
        if previously_ok:
            return {"name": "xiaohongshu-mcp", "status": "ok", "detail": "检查超时，按 state 已就绪处理", "action": None}
    except FileNotFoundError:
        pass
    except Exception as e:
        if previously_ok:
            return {"name": "xiaohongshu-mcp", "status": "ok", "detail": f"检查异常 {e}，按 state 已就绪处理", "action": None}
        return {
            "name": "xiaohongshu-mcp",
            "status": "error",
            "detail": str(e),
            "action": "ask_user",
            "ask": "检查 xiaohongshu-mcp 时出错。请确认是否已安装。",
        }

    if previously_ok:
        return {"name": "xiaohongshu-mcp", "status": "ok", "detail": "状态未知，按 state 已就绪处理", "action": None}
    return {
        "name": "xiaohongshu-mcp",
        "status": "unknown",
        "detail": "无法确认 MCP 状态",
        "action": "ask_user",
        "ask": "无法确认 xiaohongshu-mcp 状态。请问 MCP 服务是否已安装并运行？",
    }


def check_image_gen():
    """检查图片生成能力（仅看 config/runtime.env）。"""
    api_key = os.environ.get("IMAGE_GEN_API_KEY", "")

    if not api_key and RUNTIME_ENV.exists():
        for line in RUNTIME_ENV.read_text().splitlines():
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k.strip() == "IMAGE_GEN_API_KEY" and v.strip().strip("'\""):
                api_key = v.strip().strip("'\"")

    if api_key:
        return {"name": "图片生成 API", "status": "ok", "action": None}

    return {
        "name": "图片生成 API",
        "status": "not_configured",
        "detail": "未配置图片生成 API Key（可选，不影响核心功能）",
        "action": "optional",
        "ask": (
            "图片生成 API 未配置。\n"
            "- 不配置：所有图片走 HTML 模板截图（效果也不错）\n"
            "- 配置 OpenAI：高质量 AI 图片（需要 API Key + 费用）\n"
            "- 配置 Gemini：免费额度的 AI 图片（推荐）\n"
            "\n要配置吗？如果要，告诉我你的 API Key 和服务商（openai/gemini）。"
        ),
    }


def check_database():
    """检查数据库状态"""
    db_path = DATA_DIR / "xhs.db"
    if db_path.exists():
        return {"name": "SQLite 数据库", "status": "ok", "detail": str(db_path), "action": None}

    db_sh = SCRIPTS_DIR / "db.sh"
    if db_sh.exists():
        return {
            "name": "SQLite 数据库",
            "status": "not_initialized",
            "action": "auto_fix",
            "fix_cmd": f"bash {db_sh} init",
        }

    return {
        "name": "SQLite 数据库",
        "status": "missing",
        "detail": "db.sh 未找到",
        "action": "ask_user",
        "ask": "数据库初始化脚本未找到，请确认 skill 文件完整。",
    }


def check_profile():
    """检查博主画像"""
    profile = KB_DIR / "profile.json"
    if profile.exists():
        try:
            data = json.loads(profile.read_text())
            niche = data.get("niche", "未设置")
            update_state(profile_created=True)
            return {"name": "博主画像", "status": "ok", "detail": f"领域: {niche}", "action": None}
        except Exception:
            pass
    return {
        "name": "博主画像",
        "status": "not_created",
        "detail": "首次使用时通过对话建立",
        "action": "none_needed",
    }


def run_preflight():
    checks = [
        check_python(),
        check_node(),
        check_sqlite(),
        check_playwright(),
        check_mcp(),
        check_image_gen(),
        check_database(),
        check_profile(),
    ]

    summary = {
        "ok": [],
        "auto_fixable": [],
        "need_user": [],
        "optional": [],
    }

    for c in checks:
        if c["status"] == "ok":
            summary["ok"].append(c["name"])
        elif c.get("action") in ("auto_install", "auto_fix"):
            summary["auto_fixable"].append(c)
        elif c.get("action") == "ask_user":
            summary["need_user"].append(c)
        elif c.get("action") == "optional":
            summary["optional"].append(c)

    ready = len(summary["need_user"]) == 0 and len(summary["auto_fixable"]) == 0

    state = load_state()
    setup_completed = bool(ready and state.get("mcp_configured") and state.get("profile_created"))
    if setup_completed and not state.get("setup_completed"):
        from datetime import date
        update_state(setup_completed=True, setup_date=date.today().isoformat())

    result = {
        "checks": checks,
        "summary": summary,
        "ready": ready,
        "setup_completed": setup_completed,
        "state": load_state(),
    }

    return result


if __name__ == "__main__":
    result = run_preflight()
    print(json.dumps(result, ensure_ascii=False, indent=2))

    print("\n" + "=" * 50, file=sys.stderr)
    s = result["summary"]
    if s["ok"]:
        print(f"✅ 就绪: {', '.join(s['ok'])}", file=sys.stderr)
    if s["auto_fixable"]:
        names = [c["name"] for c in s["auto_fixable"]]
        print(f"🔧 可自动修复: {', '.join(names)}", file=sys.stderr)
    if s["need_user"]:
        names = [c["name"] for c in s["need_user"]]
        print(f"❗ 需要用户配合: {', '.join(names)}", file=sys.stderr)
    if s["optional"]:
        names = [c["name"] for c in s["optional"]]
        print(f"💡 可选配置: {', '.join(names)}", file=sys.stderr)
    print("=" * 50, file=sys.stderr)
    if result["ready"]:
        print("🎉 环境就绪，可以开始使用！", file=sys.stderr)
    else:
        print("⚠️  部分依赖需要处理后才能使用", file=sys.stderr)
