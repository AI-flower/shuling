#!/usr/bin/env python3
"""
环境预检工具 — 供智能体安装 skill 时调用，也可给人看。

默认：stdout 输出 JSON（智能体用），stderr 输出简要中文摘要。
--human：只输出彩色表格 + 修复建议（人类自检用，不打 JSON）。
--json：只输出 JSON，无 stderr 噪声（脚本管道用）。

退出码：
  0  环境就绪（ready=True）
  1  只差可自动修复项（auto_fixable）
  2  存在需用户配合项（ask_user）

用法：
  python3 scripts/preflight.py             # 默认混合输出
  python3 scripts/preflight.py --human     # 人类彩色自检
  python3 scripts/preflight.py --json      # 纯 JSON（管道/CI 用）
"""
import argparse
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


def check_mcp():
    """检查 xiaohongshu-mcp 是否可用。

    v2.4.1+ 严格判据（修正历史误判）：
    - xhs.sh status 底层调 MCP check_login_status。
    - **否定信号**（error/refused/未登录/401/503 等）优先判失败，
      不因 returncode==0 或 state.mcp_configured=True 被掩盖。
    - **肯定信号**必须明确：`"logged_in": true` / `"success": true` /
      `"status": "ok"` / 中文「已登录/登录成功/在线」。
    - 超时 / 异常 / returncode!=0 / 无法匹配 → not_running；
      state.mcp_configured 不再改变判定，只用于错误消息里的措辞。
    """
    xhs_sh = SCRIPTS_DIR / "xhs.sh"
    if not xhs_sh.exists():
        return {
            "name": "xiaohongshu-mcp",
            "status": "missing",
            "detail": "xhs.sh 脚本未找到",
            "action": "ask_user",
            "ask": "xiaohongshu-mcp 服务未安装。这是小红书操作的核心依赖。\n安装指南见 docs/runbooks/mcp-setup.md\n安装完成后告诉我，我来验证。",
        }

    state = load_state()
    previously_ok = state.get("mcp_configured") is True
    hint_suffix = "（曾就绪过，可能是 MCP 服务停了或登录失效）" if previously_ok else ""

    def _not_running(detail, ask_extra=""):
        return {
            "name": "xiaohongshu-mcp",
            "status": "not_running",
            "detail": detail,
            "action": "ask_user",
            "ask": (
                f"xiaohongshu-mcp 未就绪{hint_suffix}。请先启动/登录小红书 MCP。\n"
                "可尝试：bash scripts/xhs.sh status 或 bash scripts/xhs.sh login"
                f"{ask_extra}"
            ),
        }

    try:
        result = subprocess.run(
            ["bash", str(xhs_sh), "status"],
            cwd=str(SKILL_DIR),
            capture_output=True,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        return _not_running("status timeout")
    except Exception as e:
        return _not_running(f"status exception: {e}")

    output = (result.stdout or "") + "\n" + (result.stderr or "")
    out_lower = output.lower()

    negative_tokens = (
        "login_required", "not logged", "not_logged", "未登录", "需要登录",
        "connection refused", "econnrefused", "timeout", "timed out",
        "error", "failed", "401", "403", "503",
    )
    if any(tok in out_lower for tok in negative_tokens) or any(tok in output for tok in ("未登录", "需要登录")):
        return _not_running(
            f"status 输出包含否定信号{hint_suffix}",
            ask_extra=(f"\n  原始输出前 200 字符：{output[:200].strip()!r}" if output.strip() else ""),
        )

    if result.returncode != 0:
        return _not_running(f"status returncode={result.returncode}{hint_suffix}")

    positive_zh = ("已登录", "登录成功", "在线", "登录有效")
    positive_en = (
        '"logged_in": true', '"logged_in":true',
        '"success": true', '"success":true',
        '"status": "ok"', '"status":"ok"',
        'login_status: ok', 'logged in as',
    )
    has_positive = any(kw in output for kw in positive_zh) or any(tok in out_lower for tok in positive_en)
    if has_positive:
        update_state(mcp_configured=True)
        return {"name": "xiaohongshu-mcp", "status": "ok", "detail": "MCP 服务运行中且已登录", "action": None}

    return _not_running(
        f"status returncode=0 但输出无明确登录态信号{hint_suffix}",
        ask_extra=(f"\n  原始输出前 200 字符：{output[:200].strip()!r}" if output.strip() else ""),
    )


def check_image_gen():
    """检查图片生成能力 —— 必须先固定选择 Gemini 原生或 OpenAI 兼容。"""
    image_script = SCRIPTS_DIR / "image.py"
    if image_script.exists():
        result = subprocess.run(
            [sys.executable, str(image_script), "--check"],
            cwd=str(SKILL_DIR),
            capture_output=True,
            text=True,
            timeout=20,
        )
        output = (result.stderr or result.stdout or "").strip()
        if result.returncode == 0:
            return {"name": "图片生成 API", "status": "ok", "detail": output, "action": None}

    return {
        "name": "图片生成 API",
        "status": "missing",
        "detail": "未选择或未配置图片 API（必须固定为 Gemini 原生或 OpenAI 兼容其中一种）",
        "action": "ask_user",
        "ask": (
            "首次使用图片生成前，需要先确认你能提供哪一种 API；确认后后续真实生图只使用这一种，不自动切换。\n"
            "请选择并提供对应 Key：\n"
            "  1) Gemini 原生：IMAGE_GEN_PROTOCOL=gemini-native，GEMINI_API_KEY=<your-key>，GEMINI_IMAGE_MODEL=gemini-2.5-flash-image\n"
            "  2) OpenAI 兼容：IMAGE_GEN_PROTOCOL=openai-images，IMAGE_GEN_API_KEY=<your-key>，IMAGE_GEN_OPENAI_MODEL=gpt-image-2，IMAGE_GEN_BASE_URL=https://api.gjs.ink\n"
            "\n拿到你的选择和 Key 后，我会写到 config/runtime.env。"
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


def check_schemas():
    """校验 runtime 文件对 schemas/ 的一致性（v2.4.0）。

    复用 scripts/validate.py。drift 归为 optional 级别：
    - ok     : 全部 valid
    - drift  : runtime 有文件违反 schema
    - missing: schemas/ 不存在或 jsonschema 未安装
    """
    if not (SKILL_DIR / "schemas").is_dir():
        return {
            "name": "Schema 校验",
            "status": "missing",
            "detail": "schemas/ 不存在",
            "action": "optional",
        }
    try:
        sys.path.insert(0, str(SCRIPTS_DIR))
        from validate import run as _validate_run
    except ImportError as e:
        return {
            "name": "Schema 校验",
            "status": "missing",
            "detail": f"scripts/validate.py 不可用: {e}",
            "action": "optional",
        }
    try:
        result = _validate_run(target=SKILL_DIR, skill_dir=SKILL_DIR)
    except Exception as e:
        return {
            "name": "Schema 校验",
            "status": "missing",
            "detail": f"校验异常: {e}",
            "action": "optional",
        }

    if result.get("fatal"):
        return {
            "name": "Schema 校验",
            "status": "missing",
            "detail": result.get("fatal_reason") or "jsonschema 库未安装",
            "action": "optional",
            "fix_cmd": "pip install -r requirements.txt",
        }
    if result["valid"]:
        return {"name": "Schema 校验", "status": "ok", "detail": "runtime 文件全部匹配 schema", "action": None}

    drift_files = sorted({item["file"] for item in result["drift"]})
    return {
        "name": "Schema 校验",
        "status": "drift",
        "detail": f"{len(drift_files)} 个文件 drift: {', '.join(Path(p).name for p in drift_files)}",
        "action": "ask_user",
        "ask": "runtime 文件与 schema 不一致；跑 `python3 scripts/validate.py` 查细节，或在确认可接受后更新 schema/回填字段。",
        "drift_files": drift_files,
    }


def run_preflight():
    checks = [
        check_python(),
        check_sqlite(),
        check_mcp(),
        check_image_gen(),
        check_database(),
        check_profile(),
        check_schemas(),
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


# ─── 人类可读输出 ─────────────────────────────────────────────────
def _color(text: str, code: str, use_color: bool) -> str:
    return f"\033[{code}m{text}\033[0m" if use_color else text


def _status_icon(status: str, use_color: bool) -> str:
    table = {
        "ok": ("✅", "32"),
        "missing": ("❌", "31"),
        "not_running": ("⚠️ ", "33"),
        "not_initialized": ("🔧", "33"),
        "not_configured": ("💡", "36"),
        "not_created": ("💡", "36"),
        "error": ("❌", "31"),
        "unknown": ("❓", "33"),
        "skip": ("⏭ ", "2"),
        "drift": ("⚠️ ", "33"),
    }
    icon, color = table.get(status, ("·", "0"))
    return _color(icon, color, use_color)


def print_human(result: dict, use_color: bool = True) -> None:
    bold = lambda s: _color(s, "1", use_color)
    dim = lambda s: _color(s, "2", use_color)

    print()
    print(bold("薯灵 (ShuLing) 环境自检"))
    print(dim("─" * 54))

    for c in result["checks"]:
        icon = _status_icon(c["status"], use_color)
        line = f"{icon} {c['name']:<20} {dim(c['status'])}"
        if c.get("version"):
            line += f"  {c['version']}"
        if c.get("detail"):
            line += f"  {dim('— ' + str(c['detail']))}"
        print(line)

    s = result["summary"]
    print()
    print(dim("─" * 54))

    if s["auto_fixable"]:
        print(bold("🔧 可自动修复（照命令跑即可）:"))
        for c in s["auto_fixable"]:
            cmd = c.get("fix_cmd") or c.get("install_cmd") or c.get("install_hint") or "(见 detail)"
            print(f"   • {c['name']}: {cmd}")
        print()

    if s["need_user"]:
        print(bold("❗ 需要你配合:"))
        for c in s["need_user"]:
            print(f"   • {c['name']}: {c.get('detail', '')}")
            ask = c.get("ask", "")
            if ask:
                for ln in ask.splitlines():
                    print(f"     {dim(ln)}")
        print()

    if s["optional"]:
        print(bold("💡 可选配置（不配也能用）:"))
        for c in s["optional"]:
            print(f"   • {c['name']}: {c.get('detail', '')}")
        print()

    if result.get("ready"):
        print(bold(_color("🎉 环境就绪，可以开始使用！", "32", use_color)))
    else:
        print(bold(_color("⚠️  部分依赖需要处理后才能使用", "33", use_color)))

    state = result.get("state") or {}
    if state:
        print()
        print(dim("业务状态: " + ", ".join(f"{k}={v}" for k, v in state.items())))


def _exit_code(result: dict) -> int:
    s = result["summary"]
    if s["need_user"]:
        return 2
    if s["auto_fixable"]:
        return 1
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False, description="薯灵环境预检")
    parser.add_argument("--human", action="store_true", help="人类彩色输出")
    parser.add_argument("--json", dest="json_only", action="store_true", help="纯 JSON 输出")
    parser.add_argument("--no-color", action="store_true", help="关闭 ANSI 颜色")
    parser.add_argument("-h", "--help", action="help")
    args = parser.parse_args()

    result = run_preflight()

    if args.human:
        use_color = (not args.no_color) and sys.stdout.isatty()
        print_human(result, use_color=use_color)
    elif args.json_only:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
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

    sys.exit(_exit_code(result))
