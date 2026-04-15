"""XHS 自动化系统 - Telegram 轮询监听器（零依赖）

getUpdates 长轮询，解析博主指令：
  选N / 跳过 / 更多 / 自动 / 确认 / 重新生成N / 取消
"""
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import config_loader

config_loader.load_runtime_env()

POLL_INTERVAL = 30  # 秒
DRAFT_SELECT_TIMEOUT = int(os.environ.get("DRAFT_SELECT_TIMEOUT", "110"))  # 分钟
IMAGE_REVIEW_TIMEOUT = int(os.environ.get("IMAGE_REVIEW_TIMEOUT", "30"))  # 分钟


def get_bot_config():
    return {
        "token": os.environ.get("XHS_TELEGRAM_BOT_TOKEN", "").strip(),
        "chat_id": os.environ.get("XHS_TELEGRAM_CHAT_ID", "").strip(),
    }


# ---------------------------------------------------------------------------
# Telegram API
# ---------------------------------------------------------------------------

def get_updates(token, offset=None, timeout=30):
    """调用 Telegram getUpdates（长轮询）"""
    url = f"https://api.telegram.org/bot{token}/getUpdates"
    params = {"timeout": timeout}
    if offset is not None:
        params["offset"] = offset
    url += "?" + "&".join(f"{k}={v}" for k, v in params.items())

    req = urllib.request.Request(url)
    try:
        resp = urllib.request.urlopen(req, timeout=timeout + 10)
        return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"[listener] getUpdates 错误: {e}", file=sys.stderr)
        return {"ok": False, "result": []}


# ---------------------------------------------------------------------------
# 指令解析
# ---------------------------------------------------------------------------

def parse_command(text):
    """
    解析博主回复指令，返回 {"action": str, "value": any}

    支持的指令：
      选N / 选 N       → select N
      N（纯数字）      → detail N
      重新生成N        → regenerate_one N
      重新生成          → regenerate_all
      跳过              → skip
      更多 / 全部       → more
      自动              → auto_mode
      手动              → manual_mode
      确认              → confirm
      取消              → cancel
    """
    text = text.strip()

    # 选N / 选 N
    m = re.match(r'^选\s*(\d+)$', text)
    if m:
        return {"action": "select", "value": int(m.group(1))}

    # 纯数字 → 查看详情
    if text.isdigit():
        return {"action": "detail", "value": int(text)}

    # 重新生成N
    m = re.match(r'^重新生成\s*(\d+)$', text)
    if m:
        return {"action": "regenerate_one", "value": int(m.group(1))}

    # 固定指令映射
    fixed = {
        "跳过": {"action": "skip"},
        "更多": {"action": "more"},
        "全部": {"action": "more"},
        "自动": {"action": "auto_mode"},
        "手动": {"action": "manual_mode"},
        "确认": {"action": "confirm"},
        "重新生成": {"action": "regenerate_all"},
        "取消": {"action": "cancel"},
    }

    result = fixed.get(text)
    if result:
        return result

    return {"action": "unknown", "value": text}


# ---------------------------------------------------------------------------
# 轮询等待回复
# ---------------------------------------------------------------------------

def poll_for_reply(chat_id, after_timestamp, timeout_minutes=None, poll_interval=None,
                   reminder_callback=None):
    """
    轮询等待博主回复。

    Args:
        chat_id: 目标 chat ID
        after_timestamp: 只接受此时间戳之后的消息（Unix 秒）
        timeout_minutes: 超时分钟数
        poll_interval: 轮询间隔秒数
        reminder_callback: 可选回调 fn(minutes_left)，在剩余时间较少时调用

    Returns:
        {"action": str, "value": any} 或 None（超时）
    """
    config = get_bot_config()
    if not config["token"]:
        print("[listener] Telegram 未配置", file=sys.stderr)
        return None

    timeout_minutes = timeout_minutes or DRAFT_SELECT_TIMEOUT
    poll_interval = poll_interval or POLL_INTERVAL
    deadline = time.time() + timeout_minutes * 60
    offset = None
    reminded_30 = False
    reminded_10 = False

    while time.time() < deadline:
        minutes_left = (deadline - time.time()) / 60

        # 超时提醒
        if reminder_callback:
            if not reminded_30 and minutes_left <= 30:
                reminded_30 = True
                reminder_callback(30)
            if not reminded_10 and minutes_left <= 10:
                reminded_10 = True
                reminder_callback(10)

        try:
            updates = get_updates(config["token"], offset, timeout=poll_interval)
            if not updates.get("ok"):
                time.sleep(5)
                continue

            for update in updates.get("result", []):
                offset = update["update_id"] + 1
                msg = update.get("message", {})

                # 检查来源和时间
                msg_chat_id = str(msg.get("chat", {}).get("id", ""))
                msg_date = msg.get("date", 0)

                if msg_chat_id == str(chat_id) and msg_date > after_timestamp:
                    text = msg.get("text", "").strip()
                    if text:
                        cmd = parse_command(text)
                        print(f"[listener] 收到指令: {text} -> {cmd}")
                        return cmd

        except Exception as e:
            print(f"[listener] 轮询错误: {e}", file=sys.stderr)
            time.sleep(5)

    print(f"[listener] 等待超时 ({timeout_minutes}min)")
    return None  # 超时


def poll_for_image_review(chat_id, after_timestamp):
    """等待图片审核回复（较短超时）"""
    return poll_for_reply(
        chat_id, after_timestamp,
        timeout_minutes=IMAGE_REVIEW_TIMEOUT,
        poll_interval=POLL_INTERVAL,
    )


# ---------------------------------------------------------------------------
# 提醒发送
# ---------------------------------------------------------------------------

def send_reminder(minutes_left):
    """发送超时提醒"""
    import telegram
    telegram.send(
        f"⏰ 还有 {minutes_left} 分钟将自动使用评分最高的草稿\n"
        f"回复 \"选N\" 选择其他，回复 \"跳过\" 取消发布"
    )


# ---------------------------------------------------------------------------
# CLI 入口（测试用）
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    config = get_bot_config()
    if not config["token"]:
        print("请配置 XHS_TELEGRAM_BOT_TOKEN")
        sys.exit(1)

    chat_id = config["chat_id"]
    if len(sys.argv) > 1:
        chat_id = sys.argv[1]

    print(f"[listener] 开始监听 chat_id={chat_id}")
    print(f"[listener] 草稿选择超时: {DRAFT_SELECT_TIMEOUT}min, 图片审核超时: {IMAGE_REVIEW_TIMEOUT}min")
    print(f"[listener] 发送任意消息进行测试...\n")

    now_ts = int(time.time())
    result = poll_for_reply(
        chat_id, now_ts,
        timeout_minutes=5,
        poll_interval=10,
        reminder_callback=lambda m: print(f"  [提醒] 还有 {m} 分钟"),
    )

    if result:
        print(f"\n收到指令: {json.dumps(result, ensure_ascii=False)}")
    else:
        print("\n超时，未收到回复")
