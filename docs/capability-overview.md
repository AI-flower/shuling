# 小红书自动发布系统 — 完整功能业务能力清单

> 版本: 2026-04-15 | 项目: shuling

---

## 一、系统定位

| 维度 | 说明 |
|------|------|
| **品牌** | OpenClaw（开源龙虾） |
| **账号定位** | 科技博主，在小红书上用大白话分享 GitHub 开源 AI 项目 |
| **内容策略** | 每天 2 篇帖子（午间 + 晚间），图文笔记形式 |
| **项目形态** | 运行在智能体工具（Claude Code / Codex / OpenClaw）中的 Skill + 后台自动化 Workflow |
| **核心能力** | 全自动选题→创作→发布→复盘→自进化闭环 |

---

## 二、系统架构

```
┌───────────────────────────────────────────────────────────────┐
│                     Skill 层（智能体工具内）                    │
│                                                               │
│  skills/xiaohongshu/     小红书 MCP 操作 Skill（12 个 API）    │
│  skills/xhs-content-generator/   内容图生成 Skill              │
│  SKILL.md 中的自进化段落   冷启动播种 + 创作知识读取            │
└───────────────────────────┬───────────────────────────────────┘
                            │ 文件系统共享 knowledge-base/
┌───────────────────────────▼───────────────────────────────────┐
│                  Workflow 层（launchd 定时调度）                │
│                                                               │
│  08:00 research.py        选题研究                             │
│  09:00 orchestrator.py    智能编排（草稿→验证→交互→图片→发布）  │
│  11:30 publish_post.py    午间发布                             │
│  20:30 publish_post.py    晚间发布                             │
│  21:30 send_preview.py    次日预览                             │
│  22:00 review.py          复盘 + 周进化分析                    │
│  每4h  keepalive.py       MCP 保活 + 多时间点数据采集          │
└───────────────────────────────────────────────────────────────┘
```

---

## 三、Skill 层能力

### 3.1 小红书 MCP Skill（skills/xiaohongshu/）

基于 xiaohongshu-mcp 封装，提供 12 个小红书 API 操作能力：

| 能力 | MCP 工具 | 脚本封装 | 说明 |
|------|----------|----------|------|
| **搜索内容** | `search_feeds` | `search.sh` | 按关键词搜索笔记 |
| **首页推荐** | `list_feeds` | `recommend.sh` | 获取推荐流 |
| **帖子详情** | `get_feed_detail` | `post-detail.sh` | 获取正文+互动数据+评论 |
| **发表评论** | `post_comment_to_feed` | `comment.sh` | 评论指定帖子 |
| **回复评论** | `reply_comment_in_feed` | — | 回复已有评论 |
| **用户主页** | `user_profile` | `user-profile.sh` | 获取用户信息 |
| **点赞/取消** | `like_feed` | — | 互动操作 |
| **收藏/取消** | `favorite_feed` | — | 互动操作 |
| **发布图文** | `publish_content` | `publish.sh` | 发布图文笔记（核心） |
| **发布视频** | `publish_with_video` | — | 发布视频笔记 |
| **登录状态** | `check_login_status` | `status.sh` | 检查+保活 |
| **登录二维码** | `get_login_qrcode` | `login.sh` | 获取扫码登录链接 |

**附加能力：**

| 能力 | 脚本 | 说明 |
|------|------|------|
| 热点跟踪 | `track-topic.sh` / `track-topic.py` | 搜索+聚合+生成 Markdown/飞书报告 |
| 长图导出 | `export-long-image.sh` / `export-long-image.py` | 帖子导出为白底黑字 JPG 长图 |
| 批量下载 | `tools/xhs-downloader/` | 批量下载帖子图片+导出记忆+导出到工作区 |
| 服务管理 | `start-mcp.sh` / `stop-mcp.sh` | 启动/停止 MCP 服务 |
| 依赖检查 | `install-check.sh` | 检查运行环境 |

### 3.2 内容图生成 Skill（skills/xhs-content-generator/）

根据主题自动生成多页小红书风格内容图（封面+内容页）。

| 能力 | 说明 |
|------|------|
| **自动搜索资料** | WebSearch 中英文搜索 + WebFetch 官方文档 |
| **规划内容结构** | 封面→概念介绍→核心内容→总结/CTA，每页 2-4 个信息模块 |
| **生成 HTML** | 1080x1440px（3:4 竖版），Google Fonts，3 种风格可选 |
| **Playwright 截图** | 逐页截图输出独立 PNG 文件 |

**三种视觉风格：**

| 风格 | 特征 |
|------|------|
| `warm`（默认） | 暖橙渐变封面，白色卡片，emoji 装饰 |
| `dark` | 深紫渐变背景，金色高亮，玻璃态卡片 |
| `minimal` | 纯白背景，细线边框，极简线条 |

### 3.3 自进化知识库（Skill 层）

| 能力 | 触发条件 | 说明 |
|------|---------|------|
| **冷启动播种** | knowledge-base/README.md 不存在时 | 竞品分析 3 组关键词 → 提取标题模式/正文结构/标签策略 → 写入 patterns.md + rules.json + README.md |
| **LLM 配置** | 首次初始化时 | 交互式选择 LLM 提供商（Claude/OpenAI/兼容格式）|
| **创作知识读取** | 每次选题/创作前 | 读取 README.md + patterns.md + rules.json 注入 prompt |

---

## 四、Workflow 层能力（8 个阶段）

### 阶段 1：晨间研究 — `research.py`（08:00）

**目标：** 从海量开源项目中筛出当天最值得写的 2 个选题

| 子能力 | 说明 |
|--------|------|
| **GitHub Trending 抓取** | 正则提取仓库路径（三级容错），前 25 个 |
| **GitHub API 搜索** | 4 组关键词轮询（OpenClaw skill / Claude Code skill / agent workflow tool / AI tool），各 6-10 个 |
| **合并去重** | 排除已发布过的项目（查 SQLite topics 表） |
| **详情丰富** | GitHub API 获取 stars/forks/language/topics，拉取 README（main→master 回退，前 3000 字符，过滤 badge/img/sponsor） |
| **竞品密度检测** | 小红书 MCP search_feeds 搜索竞品数量 |
| **三维打分** | `score_candidate`（star 高+竞品少=高分）+ `score_xhs_fit`（主线匹配度）+ `score_titleability`（标题可写性） |
| **主线优先选择** | 主线关键词（skill/openclaw/memory/browser/pdf 等）优先，非主线 -70 分 |
| **知识库读取** | 从 rules.json 读取当前权重（如有） |
| **输出** | `data/candidates-{date}.json` + topics 表记录 |

### 阶段 2：智能编排 — `orchestrator.py`（09:00）

**目标：** 将选题变成可发布的帖子，含人机协作审核

| 子能力 | 说明 |
|--------|------|
| **加载选题** | 读取 candidates JSON + 反馈洞察（feedback_analyzer 的历史数据） |
| **多草稿并行生成** | asyncio 并行调 Claude CLI，lite 模式 3 份 / pro 模式 8 份 |
| **三维验证评分** | 平台数据（蓝海指数）+ 内容质量（Claude 评审 5 维度）+ 历史对标（同 angle+style 对比）|
| **Telegram 推送草稿报告** | 发送排名+评分+亮点+风险给博主 |
| **博主选择等待** | 轮询 Telegram 消息（110 分钟超时），支持 10 种指令 |
| **AI/截图图片生成** | 四种策略：cover_ai / ai / html / auto |
| **Telegram 审图** | 推送生成的图片供博主确认（30 分钟超时） |
| **写入 DB** | 帖子+草稿+评分+图片记录入库 |
| **完整降级链** | 编排失败→单次生成→兜底模板→Telegram 告警 |

### 阶段 2a：多草稿生成 — `draft_generator.py`

| 子能力 | 说明 |
|--------|------|
| **角度×风格矩阵** | 3 种角度（pain-point/tutorial/discovery）× 3 种风格（casual/step-by-step/comparison）|
| **多样性保证** | 避开最近 7 天用过的角度，排列组合采样 |
| **反馈注入** | 读取最近 3 篇帖子的评论分析，注入创作 prompt |
| **asyncio 并行** | DRAFT_CONCURRENCY 控制并发（默认 3） |
| **lite/pro 双模式** | lite=3 份（快速），pro=8 份（深度探索） |
| **知识库注入** | 读取 knowledge-base/ 活跃 pattern 注入 prompt |

### 阶段 2b：草稿验证 — `draft_validator.py`

| 子能力 | 说明 |
|--------|------|
| **平台数据验证** | 标题关键词 → MCP search_feeds → 蓝海指数（≥5 得 90-100 分）|
| **内容质量评估** | Claude 批量评分 5 维度：标题吸引力 25% / 内容完整性 30% / 合规性 20% / 格式匹配 15% / CTA 有效性 10% |
| **历史对标** | 同 angle+style 组合的历史平均互动率对比 |
| **权重自适应** | 冷启动(≤5)：平台50%+质量50% / 成长期(6-19)：45%+40%+15% / 成熟期(≥20)：40%+35%+25% |
| **关键词缓存** | 24 小时 TTL 避免重复搜索（keyword_tracking 表） |

### 阶段 2c：图片生成 — `image_generator.py`

| 子能力 | 说明 |
|--------|------|
| **cover_ai 策略** | 封面用 AI（OpenAI gpt-image-1）+ 内容页用 Playwright 截图 |
| **ai 策略** | 全部页面用 AI 生成 |
| **html 策略** | 全部页面用 HTML 截图 |
| **auto 策略** | AI 优先，失败降级为截图 |
| **品牌风格注入** | IMAGE_BRAND_STYLE 配置注入所有图片 prompt |
| **零依赖 API 调用** | urllib 直接调 OpenAI Images API，不依赖 SDK |
| **asyncio 并行** | 多图并行生成 |

### 阶段 3：定时发布 — `publish_post.py` + `publish.sh`（11:30/20:30）

| 子能力 | 说明 |
|--------|------|
| **DB 查询发布** | 从 posts 表查 scheduled 状态的帖子 |
| **目录直接发布** | 从 post 目录读取 meta.json + 图片 |
| **MCP 健康检查** | curl 检测 MCP Session-Id 响应头 |
| **自动启动 MCP** | 未就绪时调 start-mcp.sh |
| **JSON-RPC 调用** | 构建 publish_content 请求，解析响应判断成败 |
| **DB 状态更新** | 成功→published + note_id / 失败→failed |
| **发布约束** | 标题 ≤20 字 / 正文 ≤1000 字 / 日发布 ≤50 条 |

### 阶段 4：次日预览 — `send_preview.py`（21:30）

| 子能力 | 说明 |
|--------|------|
| **扫描帖子目录** | 查找次日日期的 post 目录 |
| **发送图文相册** | Telegram sendMediaGroup 发送封面+内容页 |
| **发送 meta 信息** | 标题+正文+标签+定时发布时间 |

### 阶段 5：晚间复盘 — `review.py`（22:00）

| 子能力 | 说明 |
|--------|------|
| **互动数据采集** | MCP get_feed_detail 拉取每篇帖子的 likes/saves/comments/shares |
| **粉丝数采集** | MCP check_login_status 获取 follower_count |
| **洞察生成** | 最好/最差帖子对比 + 收藏率分析 + 趋势对比 |
| **DB 存储** | daily_reviews 表 + post_metrics 表 |
| **Telegram 日报** | 发送结构化日报（帖子数据+洞察+明日建议） |
| **评论反馈分析** | 调用 feedback_analyzer 采集评论 + AI 分析 |
| **知识库阶段更新** | 更新 README.md 帖子计数和阶段（cold-start/growth/mature） |
| **周进化分析** | 每周日触发（详见阶段 7） |

### 阶段 6：登录保活 — `keepalive.py`（每 4 小时）

| 子能力 | 说明 |
|--------|------|
| **MCP 进程检查** | 读 PID 文件 + os.kill 信号检测 |
| **自动启动 MCP** | 未运行时调 start-mcp.sh |
| **登录保活** | 调 check_login_status 维持会话 |
| **二维码告警** | 登录过期时获取二维码 → Telegram 推送 |
| **多时间点采集** | T+1h / T+6h / T+24h / T+72h 四个检查点自动采集互动数据，±2 小时窗口 |

### 阶段 7：周进化分析 — `review.py` 中的 `weekly_evolution()`（每周日 22:00）

| 子能力 | 说明 |
|--------|------|
| **周数据导出** | 从 SQLite 导出本周所有帖子数据为结构化 Markdown（标题/角度/风格/pattern/预测分/实际互动/增长曲线/收藏率）|
| **LLM 归因分析** | 调 llm.call_llm() 传入周数据+当前 patterns+rules，分析什么有效什么无效 |
| **Pattern 发现** | 表现好的帖子共性 → 新 pattern（status: experimental） |
| **Pattern 升降级** | 验证有效 → confidence 升级 / 连续失效 → deprecated |
| **规则权重更新** | 根据数据调整 angle_weights 和 style_weights |
| **评分校准** | 预测分 vs 实际收藏率偏差分析 |
| **README 摘要更新** | Top Pattern + 本周关键发现 + 近期复盘入口 |
| **旧复盘清理** | 保留最近 4 周，自动删除更早的 |

### 阶段 8：反馈分析 — `feedback_analyzer.py`（review.py 内调用）

| 子能力 | 说明 |
|--------|------|
| **评论采集** | MCP get_feed_detail 获取评论列表 |
| **垃圾过滤** | 纯 emoji / 太短 / 引流广告关键词 |
| **AI 情感分析** | Claude 分析：正面/负面/提问分类 |
| **需求提取** | 提取 top 问题 / top 好评 / top 吐槽 / 内容需求 |
| **DB 存储** | comment_analysis 表（支持跨会话查询） |
| **创作注入** | build_feedback_section() 将分析结果格式化为 prompt 片段 |

---

## 五、自进化系统能力

### 5.1 知识库结构

```
knowledge-base/
  README.md        索引 + 阶段 + Top Pattern 摘要 + 近期复盘入口
  patterns.md      活跃 Pattern 库（≤15 条），含模板/示例/适用场景/confidence
  rules.json       程序可读的生成规则（角度权重/风格权重/标题约束/标签策略）
  reviews/         周复盘文件（每周一个，保留最近 4 周）
```

### 5.2 Pattern 生命周期

```
竞品分析播种(confidence: low) ──验证 1 次──→ medium ──连续 3+ 次有效──→ high
自己数据发现(experimental)   ──验证 1 次──→ medium ──连续 3+ 次有效──→ high

连续 3 次差 → deprecated（移出活跃列表）
活跃 > 15 条 → 淘汰 confidence 最低的
```

### 5.3 阶段演进

| 阶段 | 条件 | 行为 |
|------|------|------|
| cold-start | 帖子 < 10 | 依赖竞品 pattern（confidence: low），鼓励探索多种风格 |
| growth | 10 ≤ 帖子 < 30 | 自己数据开始验证 pattern，规则权重首次被数据更新 |
| mature | 帖子 ≥ 30 | 完整归因分析，pattern 库以自己数据为主，权重完全数据驱动 |

### 5.4 数据闭环流

```
创作时记录 angle/style/pattern_used 到 DB
    ↓
keepalive.py 采集 T+1h/6h/24h/72h 互动数据
    ↓
review.py 每日复盘 + 评论 AI 分析
    ↓
review.py 每周日导出数据 → LLM 归因分析
    ↓
程序化更新 patterns.md / rules.json / README.md
    ↓
下周 research.py + create_content.py 读取更新后的知识库
    ↓ 循环
```

---

## 六、Telegram 双向交互能力

### 推送能力（telegram.py，10 个函数）

| 函数 | 用途 |
|------|------|
| `send(text)` | 通用文本消息 |
| `send_photo(path, caption)` | 发送单张图片 |
| `send_media_group(paths, caption)` | 发送图片相册 |
| `send_publish_confirmation(title, note_id)` | 发布成功确认 |
| `send_error(context, error)` | 错误告警 |
| `send_daily_review(...)` | 结构化日报 |
| `send_draft_report(drafts, scores)` | 草稿评分排名报告 |
| `send_draft_detail(draft)` | 单份草稿详情 |
| `send_draft_summary(date, slot, count)` | 草稿生成摘要 |
| `send_image_review(images, meta)` | 审图推送 |

### 监听能力（telegram_listener.py，10 种指令）

| 指令 | 格式 | 说明 |
|------|------|------|
| 选择草稿 | `选1` / `1` / `select 1` | 选定第 N 个草稿 |
| 跳过 | `跳过` / `skip` | 跳过当前 slot |
| 查看更多 | `更多` / `more` | 查看更多草稿详情 |
| 自动选择 | `自动` / `auto` | 系统选最高分 |
| 确认发布 | `确认` / `ok` / `好` | 确认审图通过 |
| 重新生成 | `重新生成1` / `redo 1` | 重新生成第 N 张图 |
| 取消 | `取消` / `cancel` | 取消本次发布 |
| 换风格 | `换风格` | 切换图片生成策略 |
| 全部重做 | `全部重做` / `redo all` | 重新生成全部图片 |
| 查看原文 | `原文` / `原始` | 查看生成的 HTML 源码 |

---

## 七、数据存储架构

### SQLite 数据库（WAL 模式，9 张表）

| 表名 | 记录数量级 | 核心用途 |
|------|-----------|---------|
| **posts** | 每日 2 条 | 帖子主记录（标题/正文/标签/状态/角度/风格/pattern） |
| **post_metrics** | 每帖 5 条 | 互动数据时序（review + T+1h/6h/24h/72h） |
| **topics** | 每日 15-30 条 | 选题候选记录 |
| **daily_reviews** | 每日 1 条 | 复盘汇总 |
| **drafts** | 每帖 3-8 条 | 多草稿记录 |
| **draft_scores** | 每帖 3-8 条 | 草稿三维评分 |
| **comment_analysis** | 每帖 1 条 | 评论 AI 分析结果 |
| **keyword_tracking** | 按需 | 关键词竞争度缓存（24h TTL） |
| **generated_images** | 每帖 5-6 条 | 图片生成记录 |

### 知识库文件

| 文件 | 更新频率 | 用途 |
|------|---------|------|
| README.md | 每日 | 阶段状态 + Top Pattern 摘要 |
| patterns.md | 每周 | 活跃 Pattern 库 |
| rules.json | 每周 | 程序可读的生成规则 |
| reviews/*.md | 每周 | 周复盘数据 |

---

## 八、LLM 调用能力

### 统一接口（llm.py）

| 提供商 | 配置值 | SDK |
|--------|--------|-----|
| Claude API | `LLM_PROVIDER=claude` | Anthropic Python SDK |
| OpenAI API | `LLM_PROVIDER=openai` | OpenAI Python SDK |
| 兼容格式 | `LLM_PROVIDER=openai-compatible` | OpenAI SDK + 自定义 base_url |

**兼容旧配置：** `LLM_API_KEY` 未设置时自动回退到 `ANTHROPIC_AUTH_TOKEN`。

### LLM 调用场景

| 场景 | 调用方 | 模型 | 用途 |
|------|--------|------|------|
| 草稿生成 | draft_generator.py → Claude CLI | Claude | 生成差异化文案 |
| 内容生成 | create_content.py → Claude CLI | Claude | 生成 HTML 帖子 |
| 质量评估 | draft_validator.py → Claude CLI | Claude | 5 维度内容打分 |
| 评论分析 | feedback_analyzer.py → Claude CLI | Claude | 情感分类+需求提取 |
| 周进化分析 | review.py → llm.call_llm() | 可配置 | 归因分析+规则更新 |

---

## 九、图片生成能力

| 策略 | 封面 | 内容页 | 依赖 |
|------|------|--------|------|
| **cover_ai** | OpenAI gpt-image-1 | Playwright 截图 | IMAGE_GEN_API_KEY |
| **ai** | OpenAI gpt-image-1 | OpenAI gpt-image-1 | IMAGE_GEN_API_KEY |
| **html** | Playwright 截图 | Playwright 截图 | Node.js + Playwright |
| **auto** | AI 优先，失败降级截图 | AI 优先，失败降级截图 | 两者都需 |

**图片规格：** 1080x1440px（3:4 竖版，小红书标准）

**品牌风格：** 通过 `IMAGE_BRAND_STYLE` 配置注入所有 AI 图片 prompt（OpenClaw 暖橙风格+龙虾吉祥物）。

---

## 十、部署架构

### 定时调度（macOS launchd，6 个 plist 模板）

| plist | 时间 | 脚本 |
|-------|------|------|
| com.yl.xhs-research | 08:00 | research.py |
| com.yl.xhs-create | 09:00 | orchestrator.py / create_content.py |
| com.yl.xhs-publish | 11:30 + 20:30 | publish_post.py |
| com.yl.xhs-preview | 21:30 | send_preview.py |
| com.yl.xhs-review | 22:00 | review.py |
| com.yl.xhs-keepalive | 每 4h | keepalive.py |

### 安装方式

```bash
bash install.sh [安装目录]
```

安装脚本自动：
- Skills 安装到三平台路径（`~/.agents/` / `~/.claude/` / `~/.codex/`）并创建符号链接
- Workflow 安装到指定目录（默认 `~/xhs-automation/`）
- 生成 launchd plist（替换工作目录路径）
- 交互式 LLM 配置（选择提供商+API Key）
- 创建 knowledge-base/ 目录结构

### 外部依赖清单

| 依赖 | 必须 | 用途 |
|------|------|------|
| xiaohongshu-mcp | 是 | 小红书所有操作 |
| Claude CLI | 是 | 内容生成/质量评估 |
| Node.js + Playwright | 是 | HTML 截图 |
| Python 3 | 是 | 所有自动化脚本 |
| Telegram Bot | 是 | 通知+双向交互 |
| OpenAI API | 否 | AI 图片生成（可选，无则全走截图） |
| Anthropic/OpenAI SDK | 否 | llm.py 统一调用（仅周进化分析需要） |

### 异常处理策略

| 场景 | 处理 |
|------|------|
| Claude CLI 生成失败 | 本地 HTML 兜底模板（generate_html_fallback） |
| AI 图片生成失败 | 降级为 Playwright 截图 |
| MCP 服务未运行 | keepalive 自动启动 |
| 登录过期 | Telegram 推送二维码 |
| Telegram 超时 | 自动选择最高分草稿 |
| LLM 调用失败 | 跳过进化步骤，不阻塞发布 |
| knowledge-base 文件损坏 | try/except 用默认值，不阻塞创作 |
| 数据库损坏 | recover_db.py 从 posts/ 目录重建 |

---

## 十一、内容合规规则（data/content-rules.md）

| 类型 | 规则 |
|------|------|
| **硬性禁止** | 不出现平台名（小红书/抖音等）、不提区块链/Web3、不做"AI 写小红书"主题 |
| **格式约束** | 标题 ≤20 字、正文 ≤1000 字、标签 5-8 个 |
| **质量标准** | 教程第 4 页必须有可操作步骤、命令要完整可运行、每页 3-5 个信息点 |
| **品牌一致性** | 保持 OpenClaw 口吻、第一人称真实分享感 |

---

## 十二、配置项完整列表

| 配置项 | 必填 | 默认值 | 说明 |
|--------|------|--------|------|
| LLM_PROVIDER | 否 | claude | LLM 提供者 |
| LLM_API_KEY | 否 | 空 | LLM API Key |
| LLM_BASE_URL | 否 | 空 | 自定义 LLM API 地址 |
| LLM_MODEL | 否 | claude-sonnet-4-20250514 | LLM 模型名 |
| ANTHROPIC_AUTH_TOKEN | **是** | 空 | Claude CLI 认证 |
| ANTHROPIC_BASE_URL | **是** | 空 | Claude API 地址 |
| XHS_TELEGRAM_BOT_TOKEN | **是** | 空 | Telegram Bot Token |
| XHS_TELEGRAM_CHAT_ID | **是** | 空 | Telegram 聊天 ID |
| XHS_CLAUDE_BIN | 否 | claude | Claude CLI 路径 |
| XHS_NODE_BIN | 否 | node | Node.js 路径 |
| XHS_NODE_PATH | 否 | 空 | NODE_PATH |
| MCP_URL | 否 | http://localhost:18060 | MCP 服务地址 |
| IMAGE_GEN_API_KEY | 否 | 空 | 图片 AI API Key |
| IMAGE_GEN_BASE_URL | 否 | https://api.openai.com/v1 | 图片 API 地址 |
| IMAGE_GEN_MODEL | 否 | gpt-image-1 | 图片生成模型 |
| IMAGE_GEN_SIZE | 否 | 1024x1024 | 图片尺寸 |
| IMAGE_GEN_STYLE | 否 | vivid | 图片风格 |
| IMAGE_BRAND_STYLE | 否 | OpenClaw 品牌描述 | 品牌视觉风格 |
| DRAFT_MODE | 否 | lite | 草稿模式(lite/pro) |
| DRAFT_CONCURRENCY | 否 | 3 | 草稿并发数 |
| DRAFT_SELECT_TIMEOUT | 否 | 110 | 草稿选择超时(分钟) |
| IMAGE_REVIEW_TIMEOUT | 否 | 30 | 审图超时(分钟) |
| POLL_INTERVAL | 否 | 30 | Telegram 轮询间隔(秒) |
