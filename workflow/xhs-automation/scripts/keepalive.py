#!/usr/bin/env python3
"""XHS MCP 登录保活 + 掉线自动告警

每隔几小时运行一次：
1. 检查 MCP 服务是否在运行，不在则尝试启动
2. 调用 check_login_status 保持会话活跃
3. 如果登录过期 → 调用 get_login_qrcode → 发 Telegram 二维码
"""

import json
import subprocess
import sys
import os
import time
import tempfile
import base64

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
import telegram



def resolve_mcp_script(script_name):
    candidates = [
        os.environ.get(f"XHS_{script_name.upper().replace('.', '_')}"),
        os.path.expanduser(f"~/.agents/skills/xiaohongshu/scripts/{script_name}"),
        os.path.expanduser(f"~/.claude/skills/xiaohongshu/scripts/{script_name}"),
        os.path.expanduser(f"~/.codex/skills/xiaohongshu/scripts/{script_name}"),
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return path
    return os.path.expanduser(f"~/.agents/skills/xiaohongshu/scripts/{script_name}")


MCP_CALL = resolve_mcp_script("mcp-call.sh")
MCP_START = resolve_mcp_script("start-mcp.sh")
MCP_PID_FILE = os.path.expanduser("~/.xiaohongshu/mcp.pid")
LOG_FILE = os.path.join(os.path.dirname(SCRIPT_DIR), "logs", "keepalive.log")


def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def is_mcp_running():
    """检查 MCP 进程是否存活"""
    if not os.path.exists(MCP_PID_FILE):
        return False
    try:
        with open(MCP_PID_FILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)  # 不杀进程，只检查是否存在
        return True
    except (ValueError, ProcessLookupError, PermissionError):
        return False


def start_mcp():
    """启动 MCP 服务"""
    log("MCP 未运行，尝试启动...")
    try:
        subprocess.run([MCP_START], timeout=30, capture_output=True)
        time.sleep(3)
        if is_mcp_running():
            log("MCP 启动成功")
            return True
        else:
            log("MCP 启动失败")
            return False
    except Exception as e:
        log(f"MCP 启动异常: {e}")
        return False


def mcp_call(tool, args="{}"):
    """调用 MCP 工具，返回解析后的 JSON"""
    try:
        result = subprocess.run(
            [MCP_CALL, tool, args],
            capture_output=True, text=True, timeout=30,
            env={**os.environ, "no_proxy": "localhost,127.0.0.1"}
        )
        if result.returncode != 0:
            log(f"MCP 调用失败 ({tool}): {result.stderr.strip()}")
            return None
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        log(f"MCP 返回非 JSON ({tool}): {result.stdout[:200]}")
        return None
    except subprocess.TimeoutExpired:
        log(f"MCP 调用超时 ({tool})")
        return None
    except Exception as e:
        log(f"MCP 调用异常 ({tool}): {e}")
        return None


def check_login():
    """检查登录状态，返回 True=已登录"""
    resp = mcp_call("check_login_status")
    if resp is None:
        return None  # 调用失败

    # 解析 MCP 响应格式
    try:
        content = resp.get("result", {}).get("content", [])
        if content:
            text = content[0].get("text", "")
            # 登录成功通常包含用户信息或 "logged in"
            if "登录" in text and ("过期" in text or "失效" in text or "未登录" in text):
                return False
            if "error" in text.lower() or "expire" in text.lower():
                return False
            # 有内容返回且没有错误标记 → 大概率已登录
            return True
        # content 为空但有 isError
        if resp.get("result", {}).get("isError"):
            return False
    except Exception:
        pass

    return True  # 默认假设成功


def get_qrcode_and_alert():
    """获取登录二维码并发送到 Telegram"""
    log("登录已过期，获取二维码...")
    resp = mcp_call("get_login_qrcode")
    if resp is None:
        telegram.send_error("保活检测", "登录过期且无法获取二维码，请手动处理")
        return

    try:
        content = resp.get("result", {}).get("content", [])
        qr_url = None
        qr_image_data = None

        for item in content:
            text = item.get("text", "")
            # 尝试从返回中提取 URL 或 base64 图片
            if "http" in text:
                # 提取 URL
                for word in text.split():
                    if word.startswith("http"):
                        qr_url = word.strip('"\'')
                        break
            if item.get("type") == "image":
                qr_image_data = item.get("data", "")

        if qr_url:
            telegram.send(
                f"🔴 <b>XHS 登录已过期</b>\n\n"
                f"请扫码重新登录：\n{qr_url}\n\n"
                f"⏰ 扫码后保活将自动恢复"
            )
            log(f"二维码链接已发送到 Telegram: {qr_url}")
        elif qr_image_data:
            # base64 图片保存为临时文件
            tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
            tmp.write(base64.b64decode(qr_image_data))
            tmp.close()
            telegram.send_photo(tmp.name, caption="🔴 <b>XHS 登录已过期</b>\n请扫码重新登录")
            os.unlink(tmp.name)
            log("二维码图片已发送到 Telegram")
        else:
            # 直接把原始返回发给用户
            raw_text = json.dumps(content, ensure_ascii=False)[:500]
            telegram.send(
                f"🔴 <b>XHS 登录已过期</b>\n\n"
                f"二维码获取结果：\n<code>{raw_text}</code>\n\n"
                f"请手动登录: https://www.xiaohongshu.com"
            )
            log("二维码原始数据已发送到 Telegram")
    except Exception as e:
        log(f"二维码处理异常: {e}")
        telegram.send_error("保活检测", f"登录过期，二维码处理失败: {e}")


def main():
    log("=== 开始保活检测 ===")

    # 1. 检查 MCP 服务
    if not is_mcp_running():
        if not start_mcp():
            telegram.send_error("保活检测", "MCP 服务无法启动，请手动检查")
            log("=== 保活检测结束（MCP 未运行）===")
            return

    # 2. 检查登录状态（同时起到 keep-alive 作用）
    status = check_login()

    if status is None:
        log("登录状态检查失败（MCP 调用失败）")
        telegram.send_error("保活检测", "MCP 调用失败，请检查服务状态")
    elif status:
        log("登录状态正常 ✓")
    else:
        get_qrcode_and_alert()

    log("=== 保活检测结束 ===")


if __name__ == "__main__":
    main()
