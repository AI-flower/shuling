---
id: 01-onboarding-new
title: New Creator Onboarding
when:
  - "用户首次使用"
  - "agent/knowledge-base/profile.json 不存在"
needs:
  required:
    - agent/schemas/profile.schema.json
  optional:
    mcp:
      - xhs-mcp
    fallback: "MCP 未就绪则跳过竞品分析步骤"
calls:
  scripts:
    - agent/scripts/xhs.sh
    - agent/scripts/db.sh
    - agent/scripts/preflight.py
writes:
  files:
    - agent/knowledge-base/profile.json
    - agent/knowledge-base/preferences.json
    - agent/knowledge-base/patterns.md
    - agent/config/state.json
preconditions:
  - "NOT EXISTS agent/knowledge-base/profile.json"
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
---

# 01 New Creator Onboarding

## Trigger

- 用户**首次**与 skill 对话且 `agent/knowledge-base/profile.json` 不存在
- 或 `agent/scripts/preflight.py` 输出 `setup_completed: false`、且用户**不是**自述老博主（否则走 `02-onboarding-existing.md`）
- 或 `state.profile_created == true` 但 `state.cold_start_done == false`（仅跑"冷启动播种"子段）

## Read This When

剧本分两个独立子段，按场景挑：

- **Environment Setup** —— 用户说"安装"/"setup"/preflight 未通过，或路由表判定环境未就绪
- **Profile Building & Cold Start Seeding** —— 环境就绪但 profile.json 还不存在，且用户表达了内容方向需求

两段串跑是默认路径（首次冷装）；也可只跑后者（环境已绿，仅缺画像）。

## Inputs

- `agent/scripts/preflight.py` 输出 JSON（`status / action / install_cmd / fix_cmd / ask` 字段）
- 用户对话回复（领域 / 受众 / 风格三问）
- MCP 可用时：`agent/scripts/xhs.sh search "关键词"` 与 `xhs.sh detail <note_id>` 的爆款返回
- 已有 profile.json（**如存在**则**直读不再问**，详见下文）

## Procedure

### Environment Setup

**第 1 步：运行环境预检**

```bash
python3 agent/scripts/preflight.py
```

输出 JSON 告诉你每个依赖的状态：
- `status: "ok"` → 已就绪，不用管
- `action: "auto_install"` / `auto_fix` → 直接执行 `install_cmd` 或 `fix_cmd`，不用问用户
- `action: "ask_user"` → 用 `ask` 字段中的话术引导用户提供信息
- `action: "optional"` → 可选功能，问用户要不要配置

**第 2 步：自动修复能修的**

对所有 `auto_install` / `auto_fix` 项直接执行：
- 数据库未初始化 → `bash agent/scripts/db.sh init`
- Playwright 未安装 → `npx playwright install chromium`
- Node 模块缺失 → `npm install`

**第 3 步：逐项处理需要人工配合的项**（重要的先问）

1. **xiaohongshu-mcp**（核心依赖——没有它就无法操作小红书）
   - 未运行：问用户是否已安装；已安装但未启动：跑 `bash agent/scripts/xhs.sh status` 据输出判断
   - 未安装：告诉用户需要安装，参考 `agent/docs/runbooks/mcp-setup.md`
   - MCP 启动后跑 `bash agent/scripts/xhs.sh status` 验证登录态
   - **登录策略**（按优先级）：
     - **用户主动提议方案优先**：用户说"我给你 cookie"/"我直接粘贴"/"帮我用 cookie 登录"等任何变体 → **立即接受**，让用户从浏览器复制完整 `Cookie` 头字符串，调用 `bash agent/scripts/xhs.sh import-cookie '<cookie字符串>'`。**不要绕回扫码、不要继续解释扫码流程**
     - 默认扫码：`bash agent/scripts/xhs.sh login` 获取二维码链接，返回给上层让用户扫码

2. **图片生成 API**（**必需** —— 强制 Gemini，无降级路径）
   - 薯灵已移除 HTML 截图降级。没有 Gemini API Key 就无法生图，也就无法发帖
   - 问用户："薯灵需要 Gemini 图片 API（免费额度 / 有 Nano Banana Pro 模型）。请提供你的 API Key。"
   - 获取地址：https://aistudio.google.com/app/apikey
   - 拿到 Key 写入：`python3 agent/scripts/image.py --set-key <KEY>`
   - **用户拒绝提供 Key 时**：明确告知这是强依赖，安装流程停在这一步，不进入建画像

> **不要在本节问 Telegram / IM 通讯凭证**——通讯渠道由 hermes-agent 自己配置，不属于 skill 业务范围。
> **不需要配置 LLM API Key**——你（智能体）本身就是 LLM，所有需要 AI 的地方直接用你的能力即可。

**第 4 步：验证**

所有配置完成后，再跑一次预检：

```bash
python3 agent/scripts/preflight.py
```

`ready: true` 时告诉用户："环境准备完成！现在可以开始了。告诉我你想在小红书上做什么方向的博主，我来帮你建立画像。"，然后进入下一段。

### Profile Building & Cold Start Seeding

**画像已存在的处理**：如果 `agent/knowledge-base/profile.json` 已存在，**直接读取使用**，**绝不再问用户领域/受众/风格**。要更新画像必须等用户主动说"更新画像"或"我想换方向"，才能进入对话流程并最终覆盖文件。

**冷启动独立性**：本子段不依赖图片生成 API，也不依赖 hermes 通讯渠道是否就绪。即使图片生成 API 标 `optional` 未配，本子段也应正常完成（建立画像 + 冷启动播种 patterns.md）。MCP 未就绪时跳过"竞品分析"，仅完成画像写入与默认 `preferences.json` 初始化即可，并写 `state.profile_created = true`；待 MCP 就绪后再补冷启动播种，写 `state.cold_start_done = true`。

**第 1 步：问领域方向**

> 你想在小红书上做什么方向的博主？比如：
> - 美食探店
> - 职场干货
> - 穿搭分享
> - 家居收纳
> - 读书笔记
> - 旅行攻略
>
> 或者告诉我你自己的想法

**第 2 步：问目标受众**

> 你的目标读者是谁？比如：
> - 程序员 / 产品经理
> - 大学生
> - 职场新人
> - 宝妈
>
> 或者描述你想吸引什么样的人

**第 3 步：问风格偏好**

> 你希望什么样的内容风格？
> - 轻松口语（像朋友聊天）
> - 专业干货（有深度有数据）
> - 幽默吐槽（有梗有共鸣）
>
> 或者给我看一个你喜欢的博主/帖子，我来分析

**第 4 步：保存画像**

按 `agent/schemas/profile.schema.json` 校验后写入 `agent/knowledge-base/profile.json`：

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

**第 5 步：冷启动播种**（MCP 就绪才跑；否则跳过本步并把 `state.cold_start_done` 留 false）

1. 用 `agent/scripts/xhs.sh search "领域关键词1"` 搜 3 组与用户领域相关的关键词
2. 对搜索结果中互动量最高的 10 条帖子，调 `agent/scripts/xhs.sh detail <note_id>` 拿完整内容
3. 分析这些爆款帖子，提取：
   - 标题模式 3-5 个（如"数字清单体：5 个 XX 工具"）
   - 正文结构 2-3 种（如"痛点→方案→效果"）
   - 高频标签 top 10
   - 互动引导话术 2-3 种
4. 把提取的模式写入 `agent/knowledge-base/patterns.md`，每个 pattern 标记 `source: competitor, confidence: low`

**第 6 步：初始化 preferences.json**

按 `agent/schemas/preferences.schema.json` 校验后写入 `agent/knowledge-base/preferences.json`：

```json
{
  "confidence_level": 0.0,
  "total_choices": 0,
  "topic_preferences": {},
  "style_preferences": {},
  "title_pattern_preferences": {},
  "choice_log": [],
  "last_exploration_at": null,
  "consecutive_rejects": 0,
  "options_config": {
    "topic_options": 3,
    "draft_options": 2,
    "reduce_threshold": 0.75,
    "expand_on_reject": true,
    "exploration_cooldown_days": 7
  },
  "updated_at": "YYYY-MM-DD"
}
```

字段语义：
- `topic_preferences` / `style_preferences` / `title_pattern_preferences` —— 每个维度按类型记录 `{type_name: {chosen: N, skipped: M}}`；`weight` 与 `confidence` 如何由这两个计数推出 → **见 `06-learning-loop.md`**
- `choice_log` —— 每次选择追加一条 `{date, dimension, chosen, skipped}`，用于时间衰减分析
- `last_exploration_at` —— 上次"探索窗口"触发日期（YYYY-MM-DD 或 null），配合 ε-greedy 保底
- `consecutive_rejects` —— 连续"换"次数，达到 2 立即降档

**第 7 步：通知用户冷启动完成**

> "我已经分析了你这个领域的爆款帖子，找到了 X 个有效模式。现在可以开始帮你选题和创作了。"

## Writes

- `agent/knowledge-base/profile.json` —— 第 4 步写入；写前按 `agent/schemas/profile.schema.json` 校验
- `agent/knowledge-base/patterns.md` —— 第 5 步追加竞品种子（`source: competitor, confidence: low`）
- `agent/knowledge-base/preferences.json` —— 第 6 步写入空骨架；写前按 `agent/schemas/preferences.schema.json` 校验
- `agent/config/state.json` —— `profile_created = true`（第 4 步后）；`cold_start_done = true`（第 5 步成功落 patterns 后）；`setup_completed = true`（环境与画像皆就绪后）
- `agent/config/runtime.env` —— 仅在用户提供 Gemini Key 时由 `image.py --set-key` 改写

## Failure Handling

- **MCP 未就绪 / list_feeds 不可用** → 跳过第 5 步竞品分析；画像仍正常写入；`state.cold_start_done = false`，等 MCP 恢复后由路由表（`00-routing.md` 第三行）回到本剧本仅跑冷启动播种段
- **用户拒绝提供 Gemini Key** → 安装流程停在 Environment Setup 第 3 步第 2 项，不进入 Profile Building；告知用户这是强依赖
- **MCP 登录失败 / cookie 无效** → 重试一次；失败则把详细错误回报用户并交给 `09-troubleshooting.md`
- **Schema 校验失败** → 不写盘；把缺失/越界字段告诉用户并重写，**绝不**直接写入越界数据（详见 `08-compliance.md`）
- **三问对话用户未答完整** → 已答字段先暂存，缺什么再追问；不允许半填的 `profile.json` 落盘

## Anti-Patterns
- 不擅自合并多方向（让用户决策主攻）
- profile 已存在绝不再问（覆盖必须用户主动说"更新画像"）
- 不在本节问 Telegram / IM 通讯凭证（hermes-agent 的事）
- 不绕回扫码（用户主动给 cookie 必须立即接受）
- 不让冷启动失败拖死建画像（两步可拆，state 分别标记）

## Cross-Refs
- → 00-routing.md（路由表决定本剧本是否被命中）
- → 02-onboarding-existing.md（用户其实是老博主时切过去）
- → 06-learning-loop.md（preferences.json 中 `weight` / `confidence_level` 公式与 sample_factor 语义）
- → 08-compliance.md（schema 校验细则、日期格式、异常处理纪律）
- → 09-troubleshooting.md（任何步骤失败）
