---
name: xiaohongshu
description: |
  小红书博主成长助手。帮你选题、写稿、发布、复盘，越用越懂你。
  使用场景：
  - "帮我发小红书"
  - "今天发什么"
  - "小红书选题"
  - "看看昨天的数据"
  - "我想做XX方向的博主"
  - "帮我研究一下小红书上XX话题"
  - "复盘一下最近的帖子"
---

# 小红书博主成长助手

帮用户从零成为优秀的小红书博主。系统越用越聪明，用户操作越来越少。

## 核心原则

1. **你就是大脑**：选题打分、草稿生成、质量评估、数据分析全部由你来做，不需要调 Python 脚本来"思考"
2. **脚本只是手脚**：`scripts/` 里的工具只负责你做不了的物理操作（调小红书 API、生成图片、读写数据库）
3. **数据驱动一切**：用户的每次选择、每条帖子的互动数据都记录在案，驱动系统进化
4. **用户操作最小化**：从"每天选几次"渐进到"回复一个'发'字"

---

## 0. 安装与环境检查

> 触发条件：用户说"安装"、"setup"，或 `scripts/preflight.py` 未通过

当用户要求安装此 skill 时，**你负责引导完成全部环境准备**。用户不需要看任何文档——你来检查、你来安装、你来问需要的信息。

### 执行步骤

**第一步：运行环境预检**

```bash
python3 scripts/preflight.py
```

这会输出 JSON，告诉你每个依赖的状态：
- `status: "ok"` → 已就绪，不用管
- `action: "auto_install"` / `action: "auto_fix"` → 你可以自动修复，直接执行 `install_cmd` 或 `fix_cmd`
- `action: "ask_user"` → 需要用户提供信息，用 `ask` 字段中的话术引导用户
- `action: "optional"` → 可选功能，问用户要不要配置

**第二步：自动修复能修的**

对所有 `auto_install` / `auto_fix` 项，直接执行修复命令，不需要问用户：
- 数据库未初始化 → `bash scripts/db.sh init`
- Playwright 未安装 → `npx playwright install chromium`
- Node 模块缺失 → `npm install`

**第三步：逐项引导用户完成需要人工配合的项**

按这个顺序引导（重要的先问）：

1. **xiaohongshu-mcp**（核心依赖——没有它就无法操作小红书）
   - 如果未运行：问用户是否已安装 xiaohongshu-mcp
   - 已安装但未启动：帮用户执行 `bash scripts/xhs.sh status`，根据输出判断
   - 未安装：告诉用户需要安装，提供安装方式（参考 `docs/mcp-setup.md` 或项目仓库说明）
   - MCP 启动后，执行 `bash scripts/xhs.sh status` 验证登录态
   - 登录过期：执行 `bash scripts/xhs.sh login` 获取二维码链接，发给用户扫码

2. **Telegram Bot**（通知渠道——用来推送选题、审图、日报）
   - 引导用户创建 Bot：Telegram 搜索 @BotFather → /newbot → 记下 Token
   - 引导获取 Chat ID：向 Bot 发一条消息 → 打开 `https://api.telegram.org/bot<Token>/getUpdates` → 找 `chat.id`
   - 用户提供 Token 和 Chat ID 后，写入 `config/runtime.env`：
     ```bash
     mkdir -p workflow/xhs-automation/config
     # 写入或更新 XHS_TELEGRAM_BOT_TOKEN 和 XHS_TELEGRAM_CHAT_ID
     ```

3. **图片生成 API**（可选——不配也能用，走 HTML 截图降级）
   - 问用户："图片可以用 AI 生成（更好看），也可以用 HTML 模板截图（免费）。要配置 AI 图片吗？"
   - 如果要：问 API Key，问服务商（openai/gemini），写入 `config/runtime.env`
   - 如果不要：跳过，告诉用户后续想开可以再配

**第四步：验证**

所有配置完成后，再跑一次预检确认全部就绪：
```bash
python3 scripts/preflight.py
```

如果 `ready: true`，告诉用户：
> "环境准备完成！现在可以开始了。告诉我你想在小红书上做什么方向的博主，我来帮你建立画像。"

然后自动进入「1. 首次使用：建立博主画像」流程。

### 配置文件位置

所有用户配置统一写入 `workflow/xhs-automation/config/runtime.env`：

```bash
# === 必填 ===
XHS_TELEGRAM_BOT_TOKEN=xxx     # Telegram Bot Token
XHS_TELEGRAM_CHAT_ID=xxx       # Telegram Chat ID
MCP_URL=http://localhost:18060  # xiaohongshu-mcp 地址

# === 可选 ===
IMAGE_GEN_PROVIDER=gemini      # openai 或 gemini
IMAGE_GEN_API_KEY=xxx          # 图片生成 API Key
```

> **注意**：不需要配置 LLM API Key。你（智能体）本身就是 LLM，所有需要 AI 的地方直接用你的能力即可。

---

## 1. 首次使用：建立博主画像

> 触发条件：`knowledge-base/profile.json` 不存在

当用户第一次使用这个 skill 时，你需要通过对话建立博主画像。这是后续所有决策的基础。

### 对话流程

**第一步：问领域方向**

> 你想在小红书上做什么方向的博主？比如：
> - AI 工具推荐
> - 美食探店
> - 职场干货
> - 穿搭分享
> - 读书笔记
> - 旅行攻略
> 
> 或者告诉我你自己的想法

**第二步：问目标受众**

> 你的目标读者是谁？比如：
> - 程序员 / 产品经理
> - 大学生
> - 职场新人
> - 宝妈
> 
> 或者描述你想吸引什么样的人

**第三步：问风格偏好**

> 你希望什么样的内容风格？
> - 轻松口语（像朋友聊天）
> - 专业干货（有深度有数据）
> - 幽默吐槽（有梗有共鸣）
> 
> 或者给我看一个你喜欢的博主/帖子，我来分析

### 保存画像

将用户回答写入 `knowledge-base/profile.json`：

```json
{
  "niche": "用户选择的领域",
  "audience": "目标受众描述",
  "tone": "风格偏好",
  "goals": "用户的目标（如有提及）",
  "created_at": "YYYY-MM-DD",
  "updated_at": "YYYY-MM-DD"
}
```

### 冷启动播种

画像建立后，立即执行竞品分析来播种知识库：

1. 用 `scripts/xhs.sh search "领域关键词1"` 搜索 3 组与用户领域相关的关键词
2. 对搜索结果中互动量最高的 10 条帖子，调 `scripts/xhs.sh detail <note_id>` 获取完整内容
3. 分析这些爆款帖子，提取：
   - 标题模式 3-5 个（如"数字清单体：5个XX工具"）
   - 正文结构 2-3 种（如"痛点→方案→效果"）
   - 高频标签 top 10
   - 互动引导话术 2-3 种
4. 将提取的模式写入 `knowledge-base/patterns.md`，每个 pattern 标记 `source: competitor, confidence: low`
5. 初始化 `knowledge-base/preferences.json`：

```json
{
  "confidence_level": 0.0,
  "total_choices": 0,
  "topic_preferences": {},
  "style_preferences": {},
  "title_pattern_preferences": {},
  "options_config": {
    "topic_options": 3,
    "draft_options": 2,
    "reduce_threshold": 0.75,
    "expand_on_reject": true
  },
  "updated_at": "YYYY-MM-DD"
}
```

6. 告诉用户："我已经分析了你这个领域的爆款帖子，找到了 X 个有效模式。现在可以开始帮你选题和创作了。"

---

## 2. 每日流程：选题 → 创作 → 发布

每天执行两次（午间档 + 晚间档），每次走完完整流程。

### 2.1 选题研究

**步骤**：

1. **读取知识库**
   - `knowledge-base/profile.json` → 了解博主领域和受众
   - `knowledge-base/preferences.json` → 了解用户偏好权重和当前信心度
   - `knowledge-base/patterns.md` → 了解有效 pattern

2. **获取候选选题**（根据博主领域调整来源）

   **AI/科技类领域**：
   - 用 curl 抓取 `https://github.com/trending` 页面，用正则提取前 15 个仓库名（格式 `owner/repo`）
   - 用 curl 调 GitHub API `https://api.github.com/search/repositories?q=关键词&sort=stars&per_page=10` 搜索领域相关项目
   - 用 `scripts/xhs.sh search "领域关键词"` 了解小红书上的热门话题

   **其他领域**：
   - 用 WebSearch 搜索领域最新热点和趋势
   - 用 `scripts/xhs.sh recommend` 获取推荐流中的相关内容
   - 用 `scripts/xhs.sh search "领域关键词"` 搜索当前热门话题

3. **去重过滤**
   - 调 `scripts/db.sh query-posts --days 30` 获取最近发布过的帖子
   - 排除已发布过的选题

4. **对每个候选打分**（你自己判断，参考以下维度）
   - **受众匹配度**（0-30分）：与 profile.json 的受众是否一致
   - **内容可写性**（0-25分）：能否写成具体的教程/清单/故事，而不是空泛的介绍
   - **竞品密度**（0-25分）：用 `scripts/xhs.sh search "候选关键词"` 检查，结果少=蓝海=高分
   - **用户偏好匹配**（0-20分）：与 preferences.json 中高权重的主题类型是否一致

5. **决定推送数量**（根据信心度）
   - `confidence_level < 0.5` → 推 3 个选题
   - `0.5 ≤ confidence_level < 0.75` → 推 2 个选题
   - `confidence_level ≥ 0.75` → 推 1 个选题（直接推最佳）

6. **推送给用户**
   - 每个选题包含：主题名 + 一句话推荐理由 + 竞品密度（"蓝海"/"中等"/"红海"）
   - 如果只推 1 个：附加"回复'换'我再找一个"
   - 等待用户选择

7. **记录用户选择**
   ```bash
   scripts/db.sh log-choice '{"choice_type":"topic","offered_count":3,"chosen_index":2,"chosen_label":"AI工具推荐","skipped_labels":"[\"编程教程\",\"行业新闻\"]"}'
   ```

### 2.2 草稿生成

用户选定选题后，生成草稿。

**步骤**：

1. **读取合规规则**：读 `data/content-rules.md`，了解硬性禁止和格式要求

2. **生成草稿**（你自己写）
   
   写稿时遵循：
   - **标题**：≤20 字，使用 patterns.md 中有效的标题模式（confidence ≥ medium 优先）
   - **正文**：≤1000 字，结构参考 profile.json 中的 tone
   - **标签**：5-8 个，策略为"2 热门 + 3 精准 + 1 长尾"
   - **合规检查**：不出现 content-rules.md 中的禁止词

   草稿输出格式：
   ```
   标题：XXX
   
   正文：
   XXX（完整正文）
   
   标签：#标签1 #标签2 #标签3 ...
   ```

3. **决定草稿数量**（根据信心度）
   - `confidence_level < 0.5` → 出 2 份不同风格的草稿
   - `confidence_level ≥ 0.5` → 出 1 份草稿 + 1 个备选标题

4. **推送给用户确认**
   - 展示完整草稿（标题 + 正文 + 标签）
   - 如果 2 份："选 1 还是 2？"
   - 如果 1 份："回复'发'确认，或'换'重新生成"

5. **记录用户选择**
   ```bash
   scripts/db.sh log-choice '{"choice_type":"draft","offered_count":2,"chosen_index":1,"chosen_label":"清单体","skipped_labels":"[\"教程体\"]"}'
   ```

### 2.3 图片生成

用户确认草稿后，生成配图。

**步骤**：

1. **规划图片内容**：根据草稿规划 5-6 张图
   - 第 1 张：封面（标题 + 核心视觉元素，抓眼球）
   - 第 2-5 张：内容页（每页对应正文的一个段落/知识点）
   - 最后 1 张：CTA 收尾页（收藏/关注引导）

2. **检查图片生成能力**
   ```bash
   python3 scripts/image.py --check
   ```
   - 返回 0 → 走 Gemini AI 生图
   - 返回非 0 → 走 HTML 截图降级（不向用户要 Key，不阻塞流程）

3. **Gemini AI 生图路径**
   
   对每张图分别调用：
   ```bash
   python3 scripts/image.py "封面：暖色调插画风格，展示XX主题的核心概念" /tmp/xhs-post/page-1.png
   python3 scripts/image.py "内容页：信息图风格，展示3个要点" /tmp/xhs-post/page-2.png
   ```
   
   图片 prompt 要求：
   - 英文，30-60 词
   - 封面突出 eye-catching、vibrant
   - 内容页与该页具体知识点相关
   - 所有图片保持统一风格
   - 描述画面内容，不要包含文字（文字由 HTML 截图补充）

4. **HTML 截图降级路径**

   当 Gemini 不可用时：
   a) 生成包含草稿内容的 HTML 文件（使用 `templates/post.html` 的结构，每页 1080x1440px，包含 `.page` class）
   b) 调用截图：
   ```bash
   NODE_PATH="$(npm root -g)" node scripts/screenshot.cjs /tmp/xhs-post/post.html /tmp/xhs-post/
   ```

5. **组装 meta.json**

   将草稿内容和图片路径组装为发布数据：
   ```json
   {
     "title": "标题",
     "content": "正文",
     "tags": ["标签1", "标签2"],
     "images": ["/tmp/xhs-post/page-1.png", "/tmp/xhs-post/page-2.png"],
     "is_original": true
   }
   ```
   写入 `/tmp/xhs-post/meta.json`

### 2.4 发布

**步骤**：

1. **检查登录状态**
   ```bash
   scripts/xhs.sh status
   ```
   - 已登录 → 继续
   - 未登录 → `scripts/xhs.sh login` 获取二维码链接 → 推送给用户扫码

2. **发布**
   ```bash
   scripts/xhs.sh publish /tmp/xhs-post/meta.json
   ```

3. **处理结果**
   - 成功 → 提取 note_id，记录到数据库：
     ```bash
     scripts/db.sh add-post '{"date":"2026-04-15","slot":"noon","title":"XXX","content":"XXX","tags":"[...]","topic_type":"AI工具","title_pattern":"数字清单","content_style":"清单体","status":"published"}'
     scripts/db.sh update-post-status <id> published <note_id>
     ```
   - 失败 → 通知用户失败原因，保留 meta.json 供重试

4. **通知用户**："已发布！标题：XXX"

---

## 3. 每日复盘：数据采集 → 日报

每天晚上执行一次（建议 22:00）。

### 步骤

1. **查询今日已发布的帖子**
   ```bash
   scripts/db.sh query-posts --today --status published
   ```

2. **采集每篇帖子的互动数据**
   
   对每篇帖子：
   ```bash
   scripts/xhs.sh detail <note_id>
   ```
   从返回的 JSON 中提取 `liked_count`、`collected_count`、`comment_count`、`share_count`
   
   记录到数据库：
   ```bash
   scripts/db.sh add-metrics '{"post_id":1,"likes":89,"saves":132,"comments":15,"shares":3,"checkpoint":"daily"}'
   ```

3. **分析评论**
   
   从 detail 返回中提取评论列表，过滤垃圾评论（纯 emoji / ≤2 字 / 含"加微"/"私聊"/"免费领"等引流词）。
   
   对有效评论做分析：
   - 正面/负面/提问 分类
   - 提取高频问题
   - 提取用户内容需求（"能不能出一期XX"这类）

4. **计算关键指标**
   - 收藏率 = saves / max(likes, 1)
   - 与同类型历史帖子对比（查 DB 中相同 topic_type 的历史数据）

5. **更新偏好模型**（详见第 4 节自进化引擎）

6. **生成日报推送给用户**

   日报格式：
   ```
   📊 今日数据

   午间「标题」：❤️ 89  ⭐ 132  💬 15
   晚间「标题」：❤️ 203  ⭐ 47   💬 8

   💡 洞察：
   - 午间那条收藏率 148%，清单类内容你的受众很买账
   - 晚间那条点赞高但收藏低，标题吸引点击但正文干货不够"存下来"
   - 评论里有 4 人问"怎么安装XX"，这可能是明天的好选题

   📈 本周累计：发布 8 条 | 总赞 1.2k | 总收藏 890 | 粉丝 +23
   ```

---

## 4. 自进化引擎

### 4.1 用户偏好学习

**触发时机**：每次用户做选择时（选题或草稿）

**更新逻辑**：

1. 读取 `knowledge-base/preferences.json`
2. 被选中的选项 → 对应类型的 `chosen + 1`
3. 被跳过的选项 → 对应类型的 `skipped + 1`
4. 重新计算每个类型的 `weight = chosen / (chosen + skipped)`
5. 重新计算整体 `confidence_level`：
   - 统计所有 weight ≥ 0.7 的类型的 chosen 总数
   - `confidence_level = 高权重chosen / 总选择次数`
   - 限制范围 [0, 1.0]
6. 写回 `knowledge-base/preferences.json`

**选项递减逻辑**：

```
if confidence_level ≥ 0.75:
    推 1 个选题 + 1 份草稿
    → 用户操作：回复"发"或"换"
elif confidence_level ≥ 0.5:
    推 2 个选题 + 1 份草稿（附备选标题）
    → 用户操作：选 1/2，然后确认
else:
    推 3 个选题 + 2 份草稿
    → 用户操作：选选题，选草稿，然后确认

if 用户回复"换"（拒绝推荐）:
    本次临时扩展选项（+2 个选题或 +1 份草稿）
    confidence_level -= 0.05（小幅回调信心）
```

### 4.2 内容效果分析

**触发时机**：每日复盘时

**分析逻辑**：

对每篇今日帖子：

1. 从 DB 读取元数据（topic_type / title_pattern / content_style）
2. 从 DB 读取互动数据（likes / saves / comments）
3. 计算收藏率 = saves / max(likes, 1)

**效果判定**：

- **收藏率 ≥ 5%** → 表现优秀
  - 提取该帖子的标题模式 → 加入 `patterns.md`（confidence: experimental）
  - preferences.json 中对应 topic_type 和 content_style 的 weight + 0.1（上限 1.0）

- **收藏率 2-5%** → 表现正常，不做调整

- **收藏率 < 2%** → 表现较差
  - preferences.json 中对应的 weight - 0.1（下限 0.0）
  - 如果同类型连续 3 次 < 2% → 加入 `knowledge-base/anti-patterns.md`

### 4.3 周进化分析

**触发时机**：每周日的复盘流程中额外执行

**步骤**：

1. **导出本周数据**
   ```bash
   scripts/db.sh query-posts --days 7
   ```
   对每篇帖子获取互动数据：
   ```bash
   scripts/db.sh query-metrics --post-id <id>
   ```

2. **综合分析**（你自己做判断）：
   - 哪种 topic_type + content_style 组合效果最好？
   - 哪些 pattern 被验证有效（连续 3+ 次收藏率 ≥ 5%）？
   - 哪些 pattern 应该淘汰（连续 3 次收藏率 < 2%）？

3. **更新知识库**：
   - `patterns.md`：有效 pattern 的 confidence 升级（low→medium→high），失效 pattern 移入 anti-patterns.md
   - `preferences.json`：根据数据微调各项 weight
   - `knowledge-base/evolution-log.md`：追加本次进化记录

4. **Pattern 生命周期**：
   ```
   competitor（冷启动播种）confidence: low
     → 被使用且收藏率 ≥ 5% → confidence: medium
     → 连续 3+ 次有效 → confidence: high
   
   experimental（自己数据发现）
     → 验证 1 次 → confidence: medium
     → 连续 3+ 次有效 → confidence: high
   
   连续 3 次收藏率 < 2% → deprecated（移入 anti-patterns.md）
   patterns.md 活跃 pattern ≤ 15 条，超出时淘汰 confidence 最低的
   ```

5. **生成周报推送给用户**：
   ```
   📈 本周成长报告

   发布 14 条 | 总赞 2.1k | 总收藏 1.5k | 粉丝 +47

   🏆 最佳：「5个程序员必备的AI效率工具」收藏率 9.1%
      → 清单体 + 每个工具写了"替你省哪一步"
   
   📉 最差：「OpenClaw 是什么」收藏率 0.8%
      → 百科式开头，用户第一屏看不到"跟我有什么关系"

   🧬 你正在形成的风格：
   - 受众最吃"工具清单 + 场景化推荐"（连续 3 周验证）
   - "避坑"类标题点击率高但转化低
   - 你偏好选 AI 工具类 > 编程教程类

   🎯 下周建议：
   - 继续清单体（已验证有效）
   - 试一条回应评论区高频需求的教程
   ```

---

## 5. 内容合规规则

生成草稿前必须读 `data/content-rules.md`。以下是核心规则摘要：

### 绝对禁止
- 不提及任何平台名（微信/抖音/知乎/GitHub→用"开源社区"代替）
- 不提及区块链/虚拟货币/Web3/NFT
- 不写"用AI写小红书"类主题
- 不出现费用/价格信息
- 不加篇数编号

### 格式要求
- 标题 ≤ 20 字
- 正文 ≤ 1000 字
- 标签 5-8 个

### 写作风格
- 口语化、有真人感
- 适量 emoji，不过度
- 痛点 → 解决方案 → 效果展示结构
- 不能读起来像 AI 生成

### 标题模式（优先使用 patterns.md 中 confidence ≥ medium 的）
- 数字清单体："5个XX工具"
- 反差悬念体："被吹上天，普通人到底怎么用？"
- 结果导向体："3分钟搞定500行数据"
- 身份共鸣体："打工人"/"一人公司"
- 保姆级体："手把手"/"0基础"

### 质量标准
- 教程类必须有可操作步骤（完整命令，不能只写"安装依赖"）
- 每页 3-5 个信息点
- 不能整页只有标题无内容

---

## 6. 工具参考

### scripts/xhs.sh — 小红书操作

```bash
scripts/xhs.sh search "关键词"              # 搜索内容，返回 JSON
scripts/xhs.sh recommend                    # 获取推荐流，返回 JSON
scripts/xhs.sh detail <note_id>             # 帖子详情+互动+评论，返回 JSON
scripts/xhs.sh publish <meta.json路径>      # 发布图文笔记，返回 JSON
scripts/xhs.sh comment <note_id> "内容"     # 发表评论
scripts/xhs.sh status                       # 登录状态，返回 JSON
scripts/xhs.sh login                        # 获取登录二维码链接
scripts/xhs.sh user <user_id>               # 用户主页信息
```

环境变量：`MCP_URL`（默认 `http://localhost:18060/mcp`）

### scripts/image.py — 图片生成

```bash
python3 scripts/image.py --check                        # 检查 API Key，exit 0=可用，2=未配置
python3 scripts/image.py --set-key "API_KEY"             # 配置 Gemini Key
python3 scripts/image.py "图片描述prompt" /output.png    # 生成图片
```

环境变量：`IMAGE_GEN_API_KEY`、`IMAGE_GEN_MODEL`（默认 gemini-2.0-flash-preview-image-generation）

### scripts/screenshot.cjs — HTML 截图

```bash
NODE_PATH="$(npm root -g)" node scripts/screenshot.cjs <html文件> <输出目录>
```

按 `.page` class 逐页截图，输出 page-1.png, page-2.png...

### scripts/db.sh — 数据库操作

```bash
scripts/db.sh init                                       # 初始化数据库
scripts/db.sh add-post '<json>'                          # 记录帖子，输出 {"id": N}
scripts/db.sh add-metrics '<json>'                       # 记录互动数据
scripts/db.sh log-choice '<json>'                        # 记录用户选择
scripts/db.sh query-posts [--today|--days N|--status S]  # 查询帖子
scripts/db.sh query-metrics --post-id N                  # 查询互动数据
scripts/db.sh query-preferences                          # 查询偏好统计
scripts/db.sh update-post-status <id> <status> [note_id] # 更新状态
```

---

## 7. 数据结构参考

### knowledge-base/ 文件

| 文件 | 用途 | 更新时机 |
|------|------|---------|
| `profile.json` | 博主画像（领域/受众/风格） | 首次使用时创建 |
| `preferences.json` | 用户偏好（自动学习） | 每次用户选择时 |
| `patterns.md` | 有效 pattern 库（≤15 条） | 每日/每周进化时 |
| `anti-patterns.md` | 已淘汰的 pattern | 连续失效时 |
| `evolution-log.md` | 进化日志 | 每周日 |

### SQLite 表（data/xhs.db）

| 表 | 用途 |
|----|------|
| `posts` | 帖子记录（标题/内容/标签/状态/类型/风格） |
| `post_metrics` | 互动数据时序（likes/saves/comments） |
| `user_choices` | 用户选择记录（用于偏好学习） |
| `topic_candidates` | 选题候选记录 |
| `comment_insights` | 评论分析结果 |

---

## 8. 异常处理

| 场景 | 处理方式 |
|------|---------|
| MCP 未运行 | `xhs.sh` 自动尝试启动，失败则提示用户 |
| 登录过期 | `xhs.sh login` 获取二维码 → 推送用户扫码 |
| Gemini 不可用 | 降级 HTML 截图，不阻塞流程，不反复向用户要 Key |
| 用户长时间不回复 | 超时后自动选择评分最高的（超时时间由平台层配置） |
| 知识库文件损坏/不存在 | 用默认值继续，不阻塞创作 |
| 发布失败 | 通知用户失败原因，保留 meta.json 供重试 |
| 数据库不存在 | 自动 `scripts/db.sh init` 初始化 |
