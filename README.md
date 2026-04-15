# 小红书博主成长助手

> 帮你选题、写稿、发布、复盘，越用越懂你。

---

## 核心理念

**Skill-as-Brain** — 业务逻辑全部在 `SKILL.md` 里，AI 助手读了它就是大脑；`scripts/` 里的工具只是手脚，负责调 API、读写数据库、生成图片这些 AI 做不了的物理操作。

这意味着：
- 换一个 AI 平台？只要它能读 SKILL.md，就能无缝迁移
- 想改流程？改 SKILL.md 就行，不用动代码
- 系统越用越聪明：每次选择、每条数据都记录在案，驱动偏好进化

---

## 快速开始

```bash
# 1. 安装
git clone <repo-url> && cd xiaohongshu-skill
bash install.sh

# 2. 首次对话，建立博主画像
#    在你的 AI 助手中说：
#    "我想做小红书博主"
#    助手会通过几轮对话了解你的方向、受众和风格偏好

# 3. 开始使用
#    "帮我发小红书"     → 完整发布流程
#    "今天发什么"       → 选题研究
#    "看看昨天的数据"   → 数据复盘
```

---

## 支持平台

| 平台 | 状态 | 说明 |
|------|------|------|
| [Hermes](platform/hermes.md) | ✅ | 支持 cron job 全自动发布 + 复盘 |
| [Claude Code](platform/claude-code.md) | ✅ | 对话式使用，支持 /loop 定时 |
| [Codex](platform/codex.md) | ✅ | 对话式使用 |
| OpenClaw | ✅ | 兼容 agents 目录规范 |

---

## 架构

```
┌─────────────────────────────────────────────────┐
│                   AI 助手（大脑）                 │
│                                                   │
│   读取 SKILL.md → 理解流程 → 做决策 → 调工具     │
└──────────┬───────────────┬───────────────┬────────┘
           │               │               │
     ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼─────┐
     │  xhs.sh   │  │  db.sh    │  │ image.py  │
     │  小红书API │  │  数据存储  │  │ 图片生成   │
     └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
           │               │               │
     ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼─────┐
     │ xiaohongshu│  │  SQLite   │  │  Gemini   │
     │    MCP     │  │  xhs.db   │  │  / HTML   │
     └───────────┘  └───────────┘  └───────────┘

knowledge-base/          data/
├── profile.json         ├── xhs.db          ← 五张表
├── preferences.json     └── content-rules.md
└── evolution-log.json

templates/
└── post.html            ← HTML 截图降级模板
```

---

## 文件结构

```
xiaohongshu-skill/
├── SKILL.md              # Agent 主剧本（核心）
├── install.sh            # 安装脚本
├── scripts/
│   ├── db.sh             # SQLite 数据库操作（增删改查）
│   ├── xhs.sh            # 小红书 MCP 统一入口
│   ├── image.py           # Gemini 图片生成
│   └── screenshot.cjs     # HTML → PNG 截图（Playwright）
├── data/
│   ├── xhs.db            # SQLite 数据库
│   └── content-rules.md   # 内容规则与平台限制
├── knowledge-base/        # 博主画像与偏好（运行时生成）
├── templates/
│   └── post.html          # 小红书风格 HTML 模板
└── platform/
    ├── hermes.md          # Hermes 适配指南
    ├── claude-code.md     # Claude Code 适配指南
    └── codex.md           # Codex 适配指南
```

---

## 自进化机制

系统通过三层机制越来越懂你：

1. **偏好学习** — 记录你每次在选题、标题、风格上的选择，构建偏好权重模型。下次推荐时优先考虑你喜欢的方向。

2. **数据驱动** — 每条帖子的点赞、收藏、评论数据都会回流。系统会分析"什么选题表现好"、"什么时间段发效果好"、"什么风格更受欢迎"，自动调整策略。

3. **选项递减** — 从最初每天让你选 5 个选题，逐步减少到 3 个、2 个，直到系统自信到只推 1 个让你确认。最终目标：你回复一个"发"字就完成一天的内容。

---

## 许可

MIT
