# 薯灵 (ShuLing)

> 小红书博主成长助手 — 帮你选题、写稿、发布、复盘，越用越懂你。

[![Version](https://img.shields.io/badge/version-2.2.0-blue)](VERSION)
[![Codename](https://img.shields.io/badge/codename-Existing%20Creator%20Support-green)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](#许可)

**当前版本**：`v2.2.0 "Existing Creator Support"`（2026-04-21）
**完整变更**：[CHANGELOG.md](CHANGELOG.md) ｜ **升级指南**：[UPGRADE.md](UPGRADE.md) ｜ **发版流程**：[RELEASING.md](RELEASING.md)

---

## 核心理念

**Skill-as-Brain** — 业务逻辑全部在 `SKILL.md` 里，AI 助手读了它就是大脑；`scripts/` 里的工具只是手脚，负责调 API、读写数据库、生成图片这些 AI 做不了的物理操作。

这意味着：
- 换一个 AI 平台？只要它能读 SKILL.md，就能无缝迁移
- 想改流程？改 SKILL.md 就行，不用动代码
- 系统越用越聪明：每次选择、每条数据都记录在案，驱动偏好进化

---

## 前置依赖（先备好）

| 依赖 | 用途 | 安装 |
|------|------|------|
| **AI 助手** | 大脑，读 SKILL.md 后驱动整个流程 | 装 hermes、[claude code](https://claude.com/claude-code) 或 [codex](https://github.com/openai/codex) 任一 |
| **xiaohongshu-mcp** | 操作小红书的 MCP 服务（搜索/发布/详情） | [xpzouying/xiaohongshu-mcp](https://github.com/xpzouying/xiaohongshu-mcp)，按其 README 装好并用自己的小红书账号登录 |
| Node.js / Python 3 / sqlite3 / Playwright | 截图、数据库、生图 | macOS：`brew install node sqlite`，然后 `npx playwright install chromium`<br>Linux：`apt install nodejs sqlite3`，然后 `npx playwright install chromium` |
| 图片生成 API（可选） | AI 生图（不配则走 HTML 截图，效果也不错） | Gemini Key（推荐，有免费额度）或 OpenAI Key |

> **本 skill 不假设也不配置任何 IM 通讯渠道**（Telegram 等）。与用户对话由 AI 助手平台（如 hermes）自己负责。

---

## 快速开始

```bash
# 1. 克隆并安装
git clone git@github.com:AI-flower/shuling.git && cd shuling
bash install.sh
# install.sh 会自动检测 hermes/claude/codex/agents 各平台目录并部署到对应位置

# 2. 在你的 AI 助手中说一句
#    "我想做小红书博主"  →  助手通过对话了解你的方向、受众和风格

# 3. 登录小红书（两种方式任选）
#    - 默认扫码：助手会调 scripts/xhs.sh login 拿二维码链接给你扫
#    - 直接给 cookie：从浏览器 F12 复制完整 Cookie 头字符串，告诉助手
#      "我给你 cookie：<贴在这里>"  →  助手会自动调 scripts/xhs.sh import-cookie

# 4. 进入日常使用
#    "帮我发小红书"     → 完整发布流程
#    "今天发什么"       → 选题研究
#    "看看昨天的数据"   → 数据复盘
```

### 已经在运营小红书？老博主接入（v2.2.0+）

```bash
# 方式一：装的时候选老博主模式
bash install.sh --mode=existing-creator

# 方式二：已装过，直接跟 AI 说
#    "我已经在运营小红书，帮我接入"
#
# AI 会走 SKILL.md §0c 的 5 步流程：
#   1. 确认账号登录
#   2. 批量导入最近 200 条历史帖（约 30 分钟，带节流保护）
#   3. AI 自动给每条分类（topic_type / title_pattern / content_style）
#   4. 从最近 30 条反推画像（领域/受众/风格），展示给你确认/微调
#   5. 出账号体检报告 + 挖 patterns 种子写入 patterns.md
#
# 完成后系统已具备你 6 个月以上的历史记忆，第一条薯灵发帖即达历史 P50 水平
```

也可手动跑：

```bash
bash scripts/import-existing.sh --limit 200           # 批量导入（可 --resume 续跑）
bash scripts/audit-report.sh --extract-patterns       # 出体检报告 + patterns 候选
```
详细设计：[docs/features/existing-creator-onboarding.md](docs/features/existing-creator-onboarding.md)

> **首次安装后**：`config/runtime.env`、`config/state.json`、`knowledge-base/profile.json`、`data/xhs.db` 等都是你的私人数据，已被 `.gitignore` 屏蔽。不要 `git add -f` 这些文件。

---

## 升级已有安装

```bash
cd /path/to/shuling
git fetch --tags origin
git checkout main && git pull
bash install.sh              # v2.1.2+ 自动识别已部署版本、按需运行 migration
```

`install.sh` 升级模式会：
1. 对比每个部署目录的 `VERSION` 与源版本
2. 按需运行 `migrations/vX.Y.Z.sh`（幂等）
3. 保留你的私人数据（`.env` / `config/runtime.env` / `data/*.db` / `knowledge-base/*`）

### v2.1.3 新增的非交互模式

```bash
bash install.sh --check                             # 只自检：依赖 + 平台 + 版本对比，不写文件
bash install.sh --dry-run                           # 预演：列出将要执行的全部动作，不真跑
bash install.sh --yes                               # 跳过所有交互，用默认值（cron/CI）
bash install.sh --target ~/.myagents/skills/shuling # 显式指定部署目标（可重复）
SHULING_ASSUME_YES=1 GEMINI_API_KEY=xxx bash install.sh  # 远程/自动化一键部署

python3 scripts/preflight.py --human                # 人类可读的彩色健康检查
```

逐版本升级注意事项 → [UPGRADE.md](UPGRADE.md)

## 支持平台

| 平台 | 状态 | 说明 |
|------|------|------|
| [Hermes](platform/hermes.md) | ✅ | 支持 cron job 全自动发布 + 复盘 |
| [Claude Code](platform/claude-code.md) | ✅ | 对话式使用，支持 /loop 定时 |
| [Codex](platform/codex.md) | ✅ | 对话式使用 |
| OpenClaw | ✅ | 兼容 agents 目录规范 |

---

## 环境变量参考

所有 `XHS_*` 变量可在 `.env` 或进程环境中设置。

### MCP 服务 & 缓存

| 变量 | 默认 | 作用 |
|---|---|---|
| `MCP_URL` | `http://localhost:18060/mcp` | xiaohongshu-mcp 服务地址 |
| `XHS_CACHE_DIR` | `~/.cache/shuling` | 节流戳文件 + quota 状态目录 |

### 节流与限额（v2.1.0+）

| 变量 | 默认 | 作用 |
|---|---|---|
| `XHS_DISABLE_THROTTLE` | `0` | 设 `1` 跳过节流（仅调试，**慎用**） |
| `XHS_DISABLE_QUOTA` | `0` | 设 `1` 跳过日限额（仅调试，**慎用**） |

**默认节流 profile `v1-conservative`**（见 `scripts/xhs.sh` 可自行调整）：

| 接口 | MIN_GAP | 日上限 |
|---|---|---|
| `search_feeds` | 20s | 15/日 |
| `get_feed_detail` | 10s | 50/日 |
| `list_feeds` | 15s | 20/日 |
| `publish_content` | 300s | 2/日 |
| `post_comment_to_feed` | 180s | 5/日 |
| `user_profile` | 30s | 20/日 |

### Session 复用（v2.1.0+，opt-in）

| 变量 | 默认 | 作用 |
|---|---|---|
| `XHS_REUSE_SESSION` | `0` | 设 `1` 启用 session 复用（上游服务端 2-3 次后会失效，谨慎） |
| `XHS_SESSION_TTL` | `120` | session 复用 TTL 秒数 |

### 请求日志（v2.1.1+）

| 变量 | 默认 | 作用 |
|---|---|---|
| `XHS_DISABLE_LOG` | `0`（开启）| 设 `1` 跳过写 `request_log` 表 |

查询日志：
```bash
bash scripts/xhs.sh log --limit 10         # 最近 10 条
bash scripts/xhs.sh log --summary           # 按 tool × status 聚合
bash scripts/xhs.sh log --tool search_feeds --days 7
```

### 图片生成

| 变量 | 默认 | 作用 |
|---|---|---|
| `GEMINI_API_KEY` | 空 | Gemini 生图 Key（推荐） |
| `IMAGE_GEN_MODEL` | `gemini-3-pro-image-preview` | 图像模型 |

### NoteRx 诊断

| 变量 | 默认 | 作用 |
|---|---|---|
| `NOTERX_API_KEY` | 空 | NoteRx 五维诊断 Key |

## 架构

```
┌─────────────────────────────────────────────────────┐
│              AI 助手（大脑 / Skill-as-Brain）         │
│                                                       │
│   读 SKILL.md → 业务路由 → 决策 → 调脚本 → 写知识库   │
└─┬─────────┬─────────┬─────────┬──────────┬──────────┘
  │         │         │         │          │
┌─▼──────┐┌─▼──────┐┌─▼─────┐┌─▼────────┐┌─▼─────────┐
│xhs.sh  ││db.sh   ││image  ││fetch-*   ││noterx-    │
│小红书  ││数据库  ││.py    ││.sh       ││diagnose.sh│
│MCP     ││SQLite  ││Gemini ││metrics + ││NoteRx API │
│        ││xhs.db  ││/HTML  ││comments  ││5 维评分    │
└────────┘└────────┘└───────┘└──────────┘└───────────┘

knowledge-base/                data/
├── profile.json               ├── xhs.db          ← 7 张表
├── preferences.json           └── content-rules.md
├── patterns.md
├── anti-patterns.md
├── evolution-log.md           templates/
└── reviews/<YYYY-W##>.md      └── post.html       ← HTML 截图模板
```

**只有一条路线**：智能体 → SKILL.md → scripts/。所有自动化（每日发布 + 每日复盘 + NoteRx 诊断 + 知识库进化）全部走这条路，由 hermes cron 定时唤起助手实现。
---

## 文件结构

```
shuling/
├── SKILL.md                  # 大脑剧本（核心）
├── install.sh                # 安装脚本
├── README.md                 # 本文件
├── config/
│   └── runtime.env.example   # 配置模板（MCP_URL / IMAGE_GEN_* / NOTERX_*）
├── scripts/
│   ├── preflight.py          # 环境预检
│   ├── db.sh                 # SQLite 增删改查
│   ├── xhs.sh                # 小红书 MCP 入口
│   ├── image.py              # Gemini 图片生成
│   ├── screenshot.cjs        # HTML → PNG 截图
│   ├── fetch-metrics.sh      # 拉互动数据写 DB
│   ├── fetch-comments.sh     # 拉评论原文 + 过滤 spam
│   └── noterx-diagnose.sh    # NoteRx 5 维诊断
├── data/
│   ├── xhs.db                # SQLite（7 张表，运行时生成）
│   └── content-rules.md      # 内容规则与平台限制
├── knowledge-base/           # 博主画像与偏好（运行时生成）
├── templates/
│   └── post.html             # 小红书风格 HTML 模板
└── platform/
    ├── hermes.md
    ├── claude-code.md
    └── codex.md
```
---

## 自进化机制

系统通过三层机制越来越懂你：

1. **偏好学习** — 记录你每次在选题、标题、风格上的选择，构建偏好权重模型。下次推荐时优先考虑你喜欢的方向。

2. **数据驱动** — 每条帖子的点赞、收藏、评论数据都会回流。系统会分析"什么选题表现好"、"什么时间段发效果好"、"什么风格更受欢迎"，自动调整策略。

3. **选项递减** — 从最初每天让你选 5 个选题，逐步减少到 3 个、2 个，直到系统自信到只推 1 个让你确认。最终目标：你回复一个"发"字就完成一天的内容。


---

## 版本管理

- 版本号遵循 **BRAIN.HANDS.CALIB** 三段语义（见 [`VERSION`](VERSION)）
- 所有改动必经 [CHANGELOG.md](CHANGELOG.md)，含「📦 用户可见改动」「⬆️ 如何升级」两栏
- 发版流程标准化在 [RELEASING.md](RELEASING.md)
- Breaking change 仅在 BRAIN 位升级时发生（如 v1.x → v2.0.0）

### 如何贡献 / 借鉴

这是个人项目，但代码开源借鉴欢迎：

- **Fork + 本地改 + 测试**（至少跑通一次 `install.sh` + 一次 `xhs.sh search`）
- **遵守 [RELEASING.md](RELEASING.md) 的版本号决策树**
- **CHANGELOG 写给用户看**，不是给开发者看（参考已有条目格式）
- 发 PR 时附上 smoke test 结果（截图或命令输出）

---

## 许可

MIT

