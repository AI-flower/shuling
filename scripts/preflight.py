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
WORKFLOW_DIR = SKILL_DIR / "workflow" / "xhs-automation"
CONFIG_DIR = WORKFLOW_DIR / "config"


def check_python():
    return {
        "name": "Python 3",
        "status": "ok",
        "version": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "action": None,
    }


def check_node():
    node = shutil.which("node")
    if not node:
        return {
            "name": "Node.js",
            "status": "missing",
            "detail": "截图功能需要 Node.js",
            "action": "auto_install",
            "install_hint": "brew install node（macOS）或 apt install nodejs（Linux）",
        }
    try:
        ver = subprocess.check_output([node, "-v"], text=True, timeout=5).strip()
    except Exception:
        ver = "unknown"
    return {"name": "Node.js", "status": "ok", "version": ver, "action": None}


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
    node = shutil.which("node")
    if not node:
        return {
            "name": "Playwright",
            "status": "skip",
            "detail": "Node.js 未安装，无法检查 Playwright",
            "action": None,
        }
    try:
        result = subprocess.run(
            ["npx", "playwright", "--version"],
            capture_output=True, text=True, timeout=15,
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
    """检查 xiaohongshu-mcp 是否可用"""
    xhs_sh = SCRIPTS_DIR / "xhs.sh"
    if not xhs_sh.exists():
        # 也检查 workflow 里的
        xhs_sh_alt = WORKFLOW_DIR / "scripts" / "xhs.sh" if WORKFLOW_DIR.exists() else None
        if not xhs_sh_alt or not xhs_sh_alt.exists():
            return {
                "name": "xiaohongshu-mcp",
                "status": "missing",
                "detail": "xhs.sh 脚本未找到",
                "action": "ask_user",
                "ask": "xiaohongshu-mcp 服务未安装。请参考文档安装后，告诉我 MCP 的地址（默认 http://localhost:18060）",
            }

    # 尝试调 status
    try:
        result = subprocess.run(
            ["bash", str(xhs_sh), "status"],
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout + result.stderr
        if result.returncode == 0 and ("login" in output.lower() or "ok" in output.lower() or "success" in output.lower()):
            return {"name": "xiaohongshu-mcp", "status": "ok", "detail": "MCP 服务运行中", "action": None}
        elif "connect" in output.lower() or "refused" in output.lower() or "error" in output.lower():
            return {
                "name": "xiaohongshu-mcp",
                "status": "not_running",
                "detail": "MCP 服务未启动或无法连接",
                "action": "ask_user",
                "ask": "xiaohongshu-mcp 服务未运行。需要先启动 MCP 服务并确保小红书已登录。请问你已经安装了 xiaohongshu-mcp 吗？",
            }
    except FileNotFoundError:
        pass
    except Exception as e:
        return {
            "name": "xiaohongshu-mcp",
            "status": "error",
            "detail": str(e),
            "action": "ask_user",
            "ask": "检查 xiaohongshu-mcp 时出错。请确认是否已安装。",
        }

    return {
        "name": "xiaohongshu-mcp",
        "status": "unknown",
        "detail": "无法确认 MCP 状态",
        "action": "ask_user",
        "ask": "无法确认 xiaohongshu-mcp 状态。请问 MCP 服务是否已安装并运行？",
    }


def check_telegram():
    """检查 Telegram Bot 配置"""
    # 检查多个可能的配置位置
    token = os.environ.get("XHS_TELEGRAM_BOT_TOKEN", "")
    chat_id = os.environ.get("XHS_TELEGRAM_CHAT_ID", "")

    # 也检查 runtime.env
    if not token or not chat_id:
        env_file = CONFIG_DIR / "runtime.env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                line = line.strip()
                if line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip().strip("'\"" )
                if k == "XHS_TELEGRAM_BOT_TOKEN" and v:
                    token = v
                if k == "XHS_TELEGRAM_CHAT_ID" and v:
                    chat_id = v

    if token and chat_id:
        return {"name": "Telegram Bot", "status": "ok", "action": None}

    missing = []
    if not token:
        missing.append("Bot Token")
    if not chat_id:
        missing.append("Chat ID")

    return {
        "name": "Telegram Bot",
        "status": "not_configured",
        "detail": f"缺少: {', '.join(missing)}",
        "action": "ask_user",
        "ask": (
            "Telegram Bot 未配置。这是用来接收选题推送、审图、日报的。\n"
            "配置方法：\n"
            "1. 在 Telegram 中搜索 @BotFather，发送 /newbot 创建一个 Bot\n"
            "2. 记下返回的 Bot Token（格式：123456:ABC-DEF...）\n"
            "3. 向你新创建的 Bot 发一条消息\n"
            "4. 打开 https://api.telegram.org/bot<你的Token>/getUpdates 找到 chat.id\n"
            "\n请告诉我你的 Bot Token 和 Chat ID，我来帮你写入配置。"
        ),
    }


def check_image_gen():
    """检查图片生成能力"""
    api_key = os.environ.get("IMAGE_GEN_API_KEY", "")

    # 检查 runtime.env
    if not api_key:
        env_file = CONFIG_DIR / "runtime.env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                line = line.strip()
                if line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() == "IMAGE_GEN_API_KEY" and v.strip().strip("'\"" ):
                    api_key = v.strip().strip("'\"" )

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
            "\n要配置吗？如果要，告诉我你的 API Key 和选择的服务商（openai/gemini）。"
        ),
    }


def check_database():
    """检查数据库状态"""
    db_path = DATA_DIR / "xhs.db"
    if db_path.exists():
        return {"name": "SQLite 数据库", "status": "ok", "detail": str(db_path), "action": None}

    # 尝试初始化
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
        check_telegram(),
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
        # skip / none_needed → ignore

    result = {
        "checks": checks,
        "summary": summary,
        "ready": len(summary["need_user"]) == 0 and len(summary["auto_fixable"]) == 0,
    }

    return result


if __name__ == "__main__":
    result = run_preflight()
    print(json.dumps(result, ensure_ascii=False, indent=2))

    # 人类友好的摘要
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
