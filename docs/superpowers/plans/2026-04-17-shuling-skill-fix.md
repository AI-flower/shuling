# 薯灵 Skill 路径统一、渠道解耦与稳健化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 hermes 上 shuling skill 的路径混乱、状态丢失、AI 反复打扰用户、渠道偶合等问题，让 skill 专注小红书业务，不与通讯渠道耦合。

**Architecture:**
- **职责边界**：hermes-agent 负责通讯渠道（Telegram 等 IM）、用户对话、cron 调度；shuling skill 只负责小红书业务（画像、选题、创作、发布、复盘、进化）。skill 输出**结构化业务内容**，由 hermes 决定如何送达用户、如何收回回应再喂给 skill
- **路径**：所有配置/状态/数据/知识库以 skill 根目录为基准，与 `workflow/xhs-automation/` 完全脱钩
- **状态恢复**：`config/state.json` 持久化业务里程碑（mcp_configured / profile_created / cold_start_done），preflight 写入、SKILL.md 业务路由段读取，避免重复打扰
- **业务路由**：skill 启动时无论是用户对话触发还是 hermes cron 调度，都根据 state 自动判定下一步业务动作
- **渠道脱敏**：SKILL.md 全文去除"推送/通知/Telegram"等渠道偶合措辞，统一为"返回/输出/等待用户回应"
- **用户主动方案优先**：用户提议替代方案（如"我给你 cookie"）时，立即接受，不强制走默认路径

**Tech Stack:** Bash / Python 3 / rsync / SSH / git

**部署目标:** Mac (100.79.106.110) `/Users/weiyong/Documents/10/shuling` → `~/.hermes/skills/social-media/shuling/`

---

## File Structure

```
/tmp/shuling-src/                          # 本地工作镜像
├── SKILL.md                               # [改写] 顶部 0a 业务路由 + 0 节去 Telegram + 全文渠道脱敏
├── install.sh                             # [改写] 删 Telegram wizard、保护用户 config/data/kb
├── scripts/
│   ├── preflight.py                       # [改写] 删 check_telegram、加 state.json、nvm fallback
│   └── xhs.sh                             # [改写] 加 import-cookie 子命令
├── skills/shuling/SKILL.md                # [改写] 路径同步
└── workflow/xhs-automation/config/runtime.env.example   # [改写] 去 Telegram 字段

# 部署后 ~/.hermes/skills/social-media/shuling/
├── SKILL.md
├── scripts/...
├── data/, knowledge-base/, docs/, templates/
└── config/                                # 用户数据，install.sh 永不覆盖
    ├── runtime.env                        # MCP_URL + IMAGE_GEN_*（不再含 Telegram）
    └── state.json                         # 业务里程碑（自动维护）
```

**Workflow 目录处理：** 源项目 `workflow/xhs-automation/` 是另一个独立后台项目（含自己的 telegram.py、orchestrator.py 等），与 skill 完全脱钩。skill 不引用、不读取、不修改该目录任何文件。

---

## 阶段 A：preflight.py 重构

### Task A1: 替换路径常量

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py:15-21`

- [ ] **Step 1: 替换路径常量块**

将第 15-21 行：

```python
SKILL_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SKILL_DIR / "scripts"
DATA_DIR = SKILL_DIR / "data"
KB_DIR = SKILL_DIR / "knowledge-base"
WORKFLOW_DIR = SKILL_DIR / "workflow" / "xhs-automation"
CONFIG_DIR = WORKFLOW_DIR / "config"
SKILL_CONFIG_DIR = SKILL_DIR / "config"
```

替换为：

```python
SKILL_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SKILL_DIR / "scripts"
DATA_DIR = SKILL_DIR / "data"
KB_DIR = SKILL_DIR / "knowledge-base"
CONFIG_DIR = SKILL_DIR / "config"
STATE_FILE = CONFIG_DIR / "state.json"
RUNTIME_ENV = CONFIG_DIR / "runtime.env"
```

### Task A2: 新增 state 工具与 nvm node 查找

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py`（在路径常量之后、`def check_python` 之前插入）

- [ ] **Step 1: 插入工具函数块**

```python


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
```

### Task A3: check_node 用 find_node

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py`（check_node 函数）

- [ ] **Step 1: 替换 check_node 函数体**

```python
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
```

### Task A4: check_playwright 用 find_node + 注入 PATH

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py`（check_playwright 函数）

- [ ] **Step 1: 替换函数体**

```python
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
```

### Task A5: check_mcp 加 state 短路 + 中文匹配 + timeout 30s

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py`（check_mcp 函数）

- [ ] **Step 1: 替换 check_mcp 整个函数**

```python
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
```

### Task A6: 删除 check_telegram 函数

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py`（check_telegram 函数）

- [ ] **Step 1: 整段删除 check_telegram 函数**

删除原文件 140-184 行 `def check_telegram(): ...` 整个函数定义。理由：Telegram 是 hermes 通讯渠道，不属于 skill 业务范畴。

### Task A7: check_image_gen 改单一路径

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py`（check_image_gen 函数）

- [ ] **Step 1: 替换 check_image_gen 整个函数**

```python
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
```

### Task A8: check_profile 写入 state

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py`（check_profile 函数）

- [ ] **Step 1: 替换 check_profile**

```python
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
```

### Task A9: run_preflight 调用列表去 telegram、加 setup_completed

**Files:**
- Modify: `/tmp/shuling-src/scripts/preflight.py`（run_preflight 函数）

- [ ] **Step 1: 替换 checks 列表**

将：

```python
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
```

替换为：

```python
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
```

- [ ] **Step 2: 替换 result 构造块**

将原 295-301 行 `result = {...}` 替换为：

```python
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
```

> **注意**：`setup_completed` 不再依赖 telegram_configured。判定条件简化为：`ready=True`（无 ask_user/auto_fixable 项）+ MCP 已就绪 + 画像已建立。

### Task A10: 验证 preflight.py 语法

- [ ] **Step 1: 编译检查**

Run: `python3 -c "import ast; ast.parse(open('/tmp/shuling-src/scripts/preflight.py').read())"`
Expected: 无输出

---

## 阶段 B：xhs.sh 加 import-cookie 子命令

### Task B1: usage 帮助里加一行

**Files:**
- Modify: `/tmp/shuling-src/scripts/xhs.sh:24`（在 `login` 行之后插入）

- [ ] **Step 1: 找到 `login                         获取登录二维码` 这行，在其后插入：**

```
  import-cookie <cookie|@文件>  导入已抓取的 cookie 替代扫码（用户主动给 cookie 时优先用此入口）
```

### Task B2: 加 import-cookie case

**Files:**
- Modify: `/tmp/shuling-src/scripts/xhs.sh`（在 `login)` case 之后、`user)` case 之前）

- [ ] **Step 1: 在 `login)` 块之后插入新 case**

在 `login)` case 块之后（即 `mcp_call "get_login_qrcode" "{}"` 后的 `;;` 之后）插入：

```bash
  import-cookie)
    [ -z "${1:-}" ] && { echo "错误: 缺少 cookie 字符串或文件路径"; echo "用法: $(basename "$0") import-cookie <cookie字符串|@cookie.txt>"; exit 1; }
    if [[ "$1" == @* ]]; then
      COOKIE_FILE="${1#@}"
      [ ! -f "$COOKIE_FILE" ] && { echo "错误: cookie 文件不存在: $COOKIE_FILE" >&2; exit 1; }
      COOKIE_RAW=$(cat "$COOKIE_FILE")
    else
      COOKIE_RAW="$1"
    fi
    ESCAPED=$(printf '%s' "$COOKIE_RAW" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()), end="")')
    mcp_call "import_cookie" "{\"cookie\": $ESCAPED}"
    ;;

```

> **注意**：xiaohongshu-mcp 是否实现 `import_cookie` 工具未知。若不支持，调用会返回错误信息，给 AI/用户清晰信号去查 MCP 文档；后续若 MCP 升级支持，本入口无需改动。

### Task B3: 验证语法

- [ ] **Step 1: bash 语法检查**

Run: `bash -n /tmp/shuling-src/scripts/xhs.sh && echo OK`
Expected: `OK`

---

## 阶段 C：install.sh 精简（去 Telegram + 保护用户数据）

### Task C1: rsync 加多个 --exclude 保护用户数据

**Files:**
- Modify: `/tmp/shuling-src/install.sh:85-92`

- [ ] **Step 1: 替换 rsync 命令**

将：

```bash
    rsync -a --exclude=.git --exclude=.DS_Store --exclude=.idea \
        --exclude=workflow --exclude=skills --exclude=docs \
        --exclude=.session-recorder --exclude=*.md \
        "$SKILL_DIR/" "$target/"
    cp "$SKILL_DIR/SKILL.md" "$target/"
```

替换为：

```bash
    rsync -a --exclude=.git --exclude=.DS_Store --exclude=.idea \
        --exclude=workflow --exclude=skills --exclude=docs \
        --exclude=.session-recorder --exclude=*.md \
        --exclude=config --exclude=knowledge-base/profile.json \
        --exclude=knowledge-base/preferences.json --exclude=knowledge-base/patterns.md \
        --exclude=data/xhs.db --exclude=data/xhs.db-shm --exclude=data/xhs.db-wal \
        "$SKILL_DIR/" "$target/"
    cp "$SKILL_DIR/SKILL.md" "$target/"
```

### Task C2: 删除 7.5 节 Telegram 配置 wizard

**Files:**
- Modify: `/tmp/shuling-src/install.sh:148-184`

- [ ] **Step 1: 整段删除 7.5 节**

删除从 `# ─── 7.5 配置 Telegram Bot ─────` 到对应 `fi` 结束的整段（约 37 行）。

> Telegram 是 hermes-agent 与用户对话的渠道，由 hermes 自己配置，skill 安装脚本不应触碰。

### Task C3: 加一段：确保每个 target 有 config/runtime.env（只复制模板，不交互）

**Files:**
- Modify: `/tmp/shuling-src/install.sh`（在原 7.5 删除之处插入新段）

- [ ] **Step 1: 在删除的 7.5 位置插入新段**

```bash
# ─── 7.5 确保每个 target 有 config/runtime.env（无交互，仅初始化）──
RUNTIME_ENV_TEMPLATE="$SKILL_DIR/workflow/xhs-automation/config/runtime.env.example"

if [ -f "$RUNTIME_ENV_TEMPLATE" ]; then
    for entry in "${PLATFORMS[@]}"; do
        target="${entry#*:}"
        cfg_dir="$target/config"
        runtime_env="$cfg_dir/runtime.env"
        mkdir -p "$cfg_dir"
        if [ ! -f "$runtime_env" ]; then
            cp "$RUNTIME_ENV_TEMPLATE" "$runtime_env"
            info "$target: 已创建 config/runtime.env（来自模板）"
        else
            info "$target: config/runtime.env 已存在，保留"
        fi
    done
fi
```

> 安装阶段不再问任何凭证。skill 运行时若 IMAGE_GEN_API_KEY 缺失，preflight 会标 `optional` 让 AI 自行决定。

### Task C4: 7.6 预检改为遍历 target

**Files:**
- Modify: `/tmp/shuling-src/install.sh:186-193`

- [ ] **Step 1: 替换为按 target 跑预检**

```bash
# ─── 7.6 运行环境预检 ────────────────────────────────────────────
printf "\n${BOLD}=== 环境预检 ===${RESET}\n\n"

for entry in "${PLATFORMS[@]}"; do
    target="${entry#*:}"
    if [ -f "$target/scripts/preflight.py" ]; then
        printf "${BOLD}-- %s --${RESET}\n" "$target"
        python3 "$target/scripts/preflight.py" 2>&1 >/dev/null || true
    fi
done
```

### Task C5: 验证 install.sh 语法

- [ ] **Step 1: bash 语法检查**

Run: `bash -n /tmp/shuling-src/install.sh && echo OK`
Expected: `OK`

---

## 阶段 D：runtime.env.example 去 Telegram

### Task D1: 改写 runtime.env.example 模板

**Files:**
- Modify: `/tmp/shuling-src/workflow/xhs-automation/config/runtime.env.example`

- [ ] **Step 1: 替换整个文件内容为：**

```
# === skill 必备 ===
MCP_URL=http://localhost:18060/mcp  # xiaohongshu-mcp 服务地址

# === 可选：图片生成（不配则走 HTML 截图，效果也不错）===
# IMAGE_GEN_PROVIDER=gemini       # openai 或 gemini
# IMAGE_GEN_API_KEY=              # API Key
# IMAGE_GEN_MODEL=gemini-2.0-flash-preview-image-generation
# IMAGE_GEN_SIZE=1024x1024
# IMAGE_GEN_ASPECT_RATIO=3:4

# === 可选：品牌风格（生图时使用）===
# IMAGE_BRAND_STYLE=你的品牌风格描述

# === 注意 ===
# Telegram / IM 通讯凭证不在此文件配置——它们是 hermes-agent 的职责，
# 由 hermes 自己的配置系统管理。本 skill 不假设任何特定通讯渠道。
```

> **注意**：源项目 workflow/xhs-automation/ 是另一个独立后台脚本项目，会继续使用自己的 Telegram 配置（在它自己的 .env 或代码里）。本模板是 skill 部署时复制到 `~/.hermes/skills/.../config/runtime.env` 的初始版本，与 workflow 的 runtime.env 互不影响。

---

## 阶段 E：SKILL.md 全面改造

### Task E1: 顶部加 0a 业务路由段

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md:28`（在 `## 0. 安装与环境检查` 之前插入）

- [ ] **Step 1: 在 `## 0. 安装与环境检查` 之前、`---` 之后插入：**

```markdown
## 0a. 业务路由（每次 skill 被调起时第一件事）

**无论是用户主动对话调起，还是 hermes 通过 cron 等机制自动触发，第一件事都是跑预检并按 state 决定下一步业务，不要默认从头开始**：

```bash
python3 scripts/preflight.py
```

读输出 JSON 中的 `setup_completed`、`state` 与 `checks`，按下表行动：

| 当前状态 | 下一步 |
|---------|------|
| `setup_completed: true` 且 `state.profile_created: true` 且 `state.cold_start_done: true` | 直接进入 `2. 每日流程`：根据当前时间（午间档/晚间档）走选题→创作→发布；夜间走 `3. 每日复盘` |
| `setup_completed: true` 且 `state.profile_created: true` 且 cold_start 未做 | 跳过 `0`/`1`，直接执行 `1. 冷启动播种` 部分（竞品分析 + 写 patterns.md），完成后写 `state.cold_start_done = true` |
| `state.profile_created: true` 但某个 check 报 `error`/`missing` | 仅修复缺失项，**不要重新走 0/1 流程**，**不要重新问画像** |
| `state.profile_created` 缺失/false | 走 `0` 安装（仅缺失项）→ `1. 首次使用：建立画像` |

**关键纪律**：
- **不要重复打扰用户**：state 标记过 ok 的，即使本次 check 超时/不确定，也按 ok 处理
- **不要重复问画像**：如果 `knowledge-base/profile.json` 已存在，直接读取使用；要修改请等用户主动说"更新画像"
- **不要因为没具体指令就放空**：如果用户/hermes 调起但没给具体业务指令（例如 cron 触发只给 skill 加载），按上表自行选择下一步业务动作

---

```

### Task E2: 顶部"核心原则"加禁读 workflow

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md:19-25`

- [ ] **Step 1: 在"核心原则"4 条之后追加第 5 条**

在 `4. **用户操作最小化**：从"每天选几次"渐进到"回复一个'发'字"` 之后插入：

```markdown
5. **不读 workflow 目录**：`workflow/xhs-automation/` 是另一个独立后台项目（不属于本 skill），其中的 .py 脚本与本 skill 行为无关。**禁止 grep / Read / 引用** 该目录下任何文件。本 skill 的所有路径都相对 skill 根目录（包含本 SKILL.md 的目录）。
```

### Task E3: 改写 0 节（去 Telegram、精简引导）

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md:55-108`

- [ ] **Step 1: 替换"第三步：逐项引导"整段（55-78 行）**

将原 55-78 行（`**第三步：逐项引导用户完成需要人工配合的项**` 到 `   - 如果不要：跳过，告诉用户后续想开可以再配`）替换为：

```markdown
**第三步：逐项处理需要人工配合的项**

按这个顺序处理（重要的先问）：

1. **xiaohongshu-mcp**（核心依赖——没有它就无法操作小红书）
   - 如果未运行：问用户是否已安装 xiaohongshu-mcp
   - 已安装但未启动：执行 `bash scripts/xhs.sh status`，根据输出判断
   - 未安装：告诉用户需要安装，提供安装方式（参考 `docs/mcp-setup.md`）
   - MCP 启动后，执行 `bash scripts/xhs.sh status` 验证登录态
   - **登录策略**：
     - **若用户主动提议方案**（"我给你 cookie"/"我直接粘贴"/"帮我用 cookie 登录"等任何变体）→ **立即接受**：让用户从浏览器复制 `Cookie` 头完整字符串，调用 `bash scripts/xhs.sh import-cookie '<cookie字符串>'`。**不要绕回扫码**
     - 否则默认走扫码：执行 `bash scripts/xhs.sh login` 获取二维码链接，返回给上层让用户扫码

2. **图片生成 API**（可选——不配也能用，走 HTML 截图降级）
   - 问用户："图片可以用 AI 生成（更好看），也可以用 HTML 模板截图（免费）。要配置 AI 图片吗？"
   - 如果要：问 API Key、服务商（openai/gemini），写入 `config/runtime.env`
   - 如果不要：跳过，告诉用户后续想开可以再配
```

> **注意**：原"2. Telegram Bot"段落整段移除——Telegram 由 hermes-agent 配置，与本 skill 无关。

- [ ] **Step 2: 替换"配置文件位置"段（92-108 行）**

将原 92-108 行替换为：

```markdown
### 配置文件位置

> **重要**：所有路径**相对 skill 根目录**（即包含本 SKILL.md 的目录）。**不要**在任何子目录如 `workflow/`、`xhs-automation/` 下创建配置——那是另一个独立项目。

| 文件 | 用途 |
|------|------|
| `config/runtime.env` | MCP_URL、可选的图片生成 API Key |
| `config/state.json` | 业务里程碑状态（自动维护，不要手改） |
| `knowledge-base/profile.json` | 博主画像 |
| `knowledge-base/preferences.json` | 用户偏好（自动学习） |
| `knowledge-base/patterns.md` | 有效内容 pattern 库 |
| `data/xhs.db` | SQLite 数据库 |

`config/runtime.env` 模板：

```bash
MCP_URL=http://localhost:18060/mcp
# IMAGE_GEN_PROVIDER=gemini
# IMAGE_GEN_API_KEY=...
```

> **不要在此配置任何 IM/通讯凭证**（Telegram Token 等）。通讯渠道是 hermes-agent 的职责。
```

### Task E4: 1 节加"已存在画像不重问"分支

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md:111-115`

- [ ] **Step 1: 替换 `> 触发条件：knowledge-base/profile.json 不存在` 为：**

```markdown
> 触发条件：`knowledge-base/profile.json` **不存在** 且用户表达内容方向需求

**画像已存在的处理**：如果 `knowledge-base/profile.json` 已存在，**直接读取使用**，绝不再问用户领域/受众/风格。要更新画像必须等用户主动说"更新画像"或"我想换方向"，才能进入对话流程并最终覆盖文件。

**与 0 节的关系**：本节流程不依赖图片生成 API，也不依赖 hermes 通讯渠道是否就绪。即使 0 节中 `图片生成 API` 标 `optional` 未配，本节也应正常完成（建立画像 + 冷启动播种 patterns.md）。MCP 未就绪时跳过冷启动中"竞品分析"步骤，仅完成画像写入与默认 preferences.json 初始化即可，并写 `state.profile_created = true`。
```

### Task E5: 全文渠道脱敏（"推送/通知" → "返回/输出"）

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md`（多处）

- [ ] **Step 1: 替换 235 行**

将 `5. **决定推送数量**（根据信心度）` 改为 `5. **决定输出选题数量**（根据信心度）`

- [ ] **Step 2: 替换 240 行整段**

将：

```markdown
6. **推送给用户**
   - 每个选题包含：主题名 + 一句话推荐理由 + 竞品密度（"蓝海"/"中等"/"红海"）
   - 如果只推 1 个：附加"回复'换'我再找一个"
   - 等待用户选择
```

改为：

```markdown
6. **返回选题列表**
   - 每个选题包含：主题名 + 一句话推荐理由 + 竞品密度（"蓝海"/"中等"/"红海"）
   - 如果只 1 个：附加"回复'换'我再找一个"
   - 输出后等待用户回应（hermes 负责把内容送到用户，并把回复喂回来）
```

- [ ] **Step 3: 替换 280 行**

将 `4. **推送给用户确认**` 改为 `4. **返回草稿等用户确认**`

- [ ] **Step 4: 替换 355 行**

将 `   - 未登录 → \`scripts/xhs.sh login\` 获取二维码链接 → 推送给用户扫码` 改为 `   - 未登录 → \`scripts/xhs.sh login\` 获取二维码链接，返回给上层让用户扫码；若用户主动提议给 cookie，改用 \`scripts/xhs.sh import-cookie\``

- [ ] **Step 5: 替换 368 行**

将 `   - 失败 → 通知用户失败原因，保留 meta.json 供重试` 改为 `   - 失败 → 返回失败原因，保留 meta.json 供重试`

- [ ] **Step 6: 替换 370 行**

将 `4. **通知用户**："已发布！标题：XXX"` 改为 `4. **返回发布结果**："已发布！标题：XXX"`

- [ ] **Step 7: 替换 413 行整段**

将：

```markdown
6. **生成日报推送给用户**

   日报格式：
```

改为：

```markdown
6. **生成日报输出**

   日报格式（输出后由 hermes 决定如何送达）：
```

- [ ] **Step 8: 替换 531 行**

将 `5. **生成周报推送给用户**：` 改为 `5. **生成周报输出**：`

- [ ] **Step 9: 替换 670 行**

将 `| 登录过期 | \`xhs.sh login\` 获取二维码 → 推送用户扫码 |` 改为 `| 登录过期 | \`xhs.sh login\` 获取二维码 → 返回给上层让用户扫码 |`

- [ ] **Step 10: 替换 674 行**

将 `| 发布失败 | 通知用户失败原因，保留 meta.json 供重试 |` 改为 `| 发布失败 | 返回失败原因，保留 meta.json 供重试 |`

### Task E6: 8 节异常处理表加新条目

**Files:**
- Modify: `/tmp/shuling-src/SKILL.md`（异常处理表末尾）

- [ ] **Step 1: 在表格最后一行 `| 数据库不存在 | ... |` 之后追加：**

```markdown
| 模型 API 报错（404/401/503/空响应） | 告知用户切换模型或稍后重试，**最多 1 次重试，失败即停**，不要在同一会话反复重试同一失败调用 |
| 配置已存在但 preflight 检查超时 | 视为已配置（preflight 会基于 `state.json` 自动放宽），继续后续流程 |
| `setup_completed: true` 但某 check 当前报 `error` | 仅修复该项，**不要重新走整个安装流程** |
| `xhs.sh login` 已是登录态 | 视为成功，**不要重复扫码** |
| 用户重复输入相同句子（≥2 次） | 上次明显没成。**换思路**：检查上一次失败原因，向用户说明，询问要换路径还是给更多信息 |
| 用户主动提议替代方案 | **优先采纳**用户方案；除非有强证据该方案不可行，否则不要绕回默认路径 |
| context compaction 后 task list 含"workflow"字样 | 标记为 cancelled 并解释；按当前 SKILL.md 重新规划任务 |
```

### Task E7: skills/shuling/SKILL.md 路径同步

**Files:**
- Modify: `/tmp/shuling-src/skills/shuling/SKILL.md:122,133`

- [ ] **Step 1: 替换 122 行**

将 `如果 \`workflow/xhs-automation/knowledge-base/README.md\` 不存在，按顺序执行：` 改为：

`如果 \`knowledge-base/README.md\` 不存在（相对 skill 根目录），按顺序执行：`

- [ ] **Step 2: 替换 133 行**

将 `根据选择，编辑 \`workflow/xhs-automation/config/runtime.env\` 中的 LLM_PROVIDER、LLM_API_KEY、LLM_BASE_URL、LLM_MODEL。` 改为：

`根据选择，编辑 \`config/runtime.env\` 中的 LLM_PROVIDER、LLM_API_KEY、LLM_BASE_URL、LLM_MODEL。`

### Task E8: 最终扫描确认无残留

- [ ] **Step 1: grep workflow/xhs-automation 残留**

Run: `grep -n "workflow/xhs-automation" /tmp/shuling-src/SKILL.md /tmp/shuling-src/skills/shuling/SKILL.md`
Expected: 仅出现在"禁止"或"另一个项目"上下文中（核心原则第 5 条 + 配置位置说明），其它位置应无残留

- [ ] **Step 2: grep Telegram 残留**

Run: `grep -n "Telegram\|telegram" /tmp/shuling-src/SKILL.md /tmp/shuling-src/skills/shuling/SKILL.md`
Expected: 仅出现在"不在此配置任何 IM/通讯凭证（Telegram Token 等）"这种否定/边界说明上下文中

- [ ] **Step 3: grep 推送/通知 残留**

Run: `grep -n "推送\|通知" /tmp/shuling-src/SKILL.md`
Expected: 0 行（应已全部替换为返回/输出/告诉）

如有遗漏，逐一修正。

---

## 阶段 F：部署到 Mac + 重装 + 验证

### Task F1: 单文件 scp 推回 Mac

- [ ] **Step 1: 列出本地修改的文件**

Run:
```bash
ls -la /tmp/shuling-src/SKILL.md /tmp/shuling-src/scripts/preflight.py /tmp/shuling-src/scripts/xhs.sh /tmp/shuling-src/install.sh /tmp/shuling-src/skills/shuling/SKILL.md /tmp/shuling-src/workflow/xhs-automation/config/runtime.env.example
```

- [ ] **Step 2: scp 单文件推回（不删 Mac 上 untracked 内容）**

Run:
```bash
scp /tmp/shuling-src/SKILL.md weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/SKILL.md
scp /tmp/shuling-src/scripts/preflight.py weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/scripts/preflight.py
scp /tmp/shuling-src/scripts/xhs.sh weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/scripts/xhs.sh
scp /tmp/shuling-src/install.sh weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/install.sh
scp /tmp/shuling-src/skills/shuling/SKILL.md weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/skills/shuling/SKILL.md
scp /tmp/shuling-src/workflow/xhs-automation/config/runtime.env.example weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/workflow/xhs-automation/config/runtime.env.example
scp /tmp/shuling-src/docs/superpowers/plans/2026-04-17-shuling-skill-fix.md weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/docs/superpowers/plans/
```

### Task F2: Mac 上看 diff，等用户授权再 commit

- [ ] **Step 1: ssh 到 Mac 看 diff stat**

Run: `ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git diff --stat SKILL.md scripts/preflight.py scripts/xhs.sh install.sh skills/shuling/SKILL.md workflow/xhs-automation/config/runtime.env.example"`

- [ ] **Step 2: 把 diff 汇报给用户**

文字描述每个文件的增删行数，**等用户明确授权再继续 commit**。

- [ ] **Step 3: 用户确认后 commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add SKILL.md scripts/preflight.py scripts/xhs.sh install.sh skills/shuling/SKILL.md workflow/xhs-automation/config/runtime.env.example docs/superpowers/plans/2026-04-17-shuling-skill-fix.md && git commit -m 'fix(skill): 路径统一 + 渠道解耦（Telegram 移除）+ state.json 业务路由 + preflight 健壮化'"
```

### Task F3: 在 Mac 上重装 skill

- [ ] **Step 1: 重跑 install.sh（无交互式输入）**

Run: `ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && bash install.sh </dev/null 2>&1" | tail -60`

Expected:
- rsync OK
- "config/runtime.env 已存在，保留" — 用户的 token、画像、DB 完整保留
- 末尾环境预检：MCP ok / 画像 ok / 图片 API optional

### Task F4: 跑 preflight.py 验证 setup_completed

- [ ] **Step 1: 在安装目录跑 preflight**

Run: `ssh weiyong@100.79.106.110 "python3 ~/.hermes/skills/social-media/shuling/scripts/preflight.py"`

Expected:
- JSON 输出含 `"setup_completed": true`（MCP ok + profile_created 已写入 state）
- `state.json` 落在 `~/.hermes/skills/social-media/shuling/config/state.json`

- [ ] **Step 2: 看 state.json 内容**

Run: `ssh weiyong@100.79.106.110 "cat ~/.hermes/skills/social-media/shuling/config/state.json"`

Expected: 含 `mcp_configured: true` + `profile_created: true`，可能 `setup_completed: true`

### Task F5: 验证用户数据未被覆盖

- [ ] **Step 1: 检查 token 仍在（runtime.env 历史值用户已写入，重装应保留）**

Run: `ssh weiyong@100.79.106.110 "cat ~/.hermes/skills/social-media/shuling/config/runtime.env"`

Expected: 看到原有 MCP_URL（用户自定义的 `/mcp` 后缀也保留）。**注意**：原 runtime.env 里有 XHS_TELEGRAM_*，重装后会保留——但 skill 不再引用，无副作用。

- [ ] **Step 2: 画像未被覆盖**

Run: `ssh weiyong@100.79.106.110 "cat ~/.hermes/skills/social-media/shuling/knowledge-base/profile.json"`

Expected: 仍是用户上次的画像（AI 工具推荐与科技资讯），未被重置

### Task F6: 用 hermes 实操验证

- [ ] **Step 1: 让用户在 hermes 里说一句正常对话（如"今天发什么"）**

期待行为（与之前对照）：
- AI 不再问 Telegram 配置
- AI 直接读 profile.json 不再问"你想做什么方向"
- AI 不去 grep workflow/xhs-automation 下文件
- 如果用户说"我给你 cookie"，AI 立刻调 `xhs.sh import-cookie`，不绕回扫码

如果观察到不符预期的行为，记录具体场景，下一轮迭代修订 SKILL.md 措辞。

---

## Self-Review Checklist

- [x] **Telegram 是否完全从 skill 剥离？** preflight 删 check_telegram；install.sh 删 7.5；SKILL.md 0 节删 Telegram 段、配置表删 Telegram 行；runtime.env.example 删 XHS_TELEGRAM_*；setup_completed 不再依赖 telegram_configured
- [x] **路径是否完全统一？** preflight 路径常量重写；SKILL.md 顶部加禁读 workflow；E8 grep verify
- [x] **state.json 写入和读取是否一致？** preflight 写到 `CONFIG_DIR/state.json`，SKILL.md 0a 段引用同一字段名（mcp_configured/profile_created/cold_start_done）
- [x] **install.sh 是否保护用户数据？** C1 加 --exclude config/profile.json/preferences.json/patterns.md/xhs.db
- [x] **冷启动业务流程是否独立于 Telegram？** 是——E4 明确说明
- [x] **是否覆盖深度分析的 4 个新问题？** B1 cron 哑火→0a 业务路由；B2 重复问画像→E4；B3 读 workflow→E2 核心原则第 5 条；B4 用户给 cookie→E3 登录策略 + E6 异常表
- [x] **渠道脱敏是否完整？** E5 共 10 处替换 + E8 grep 0 行验证
- [x] **xhs.sh import-cookie 在 MCP 不支持时是否给清晰反馈？** 是——mcp_call 失败会返回 JSON 错误

---

## Execution Handoff

**Plan saved to `/tmp/shuling-src/docs/superpowers/plans/2026-04-17-shuling-skill-fix.md`**

推荐 **Inline Execution**：阶段 A→B→C→D→E→F 顺序较强（路径决定 SKILL.md 措辞，SKILL.md 0a 决定 preflight 输出契约），并行收益不大；本计划阶段 D（runtime.env.example）独立，可与阶段 B/C 并行。

执行节奏：
1. 阶段 A 完成后跑 `python3 -c "ast.parse(...)"` 验证语法
2. 阶段 B/C/D 完成后 `bash -n` + 文件存在性验证
3. 阶段 E 完成后跑 E8 三个 grep 校验
4. 阶段 F 由用户在 Mac 上观察实际安装与 hermes 调用结果；F2 commit、F3 重装、F6 实操触发前都需用户授权
