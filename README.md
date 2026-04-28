# 薯灵 (ShuLing)

> Stateful Creator Agent for 小红书博主 — 通过 SKILL.md 接入 Claude Code / Codex / Hermes，业务大脑在 `agent/playbook/`。

[![Version](https://img.shields.io/badge/version-3.0.0-blue)](VERSION)
[![Codename](https://img.shields.io/badge/codename-Stateful%20Creator%20Agent-green)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-BSL%201.1-orange)](#许可)
[![Website](https://img.shields.io/badge/🌐_website-shuling.pages.dev-f97316)](https://shuling.pages.dev)

📦 **v3.0.0** · 2026-04-27 · [CHANGELOG](CHANGELOG.md) · [UPGRADE](UPGRADE.md) · [Architecture](docs/architecture.md)

🌐 **官网**：[https://shuling.pages.dev](https://shuling.pages.dev)（双语介绍页，源码同步在 `site/landing/`）

---

## 快速导航

- 🆕 **新博主从零起步** → [路径 A](#路径-a新博主从零起步)
- 📈 **已有账号存量接入** → [路径 B](#路径-b老博主存量接入)
- ⬆️ **从 v2.x 升级到 v3.0** → [升级 §v2→v3](#从-v2x-升级到-v30)
- 🤖 **AI 开发者 / 想借鉴架构** → [三层架构速读](#三层架构速读) ｜ [docs/architecture.md](docs/architecture.md)

---

## 目录

- [这是什么](#这是什么)
- [三层架构速读](#三层架构速读)
- [v3.0 重构纪律](#v30-重构纪律)
- [给谁用 / 不是什么](#给谁用)
- [前置依赖](#前置依赖)
- [快速开始](#快速开始)
- [日常使用](#日常使用)
- [部署到 AI 平台](#部署到-ai-平台)
- [升级](#升级)
- [架构与目录](#架构与目录)
- [配置参考](#配置参考)
- [文档地图](#文档地图)
- [版本管理与路线图](#版本管理与路线图)
- [贡献与许可](#贡献与许可)

---

## 这是什么

**一句话**：把你的 AI 助手变成懂小红书的博主搭档——选题、创作、发布、复盘形成闭环，历史数据驱动自进化，越用越懂你。

v3.0 起，薯灵的形态明确分成 **三层**：

- **协议适配层**（`SKILL.md` ≤ 150 行）：被 Claude Code / Codex / Hermes 装载时的入口，只做识别意图、初始化、路由、全局约束。
- **业务内核**（`agent/`）：playbook + scripts + schemas + prompts + policies + migrations + 用户态。AI 真正"读"的剧本在这里。
- **部署运维层**（`ops/`）：安装、cron 模板、verify 门禁、布局迁移。只在源仓库里，不会被打包进 target。

详细决策与 12 条总原则见 [`docs/adr/0001-stateful-creator-agent.md`](docs/adr/0001-stateful-creator-agent.md)，完整架构图与三层职责见 [`docs/architecture.md`](docs/architecture.md)。

---

## 三层架构速读

```
Claude Code / Codex / Hermes / OpenClaw     ← 宿主平台
            ↓ 装载
SKILL.md  (≤ 150 行)                         ← 协议适配层：入口 / 路由 / 全局约束
            ↓ 第 4 步：路由
agent/playbook/00-routing.md                 ← 业务内核入口
  ├─ 01-onboarding-new           新博主冷启动
  ├─ 02-onboarding-existing      老博主存量接入
  ├─ 03-daily-flow               选题 / 创作 / 起稿
  ├─ 04-publish-flow             发布 + meta.json + 图片
  ├─ 05-review                   夜间复盘 / 周日深度回顾
  ├─ 06-learning-loop            自进化算法（公式权威）
  ├─ 07-comment-insights         评论提炼
  ├─ 08-compliance               schema + 内容合规
  └─ 09-troubleshooting          异常总入口
            ↓ 调用
agent/scripts/  + agent/data/xhs.db  + agent/knowledge-base/
            ↑
ops/  仅在源仓库（install / cron / verify / layout-migrations）
```

每次 SKILL.md 被装载，AI 必须按"启动协议"4 步走：`ensure-runtime-layout → ensure-schema → preflight → 读 00-routing.md`。其中前两步是 v3.0 新增的 **runtime self-healing**，让"只 `git pull` 不跑安装"的用户也能升级。

---

## v3.0 重构纪律

ADR-0001 锁定了 4 条不可让步的工程纪律，所有贡献者必须遵守：

1. **路径单一来源**：`agent/scripts/_paths.sh` 是仓库内所有运行时路径的唯一权威。所有 shell 脚本必须 `source _paths.sh`，禁止 hardcode `agent/data/...`、`config/...` 等字面量。verify 第 29 条门禁。
2. **playbook frontmatter 可机器校验**：每份 playbook 都带 YAML frontmatter（`id / title / when / needs / calls / writes / preconditions / on_failure / version / last_updated`）。verify 第 4-6、28、32、34 条覆盖。
3. **算法权威唯一**：`weight` / `confidence_level` / `ε-greedy` / `consecutive_rejects` 公式只在 `06-learning-loop.md` 出现。其它 playbook 必须 cross-ref，不允许复述。verify 第 31 条。
4. **34 条 verify 门禁**：发版前 `bash ops/verify/pre-submit-verify.sh` 必须全绿（v2.x 是 21 条本地回归，v3.0 升到 34 条，覆盖 active vs inactive 分区、playbook 调用图无环、package 白名单等）。

---

## 给谁用

| 身份 | 薯灵做什么 | 入口 |
|---|---|---|
| 🆕 **新博主**（还没发或刚开始） | 三问对话建画像 → 竞品冷启动 → 每日选题/起稿/发布/复盘 | [路径 A](#路径-a新博主从零起步) |
| 📈 **老博主**（已发 30~1000+ 条） | 批量导入历史 → AI 反推画像 → 挖掘已验证的 patterns → 账号体检报告 → 历史加权的日常优化 | [路径 B](#路径-b老博主存量接入) |
| 🤖 **AI 智能体开发者** | 三层架构、playbook frontmatter 规范、JSON Schema 契约、34 条 verify 门禁、ADR / 反模式禁令 | [docs/architecture.md](docs/architecture.md) |

### 不是什么

- ❌ **不是**小红书自动化工具（没有批量发布、不刷量、不绕风控）
- ❌ **不是**内容农场（08-compliance 合规规则兜底，不做标题党 / 同质化）
- ❌ **不是**独立运行机器人（必须搭一个能读 SKILL.md 的 AI 助手）
- ❌ **不假设通讯渠道**（Telegram / 微信等由宿主 agent 负责）

---

## 前置依赖

| 依赖 | 用途 | 安装 |
|---|---|---|
| **AI 助手** | 大脑，装载 SKILL.md 驱动 playbook | [Claude Code](https://claude.com/claude-code) / [Codex](https://github.com/openai/codex) / [Hermes](https://github.com/anthropics/hermes) / OpenClaw 任选 |
| **xiaohongshu-mcp** | 小红书 MCP（搜索/详情/发布/评论/登录） | [xpzouying/xiaohongshu-mcp](https://github.com/xpzouying/xiaohongshu-mcp)；详见 [docs/runbooks/mcp-setup.md](docs/runbooks/mcp-setup.md) |
| **Python 3 / sqlite3 / jq** | DB / 生图 / JSON | macOS: `brew install sqlite jq`；Linux: `apt install sqlite3 jq` |
| **Gemini 图片 API**（**必需**） | AI 生图（唯一路径，无 HTML 降级） | Gemini Key（https://aistudio.google.com/app/apikey） |
| **NoteRx API**（可选） | 五维诊断 | 配 `NOTERX_API_KEY` 才启用 |

> ❌ **不在本 skill 范围**：Telegram / 微信等 IM 通讯凭证——由宿主 agent 或你的 AI 平台管理。

---

## 快速开始

### 安装

```bash
git clone git@github.com:AI-flower/shuling.git && cd shuling

# 推荐：直接用 ops/install.sh
bash ops/install.sh                       # 自动检测平台 + 依赖预检 + 初始化 + 生成配置

# 兼容入口：根 install.sh 是 v3.0 stub，原样转发到 ops/install.sh（v3.2 移除）
bash install.sh                           # 等同于 bash ops/install.sh

# 其他模式
bash ops/install.sh --check               # 只自检不动手
bash ops/install.sh --dry-run             # 列出将做的所有动作
bash ops/install.sh doctor                # 12 项 target 健康检查（v3.0+）
SHULING_ASSUME_YES=1 bash ops/install.sh  # CI / 远程非交互
```

### 路径 A：新博主（从零起步）

```bash
# 1. 安装（默认 new，直接回车）
bash ops/install.sh

# 2. 登录小红书（二选一）
#    扫码:   AI 调 agent/scripts/xhs.sh login 给二维码链接
#    Cookie: 对话里说 "我给你 cookie：<浏览器 F12 复制的完整串>"
#    详细图文 → docs/runbooks/mcp-setup.md

# 3. 建立画像（在 AI 里说 "我想做小红书博主"）
#    AI 三问: 做什么方向 / 目标受众 / 风格偏好
#    走 agent/playbook/01-onboarding-new.md

# 4. 日常
#    "帮我发小红书"   → 完整发布流程
#    "今天发什么"     → 选题研究
#    "看看昨天的数据" → 数据复盘
```

### 路径 B：老博主（存量接入）

```bash
# 1. 老博主模式安装
bash ops/install.sh --mode=existing-creator

# 2. 登录（扫码或 Cookie，同路径 A）

# 3. 对话里说 "我已经在运营小红书，帮我接入"
#    AI 按 agent/playbook/02-onboarding-existing.md 自动走 5 步:
#      1) 确认账号登录
#      2) 批量导入最近 200 条历史（≈30 分钟，带节流保护）
#      3) 自动分类 (topic_type / title_pattern / content_style)
#      4) 读 30 条样本反推画像 → 展示给你确认/微调
#      5) 出账号体检报告 audit-YYYY-MM-DD.md + 挖 patterns 种子

# 完成后系统已具备 6 个月+ 的历史记忆，第一条薯灵发帖即达历史 P50 水平
```

手动跑：

```bash
bash agent/scripts/import-existing.sh --limit 200            # 批量导入（可 --resume 断点续跑）
bash agent/scripts/audit-report.sh --extract-patterns        # 出体检报告 + patterns 候选
```

详细设计 → [docs/plans/existing-creator-onboarding.md](docs/plans/existing-creator-onboarding.md)

> **首次安装后**：`agent/config/runtime.env`、`agent/config/state.json`、`agent/knowledge-base/profile.json`、`agent/data/xhs.db` 等是你的私人数据，已被 `.gitignore` 屏蔽。**不要 `git add -f` 这些文件**。

---

## 日常使用

### 🗣️ 对话指令（触发 AI 业务）

| 说这句 | 做什么 | 进入剧本 |
|---|---|---|
| "帮我发小红书" | 完整发布流程（选题 → 创作 → 图片 → 发布） | 03 → 04 |
| "今天发什么" | 只跑选题研究 | 03 |
| "起个稿子" | 只跑创作 | 03 |
| "看看昨天的数据" / "复盘" | 手动触发复盘 | 05 |
| "最近怎么样" | 近期小结 | 05 |
| "我想换方向" | 更新画像 | 01 |
| "我给你 cookie：..." | Cookie 登录（绕过扫码） | 09 |

### 🔧 命令行（手动工具）

```bash
# 健康检查
bash ops/install.sh --check                          # 依赖 + 平台 + 版本对比
bash ops/install.sh doctor                           # 12 项 target 健康表（v3.0+）
python3 agent/scripts/preflight.py --human           # 人类可读彩色自检

# 小红书 MCP（agent/scripts/xhs.sh 统一入口）
bash agent/scripts/xhs.sh status                     # 登录态
bash agent/scripts/xhs.sh login                      # 获取二维码
bash agent/scripts/xhs.sh import-cookie '<cookie>'   # Cookie 登录
bash agent/scripts/xhs.sh log --summary              # 请求日志聚合（v2.1.1+）

# 数据库（agent/scripts/db.sh 统一入口）
bash agent/scripts/db.sh ensure-runtime-layout       # v2→v3 用户态自愈（v3.0+ 启动协议第 1 步）
bash agent/scripts/db.sh ensure-schema               # 自动应用 pending migration（v3.0+ 第 2 步）
bash agent/scripts/db.sh init                        # 初始化/补建 11 表（幂等）
bash agent/scripts/db.sh query-posts --today
bash agent/scripts/db.sh query-posts --source imported
bash agent/scripts/db.sh query-preferences

# 老博主专用
bash agent/scripts/import-existing.sh --limit 200    # 批量导入历史
bash agent/scripts/import-existing.sh --resume       # 断点续跑
bash agent/scripts/audit-report.sh --extract-patterns
```

完整脚本契约见 [agent/scripts/README.md](agent/scripts/README.md)。

---

## 部署到 AI 平台

| 平台 | 状态 | 触发 | cron 模板 |
|---|---|---|---|
| [Claude Code](docs/runbooks/platform/claude-code.md) | ✅ | 对话 + `/loop 8h ...` | [`ops/cron/claude-code.md`](ops/cron/claude-code.md) |
| [Codex](docs/runbooks/platform/codex.md) | ✅ | 对话 | 手动触发 |
| [Hermes](docs/runbooks/platform/hermes.md) | ✅ | cron job + `prompt: 使用 shuling skill` | [`ops/cron/hermes.yaml.example`](ops/cron/hermes.yaml.example) |
| OpenClaw | ✅ | 兼容 `agents/` 目录规范 | 通用 agents 兜底 |
| macOS launchd | ✅ | OS 级 user agent | [`ops/cron/launchd.plist.example`](ops/cron/launchd.plist.example) |
| Linux systemd | ✅ | OS 级 user timer | [`ops/cron/systemd.timer.example`](ops/cron/systemd.timer.example) |

> 一份 SKILL.md 在所有平台产生相同业务行为；00-routing.md 第 3 步识别平台，仅用于调用各自特有能力（如 Hermes cron、Claude `/loop`）。
>
> 薯灵**不会自动启用任何 cron**——`ops/cron/` 是模板库，用户必须显式选模板 + 自己装。详见 [`ops/cron/README.md`](ops/cron/README.md)。

---

## 升级

### 从 v2.x 升级到 v3.0

v3.0 是 **BRAIN +1 breaking** 升级，目录布局与 SKILL.md 形态都有变化。**升级前请备份**用户态数据（`data/xhs.db`、`config/runtime.env`、`knowledge-base/`）。

```bash
cd /path/to/shuling
git fetch --tags origin && git checkout main && git pull

bash ops/install.sh --check               # 看清要做哪些事
bash ops/install.sh upgrade-all --json    # 批量升级所有 target，机器可读 JSON
```

`upgrade-all` 升级模式做 4 件事：

1. 调 `ops/layout-migrations/v2-to-v3.sh` 把 target 内 v2 布局迁到 v3（用户态文件不动）
2. 跑 `ensure-runtime-layout`：copy-first 把 `data/xhs.db` 等迁到 `agent/data/xhs.db`，源文件保留至 v3.2 删除窗口
3. 按 `__migrations` 表台账跑 pending DB migration（幂等）
4. 跑 `ensure-schema`：自动应用 state migration，失败进入 read-only 降级模式

详细步骤、回滚方案与 troubleshooting 见 [UPGRADE.md](UPGRADE.md) 的 v2→v3 章节。

### v3.0 内部小版本升级

```bash
git pull && bash ops/install.sh upgrade-all
```

正常情况下零交互、保留所有用户私人数据。

### ops/install.sh 子命令速查

```bash
bash ops/install.sh                              # install
bash ops/install.sh upgrade-all                  # 批量升级所有 target
bash ops/install.sh --check                      # 只自检不写文件
bash ops/install.sh --dry-run                    # 预演
bash ops/install.sh --target ~/.myagents/skills/shuling   # 显式指定部署目标
bash ops/install.sh --mode=existing-creator      # 老博主模式
bash ops/install.sh doctor [TARGET]              # 12 项 target 健康检查
bash ops/install.sh migrate-layout [TARGET]      # v2 → v3 布局迁移（单 target）
bash ops/install.sh rollback-to-v2 <TARGET>      # 输出回滚指引（不动用户态）
```

逐版本升级步骤 → [UPGRADE.md](UPGRADE.md)

---

## 架构与目录

> 完整三层心智模型 + ASCII 架构图见 [`docs/architecture.md`](docs/architecture.md)。

### 数据流（一条主线）

```
AI → SKILL.md（启动协议 4 步）
       ↓ 第 4 步路由
agent/playbook/00-routing.md → 选具体剧本
       ↓
具体 playbook → 调 agent/scripts/* → 读写 agent/data/xhs.db + agent/knowledge-base/
       ↓
状态落 agent/config/state.json，下次路由读 state 决定下一步
```

所有自动化（午/晚间发布 + 夜间复盘 + 周日回顾）走同一条主线，由 cron 唤起助手 → 助手读 SKILL.md → 路由到对应 playbook。

### 顶层目录

```
shuling/
├── SKILL.md                # 协议适配层（≤150 行）
├── VERSION                 # 版本号 + BRAIN/HANDS/CALIB 清单
├── README.md / CHANGELOG.md / UPGRADE.md / RELEASING.md
├── install.sh              # v3.0 兼容 stub，转发到 ops/install.sh（v3.2 移除）
├── agents/                 # 多平台元数据（OpenClaw 兼容）
│
├── agent/                  # ───── 业务内核（进 target 包）─────
│   ├── playbook/           # 9 个剧本 + _shared/（emoji 词典 / 决策档映射 / 大纲范例）
│   ├── scripts/            # 手脚层（_paths.sh 是路径单一来源）
│   ├── schemas/            # JSON Schema 数据契约（4 + 1 frontmatter）
│   ├── prompts/            # 图像生成 prompt 模板
│   ├── policies/           # 内容规则 / 节流 / 限额
│   ├── migrations/db/      # SQLite migration（v*.sh + _guard.sh + __migrations）
│   ├── migrations/state/   # JSON / knowledge-base 结构迁移
│   ├── config/             # runtime.env / state.json / .layout-v3.done（用户态）
│   ├── data/               # xhs.db（用户态，11 张表）
│   └── knowledge-base/     # profile / preferences / patterns / evolution-log（用户态）
│
├── ops/                    # ───── 部署运维层（不进 target）─────
│   ├── install.sh          # 7 子命令：install / upgrade-all / dry-run / check / doctor / migrate-layout / rollback-to-v2
│   ├── doctor.sh           # 12 项 target 健康检查
│   ├── layout-migrations/  # v2-to-v3.sh
│   ├── upgrade-hooks/      # 单参数+单行 JSON 契约的副作用 hook
│   ├── cron/               # 4 平台 cron 模板（hermes / claude-code / launchd / systemd）
│   └── verify/             # 34 条门禁 + pre-submit-verify.sh
│
├── build/                  # ───── 工程支撑层（不进 target）─────
│   ├── package-skill.sh    # 按白名单 rsync 到 dist/
│   ├── check-package.sh    # 校验 dist/ 顶层只有 4 项
│   ├── check-version-sync.sh
│   ├── check-playbook-frontmatter.py
│   └── check-active-region-refs.py
│
├── docs/                   # 文档（adr / plans / runbooks / reference）
├── site/                   # landing page 源码
├── marketing/              # v2.x 推广物料
├── legacy/                 # 归档（old-xhs-mcp-skill / archive / promotion-archive / shuling-full-spec.md）
└── dist/                   # package-skill.sh 输出（gitignored）
```

`agents/`（顶层）+ `agent/`（业务内核）+ `SKILL.md` + `VERSION` 是唯一会被打包到 target 的 4 个顶级条目；其它目录全部留在源仓库。verify 第 12-14 条强制约束。

---

## 配置参考

所有 `XHS_*` / `SHULING_*` / `MCP_*` 变量可在 `agent/config/runtime.env` 或进程环境中设置。

### 通用配置

| 变量 | 默认 | 作用 |
|---|---|---|
| `MCP_URL` | `http://localhost:18060/mcp` | xiaohongshu-mcp 服务地址 |
| `XHS_CACHE_DIR` | `~/.cache/shuling` | 节流戳 + quota + session + import-state 目录 |
| `SHULING_ASSUME_YES` | `0` | 设 `1` 等同 `--yes`，所有交互用默认值 |
| `SHULING_CREATOR_MODE` | 空 | 设 `existing` 等同 `--mode=existing-creator` |
| `SHULING_DB` | `agent/data/xhs.db` | DB 路径覆盖（v2.4.2+ 兼容） |
| `SHULING_AGENT_ROOT` | 自动推导 | agent/ 根路径覆盖（v3.0+） |
| `XHS_MCP_URL` | 空 | 预填 MCP URL（避免 prompt 卡住） |
| `IMAGE_GEN_API_KEY` | 空 | Gemini 生图 Key（必需，写入 `agent/config/runtime.env`） |
| `IMAGE_GEN_MODEL` | `gemini-3-pro-image-preview` | 图像模型（Nano Banana Pro，中文渲染稳） |
| `IMAGE_GEN_PROTOCOL` | `gemini-native` | 也可设 `openai-chat`（走兼容代理）；不配置无 HTML 降级 |
| `NOTERX_API_KEY` | 空 | NoteRx 五维诊断 Key（不配则跳过 05 诊断步骤） |

### 节流与限额（profile `v1-conservative`，v2.1.0+）

| 接口 | MIN_GAP | 日上限 |
|---|---|---|
| `search_feeds` | 20s | 15 / 日 |
| `get_feed_detail` | 10s | 50 / 日 |
| `list_feeds` | 15s | 20 / 日 |
| `publish_content` | 300s | **2 / 日** |
| `post_comment_to_feed` | 180s | 5 / 日 |
| `user_profile` | 30s | 20 / 日 |

| 变量 | 默认 | 作用 |
|---|---|---|
| `XHS_DISABLE_THROTTLE` | `0` | 设 `1` 跳过节流（**账号安全自理**） |
| `XHS_DISABLE_QUOTA` | `0` | 设 `1` 跳过日限额（**账号安全自理**） |
| `XHS_REUSE_SESSION` | `0` | 设 `1` 启用 session 复用（opt-in，上游 2-3 次后失效） |
| `XHS_SESSION_TTL` | `120` | session 复用 TTL 秒数 |
| `XHS_DISABLE_LOG` | `0`（开启） | 设 `1` 跳过写 `request_log` 表 |

请求日志查询：

```bash
bash agent/scripts/xhs.sh log --limit 10            # 最近 10 条
bash agent/scripts/xhs.sh log --summary             # 按 tool × status 聚合
bash agent/scripts/xhs.sh log --tool search_feeds --days 7
```

---

## 文档地图

| 你想做什么 | 去读 |
|---|---|
| 想先看项目介绍页（中英文） | [shuling.pages.dev](https://shuling.pages.dev) |
| 我是 AI / 想知道整个业务怎么运行 | [`SKILL.md`](SKILL.md) → [`agent/playbook/00-routing.md`](agent/playbook/00-routing.md) |
| 我想理解 v3.0 三层架构 | [`docs/architecture.md`](docs/architecture.md) |
| 我是用户 / 每次发版有什么变化 | [`CHANGELOG.md`](CHANGELOG.md) |
| 我要从 v2.x 升级到 v3.0 | [`UPGRADE.md`](UPGRADE.md) |
| 我要自己发版 | [`RELEASING.md`](RELEASING.md) |
| v3.0 重构决策（为什么这样拆） | [`docs/adr/0001-stateful-creator-agent.md`](docs/adr/0001-stateful-creator-agent.md) |
| playbook 拆分决议 | [`docs/adr/0002-playbook-split-decisions.md`](docs/adr/0002-playbook-split-decisions.md) |
| xiaohongshu-mcp 装不上 / cookie 怎么拿 | [`docs/runbooks/mcp-setup.md`](docs/runbooks/mcp-setup.md) |
| 老博主接入流程的完整设计 | [`docs/plans/existing-creator-onboarding.md`](docs/plans/existing-creator-onboarding.md) |
| 脚本契约（命令清单 + 输入输出） | [`agent/scripts/README.md`](agent/scripts/README.md) |
| 数据契约（schema + 表 + 文件） | [`agent/schemas/_meta.md`](agent/schemas/_meta.md) |
| 我的平台（Claude / Codex / Hermes）怎么配 | [`docs/runbooks/platform/`](docs/runbooks/platform/) |
| cron 模板（自动化） | [`ops/cron/`](ops/cron/) |
| 灾备 / 回滚到 v2 | [`docs/runbooks/disaster-recovery.md`](docs/runbooks/disaster-recovery.md) |

---

## 版本管理与路线图

### 版本号语义：BRAIN.HANDS.CALIB

- **BRAIN** +1：SKILL.md / playbook 核心流程 / 自进化算法 / AI 行为方式变化 → **major**，breaking
- **HANDS** +1：scripts/ 扩展 / DB schema 变化 / MCP 接口变化 → **minor**，一般非 breaking
- **CALIB** +1：阈值 / 文档 / bugfix / prompt 微调 → **patch**，用户无感升级

版本号决策树见 [RELEASING.md](RELEASING.md#版本号决策树brainhandscalib)。

### 路线图

| 版本 | 主题 | 状态 |
|---|---|---|
| v1.x | OpenClaw + Python workflow 双线架构 | 已归档 |
| v2.0.0 | Skill-as-Brain 重构 | ✅ |
| v2.1.0 | Anti-Ban Shield（节流 + 限额 + session） | ✅ |
| v2.1.1 | Request Log（MCP 调用全量落表） | ✅ |
| v2.1.2 | Release Polish（CHANGELOG/UPGRADE/RELEASING + migrations） | ✅ |
| v2.1.3 | Friendly Onboarding（install 六模式 + preflight --human + schemas） | ✅ |
| v2.2.0 | Existing Creator Support（老博主接入 + 体检 + patterns 种子） | ✅ |
| v2.2.1 | Migration Safety Fix | ✅ |
| v2.3.0 | Pure Image Pipeline（去 HTML 截图降级 + Gemini 必需） | ✅ |
| v2.4.0 | Agent-Friendly Upgrade Infrastructure（upgrade-all + upgrade-hooks + `__migrations` + schema drift） | ✅ |
| v2.4.1 | Install reliability patch（4 处 verify 修复） | ✅ |
| v2.4.2 | Source-Target Isolation Patch（5 处 + pre-submit-verify 21 项） | ✅ |
| v2.4.3 | Business Source License Shift（BSL 1.1） | ✅ |
| **v3.0.0** | **Stateful Creator Agent（三层架构 + playbook 拆分 + ensure-* 自愈 + 34 条 verify）** | ✅ **当前** |
| v3.1 | Policies YAML 拆分（throttle / quota 从硬编码移到 `agent/policies/*.yaml`） | 规划中 |
| v3.2 | v2 兼容 stub 移除（根 `install.sh` 移除 / target 内 v2 旧路径删除窗口） | 规划中 |
| v4.0 | 触发条件之一满足时考虑（playbook >20 / 多账户 >100k posts / agent daemon 化） | 远期 |

ADR-0001 末尾的 v4.0 退出条件见 [`docs/adr/0001-stateful-creator-agent.md` §退出条件](docs/adr/0001-stateful-creator-agent.md#退出条件何时考虑-v40)。

---

## 贡献与许可

这是个人项目，但代码开源借鉴欢迎：

- **Fork + 本地改 + 测试**（至少跑通 `bash ops/install.sh --check` + `bash ops/verify/pre-submit-verify.sh` 全绿）
- **遵守 [RELEASING.md](RELEASING.md) 的版本号决策树** + ADR-0001 的 12 条总原则
- **CHANGELOG 写给用户看**（参考已有条目格式）
- 发 PR 时附上 verify 结果（截图或 JSON 输出）

如果你在做类似"AI Skill + MCP + 自进化知识库"的项目，可以直接借鉴：

- 三层架构（协议适配 / 业务内核 / 部署运维）
- playbook frontmatter + 算法权威唯一性 + 路径单一来源
- `agent/schemas/` + 写入前自校验协议
- BRAIN.HANDS.CALIB 版本号语义
- 34 条 verify 门禁的工程化纪律

### 许可

本仓库当前采用 **Business Source License 1.1**。

- `Licensor`: AI-flower
- `Change Date`: 2030-04-23
- `Change License`: Apache-2.0
- `Additional Use Grant`: 个人非商业使用可直接使用；任何公司、组织或其他商业主体需要另行与作者洽谈商业许可

这意味着它是 **source-available**，不是 OSI 批准的开源许可。完整条款见 [LICENSE](LICENSE)。
