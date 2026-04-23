# 薯灵 (ShuLing)

> 小红书博主成长助手 — 选题、写稿、发布、复盘一体化，越用越懂你。

[![Version](https://img.shields.io/badge/version-2.3.0-blue)](VERSION)
[![Codename](https://img.shields.io/badge/codename-Pure%20Image%20Pipeline-green)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](#许可)
[![Website](https://img.shields.io/badge/🌐_website-shuling.pages.dev-f97316)](https://shuling.pages.dev)

🌐 **官网**：[https://shuling.pages.dev](https://shuling.pages.dev)（中英文双语介绍页，源码同步在 `landing/index.html`，可直接双击本地预览）

📦 **v2.3.0** · 2026-04-21 · [CHANGELOG](CHANGELOG.md) · [UPGRADE](UPGRADE.md) · [RELEASING](RELEASING.md)

---

## 快速导航

- 🆕 **新博主从零起步** → [路径 A](#路径-a新博主从零起步)
- 📈 **已有账号存量接入** → [路径 B（v2.2.0+）](#路径-b老博主存量接入v220)
- 🤖 **AI 开发者 / 想借鉴架构** → [Skill-as-Brain](#核心理念skill-as-brain) ｜ [SKILL.md](SKILL.md)

---

## 目录

- [这是什么](#这是什么)
- [核心理念：Skill-as-Brain](#核心理念skill-as-brain)
- [能力全景](#能力全景)
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

**一句话**：把你的 AI 助手变成懂小红书的博主搭档——从选题、创作、发布到复盘形成闭环，历史数据驱动自进化，越用越懂你。

### 给谁用

| 身份 | 薯灵做什么 | 入口 |
|---|---|---|
| 🆕 **新博主**（还没发或刚开始） | 三问对话建画像 → 竞品冷启动 → 每日选题/起稿/发布/复盘 | [路径 A](#路径-a新博主从零起步) |
| 📈 **老博主**（已发 30~1000+ 条） | 批量导入历史 → AI 反推画像 → 挖掘你自己已验证的 patterns → 账号体检报告 → 历史加权的日常优化 | [路径 B（v2.2.0+）](#路径-b老博主存量接入v220) |
| 🤖 **AI 智能体开发者** | 可借鉴的 Skill-as-Brain 架构、业务路由 §0a、JSON Schema 契约、反模式禁令工程化 | [SKILL.md](SKILL.md) |

### 不是什么

- ❌ **不是**小红书自动化工具（没有批量发布、不刷量、不绕风控）
- ❌ **不是**内容农场（§5 合规规则兜底，不做标题党 / 同质化）
- ❌ **不是**独立运行机器人（必须搭一个能读 SKILL.md 的 AI 助手）
- ❌ **不假设通讯渠道**（Telegram / 微信等由 hermes-agent 或你自己配）

---

## 核心理念：Skill-as-Brain

> **业务逻辑全部在 `SKILL.md` 里，AI 助手读了它就是大脑；`scripts/` 只是手脚，负责调 API、读写数据库、生成图片这些 AI 做不了的物理操作。**

这意味着：
- **换 AI 平台零成本**：只要能读 SKILL.md，hermes / Claude Code / Codex / OpenClaw 都通用
- **改流程不用改代码**：改 SKILL.md 即可，版本号 BRAIN+1
- **越用越聪明**：每次选择、每条数据都记录到 DB，驱动偏好进化
- **AI 自律有工程保障**：§0a 业务路由 + §0b 写入校验 + schemas/ JSON Schema + 反模式禁令

---

## 能力全景

### 🎯 核心业务流程（7 条主线）

| # | 流程 | 触发 | 产出 |
|---|---|---|---|
| 1 | **新手引导** | 第一次对话 / preflight 未通过 | `profile.json` + 环境就绪 |
| 2 | **老博主接入**（v2.2.0） | "已在运营" / `--mode=existing-creator` | 历史导入 + 画像反推 + patterns 种子 + 体检报告 |
| 3 | **选题研究** | "今天发什么" / cron 午间 | 带偏好加权的候选话题 |
| 4 | **内容创作**（RedInk 双阶段） | "帮我写一条" / cron 午/晚间 | 6-9 页大纲 + 正文（≤1000 字）+ 5-8 标签 |
| 5 | **图片生成**（两阶段封面参考） | 起稿后 | 封面 + 内容页图（Gemini 强制、中文模板） |
| 6 | **发布** | 起稿完成 | 小红书已发帖 + 本地 `posts` 记录 |
| 7 | **每日复盘 + 周回顾** | 夜间 cron / 周日加餐 | 日/周报 + patterns/anti-patterns 进化 + NoteRx 五维诊断 |

### 🧬 自进化引擎

| 机制 | 算法 / 规则 | 效果 |
|---|---|---|
| **偏好学习** | `bayesian-laplace-v1` — Laplace 平滑 + 集中度×样本因子 confidence | 小样本不冒进，口味稳时快收敛 |
| **选项递减** | confidence `≥0.75→1 选` / `≥0.5→2 选` / `<0.5→3 选` | 从"每次选几项"退化到"回一个'发'字" |
| **ε-greedy 探索** | 距上次探索 ≥7 天追加 1 个低 weight 类型 | 防过拟合，口味可演进 |
| **"换"信号回弹** | 连续 2 次"换" → confidence 强制回 0.45 | 防单方向钻牛角尖 |
| **Pattern 生命周期** | experimental → medium → high / deprecated | 标题 / 结构 / 图片 prompt 通用 |
| **收藏率驱动** | `≥5% → patterns + weight +0.1` / `<2% → anti-patterns - 0.1` | 真实数据反馈，无人为干预 |

### ⚙️ 运维与工程纪律

| 能力 | 细节 |
|---|---|
| **install.sh 六模式** | 默认 / `--check` / `--dry-run` / `--yes` / `--target <path>` / `--mode=<new\|existing>` |
| **preflight.py 双模式** | 给 AI 的结构化 JSON + 给人的 `--human` 彩色表（退出码分级 0/1/2） |
| **版本号** | BRAIN.HANDS.CALIB 三段语义，breaking 仅发生在 BRAIN+1 |
| **文档四件套** | CHANGELOG（📦用户可见+⬆️如何升级 双栏）/ UPGRADE / RELEASING / docs/features/（新特性 spec） |
| **Migrations** | `migrations/vX.Y.Z.sh` 按版本顺序幂等执行，失败可重试 |
| **JSON Schema 契约** | `schemas/` 约束 state / profile / preferences / audit-report 四份 JSON，AI 写入前自校验 |
| **Request Log** | v2.1.1+ MCP 调用全量落表（`tool × status × latency_ms × error_hint`） |
| **账号风控** | 分级节流 + 日限额 profile `v1-conservative`，触顶自动拒绝 |

### 🤖 AI 智能体协作（Brain 的工程纪律）

| 机制 | 位置 | 作用 |
|---|---|---|
| **§0a 业务路由** | SKILL.md | AI 进项目第一动作：跑 preflight → 读 state → 查表选下一步 |
| **§0b 平台识别 + 写入校验** | SKILL.md（v2.1.3+） | 按路径识别 hermes/claude/codex，写入 JSON 前按 schema 核对 |
| **§0c 老博主接入** | SKILL.md（v2.2.0+） | 5 步流程的 additive 分支 |
| **反模式禁令** | §0a / §0c | "不重复问画像 / 不放空 / 不绕回默认路径 / 用户主动方案优先"等明文纪律 |
| **异常处理矩阵** | §8 | 12 种异常场景 × 标准处理（含"模型 API 报错最多 1 次重试"等） |

---

## 前置依赖

| 依赖 | 用途 | 安装 |
|---|---|---|
| **AI 助手** | 大脑，读 SKILL.md 驱动流程 | [hermes](https://github.com/anthropics/hermes) / [Claude Code](https://claude.com/claude-code) / [Codex](https://github.com/openai/codex) / OpenClaw 任选 |
| **xiaohongshu-mcp** | 小红书 MCP（搜索/详情/发布/评论/登录） | [xpzouying/xiaohongshu-mcp](https://github.com/xpzouying/xiaohongshu-mcp)；详见 [docs/mcp-setup.md](docs/mcp-setup.md) |
| **Python 3 / sqlite3 / jq** | DB / 生图 / JSON | macOS: `brew install sqlite jq`；Linux: `apt install sqlite3 jq` |
| **Gemini 图片 API**（**必需**） | AI 生图（唯一路径） | Gemini Key（https://aistudio.google.com/app/apikey） |
| **NoteRx API**（可选） | 五维诊断 | 配 `NOTERX_API_KEY` 才启用 |

> ❌ **不在本 skill 范围**：Telegram / 微信等 IM 通讯凭证——由 hermes-agent 或你的 AI 平台管理。

---

## 快速开始

### 安装

```bash
git clone git@github.com:AI-flower/shuling.git && cd shuling
bash install.sh                        # 自动检测平台 + 依赖预检 + init DB + 生成配置

# 其他模式
bash install.sh --check                # 只自检不动手
bash install.sh --dry-run              # 列出将做的所有动作
SHULING_ASSUME_YES=1 bash install.sh   # CI / 远程非交互
```

### 路径 A：新博主（从零起步）

```bash
# 1. 安装（默认 new，直接回车）
bash install.sh

# 2. 登录小红书（二选一）
#    扫码:   AI 会调 scripts/xhs.sh login 给二维码链接
#    Cookie: 对话里说 "我给你 cookie：<浏览器 F12 复制的完整串>"
#    详细图文 → docs/mcp-setup.md

# 3. 建立画像（在 AI 里说 "我想做小红书博主"）
#    AI 三问: 做什么方向 / 目标受众 / 风格偏好

# 4. 日常
#    "帮我发小红书"   → 完整发布流程
#    "今天发什么"     → 选题研究
#    "看看昨天的数据" → 数据复盘
```

### 路径 B：老博主（存量接入，v2.2.0+）

```bash
# 1. 老博主模式安装
bash install.sh --mode=existing-creator

# 2. 登录（扫码或 Cookie，同路径 A）

# 3. 对话里说 "我已经在运营小红书，帮我接入"
#    AI 按 SKILL.md §0c 自动走 5 步:
#      1) 确认账号登录
#      2) 批量导入最近 200 条历史（≈30 分钟，带节流保护）
#      3) 自动分类 (topic_type / title_pattern / content_style)
#      4) 读 30 条样本反推画像 → 展示给你确认/微调
#      5) 出账号体检报告 audit-YYYY-MM-DD.md + 挖 patterns 种子

# 完成后系统已具备 6 个月+ 的历史记忆，第一条薯灵发帖即达历史 P50 水平
```

手动跑：
```bash
bash scripts/import-existing.sh --limit 200            # 批量导入（可 --resume 断点续跑）
bash scripts/audit-report.sh --extract-patterns        # 出体检报告 + patterns 候选
```
详细设计 → [docs/features/existing-creator-onboarding.md](docs/features/existing-creator-onboarding.md)

> **首次安装后**：`config/runtime.env`、`config/state.json`、`knowledge-base/profile.json`、`data/xhs.db` 等是你的私人数据，已被 `.gitignore` 屏蔽。**不要 `git add -f` 这些文件**。

---

## 日常使用

### 🗣️ 对话指令（触发 AI 业务）

| 说这句 | 做什么 |
|---|---|
| "帮我发小红书" | 完整发布流程（选题 → 创作 → 图片 → 发布） |
| "今天发什么" | 只跑选题研究 |
| "起个稿子" | 只跑创作 |
| "看看昨天的数据" / "复盘" | 手动触发复盘 |
| "最近怎么样" | 近期小结 |
| "我想换方向" | 更新画像 |
| "我给你 cookie：..." | Cookie 登录（绕过扫码） |

### 🔧 命令行（手动工具）

```bash
# 健康检查
bash install.sh --check                             # 依赖 + 平台 + 版本对比
python3 scripts/preflight.py --human                # 人类可读彩色自检

# 小红书 MCP（scripts/xhs.sh 统一入口）
bash scripts/xhs.sh status                          # 登录态
bash scripts/xhs.sh login                           # 获取二维码
bash scripts/xhs.sh import-cookie '<cookie 串>'     # Cookie 登录
bash scripts/xhs.sh quota                           # 当日调用计数
bash scripts/xhs.sh log --summary                   # 请求日志聚合（v2.1.1+）

# 数据库（scripts/db.sh 统一入口）
bash scripts/db.sh init                             # 初始化/补建表（幂等）
bash scripts/db.sh query-posts --today              # 今日帖
bash scripts/db.sh query-posts --source imported    # 老博主导入的帖（v2.2.0+）
bash scripts/db.sh query-preferences                # 偏好权重快照
bash scripts/db.sh query-undiagnosed --days 7       # 近 7 天未诊断的帖

# 老博主专用（v2.2.0+）
bash scripts/import-existing.sh --limit 200         # 批量导入历史
bash scripts/import-existing.sh --resume            # 断点续跑
bash scripts/audit-report.sh                        # 账号体检报告
bash scripts/audit-report.sh --extract-patterns     # 附带 patterns 候选
bash scripts/audit-report.sh --include-organic      # 含薯灵自己发的帖
```

---

## 部署到 AI 平台

| 平台 | 状态 | 触发 | 说明 |
|---|---|---|---|
| [Hermes](platform/hermes.md) | ✅ | cron job + `prompt: 使用 shuling skill` | **全自动每日发布 + 复盘（推荐）** |
| [Claude Code](platform/claude-code.md) | ✅ | 对话 + `/loop 8h ...` | VS Code 集成，支持定时 |
| [Codex](platform/codex.md) | ✅ | 对话 | 手动触发 |
| OpenClaw | ✅ | 兼容 `agents/` 目录规范 | 通用 agents 兜底 |

> 一份 SKILL.md 在所有平台产生相同业务行为；§0b 识别平台用于调用各自特有能力（如 hermes cron、claude /loop）。

---

## 升级

### 从旧版升级（自动识别）

```bash
cd /path/to/shuling
git fetch --tags origin && git checkout main && git pull
bash install.sh         # v2.1.2+ 自动识别部署版本并跑所需 migration
```

`install.sh` 升级模式会：
1. 对比每个部署目录的 `VERSION` 与源版本
2. 按需运行 `migrations/vX.Y.Z.sh`（幂等）
3. 保留你的私人数据（`.env` / `config/runtime.env` / `data/*.db` / `knowledge-base/*`）

### install.sh 模式速查（v2.1.3+）

```bash
bash install.sh --check                             # 只自检，不写文件
bash install.sh --dry-run                           # 预演：列出将做的所有动作
bash install.sh --yes                               # 跳过交互用默认值
bash install.sh --target ~/.myagents/skills/shuling # 显式指定部署目标（可重复）
bash install.sh --mode=existing-creator             # 老博主模式（v2.2.0+）
SHULING_ASSUME_YES=1 GEMINI_API_KEY=xxx bash install.sh   # 远程/自动化一键部署
```

逐版本升级步骤 → [UPGRADE.md](UPGRADE.md)

---

## 架构与目录

### 数据流

```
┌──────────────────────────────────────────────────────────┐
│           AI 助手（大脑 / Skill-as-Brain）                │
│                                                            │
│   §0a 业务路由 → §0b 识别平台/校验 schema                  │
│   ├─→ §0c 老博主接入（v2.2.0+ 可选）                       │
│   └─→ §0/§1 新博主流程                                     │
│   → §2/§3/§4 日常（选题/创作/发布/复盘/自进化）            │
└─┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┘
  │      │      │      │      │      │      │      │
┌─▼────┐┌▼────┐┌▼───┐┌─▼───┐┌▼─────┐┌▼────┐┌▼───┐┌─▼─────┐
│xhs.sh││db.sh││image││fetch││noterx││pre- ││imp-││audit- │
│MCP   ││SQL  ││.py  ││-*.sh││-diag ││flight│ort-││report │
│9 工具 ││8 表 ││生图 ││拉数据││5 维  ││自检  ││exst││8 维  │
└──────┘└─────┘└─────┘└─────┘└─────┘└─────┘└────┘└──────┘
                                                  ↑ v2.2.0

knowledge-base/                    schemas/（AI 写入契约）
├── profile.json                   ├── state.schema.json
├── preferences.json               ├── profile.schema.json
├── patterns.md / anti-*.md        ├── preferences.schema.json
├── image-patterns.md / anti-*     └── audit-report.schema.json
├── evolution-log.md
├── reviews/<YYYY-W##>.md          data/
└── audit-<YYYY-MM-DD>.md / json   ├── xhs.db          ← 8 张表
  ↑ v2.2.0                        └── content-rules.md
```

**一条主线**：AI → SKILL.md（业务路由）→ scripts/（物理操作）→ DB + knowledge-base（持久化）→ 下次路由读 state。所有自动化（午/晚间发布 + 夜间复盘 + 周日深度回顾）全部走这条，由 hermes cron 定时唤起助手实现。

### 目录结构

```
shuling/
├── SKILL.md                             # 大脑剧本（AI 读这个，核心）
├── VERSION                               # 版本号 + BRAIN/HANDS/CALIB 清单
├── CHANGELOG.md / UPGRADE.md / RELEASING.md    # 版本管理三件套
├── README.md                             # 本文件
├── install.sh                            # 六模式安装脚本（v2.1.3+）
│
├── config/
│   └── runtime.env.example               # 配置模板
│
├── scripts/                              # ───── Hands 层 ─────
│   ├── preflight.py                      # 环境预检（JSON + --human，v2.1.3+）
│   ├── db.sh                             # SQLite CRUD（8 表）
│   ├── xhs.sh                            # 小红书 MCP 统一入口（9 工具 + 节流 + 限额 + 日志）
│   ├── image.py                          # Gemini / OpenAI 生图
│   ├── fetch-post-data.sh                # 合并拉 metrics + comments（v2.1.0+）
│   ├── fetch-metrics.sh / fetch-comments.sh  # 旧（v2.1.0 前）
│   ├── noterx-diagnose.sh                # NoteRx 五维诊断
│   ├── import-existing.sh                # 老博主批量导入（v2.2.0+）
│   └── audit-report.sh                   # 账号体检报告（v2.2.0+）
│
├── schemas/                              # ───── AI 写入契约（v2.1.3+）─────
│   ├── state.schema.json
│   ├── profile.schema.json
│   ├── preferences.schema.json
│   └── audit-report.schema.json          # v2.2.0+
│
├── migrations/                           # DB schema 迁移（vX.Y.Z.sh 幂等）
│   ├── v2.1.1.sh                         # 补建 request_log 表
│   ├── v2.1.2.sh / v2.1.3.sh             # 纯文档版本留痕
│   └── v2.2.0.sh                         # ALTER posts add source + CREATE historical_stats
│
├── knowledge-base/                       # ───── 运行时生成（私有）─────
│   ├── profile.json                      # 博主画像
│   ├── preferences.json                  # 偏好权重（自进化）
│   ├── patterns.md / anti-patterns.md    # 文字 pattern 库
│   ├── image-patterns.md / image-anti-*  # 图片 prompt 库
│   ├── evolution-log.md                  # 每日进化日志
│   ├── reviews/<YYYY-W##>.md             # 周快照
│   └── audit-<YYYY-MM-DD>.(md|json)      # 老博主体检报告（v2.2.0+）
│
├── data/
│   ├── xhs.db                            # SQLite（8 张表，运行时生成）
│   └── content-rules.md                  # 内容规则与平台限制
│
├── docs/
│   ├── mcp-setup.md                      # xiaohongshu-mcp 完整安装指南（含 cookie 图文）
│   └── features/
│       └── existing-creator-onboarding.md    # 老博主接入完整 spec（v2.2.0+）
│
└── platform/
    ├── hermes.md                         # Hermes 定时任务配置
    ├── claude-code.md                    # Claude Code 使用指南
    └── codex.md                          # Codex 使用指南
```

---

## 配置参考

所有 `XHS_*` / `SHULING_*` 变量可在 `.env`、`config/runtime.env` 或进程环境中设置。

### 通用配置（MCP / 安装 / 图片 / 诊断）

| 变量 | 默认 | 作用 |
|---|---|---|
| `MCP_URL` | `http://localhost:18060/mcp` | xiaohongshu-mcp 服务地址 |
| `XHS_CACHE_DIR` | `~/.cache/shuling` | 节流戳 + quota + session + import-state 目录 |
| `SHULING_ASSUME_YES` | `0` | 设 `1` 等同 `--yes`，所有交互用默认值（v2.1.3+） |
| `SHULING_CREATOR_MODE` | 空 | 设 `existing` 等同 `--mode=existing-creator`（v2.2.0+） |
| `XHS_MCP_URL` | 空 | 预填 MCP URL（避免 prompt 卡住） |
| `GEMINI_API_KEY` | 空 | Gemini 生图 Key（推荐） |
| `IMAGE_GEN_MODEL` | `gemini-3-pro-image-preview` | 图像模型（Nano Banana Pro，中文渲染更稳） |
| `IMAGE_GEN_PROTOCOL` | `gemini-native` | 也可设 `openai-chat`（走兼容代理）；不配置无 HTML 降级 |
| `NOTERX_API_KEY` | 空 | NoteRx 五维诊断 Key（不配则跳过 §3 诊断步骤） |

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
| `XHS_DISABLE_LOG` | `0`（开启） | 设 `1` 跳过写 `request_log` 表（v2.1.1+） |

请求日志查询：
```bash
bash scripts/xhs.sh log --limit 10            # 最近 10 条
bash scripts/xhs.sh log --summary              # 按 tool × status 聚合
bash scripts/xhs.sh log --tool search_feeds --days 7
```

---

## 文档地图

| 你想做什么 | 去读 |
|---|---|
| 想先看项目介绍页（中英文） | [shuling.pages.dev](https://shuling.pages.dev) |
| 我是 AI / 想知道整个业务怎么运行 | [SKILL.md](SKILL.md)（必读） |
| 我是用户 / 每次发版有什么变化 | [CHANGELOG.md](CHANGELOG.md) |
| 我要从 vX.Y.Z 升级到新版 | [UPGRADE.md](UPGRADE.md) |
| 我要自己发版 | [RELEASING.md](RELEASING.md) |
| xiaohongshu-mcp 装不上 / cookie 怎么拿 | [docs/mcp-setup.md](docs/mcp-setup.md) |
| 老博主接入流程的完整设计 | [docs/features/existing-creator-onboarding.md](docs/features/existing-creator-onboarding.md) |
| AI 写入 JSON 时要遵守什么契约 | [schemas/](schemas/) + [schemas/README.md](schemas/README.md) |
| 我的平台（hermes / claude / codex）怎么配 | [platform/](platform/) |
| 知道有哪些表、字段是什么 | `scripts/db.sh init` 看 SQL；或 SKILL.md §7 |

---

## 版本管理与路线图

### 版本号语义：BRAIN.HANDS.CALIB

- **BRAIN** +1：SKILL.md 核心流程 / 自进化算法 / AI 行为方式变化 → **major**，breaking
- **HANDS** +1：scripts/ 扩展 / DB schema 变化 / MCP 接口变化 → **minor**，一般非 breaking
- **CALIB** +1：阈值 / 文档 / bugfix / prompt 微调 → **patch**，用户无感升级

版本号决策树见 [RELEASING.md](RELEASING.md#版本号决策树brainhandscalib)。

### 路线图

| 版本 | 主题 | 状态 |
|---|---|---|
| v1.x | OpenClaw + Python workflow 双线架构 | 已归档 |
| v2.0.0 | Skill-as-Brain 重构 | ✅ |
| v2.1.0 | Anti-Ban Shield（节流 + 限额 + session + 合并脚本） | ✅ |
| v2.1.1 | Request Log（MCP 调用全量落表） | ✅ |
| v2.1.2 | Release Polish（CHANGELOG/UPGRADE/RELEASING 三件套 + migrations） | ✅ |
| v2.1.3 | Friendly Onboarding（install.sh 六模式 + preflight --human + schemas + §0b） | ✅ |
| v2.2.0 | Existing Creator Support（老博主接入 + 账号体检 + patterns 种子） | ✅ |
| v2.2.1 | Migration Safety Fix（v2.1.1 迁移脚本在存量 v2.0 升级时阻断修复） | ✅ |
| **v2.3.0** | **Pure Image Pipeline（去 HTML 截图降级 + Gemini 必需 + prompt 模板系统 + 封面参考图）** | ✅ **当前** |
| v2.4.0 | Agent-Friendly Upgrade Infrastructure（`install.sh upgrade-all` + `upgrade-hooks/` + `__migrations` 表 + SKILL.md §1 preferences.json 模板 schema 对齐） | 规划中 |
| v2.x 其他 | 历史帖改写重发建议 / 评论回复助手（Layer 2） | 规划中 |
| v3.0.0 | 视频笔记 / 多账号灰度 / 竞品对标（Layer 3）；候选议题：Phase-Aware Weights（phase 权重自适应硬化）/ Pattern Confidence State Machine（low→medium→high 升级规则）——待真实数据量（20+ 帖、10+ 诊断）到位后再决定 | 远期 |

---

## 贡献与许可

这是个人项目，但代码开源借鉴欢迎：

- **Fork + 本地改 + 测试**（至少跑通一次 `install.sh --check` + 一次 `xhs.sh search`）
- **遵守 [RELEASING.md](RELEASING.md) 的版本号决策树**
- **CHANGELOG 写给用户看**，不是给开发者看（参考已有条目格式）
- 发 PR 时附上 smoke test 结果（截图或命令输出）

如果你在做类似"AI Skill + MCP + 自进化知识库"的项目，可以直接借鉴以下设计：

- `SKILL.md §0a` 业务路由 + 反模式禁令
- `schemas/` + AI 写入前自校验协议
- BRAIN.HANDS.CALIB 版本号语义
- CHANGELOG 📦/⬆️ 双栏 + UPGRADE 逐版本步骤 + RELEASING SOP

### 许可

MIT
