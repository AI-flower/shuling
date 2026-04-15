# 小红书自动发布系统 — 完整业务能力说明书

## 一、系统定位

| 项目 | 说明 |
|------|------|
| 品牌 | OpenClaw（开源龙虾🦞） |
| 账号定位 | 科技博主，在小红书上用大白话分享 GitHub 开源 AI 项目 |
| 内容策略 | 每天 2 篇帖子（午间 + 晚间），图文笔记形式 |
| 午间档（noon） | 「发现宝藏项目」角度 — 痛点共鸣 → 保姆级教程 → 效果展示 |
| 晚间档（evening） | 「实操技巧分享」角度 — 背景说明 → 完整教程 → 效果验证 |

---

## 二、系统架构总览

```
┌──────────────────────────────────────────────────────────┐
│                     安装与部署层                          │
│  install.sh → skills/ + workflow/ + launchd templates    │
│  兼容 Claude Code / Agents / Codex 三平台 skill 路径      │
└──────────────────────────────────────────────────────────┘
         │
┌──────────────────────────────────────────────────────────┐
│                     技术栈                               │
│                                                          │
│  小红书操作    xiaohongshu-mcp（MCP 协议）                │
│               12 个 API: 搜索/发布/评论/回复/点赞/        │
│               收藏/推荐/详情/用户/登录/视频/二维码         │
│                                                          │
│  内容生成     Claude CLI (--dangerously-skip-permissions  │
│              --print -p)                                 │
│              新流程: 多草稿并行 + 三维验证                 │
│              旧流程: 单次生成 + 兜底模板                   │
│                                                          │
│  图片生成     三策略: AI (OpenAI API) / HTML截图           │
│              (Playwright) / auto (AI优先+截图降级)        │
│                                                          │
│  数据存储     SQLite (WAL模式) 9张表                      │
│                                                          │
│  通知交互     Telegram Bot (零依赖,urllib实现)             │
│              双向: 推送 + getUpdates长轮询监听            │
│                                                          │
│  定时调度     macOS launchd (6个plist模板)                │
│                                                          │
│  配置管理     runtime.env (环境变量) + config_loader.py   │
└──────────────────────────────────────────────────────────┘
```

---

## 三、完整每日流程（8 个阶段）

```
08:00          09:00                    11:30/20:30     21:30        22:00       每4h
  │              │                          │             │            │          │
  ▼              ▼                          ▼             ▼            ▼          ▼
研究选题 ──→ 智能编排 ──────────────────→ 定时发布 ──→ 预览明天 ──→ 晚间复盘 ──→ 登录保活
              │                                                      │
              ├─ 多草稿并行生成                                       ├─ 互动数据采集
              ├─ 三维验证评分                                         ├─ 评论AI分析
              ├─ Telegram推送 ←→ 博主选择(110min)                     └─ 反馈闭环 → 注入创作
              ├─ AI/截图生成图片
              └─ Telegram审图 ←→ 博主确认(30min)
```

---

### 阶段 1：晨间研究 — `research.py`（08:00）

**目标：** 从海量开源项目中筛出当天最值得写的 2 个选题

**执行流程：**

#### 1.1 数据采集

| 数据源 | 方法 | 采集量 |
|--------|------|--------|
| GitHub Trending | 抓取 HTML 页面，正则提取仓库路径（三级容错正则） | 前 25 个 |
| GitHub API 搜索 | 4 组关键词轮询：OpenClaw skill / Claude Code skill / agent workflow tool / AI tool | 各 6-10 个 |

- 合并去重，排除已发布过的项目（查 SQLite `topics` 表 `is_topic_used()`）

#### 1.2 详情丰富（最多分析 15 个）

对每个候选执行：
- **GitHub API** 获取 stars / forks / language / topics / 创建和更新时间
- **拉取 README**（尝试 main → master 分支，前 3000 字符）
  - 过滤 badge 行、纯图片行、`<img>` 标签、赞助/贡献链接
- **小红书 MCP `search_feeds`** 搜索竞品密度（项目名做关键词）

#### 1.3 三维打分体系

| 评分函数 | 评分逻辑 | 关键规则 |
|----------|---------|---------|
| `score_candidate()` | stars 高 + XHS 竞品少 = 高分 | 蓝海（0 条竞品）+30 分，10k+ star +40 分，AI 相关 +10 分 |
| `score_xhs_fit()` | 与账号主线的匹配度 | 主线关键词（skill/openclaw/memory/browser/pdf 等）每个 +4；非主线项目直接 **-70 分**；platform/framework 类 -6~-8 |
| `score_titleability()` | 是否容易写成「具体标题」 | 单功能/单动作/单人群可写性好 +6~+10；awesome-list、超长名称 -4~-6 |

#### 1.4 主线优先选择

`is_mainline_candidate()` 判定条件（全部满足）：
- 命中正向关键词（memory/browser/skill/record/pdf/docx 等）
- 是明确的 skill 或单功能工具（不是 platform/studio/copilot）
- 未命中负向关键词（database/dataset/minecraft/tax 等）

选择策略：优先选 2 个主线候选，不足则补非主线高分项目。

#### 1.5 输出

- `data/candidates-{date}.json`（含 selected + all_candidates）
- 写入 `topics` 表（每个分析过的项目 + 最终选中标记）

---

### 阶段 2：智能编排 — `orchestrator.py`（09:00）

**目标：** 把选中项目变成经过验证、博主确认的待发布帖子

这是系统最核心的模块，串联了多草稿生成 → 验证评分 → 人机交互选择 → 图片生成 → 审图确认的完整链路。

每个 slot（noon / evening）独立执行以下流程：

#### 2.1 加载选题

- 从 `candidates-{date}.json` 读取 selected 列表
- 检查 DB 是否已有该 slot 的活跃帖子（scheduled/published），有则跳过

#### 2.2 多草稿并行生成 — `draft_generator.py`

**双模式：**

| 模式 | 草稿数 | 组合策略 |
|------|--------|---------|
| **lite**（默认） | 3 份 | 1个历史最优组合 + 1个蓝海探索 + 1个默认补充 |
| **pro** | 8 份 | 4角度 × 2风格（每个角度选最适配的 2 种风格） |

**角度 × 风格矩阵：**

| | professional（专业） | casual（口语） | suspense（悬念） |
|---|---|---|---|
| **recommend**（推荐） | 干货密集 | 🔥网感强（默认） | 悬念推荐 |
| **tutorial**（教程） | 🔥专业教程（默认） | 口语教程 | 悬念教程 |
| **compare**（评测） | 🔥专业评测（默认） | 口语评测 | 悬念评测 |
| **story**（故事） | 专业叙事 | 口语故事 | 🔥悬念故事（默认） |

**Lite 模式智能选择逻辑：**
1. **历史最优**：从 DB 查过去 30 天各 angle+style 组合的互动表现，选综合分最高的（赞 + 收藏×2 + 评论×1.5）
2. **蓝海探索**：找最近 7 天未使用过的角度，配其最适配风格
3. **默认补充**：从 `draft-config.json` 的 `default_combos` 中补至 3 个

**反馈注入：** `build_feedback_section()` 从 DB 读取最近 3 次评论分析结果（高频提问 / 用户好评 / 吐槽点 / 内容需求），格式化后注入每份草稿的创作 prompt

**并行执行：** asyncio + Semaphore（默认并发 3），每份草稿独立调用 Claude CLI，超时 180 秒

**输出：** 每份草稿写入 `drafts` 表，包含 title / content / tags / angle / style / image_prompts / key_points

#### 2.3 三维验证评分 — `draft_validator.py`

对所有草稿进行三个维度的评估：

**维度 1 — 平台数据验证（score_platform）：**
- 从标题提取 2-3 个搜索关键词（去 emoji、去停用词、去数字模式词）
- 对每个关键词调用 XHS MCP `search_feeds` 搜索（带内存缓存 + DB 24 小时缓存）
- 计算蓝海指数 = 需求热度 / 供给量（蓝海指数 ≥5 → 90-100 分）
- 搜索间隔随机 2-5 秒，避免限流

**维度 2 — 内容质量评估（score_quality_batch）：**
- 用 Claude CLI 批量评分所有草稿（一次调用评所有）
- 5 个子维度：标题吸引力 25% / 内容完整性 30% / 合规性 20% / 格式匹配 15% / CTA 有效性 10%
- 同时提取亮点和风险文本

**维度 3 — 历史对标（score_history）：**
- 从 DB 查过去 30 天相同 angle+style 组合的平均互动表现
- 与全局平均对比，计算相对优势

**冷启动自适应权重：**

| 已发布帖子数 | 平台数据权重 | 内容质量权重 | 历史对标权重 |
|-------------|-------------|-------------|-------------|
| ≤5 篇（冷启动期） | 50% | 50% | **0%** |
| 6-19 篇（成长期） | 45% | 40% | 15% |
| ≥20 篇（成熟期） | 40% | 35% | 25% |

**输出：** 按总分排名，写入 `draft_scores` 表 + 生成中文总结（overall_insight）

#### 2.4 Telegram 推送报告 + 博主选择

**推送内容：** 排名报告（每份草稿的分数、角度、风格、亮点）+ 操作指引

**支持的博主指令（Telegram 双向交互）：**

| 指令 | 动作 | 说明 |
|------|------|------|
| `选N` | select | 选择第 N 份草稿 |
| `N`（纯数字） | detail | 查看第 N 份完整内容 |
| `更多` / `全部` | more | 查看所有草稿摘要 |
| `自动` | auto_mode | 自动选择评分最高 |
| `跳过` | skip | 取消该 slot |
| `确认` | confirm | 通过图片审核 |
| `重新生成` | regenerate_all | 重新生成所有图片 |
| `重新生成N` | regenerate_one | 重新生成第 N 张 |
| `取消` | cancel | 取消发布 |

**超时机制：**
- 草稿选择超时：110 分钟（可配置 `DRAFT_SELECT_TIMEOUT`）
- 30 分钟剩余时发送提醒
- 超时自动选择 #1

**轮询实现：** `telegram_listener.py` 通过 Telegram `getUpdates` 长轮询（30 秒间隔），解析博主回复文本，匹配指令模式

#### 2.5 图片生成 — `image_generator.py`

**三种策略：**

| 策略 | 方法 | 使用条件 |
|------|------|---------|
| `ai` | OpenAI 兼容 API（默认 gpt-image-1） | 配置了 `IMAGE_GEN_API_KEY` |
| `html` | Playwright 截图（screenshot.cjs） | 未配 API Key / 教程类内容 |
| `auto`（默认） | AI 优先，失败降级截图 | 推荐配置 |

**AI 图片生成细节：**
- Prompt 增强：原始 prompt + 品牌风格（`IMAGE_BRAND_STYLE`）+ 页码上下文（封面 → eye-catching，末页 → summary）
- 并行生成 + Semaphore 并发控制
- 单张图片可单独重新生成（`regenerate_image()`）

**HTML 截图细节：**
- 调用 `screenshot.cjs`（Playwright Chromium）
- viewport 1080 × 10000，逐个 `.page` 元素截图
- 输出 page-1.png ~ page-N.png（1080×1440 px）

**图片来源策略推荐：** `recommend_image_strategy()` 根据内容类型自动判断（教程类 → html，其他 → ai）

#### 2.6 图片审核

- 通过 Telegram 发送图片相册
- 博主可回复：确认 / 取消 / 重新生成 / 重新生成N
- 超时 30 分钟自动确认

#### 2.7 写入发布队列

- 创建 post 目录，写入 `meta.json`
- DB 插入 `posts` 记录，状态 → `scheduled`
- 发送 Telegram 确认通知

#### 2.8 完整降级链

```
orchestrator.py 降级逻辑（每个环节独立降级）：

草稿生成失败 ──→ fallback_old_flow() 旧流程（create_content.py）
验证评分失败 ──→ build_fallback_validation() 按生成顺序排列，无评分
Telegram 不可用 ──→ 自动选择 #1，跳过交互
telegram_listener 导入失败 ──→ 自动选择 #1
AI 图片失败 ──→ fallback_html_images() HTML 截图
图片全部失败 ──→ HTML 截图兜底
Telegram 审图不可用 ──→ 自动确认
```

---

### 阶段 2（旧流程）：内容生成 — `create_content.py`

**作为 orchestrator 的降级后端，或独立调用。**

流程：
1. 加载候选 + 合规规则（`content-rules.md`）
2. 构建完整 Claude prompt（项目信息 + README 摘要 + 写作角度 + 合规规则 + HTML 技术要求）
3. Claude CLI 生成 HTML（超时 180 秒）
4. 失败时调用 `generate_html_fallback()` — 硬编码 5 页彩色卡片风格模板（封面/发现/适合谁/怎么开始/总结）
5. Playwright 截图 → page-*.png
6. 从 HTML 提取标题（`<h1>` 标签）
7. 生成 meta.json（标题 ≤20 字 / 正文 ≤1000 字 / 标签 5-8 个 / schedule_at 自动计算）
8. 防重检查 `slot_already_exists()` → 写入 `posts` 表

**schedule_at 计算规则：**
- 午间默认 13:00，晚间默认 22:00
- 距当前至少 65 分钟
- 不足则向后推至最近的 :00 或 :30 时刻

---

### 阶段 3：定时发布 — `publish_post.py` + `publish.sh`（11:30 / 20:30）

#### 3.1 publish_post.py（编排层）

1. 从 DB 取当天对应时段的 draft 帖子
2. DB 无记录 → 从文件系统 `posts/{date}-post{N}` 目录 fallback 导入
3. 验证 meta.json 和 page-*.png 存在
4. 调用 `publish.sh`
5. 解析返回结果提取 `note_id`
6. 更新 DB 状态：`draft → scheduled`（定时）或 `published`（立即）
7. 发送 Telegram 确认通知
8. 支持按目录直接发布 `publish_by_dir()`（不查 DB）

**错误处理：**
- MCP 级业务错误（returncode < 3）：保留 draft 状态，便于修正后重试
- 脚本级错误（returncode ≥ 3）：标记 `failed`

#### 3.2 publish.sh（执行层）

1. 检查 MCP 服务就绪（HTTP POST 到 `localhost:18060/mcp`，检测 `Mcp-Session-Id` 响应头）
2. 未就绪 → 调用 `start-mcp.sh`，轮询最多 10 秒
3. 从 meta.json 构建 payload（title / content / images 绝对路径 / tags / schedule_at / is_original）
4. 调用 MCP `publish_content`
5. 解析 MCP JSON-RPC 响应，检测 `isError` 和 `发布失败` 关键词

---

### 阶段 4：预览次日内容 — `send_preview.py`（21:30）

1. 扫描次日帖子目录 `posts/{tomorrow}-post*`
2. 发送 Telegram 总览消息（共 N 篇待确认）
3. 每篇帖子发送：
   - 🌞/🌙 标签 + 标题 + 定时时间
   - 正文预览（前 300 字）
   - 标签列表
   - 图片相册（send_media_group，最多 10 张）
4. 发送操作指引：回复「确认」/「取消」/ 修改意见

---

### 阶段 5：晚间复盘 — `review.py`（22:00）

#### 5.1 互动数据采集

- 通过 MCP `get_feed_detail` 获取每篇帖子的 ❤️赞 / ⭐收藏 / 💬评论 / 分享
- JSON 解析 + 正则兜底（三级容错）
- MCP 失败时从 DB `post_metrics` 表读取缓存数据
- 获取当前粉丝数（`check_login_status` 解析 fans 字段）

#### 5.2 生成洞察

- 综合分 = 赞 + 收藏×2 + 评论×3
- 收藏率分析（>50% = 内容实用性强，<20% = 需增加干货）
- 与昨日趋势对比
- 找出表现最佳与最差帖子

#### 5.3 评论反馈分析 — `feedback_analyzer.py`

**采集流程：**
1. `collect_comments()` 通过 MCP `get_feed_detail` 获取评论列表
2. `is_spam_comment()` 过滤垃圾评论（纯 emoji / 太短 / 加微 / 引流 / 含链接）
3. `analyze_comments()` 调用 Claude CLI 分析评论情感

**Claude 分析输出：**
```json
{
  "positive_count": 12,
  "negative_count": 2,
  "question_count": 5,
  "top_questions": ["怎么安装", "支持 Windows 吗"],
  "top_praise": ["教程很清楚", "终于有人讲明白了"],
  "top_complaints": ["步骤太少"],
  "content_requests": ["出个视频版"],
  "ai_summary": "一句话综合分析"
}
```

- 写入 `comment_analysis` 表
- `backfill_analysis()` 可补充分析最近 N 天未分析的帖子
- `get_feedback_for_prompt()` 格式化反馈文本，供创作 prompt 注入

#### 5.4 明日建议

根据收藏率/赞数趋势给出内容方向建议（干货工具推荐 vs 趣味性内容）

#### 5.5 发送 Telegram 日报

- 数据总览（每篇帖子的赞/收藏/评论）
- 粉丝数
- 近 7 天趋势
- 洞察
- 明日计划
- 评论洞察摘要

---

### 阶段 6：登录保活 — `keepalive.py`（每 4 小时）

1. 检查 MCP 进程存活（读 PID 文件 + `os.kill(pid, 0)`）
2. 未运行 → 自动调用 `start-mcp.sh` 启动
3. 调用 `check_login_status` 保持会话活跃
4. 登录过期时：
   - 调用 `get_login_qrcode` 获取二维码
   - 优先提取 URL 发送 Telegram
   - 次选 base64 图片保存为临时文件发送
   - 兜底发送原始返回数据
5. 日志写入 `logs/keepalive.log`

---

## 四、反馈闭环

```
研究选题 → 内容生成 → 发布 → 采集互动数据 → 评论AI分析
   ↑                                              │
   │   draft_generator.build_feedback_section()    │
   └──── 注入创作 prompt ←── DB comment_analysis ←─┘
                                                   │
   feedback_analyzer.get_feedback_for_prompt()     │
   → 格式化为 prompt 片段 ←─────────────────────────┘
```

**闭环路径：**
1. `review.py` 调用 `feedback_analyzer.analyze_post()` 分析评论
2. 分析结果写入 `comment_analysis` 表
3. `draft_generator.build_feedback_section()` 读取最近 3 次分析
4. 提取高频提问 / 好评点 / 吐槽点 / 内容需求
5. 注入草稿生成 prompt 的「上期用户反馈」章节
6. 新草稿根据反馈调整内容方向

---

## 五、合规规则体系

### 5.1 绝对禁止

| 类别 | 规则 |
|------|------|
| 平台名称禁令 | 不提及微信/抖音/知乎/36氪/即刻/B站/微博/YouTube/Twitter/Telegram/WhatsApp/Hacker News/GitHub（用「开源社区」代替） |
| 敏感话题 | 禁止区块链/虚拟货币/Web3/NFT |
| 自杀式话题 | 禁止写「用 AI 写小红书」（会被封号） |
| 费用信息 | 不出现价格（AI 费用计算不准确） |
| 篇数编号 | 不加篇数编号（文章可能被封，用户看不到连续编号） |

### 5.2 格式限制

| 项目 | 限制 |
|------|------|
| 标题 | ≤ 20 字符 |
| 正文 | ≤ 1000 字符 |
| 标签 | 5-8 个，不超过 10 个 |
| 封面 CTA | 「告诉我你想用 AI 做什么，我来出教程」 |
| 最后一页 | 必须有收藏/关注引导 |

### 5.3 写作风格

- 口语化、第一人称、有真人感
- 适量 emoji，不过度
- 允许偶尔错误标点、同音字替代（的地得混用、在再互换）
- 痛点 → 解决方案 → 效果展示 结构
- 不能读起来像 AI 生成

### 5.4 选题与标题升级规则

**禁止长期重复的模板：** `X到底值不值` / `X别乱上手` / `X适合谁`

**优先标题类型：**
1. 人群 + 结果：`打工人先装这6个Skill`
2. 人群 + 错误：`新手别先装这3个Skill`
3. 顺序 + 后果：`OpenClaw别按这个顺序装`
4. 单功能 + 一句话收益：`这个skill最适合长期项目`

**5 种高互动模式：**
1. 数字清单体：「10个AI技能」「5个宝藏工具」
2. 反差悬念体：「被吹上天，普通人到底怎么用？」
3. 结果导向体：「3分钟搞定500行数据」
4. 身份共鸣体：「打工人」「一人公司」「替你上班」
5. 保姆级体：「手把手」「0基础」「纯新手」

### 5.5 内容质量标准

**教程类必须满足：**
- 第 4 页是完整操作教程，读者跟着步骤走能真正跑起来
- 每步：标题 + 具体操作（含完整命令/设置路径）+ 成功标志
- 前置条件单独列出
- 常见错误和解决办法
- 命令要完整可运行（`pip install langflow`，不是「安装依赖」）

**内容深度要求：**
- 每页至少 3-5 个信息点
- 功能介绍结合实际场景
- 对比效果要量化（「以前需要30分钟」→「现在3分钟」）

**避免的错误：**
- 整页只有大标题和装饰，没有文字内容
- 步骤只有名字没有具体操作
- 正文出现 README 英文原句、HTML 标签、Markdown 残片
- 标题和封面看起来像仓库介绍页

---

## 六、数据模型（SQLite 9 张表）

```
posts ──────────── 帖子主表（标题/正文/状态/note_id/post_dir/github信息）
  │                  状态流转: draft → scheduled → published / failed
  │
  ├── post_metrics ── 互动指标快照（赞/收藏/评论/分享 × 时间戳）
  │                    支持同一帖子多次采集，保留历史
  │
  ├── comment_analysis ── 评论 AI 分析结果
  │                        正面/负面/提问计数 + top_questions/praise/
  │                        complaints/content_requests + ai_summary
  │
  └── generated_images ── 图片生成记录
                           image_index/prompt/image_path/gen_model/
                           gen_strategy(ai|html)/gen_status(pending|done|failed)

topics ──────────── 每日候选选题（github_repo + xhs_competition + selected 标记）

daily_reviews ────── 每日复盘汇总（总赞/总收藏/总评论/粉丝数/洞察）

drafts ──────────── 多草稿系统
  │                  date/slot/draft_id/angle/style/title/content/
  │                  tags/image_prompts/key_points/image_strategy/selected
  │
  └── draft_scores ── 草稿评分详情
                       platform_score/quality_score/history_score/
                       total_score/highlights/risks

keyword_tracking ─── 关键词竞争度缓存
                      keyword/note_count/avg_likes/avg_saves/
                      blue_ocean_index/trend_direction
                      用于平台数据验证，24小时 TTL
```

**DB 接口层 `db.py`：** 31 个函数，覆盖所有 CRUD + 聚合查询 + 迁移

---

## 七、小红书 MCP 完整能力

基于 `xiaohongshu-mcp` 封装，12 个 API：

| MCP 工具 | 用途 | 使用场景 |
|----------|------|---------|
| `check_login_status` | 检查登录状态 | 保活 / 粉丝数获取 |
| `get_login_qrcode` | 获取登录二维码 | 登录过期时自动告警 |
| `search_feeds` | 搜索内容 | 选题竞品分析 / 关键词验证 |
| `list_feeds` | 获取首页推荐 | 热度参考 |
| `get_feed_detail` | 获取帖子详情和评论 | 互动数据采集 / 评论分析 |
| `post_comment_to_feed` | 发表评论 | 互动运营 |
| `reply_comment_in_feed` | 回复评论 | 评论区维护 |
| `user_profile` | 获取用户主页 | 竞品研究 |
| `like_feed` | 点赞/取消 | 互动运营 |
| `favorite_feed` | 收藏/取消 | 互动运营 |
| `publish_content` | 发布图文笔记 | 核心发布 |
| `publish_with_video` | 发布视频笔记 | 视频发布（预留） |

**辅助脚本：**

| 脚本 | 功能 |
|------|------|
| `start-mcp.sh` / `stop-mcp.sh` | MCP 服务启停 |
| `status.sh` | 登录状态检查 |
| `search.sh <关键词>` | 快速搜索 |
| `recommend.sh` | 获取推荐列表 |
| `post-detail.sh` | 帖子详情 |
| `comment.sh` | 发表评论 |
| `user-profile.sh` | 用户主页 |
| `track-topic.sh <话题>` | 热点跟踪报告（支持飞书输出） |
| `export-long-image.sh` | 帖子导出为长图（白底黑字 + 图片拼接） |
| `mcp-call.sh <tool> [args]` | 通用 MCP 工具调用 |
| `install-check.sh` | 依赖检查 |
| `login.sh` | 登录辅助 |

---

## 八、Telegram Bot 完整能力

**零依赖实现**（urllib.request，multipart/form-data 手工构建）

### 8.1 推送能力

| 函数 | 功能 |
|------|------|
| `send()` | 发送 HTML 格式文本消息 |
| `send_photo()` | 发送单张图片 + caption |
| `send_media_group()` | 发送多张图片相册 |
| `send_publish_confirm()` | 发布确认通知 |
| `send_error()` | 错误告警 |
| `send_daily_review()` | 格式化每日复盘 |
| `send_draft_report()` | 草稿排名报告（Top 3 + 操作指引） |
| `send_draft_detail()` | 单份草稿完整详情 + 评分明细 |
| `send_all_drafts_summary()` | 全部草稿摘要列表 |
| `send_image_review()` | 图片审核（相册 + 操作指引） |

### 8.2 监听能力（telegram_listener.py）

- `getUpdates` 长轮询（30 秒间隔）
- 指令解析（10 种指令模式）
- 按 chat_id + 时间戳过滤消息
- 双超时提醒（30 分钟 / 10 分钟）
- 独立草稿选择轮询和图片审核轮询

---

## 九、独立 Skill — 内容图生成器

`skills/xhs-content-generator/` — 可独立使用的小红书内容图生成器

**触发词：** 小红书内容图 / xhs 内容 / 生成小红书图文

**执行流程：**
1. WebSearch 搜索主题资料（中文 + 英文）
2. 规划 N 页内容结构（封面 + 概念 + 核心内容 + 总结 CTA）
3. 生成 HTML（13 种 CSS 组件 class）
4. Playwright 截图 → PNG

**三种风格：**

| 风格 | 背景 | 主色 | 装饰 |
|------|------|------|------|
| warm（暖橙卡通，默认） | #FFFBF5 / 暖橙渐变 | #FF6348 | emoji + blob + 星星 |
| dark（深色科技） | #0f0c29 → #302b63 | 金色渐变 | 光晕 + 网格线 |
| minimal（简约白） | #FFFFFF | #333333 | 极简线条 |

---

## 十、XHS-Downloader 辅助工具链

`skills/xiaohongshu/tools/xhs-downloader/` — 配合 XHS-Downloader 使用

**用途：** 下载小红书收藏/点赞笔记 → 导出为 OpenClaw 记忆库格式

| 脚本 | 功能 |
|------|------|
| `batch_download.py` | 批量下载笔记到 SQLite DB |
| `export_memory.py` | 导出为单个 Markdown 文件 |
| `export_to_workspace.py` | 导出为多文件（按日期+标题命名），放入 OpenClaw workspace |

**流程：** 油猴脚本提取收藏/点赞链接 → batch_download → export → 配置 OpenClaw memorySearch

---

## 十一、部署与运维

### 11.1 安装

`install.sh` 一键安装：
- Skills 安装到 `~/.agents/skills/` + 软链接到 `~/.claude/skills/` 和 `~/.codex/skills/`
- Workflow 安装到 `~/xhs-automation/`（可自定义路径）
- 生成 launchd plist 文件（`sed` 替换 `__WORKDIR__`）
- 创建所需目录（logs / posts / output / data / config）

### 11.2 配置

`config/runtime.env`：

| 配置项 | 必填 | 说明 |
|--------|------|------|
| `ANTHROPIC_AUTH_TOKEN` | 是 | Claude API 认证 |
| `ANTHROPIC_BASE_URL` | 是 | Claude API 地址 |
| `XHS_TELEGRAM_BOT_TOKEN` | 是 | Telegram Bot Token |
| `XHS_TELEGRAM_CHAT_ID` | 是 | Telegram Chat ID |
| `XHS_CLAUDE_BIN` | 否 | Claude CLI 路径（默认 `claude`） |
| `XHS_NODE_BIN` | 否 | Node.js 路径（自动检测） |
| `XHS_NODE_PATH` | 否 | NODE_PATH |
| `MCP_URL` | 否 | MCP 服务地址（默认 localhost:18060） |
| `IMAGE_GEN_API_KEY` | 否 | 图片 AI API Key（空则走截图） |
| `IMAGE_GEN_BASE_URL` | 否 | 图片 API 地址（默认 OpenAI） |
| `IMAGE_GEN_MODEL` | 否 | 图片模型（默认 gpt-image-1） |
| `DRAFT_MODE` | 否 | lite（3份）/ pro（8份） |
| `DRAFT_CONCURRENCY` | 否 | 并发数（默认 3） |
| `DRAFT_SELECT_TIMEOUT` | 否 | 草稿选择超时分钟（默认 110） |
| `IMAGE_REVIEW_TIMEOUT` | 否 | 图片审核超时分钟（默认 30） |

### 11.3 定时调度（macOS launchd）

| plist | 时间 | 脚本 |
|-------|------|------|
| `com.yl.xhs-research` | 08:00 | research.py |
| `com.yl.xhs-create` | 09:00 | orchestrator.py / create_content.py |
| `com.yl.xhs-publish` | 11:30 / 20:30 | publish_post.py |
| `com.yl.xhs-preview` | 21:30 | send_preview.py |
| `com.yl.xhs-review` | 22:00 | review.py |
| `com.yl.xhs-keepalive` | 每 4 小时 | keepalive.py |

### 11.4 DB 恢复

`recover_db.py` — 从 `posts/` 目录扫描，把缺失记录补录到 DB

---

## 十二、文件清单

```
xiaohongshu-skill/
├── README.md                           # 项目说明
├── install.sh                          # 一键安装脚本
│
├── skills/
│   ├── xhs-content-generator/          # 独立内容图生成 Skill
│   │   ├── SKILL.md
│   │   └── scripts/screenshot.cjs      # Playwright 截图脚本
│   │
│   └── xiaohongshu/                    # 小红书 MCP Skill
│       ├── SKILL.md
│       ├── README.md / README_CN.md
│       ├── LICENSE
│       ├── scripts/
│       │   ├── start-mcp.sh / stop-mcp.sh
│       │   ├── status.sh / login.sh / install-check.sh
│       │   ├── search.sh / recommend.sh / post-detail.sh
│       │   ├── comment.sh / user-profile.sh
│       │   ├── mcp-call.sh             # 通用 MCP 调用
│       │   ├── track-topic.sh / track-topic.py
│       │   └── export-long-image.sh / export-long-image.py
│       └── tools/xhs-downloader/
│           ├── README.md
│           ├── batch_download.py
│           ├── export_memory.py
│           └── export_to_workspace.py
│
└── workflow/xhs-automation/            # 自动化工作流
    ├── README.md
    ├── publish.sh                      # 发布执行脚本
    │
    ├── config/
    │   └── runtime.env.example
    │
    ├── data/
    │   ├── content-rules.md            # 合规规则
    │   └── draft-config.json           # 草稿模式配置
    │
    ├── scripts/
    │   ├── orchestrator.py             # 总编排入口（核心）
    │   ├── research.py                 # 晨间研究
    │   ├── create_content.py           # 内容生成（旧流程/降级）
    │   ├── draft_generator.py          # 多草稿并行生成
    │   ├── draft_validator.py          # 三维验证评分
    │   ├── image_generator.py          # AI/截图图片生成
    │   ├── publish_post.py             # 发布编排
    │   ├── send_preview.py             # 次日预览
    │   ├── review.py                   # 晚间复盘
    │   ├── feedback_analyzer.py        # 评论AI分析
    │   ├── keepalive.py                # 登录保活
    │   ├── telegram.py                 # Telegram 通知（10个推送函数）
    │   ├── telegram_listener.py        # Telegram 监听（指令解析+轮询）
    │   ├── db.py                       # SQLite 数据层（31个函数/9张表）
    │   ├── config_loader.py            # 环境变量加载
    │   └── recover_db.py              # DB 恢复工具
    │
    ├── launchd-templates/              # 6 个 macOS 定时任务模板
    │
    └── examples/                       # 示例数据
        ├── candidates-2026-04-14.json
        └── posts/
            ├── 2026-04-14-post1/       # 含 meta.json + post.html + page-*.png
            └── 2026-04-14-post2/
```

---

## 十三、关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 零外部依赖 | urllib.request 替代 requests/httpx | 减少安装步骤，纯标准库 |
| MCP 协议 | 通过 HTTP + JSON-RPC 调用 | 统一接口，解耦小红书操作 |
| 多草稿竞争 | 多份生成 + 评分排名 | 提升内容质量上限 |
| 人机协作 | Telegram 交互决策 | 保留博主最终控制权 |
| 全链降级 | 每环节独立 fallback | 确保系统不因单点故障完全停摆 |
| 冷启动适应 | 权重动态调整 | 数据不足时不误导评分 |
| 路径兼容 | Claude/Agents/Codex 三平台 | install.sh 创建软链接 |
| 反馈闭环 | 评论 → 分析 → 注入 prompt | 内容自动贴合粉丝需求 |
