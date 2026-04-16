# 小红书 Skill 重设计 — 完整规格文档

> 日期: 2026-04-15
> 状态: draft
> 项目: shuling

---

## 一、问题陈述

### 现有系统的核心问题

1. **智能在 Python 脚本里，不在 Skill 里**：research.py、orchestrator.py、draft_generator.py 等 17 个脚本包含全部业务逻辑，SKILL.md 只是脚本索引表。Agent 读了不知道该做什么。

2. **平台绑定**：workflow 层为 macOS launchd + Claude CLI 设计，在 Hermes（OpenAI 模型）、Codex、OpenClaw 等平台上无法运行。脚本硬编码 `claude --dangerously-skip-permissions --print -p` 调用。

3. **自进化对用户不可见**：pattern 发现、权重调整全部由脚本自动完成，用户不参与也不成长。系统变好了，用户没变好。

4. **用户体验碎片化**：实际对话记录显示，用户在 Hermes 上反复被 API Key 配额、脚本超时、Agent 不理解流程等问题打断。

### 实际对话中暴露的问题

- 用户问"小红书自动发布有在运行吗"→ Agent 只查 cron/launchctl，不知道 skill 内有完整自动化流程
- 用户说"给你安装的小红书 skill 中本身具有自动化的流程你详细的看看"→ Agent 超时卡死（30 分钟无响应）
- 用户给内容让 Hermes 帮忙生成配图 → 反复卡在 Gemini API Key 配额问题上

---

## 二、设计目标

### 核心目标

帮助用户从零成为优秀的小红书博主，系统越用越聪明，用户操作越来越少。

### 具体目标

1. **跨平台运行**：同一份 Skill 在 Hermes、Claude Code、Codex、OpenClaw 上都能工作
2. **系统主动推送**：不等用户来问，定时推送选题/草稿供用户选择确认
3. **用户操作最小化**：从"每天点 4-5 下"渐进到"每天点 1 下"
4. **自进化闭环**：发布数据自动驱动内容策略优化，无需用户手动分析
5. **偏好自动学习**：从用户的选择行为中学习，逐步减少选项数量

### 非目标

- 不做多平台发布（只做小红书）
- 不做付费推广管理
- 不做电商转化

---

## 三、用户旅程

### 目标用户

- 当前：用户自己（weiyong），在 Hermes + Telegram 上使用，已有小红书发帖经验但无系统化流程
- 未来：小红书小白，可能在任何支持 Skill 的平台上使用

### 完整旅程

```
第 0 阶段：开局对话（一次性，约 2 分钟）
  系统问 3 个问题，建立博主画像
  → 写入 knowledge-base/profile.json

第 1 阶段：冷启动（第 1-2 周）
  • 竞品分析播种知识库
  • 每天推 3 个选题，出 2 份草稿
  • 用户选择 → 记录偏好
  • 发布后采集数据（样本积累期）

第 2 阶段：学习期（第 2-4 周）
  • 数据足够（≥10 篇），开启自进化分析
  • 每天推 2 个选题，出 1+1 份草稿
  • 每周推一份成长报告

第 3 阶段：成熟期（第 4 周+）
  • 直接推 1 个选题 + 1 份草稿
  • 用户回复"发"即完成
  • 不满意回复"换"，系统再出一套
```

### 每日交互流（成熟期）

```
08:00  系统：「今天推荐给你的选题：XXX。草稿已生成，标题：XXX。配图 5 张。回复"发"确认午间发布，或回复"换"」
用户 ："发"
11:30  系统自动发布午间档
12:00  系统：「午间档已发布 ✅ 晚间档推荐：XXX。回复"发"或"换"」
用户 ："发"
20:30  系统自动发布晚间档
22:00  系统：「📊 今日数据：午间 ⭐89 ❤️132 / 晚间 ⭐47 ❤️203。收藏率不错，继续保持清单体内容」
```

---

## 四、系统架构

```
┌─────────────────────────────────────────────────────┐
│                 SKILL.md（大脑）                      │
│                                                       │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────────┐  │
│  │ 选题策略     │ │ 创作规则      │ │ 自进化引擎   │  │
│  │ 怎么找题     │ │ 怎么写稿      │ │ 偏好学习     │  │
│  │ 怎么打分     │ │ 怎么评估      │ │ 数据分析     │  │
│  │ 推几个给用户 │ │ 合规检查      │ │ 策略调整     │  │
│  └─────────────┘ └──────────────┘ └──────────────┘  │
│                                                       │
│  Agent 读了就知道每一步该做什么，跨平台通用            │
└───────────────────────┬───────────────────────────────┘
                        │ Agent 调用
┌───────────────────────▼───────────────────────────────┐
│                 scripts/（手脚）                        │
│                                                        │
│  xhs.sh          小红书 MCP 所有操作的统一入口          │
│  image.py        图片生成（Gemini API）                 │
│  screenshot.cjs  HTML → PNG 截图（降级方案）            │
│  db.sh           SQLite 读写封装                        │
└───────────────────────┬───────────────────────────────┘
                        │
┌───────────────────────▼───────────────────────────────┐
│                 data/（记忆）                           │
│                                                        │
│  xhs.db                持久化所有业务数据               │
│  knowledge-base/       自进化知识库                     │
│  content-rules.md      内容合规规则                     │
└───────────────────────┬───────────────────────────────┘
                        │
┌───────────────────────▼───────────────────────────────┐
│              platform/（各平台适配指南）                 │
│                                                        │
│  hermes.md       Hermes: cron + Telegram 推送          │
│  claude-code.md  Claude Code: /loop + 终端交互          │
│  codex.md        Codex: task + 终端交互                 │
└───────────────────────────────────────────────────────┘
```

### 设计原则

1. **Skill-as-Brain**：业务智能全在 SKILL.md 里，Agent 读了就能执行
2. **Scripts-as-Hands**：脚本只做 Agent 做不了的物理操作（API 调用、图片处理、数据库）
3. **Platform-Agnostic**：SKILL.md 不包含任何平台特定逻辑
4. **数据驱动**：所有决策基于数据，不靠硬编码规则

---

## 五、文件结构

```
shuling/
├── SKILL.md                          # 核心：Agent 的完整操作手册
├── scripts/
│   ├── xhs.sh                        # 小红书 MCP 统一入口
│   ├── image.py                      # Gemini 图片生成
│   ├── screenshot.cjs                # HTML→PNG 截图（降级）
│   └── db.sh                         # SQLite 读写封装
├── data/
│   ├── xhs.db                        # SQLite 数据库（运行时生成）
│   └── content-rules.md              # 内容合规规则
├── knowledge-base/                   # 自进化知识库（运行时生成）
│   ├── profile.json                  # 博主画像
│   ├── preferences.json              # 用户偏好（自动学习）
│   ├── patterns.md                   # 有效 pattern 库
│   ├── anti-patterns.md              # 无效 pattern
│   └── evolution-log.md              # 进化日志
├── templates/
│   └── post.html                     # HTML 截图模板
├── platform/
│   ├── hermes.md                     # Hermes 适配指南
│   ├── claude-code.md                # Claude Code 适配指南
│   └── codex.md                      # Codex 适配指南
└── install.sh                        # 安装脚本
```

---

## 六、SKILL.md 详细设计

### 6.1 触发词与使用场景

```yaml
name: xiaohongshu
description: |
  薯灵。帮你选题、写稿、发布、复盘，越用越懂你。
  使用场景：
  - "帮我发小红书"
  - "今天发什么"
  - "小红书选题"
  - "看看昨天的数据"
  - "我想做XX方向的博主"
```

### 6.2 首次使用：博主画像建立

当 `knowledge-base/profile.json` 不存在时触发。

**对话流程**（Agent 按此执行）：

```
第一步：问领域方向
  "你想在小红书上做什么方向的博主？比如：
   • AI 工具推荐
   • 美食探店
   • 职场干货
   • 穿搭分享
   • 读书笔记
   或者告诉我你自己的想法"

第二步：问目标受众
  "你的目标读者是谁？比如：
   • 程序员 / 产品经理
   • 大学生
   • 职场新人
   • 宝妈
   或者描述你想吸引什么样的人"

第三步：问风格偏好
  "你希望什么样的内容风格？
   • 轻松口语（像朋友聊天）
   • 专业干货（有深度有数据）
   • 幽默吐槽（有梗有共鸣）
   或者给我看一个你喜欢的博主/帖子，我来分析"
```

**写入 profile.json**：

```json
{
  "niche": "AI工具推荐",
  "audience": "程序员、技术爱好者",
  "tone": "轻松口语",
  "goals": "分享实用AI工具，积累粉丝",
  "created_at": "2026-04-15",
  "updated_at": "2026-04-15"
}
```

**随后执行冷启动播种**：

```
第四步：竞品分析
  1. 用 xhs.sh search 搜索 3 组与用户领域相关的关键词
  2. 对 top 10 帖子调 xhs.sh detail 获取完整内容
  3. 分析提取：
     - 标题模式 3-5 个
     - 正文结构 2-3 种
     - 高频标签 top 10
     - 互动引导话术 2-3 种
  4. 写入 knowledge-base/patterns.md（初始 pattern，标记 source: competitor, confidence: low）
  5. 告诉用户："我已经分析了你这个领域的爆款帖子，找到了 X 个有效模式。明天开始帮你选题和创作。"
```

### 6.3 每日流程：选题 → 创作 → 发布

#### 6.3.1 选题研究

**Agent 执行步骤**：

```
1. 读取 knowledge-base/profile.json 了解博主领域
2. 读取 knowledge-base/preferences.json 了解用户偏好权重
3. 读取 knowledge-base/patterns.md 了解有效 pattern

4. 获取候选选题（根据博主领域调整来源）：
   - 如果领域是 AI/科技类：
     a) curl GitHub Trending 页面，提取前 15 个仓库
     b) GitHub API 搜索领域相关关键词，各取 5-10 个
   - 如果领域是其他类：
     a) WebSearch 搜索领域最新热点
     b) xhs.sh recommend 获取推荐流中相关内容
   - 通用：xhs.sh search 搜索领域关键词，了解当前热门话题

5. 合并去重，排除已发布过的选题（scripts/db.sh query-posts）

6. 对每个候选打分（Agent 自己判断，参考以下维度）：
   - 受众匹配度：与 profile.json 的受众是否一致
   - 内容可写性：能否写成具体的教程/清单/故事
   - 竞品密度：xhs.sh search 结果多少（少=蓝海）
   - 用户偏好匹配：与 preferences.json 中高权重的主题类型是否一致
   - 时效性：是否是最近的热点

7. 根据当前信心度决定推送数量：
   - preferences.json 中 confidence_level < 0.5 → 推 3 个
   - 0.5 ≤ confidence_level < 0.75 → 推 2 个
   - confidence_level ≥ 0.75 → 推 1 个（直接推最佳）

8. 将选题推送给用户，等待选择
   - 每个选题包含：主题名 + 一句话理由 + 竞品密度
   - 如果只推 1 个：附加"回复'换'我再找一个"

9. 记录用户选择：scripts/db.sh log-choice
```

#### 6.3.2 草稿生成

**Agent 执行步骤**：

```
1. 基于用户选择的选题，读取 content-rules.md 了解合规规则

2. 生成草稿（Agent 自己写，参考以下规则）：
   - 标题：≤20 字，使用 patterns.md 中有效的标题模式
   - 正文：≤1000 字，结构参考 profile.json 中的 tone
   - 标签：5-8 个
   - 合规检查：不出现禁止词、不提其他平台名

3. 根据信心度决定草稿数量：
   - confidence_level < 0.5 → 出 2 份不同风格
   - confidence_level ≥ 0.5 → 出 1 份 + 1 个备选标题

4. 推送给用户确认
   - 展示：标题 + 正文前 200 字 + 标签
   - 如果 2 份："选 1 还是 2？"
   - 如果 1 份："回复'发'确认，或'换'重新生成"
```

#### 6.3.3 图片生成

**Agent 执行步骤**：

```
1. 根据草稿内容，规划 5-6 张图的内容（封面 + 内容页 + CTA 收尾页）

2. 检查图片生成能力：
   scripts/image.py --check
   - 返回 0：Gemini 可用，走 AI 生图
   - 返回非 0：走 HTML 截图降级

3. AI 生图路径：
   对每张图调用：scripts/image.py "图片描述prompt" 输出路径
   - 封面：突出视觉冲击力，包含主题核心元素
   - 内容页：与该页具体知识点相关
   - 所有图片保持统一风格

4. 截图降级路径：
   a) 生成 HTML 文件（参考 templates/post.html 的结构，1080x1440px）
   b) 调用 scripts/screenshot.cjs html文件路径 输出目录

5. 将图片路径写入 meta.json，推送给用户审核
```

#### 6.3.4 发布

**Agent 执行步骤**：

```
1. 用户确认后，检查 MCP 状态：
   scripts/xhs.sh status
   - 未登录 → scripts/xhs.sh login → 将二维码推送给用户

2. 组装发布数据为 JSON（包含 title/content/tags/images）

3. 发布：
   scripts/xhs.sh publish meta.json

4. 解析返回结果：
   - 成功 → 记录 note_id：scripts/db.sh add-post
   - 失败 → 通知用户失败原因

5. 记录本次发布的元数据到 DB（选题/角度/风格/pattern_used）
```

### 6.4 每日复盘：数据采集 → 日报推送

**Agent 执行步骤**：

```
1. 查询今日已发布的帖子：scripts/db.sh query-posts --today

2. 对每篇帖子采集互动数据：
   scripts/xhs.sh detail <note_id>
   → 提取 likes / saves / comments / shares
   → scripts/db.sh add-metrics

3. 采集评论内容：
   从 detail 返回中提取评论列表
   过滤垃圾评论（纯 emoji / ≤2 字 / 引流广告）
   分析评论：正面/负面/提问 分类，提取高频问题和内容需求

4. 计算关键指标：
   - 收藏率 = saves / likes（>50% 为优秀）
   - 与同类型历史帖子对比

5. 更新偏好模型（详见 6.5 自进化引擎）

6. 生成日报推送给用户：
   - 每篇帖子的互动数据
   - 一句话洞察（什么表现好/差，为什么）
   - 如果评论中有高频提问，提示"XX 可能是下一条帖子的好选题"
```

### 6.5 自进化引擎

#### 6.5.1 用户偏好学习（每次用户做选择时自动更新）

```
触发时机：用户从 N 个选题中选了 1 个，或从 N 份草稿中选了 1 个

更新逻辑：
1. 读取 knowledge-base/preferences.json
2. 被选中的选项 → 对应类型的 chosen + 1
3. 被跳过的选项 → 对应类型的 skipped + 1
4. 重新计算每个类型的 weight = chosen / (chosen + skipped)
5. 重新计算整体 confidence_level = 所有高权重(>0.7)类型的 chosen 总数 / 总选择次数
6. 写回 preferences.json
```

**preferences.json 结构**：

```json
{
  "confidence_level": 0.72,
  "total_choices": 28,
  "topic_preferences": {
    "AI工具推荐": {"chosen": 8, "skipped": 1, "weight": 0.89},
    "编程教程": {"chosen": 2, "skipped": 5, "weight": 0.29},
    "行业新闻": {"chosen": 3, "skipped": 3, "weight": 0.50}
  },
  "style_preferences": {
    "清单体": {"chosen": 6, "skipped": 1, "weight": 0.86},
    "避坑体": {"chosen": 3, "skipped": 4, "weight": 0.43},
    "教程体": {"chosen": 2, "skipped": 2, "weight": 0.50}
  },
  "title_pattern_preferences": {
    "数字清单": {"chosen": 5, "skipped": 0, "weight": 1.0},
    "反差悬念": {"chosen": 1, "skipped": 3, "weight": 0.25}
  },
  "options_config": {
    "topic_options": 2,
    "draft_options": 1,
    "reduce_threshold": 0.75,
    "expand_on_reject": true
  },
  "updated_at": "2026-04-15"
}
```

**选项递减逻辑**：

```
if confidence_level ≥ 0.75:
    推 1 个选题 + 1 份草稿
elif confidence_level ≥ 0.5:
    推 2 个选题 + 1 份草稿（附备选标题）
else:
    推 3 个选题 + 2 份草稿

if 用户回复"换"（拒绝推荐）:
    本次临时扩展选项（+2 个选题或 +1 份草稿）
    confidence_level -= 0.05（小幅回调信心）
```

#### 6.5.2 内容效果分析（每日自动运行）

```
触发时机：每日复盘时（发布 24h 后数据相对稳定）

分析逻辑：
1. 从 DB 读取该帖子的元数据（角度/风格/标题模式/标签策略）
2. 从 DB 读取互动数据（likes/saves/comments）
3. 计算收藏率 = saves / max(likes, 1)
4. 与同类型历史均值对比

效果判定：
- 收藏率 ≥ 5% → 表现优秀，提取该帖子的 pattern
- 收藏率 2-5% → 表现正常，不做调整
- 收藏率 < 2% → 表现较差，分析原因

pattern 提取（表现优秀时）：
- 标题模式 → 加入 patterns.md（confidence: experimental）
- 角度+风格组合 → preferences.json 中对应 weight +0.1
- 标签策略 → 如果某些标签反复出现在高收藏帖子里，记录

anti-pattern 标记（表现较差时）：
- 如果同类型连续 3 次收藏率 < 2% → 加入 anti-patterns.md
- preferences.json 中对应 weight -0.1
```

#### 6.5.3 周进化分析（每周日自动运行）

```
触发时机：每周日的复盘流程中

分析逻辑：
1. 从 DB 导出本周所有帖子数据
2. 综合分析：
   - 哪种角度+风格组合效果最好
   - 哪些 pattern 被验证有效（连续 3+ 次收藏率 ≥ 5%）
   - 哪些 pattern 应该淘汰（连续 3 次收藏率 < 2%）
   - 预测分 vs 实际数据的偏差

3. 更新知识库：
   - patterns.md：有效 pattern confidence 升级，失效 pattern 移入 anti-patterns.md
   - preferences.json：根据数据微调 weight
   - evolution-log.md：记录本次进化的调整内容和数据支撑

4. pattern 生命周期管理：
   competitor(冷启动播种, confidence: low)
     → 验证 1 次 → medium
     → 连续 3+ 次有效 → high
   experimental(自己数据发现)
     → 验证 1 次 → medium
     → 连续 3+ 次有效 → high
   连续 3 次差 → deprecated（移入 anti-patterns.md）
   patterns.md 活跃 pattern ≤ 15 条，超出淘汰 confidence 最低的

5. 生成周报推送给用户：
   - 本周数据总览
   - 最佳/最差帖子及原因
   - 新发现的有效 pattern
   - 下周策略建议
```

### 6.6 内容合规规则

独立文件 `data/content-rules.md`，Agent 在生成草稿前必读。

**规则摘要**：

- **绝对禁止**：不提平台名（微信/抖音/知乎/GitHub→用"开源社区"）、不提区块链/Web3、不写"AI写小红书"主题、不出现费用信息、不加篇数编号
- **格式约束**：标题 ≤20 字 / 正文 ≤1000 字 / 标签 5-8 个
- **写作风格**：口语化有真人感、适量 emoji、痛点→方案→效果结构
- **质量标准**：教程类第 4 页必须有可操作步骤、命令要完整可运行、每页 3-5 个信息点
- **标题规则**：禁止长期重复相同模板、优先写人群+结果/人群+错误/顺序+后果

### 6.7 工具参考

#### xhs.sh — 小红书 MCP 统一入口

```bash
scripts/xhs.sh <命令> [参数...]

命令列表：
  search <关键词>              搜索小红书内容，返回 JSON
  recommend                    获取首页推荐流，返回 JSON
  detail <note_id>             获取帖子详情+互动数据+评论，返回 JSON
  publish <meta.json路径>      发布图文笔记，返回 JSON（含 note_id）
  comment <note_id> <内容>     发表评论
  status                       检查登录状态，返回 JSON
  login                        获取登录二维码链接
  user <user_id>               获取用户主页信息

所有命令输出 JSON 格式，Agent 直接解析。
MCP 服务未运行时自动启动。
```

#### image.py — 图片生成

```bash
# 检查是否可用
scripts/image.py --check
# 返回 0 = 可用，非 0 = 不可用

# 配置 API Key
scripts/image.py --set-key "API_KEY"

# 生成图片
scripts/image.py "图片描述prompt" /output/path.png
# 图片规格：1024x1024 或由 API 决定
```

#### screenshot.cjs — HTML 截图

```bash
NODE_PATH="$(npm root -g)" node scripts/screenshot.cjs <html文件路径> <输出目录>
# 按 .page class 逐页截图，输出 page-1.png, page-2.png, ...
# 页面规格：1080x1440px（小红书标准 3:4）
```

#### db.sh — SQLite 操作

```bash
scripts/db.sh <命令> [参数...]

命令列表：
  init                                    初始化数据库
  add-post <json>                         记录帖子
  add-metrics <json>                      记录互动数据
  log-choice <json>                       记录用户选择（选题/草稿）
  query-posts [--today|--days N]          查询帖子
  query-metrics --post-id <id>            查询互动数据
  query-preferences                       查询用户偏好统计
  query-patterns                          查询 pattern 使用效果

所有输出 JSON 格式。
```

### 6.8 数据结构

#### SQLite 表结构（精简后，5 张表）

```sql
-- 帖子主记录
CREATE TABLE posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    slot TEXT NOT NULL,           -- noon / evening
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    tags TEXT,                    -- JSON array
    note_id TEXT,                 -- 小红书 note_id
    topic_type TEXT,              -- 选题类型（AI工具/编程教程/...）
    title_pattern TEXT,           -- 使用的标题模式
    content_style TEXT,           -- 内容风格（清单体/教程体/...）
    status TEXT DEFAULT 'draft',  -- draft/scheduled/published/failed
    published_at TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 互动数据时序
CREATE TABLE post_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER REFERENCES posts(id),
    checked_at TEXT NOT NULL,
    checkpoint TEXT DEFAULT 'daily', -- daily / T+1h / T+6h / T+24h
    likes INTEGER DEFAULT 0,
    saves INTEGER DEFAULT 0,
    comments INTEGER DEFAULT 0,
    shares INTEGER DEFAULT 0
);

-- 用户选择记录
CREATE TABLE user_choices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    choice_type TEXT NOT NULL,     -- topic / draft
    offered_count INTEGER,         -- 提供了几个选项
    chosen_index INTEGER,          -- 用户选了第几个（0=换/拒绝）
    chosen_label TEXT,             -- 选中项的类型标签
    skipped_labels TEXT,           -- 被跳过的类型标签（JSON array）
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 选题候选记录
CREATE TABLE topic_candidates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    source TEXT,                   -- github_trending / github_api / xhs_search / web
    title TEXT,
    score REAL,
    xhs_competition INTEGER,
    selected BOOLEAN DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 评论分析
CREATE TABLE comment_insights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER REFERENCES posts(id),
    total_comments INTEGER DEFAULT 0,
    positive_count INTEGER DEFAULT 0,
    negative_count INTEGER DEFAULT 0,
    question_count INTEGER DEFAULT 0,
    top_questions TEXT,            -- JSON array
    top_praise TEXT,               -- JSON array
    content_requests TEXT,         -- JSON array
    analyzed_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

#### knowledge-base/ 文件结构

```
knowledge-base/
├── profile.json          # 博主画像（领域/受众/风格）
├── preferences.json      # 用户偏好（从选择行为中自动学习）
├── patterns.md           # 有效 pattern 库（≤15 条）
├── anti-patterns.md      # 已淘汰的 pattern
└── evolution-log.md      # 每次进化的记录
```

---

## 七、平台适配

### 7.1 Hermes 适配

```yaml
# cron job 1: 每日发布（早上触发，覆盖午间+晚间）
name: "小红书每日发布"
schedule:
  kind: cron
  expression: "0 8 * * *"
prompt: |
  使用 xiaohongshu skill 执行每日发布流程。
  先读取 knowledge-base/ 了解博主画像和偏好，
  然后依次执行：选题研究 → 推送选题给用户 → 等待选择 →
  生成草稿 → 推送确认 → 生成图片 → 发布。
  午间档和晚间档各一条。
deliver: "telegram:用户ID"

# cron job 2: 每日复盘
name: "小红书每日复盘"
schedule:
  kind: cron
  expression: "0 22 * * *"
prompt: |
  使用 xiaohongshu skill 执行每日复盘流程。
  采集今日帖子互动数据，更新偏好模型，生成日报推送。
  如果是周日，额外执行周进化分析。
deliver: "telegram:用户ID"
```

### 7.2 Claude Code 适配

```bash
# 安装 skill
cp -r shuling ~/.claude/skills/xiaohongshu

# 每日发布：用 /loop 或手动触发
# 在 Claude Code 中输入：
/xiaohongshu 今天发什么

# 或者配置 hook 在每天 8:00 自动触发
```

### 7.3 Codex 适配

```bash
# 安装 skill
cp -r shuling ~/.codex/skills/xiaohongshu

# 使用方式同 Claude Code
```

---

## 八、安装流程

```bash
bash install.sh [安装目录]
```

安装脚本执行：

1. 检查依赖（Node.js、Python 3、xiaohongshu-mcp）
2. 复制 Skill 文件到平台 skill 目录（自动检测 ~/.hermes/skills / ~/.claude/skills / ~/.codex/skills）
3. 初始化 SQLite 数据库
4. 创建 knowledge-base/ 目录骨架
5. 交互式配置：
   - Gemini API Key（图片生成，可选）
   - MCP 服务地址（默认 localhost:18060）
6. 验证 MCP 连接
7. 输出下一步操作指引

---

## 九、从现有项目的迁移

### 保留的资产

- `xiaohongshu-mcp` 及其所有 MCP 能力（不变）
- `data/content-rules.md` 内容合规规则（微调后保留）
- `templates/post.html` 截图模板思路（精简后保留）
- `scripts/screenshot.cjs` 截图脚本（直接复用）
- 已有的 SQLite 数据（可导入新 schema）

### 废弃的代码

| 文件 | 原职责 | 替代方案 |
|------|--------|---------|
| research.py (200 行) | 选题研究 | Agent 按 SKILL.md 6.3.1 执行 |
| orchestrator.py (300 行) | 流程编排 | Agent 按 SKILL.md 流程走 |
| draft_generator.py (250 行) | 调 Claude CLI 生成草稿 | Agent 自己生成 |
| draft_validator.py (350 行) | 调 Claude CLI 评估 | Agent 自己评估 |
| review.py (300 行) | 调 LLM 生成洞察 | Agent 自己分析 |
| feedback_analyzer.py (200 行) | 调 Claude CLI 分析评论 | Agent 自己分析 |
| llm.py (40 行) | 统一 LLM 调用 | Agent 自身就是 LLM |
| telegram.py (200 行) | Telegram 推送 | 平台层负责 |
| telegram_listener.py | Telegram 监听 | 平台层负责 |
| keepalive.py (100 行) | MCP 保活 | xhs.sh 自动检查 |
| config_loader.py | 加载环境变量 | scripts 内部处理 |
| create_content.py | 旧流程 | 废弃 |
| image_generator.py | 图片编排 | Agent 直接调 image.py |
| publish_post.py + publish.sh | 发布 | Agent 调 xhs.sh publish |
| send_preview.py | 预览推送 | Agent 通过平台推送 |

**从 ~2500 行 Python 业务逻辑 → 4 个工具脚本 + 1 个 SKILL.md**

---

## 十、异常处理

| 场景 | Agent 的处理方式 |
|------|-----------------|
| MCP 服务未运行 | xhs.sh 内部自动启动，Agent 无需关心 |
| 登录过期 | xhs.sh status 检测到 → xhs.sh login 获取二维码 → 推送用户扫码 |
| Gemini 图片生成失败 | 降级走 screenshot.cjs HTML 截图 |
| Gemini API Key 未配置 | 走 screenshot.cjs，不阻塞流程（不再反复向用户要 Key） |
| 用户长时间不回复选题 | 超时后自动选择评分最高的（超时时间由平台层配置） |
| 知识库文件损坏 | 用默认值继续，不阻塞创作 |
| SQLite 数据库损坏 | 从 knowledge-base/ 文件重建核心数据 |
| 发布失败 | 通知用户失败原因，保留 meta.json 供重试 |
| 网络异常（GitHub/MCP 不可达） | 跳过该数据源，用已有数据继续 |

---

## 十一、成功标准

### 短期（2 周内）

- [ ] Skill 在 Hermes 上能跑通完整流程：开局对话 → 选题 → 草稿 → 图片 → 发布
- [ ] 每天 2 条帖子稳定发布
- [ ] 用户只需在 Telegram 上做选择/确认操作

### 中期（1 个月）

- [ ] 自进化引擎运行正常，preferences.json 数据积累 ≥50 次选择
- [ ] 选项从 3 个递减到 1-2 个
- [ ] 周报能给出有数据支撑的洞察

### 长期（2 个月+）

- [ ] 用户每天操作减少到 1-2 次点击
- [ ] 帖子平均收藏率相比第 1 周有可衡量的提升
- [ ] 在 Claude Code 上也能跑通同一份 Skill
