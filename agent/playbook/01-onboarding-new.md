---
id: 01-onboarding-new
title: New Creator Onboarding
when:
  - "用户首次使用"
  - "agent/knowledge-base/profile.json 不存在"
needs:
  required:
    - agent/schemas/profile.schema.json
    - agent/schemas/benchmark.schema.json
  optional:
    mcp:
      - xhs-mcp
    fallback: "MCP 未就绪则跳过 Benchmark Seeding 与 Cold Start Seeding（benchmarks/ 留空，state.cold_start_done=false）"
calls:
  scripts:
    - agent/scripts/xhs.sh
    - agent/scripts/db.sh
    - agent/scripts/preflight.py
writes:
  files:
    - agent/knowledge-base/profile.json
    - agent/knowledge-base/business-profile.json
    - agent/knowledge-base/benchmarks/<slug>.json
    - agent/knowledge-base/benchmarks/index.md
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

剧本分若干独立子段，按场景挑：

- **Environment Setup** —— 用户说"安装"/"setup"/preflight 未通过，或路由表判定环境未就绪
- **Profile Building** —— 环境就绪但 `profile.json` 还不存在，且用户表达了内容方向需求（三问：方向 / 受众 / 风格）
- **Concept Precheck / Problem Dissolution** —— 用户回答中出现「IP / 个人品牌 / 人设 / 私域 / 社群 / 流量池 / 精准流量 / 赛道 / 风口 / 红利 / 知识付费 / 课程 / 陪跑 / 变现 / 副业 / 干货」等触发词时，先做大白话重述
- **Business Profile Building** —— 内容画像写入后，做轻量「账号目标校准」三问（最多 3 个），写 `business-profile.json`
- **Benchmark Seeding** —— 用户领域搜索 + 候选对标过滤（两层过滤）+ 写 `agent/knowledge-base/benchmarks/<slug>.json` dossier；MCP 不可用时降级
- **Cold Start Seeding** —— 从已生成的 dossier（或直接从竞品爆款）抽 patterns.md 种子；MCP 不可用时跳过

整体流程顺序：

```text
Environment Setup
  ↓
Profile Building（方向 / 受众 / 风格三问）
  ↓
Concept Precheck / Problem Dissolution（命中触发词时插入；澄清结论回填 profile.json + 给 Business Profile Building 用）
  ↓
Business Profile Building（账号目标校准三问，写 business-profile.json）
  ↓
Benchmark Seeding（搜索领域 → 两层过滤 → 写 benchmarks/<slug>.json + index.md；MCP 未就绪则降级，benchmarks/ 留空，state.cold_start_done=false）
  ↓
Cold Start Seeding（从 dossier 抽 patterns.md 种子；MCP 未就绪则跳过）
  ↓
preferences 初始化（写 preferences.json 空骨架）
```

各段可独立跑（环境已绿仅缺画像 / 画像已建仅冷启动 / 冷启动已完仅补 business-profile）。**新博主全流程总问题数严格控制：三问内容画像 + 三问业务校准 = 6 个核心问题，最多再加 1-2 个澄清追问，不能更多。**

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

### Profile Building

**画像已存在的处理**：如果 `agent/knowledge-base/profile.json` 已存在，**直接读取使用**，**绝不再问用户领域/受众/风格**。要更新画像必须等用户主动说"更新画像"或"我想换方向"，才能进入对话流程并最终覆盖文件。同理 `business-profile.json` 已存在时直接读，**不再做账号目标校准三问**——除非用户主动说要更新。

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

**第 4 步：保存画像**（先**不**直接落盘——若用户的回答命中触发词，先进 Concept Precheck 段，澄清后再保存）

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

**禁止**把「副业 / IP / 个人品牌 / 人设 / 私域 / 社群 / 流量池 / 精准流量 / 赛道 / 风口 / 红利 / 知识付费 / 课程 / 陪跑 / 变现 / 干货」这类原话直接塞进 `niche` / `audience` / `tone` / `goals` —— 必须先在 Concept Precheck 段把它拆成大白话再写。详见 `08-compliance.md` Concept Precheck Rule Validation。

### Concept Precheck / Problem Dissolution

> 触发条件：第 1-3 步用户的任一回答里出现下列触发词。**澄清结论不单独写文件**，只用于修正 `profile.json` / `business-profile.json` 字段（详见 `08-compliance.md`、`docs/plans/v3.2-creator-business-intelligence-plan.md` §5.9.6）。

**触发词清单**（任一命中即进入本段）：

```text
IP / 个人品牌 / 人设
私域 / 社群 / 流量池
精准流量 / 精准获客
赛道 / 风口 / 红利
知识付费 / 课程 / 陪跑
变现 / 副业 / 干货
```

**黑话 → 大白话重述表**：

| 用户原话 | 不能直接写入 | 应追问或重述 |
|---|---|---|
| 我想做副业博主 | `niche=副业` / `goals=副业` | 你具体想帮谁通过什么方式多赚什么钱？你未来想卖信息、工具、服务，还是案例经验？ |
| 我想做个人 IP | `goals=IP` / `niche=个人 IP` | 你希望哪类人因为哪个具体问题记住你？这个被记住的结果服务什么动作（关注/咨询/复购）？ |
| 我要精准流量 | `audience=精准流量` | 精准到什么行为：关注、私信、报名、购买、复购，还是推荐？ |
| 我要做私域 | `conversion_path=私域` | 用户为什么要离开小红书？去了哪里？过去后你提供什么？ |
| 我要发干货 | `tone=干货` / `style=干货` | 读者看完能做什么具体动作？这条内容服务信任、线索还是成交？ |
| 我要做某某赛道 | `niche=赛道名` | 你要验证的是人群、问题、内容形式，还是商业供给？ |
| 我想搞知识付费 / 卖课 | `offer.delivery=course` 直接套 | 用户愿意为什么具体结果付费？你能交付什么变化？现在能不能先验证有人愿意问？ |

**重述对话示例**（完整一轮，仅作格式参考；不要照抄措辞）：

```text
你说"副业博主"，这个词太宽。先不用这个词。

用大白话说：你是想帮上班族找到可执行的副业项目，
还是想卖副业课程 / 资料 / 社群？

如果暂时没有产品，也没关系，我们先把它标成 product_research，
后面再观察评论里有没有具体购买信号。

你更接近哪一种？
```

**Question vs Problem 路由判断**：用户的提问要先分类：

| 类型 | 例子 | 处理 |
|---|---|---|
| `question`（问答） | 「小红书笔记标题多少字合适？」 | 直接回答（或交给 `08-compliance.md` Draft Time Rules）；**不要扩展为画像澄清** |
| `problem`（系统问题） | 「我怎么靠小红书赚钱？」「我适合做什么？」 | 必须靠发布、反馈、复盘才能回答。**不直接给答案**，拆成画像 + offer + 受众 + 内容实验，进入 Business Profile Building 段；先给 1-2 个最小验证动作 |
| `mixed` | 「我适合做什么赛道？我已经有公众号了」 | 先澄清目标（business goal），再给最小验证动作 |

**关键纪律**：

- **澄清结论不写文件**。不创建任何形式的概念澄清持久化文件（参见 plan §5.9.6 / §9.6 — v3.2 MVP 不为概念澄清新增独立 schema 或知识库文件）。澄清结论只回填 `profile.json` 大白话字段 + 喂给后面 Business Profile Building 段。
- **重述只问最多 2 轮追问**。两轮还说不清就允许 `unknown` 落盘，避免让 onboarding 变重。
- **schema 校验前必走本段**。如果用户原话仍出现触发词且字段没被改成大白话，回 `08-compliance.md` 的 Concept Precheck Rule Validation：拒写盘，提示用户重述。

### Business Profile Building

> 在 Concept Precheck 之后、Cold Start Seeding 之前。**最多 3 个问题**（plan §5.1.4 第二段「账号目标校准」），缺失字段允许 `unknown`，**不要卡死新用户**。`exploration` 不是低级状态、而是冷启动正确状态——必须显式向用户说明这一点。

**第 1 步：账号目标校准三问**

> 1. 你做这个账号最想先达成什么：**涨粉 / 建信任 / 私信咨询 / 卖东西 / 先测试方向**？
> 2. 你现在有没有产品或服务？**没有也可以**。
> 3. 如果有人被内容吸引，下一步你希望他做什么：**关注 / 评论 / 私信 / 进群 / 买东西 / 看直播**？

**第 2 步：自动判断 `creator_track`**（plan §5.1.4 末尾）

| 用户回答指向 | `creator_track` |
|---|---|
| 有产品/服务，并希望咨询 / 成交 / 直播 / 带货 | `offer_first` |
| 没有明确产品，但有清晰人群和长期方向（建信任 / 涨粉为主） | `creator_first` |
| 方向 / 人群 / 产品都不确定 | `exploration` |

**重要纪律**：在和用户对话时，**必须显式说明**：

> `exploration` 不是失败状态，也不是低级状态。它是新博主**正确**的冷启动状态——
> 此时系统会推荐能验证人群和问题的内容，而不是逼你写转化文案。

**第 3 步：写入 `business-profile.json`**

按 `agent/schemas/business-profile.schema.json` 校验后写入 `agent/knowledge-base/business-profile.json`：

```json
{
  "creator_track": "creator_first | offer_first | exploration",
  "creator_stage": "new",
  "primary_goal": "grow_followers | build_trust | get_leads | drive_sales | prepare_live | product_research | unknown",
  "offer_status": "none | idea | draft | selling | validated",
  "monetization_stage": "no_offer | offer_no_purchase | purchase_no_repeat | repeat_no_scale | scaled | unknown",
  "offer": {
    "name": "",
    "description": "",
    "price_range": "free | low | mid | high | unknown",
    "delivery": "content | consulting | course | service | physical_goods | digital_goods | community | unknown"
  },
  "buyer": {
    "description": "",
    "pain_points": [],
    "buying_trigger": "",
    "objections": []
  },
  "conversion_path": {
    "platform_role": "awareness | trust | lead_capture | sales | after_sales | unknown",
    "next_step": "follow | comment | dm | wechat | shop | live | link | unknown",
    "notes": ""
  },
  "business_model_probe": {
    "profit_evidence_level": "unknown",
    "profit_evidence": [],
    "platform_monetization_fit": "unknown",
    "pricing_risk": "unknown",
    "replacement_risk": "unknown",
    "model_notes": ""
  },
  "current_bottleneck": "no_direction | unclear_concept | no_benchmark | no_content | no_traffic | no_trust | no_offer | no_conversion | no_repeat | direction_hopping | no_publish | unknown",
  "risk_notes": [],
  "created_at": "YYYY-MM-DD",
  "updated_at": "YYYY-MM-DD"
}
```

**字段填写细则**（新博主默认值）：

- `creator_stage`：新博主默认 `new`
- `primary_goal`：根据问 1 回答映射；用户没明确表达 → `unknown`
- `offer_status`：问 2 回答映射；没产品 → `none`，有想法 → `idea`，有雏形 → `draft`
- `monetization_stage`：默认 `no_offer`；有产品但还没人买 → `offer_no_purchase`
- `conversion_path.next_step`：问 3 回答映射；不确定 → `unknown`
- `business_model_probe`：新博主全部 `unknown`（plan §5.1 末段：本 probe 仅 02-onboarding-existing 反推阶段必填）
- `current_bottleneck`：默认 `unclear_concept`（新博主普遍未澄清）；如果 Concept Precheck 后用户依旧含糊 → `no_direction`
- 写盘前必走 `08-compliance.md` Business Profile Validation；schema 校验失败 **不写盘**

**第 4 步：写完后通知用户**

> "你的业务画像已经记下了：
> - 当前赛道：`<creator_track>`（解释一句它的含义）
> - 主要目标：`<primary_goal>`
> - 转化下一步：`<next_step>`
>
> 这些不是终身判决，后面随时可以更新（说『我想换方向』就可以重走这一段）。
> 接下来我会基于这个画像帮你做选题筛选与冷启动播种。"

### Benchmark Seeding

> 在 Business Profile Building 之后、Cold Start Seeding 之前。本段把"先抓爆款 → 提 patterns"改造成"先筛对标 → 生成 dossier → 再从 dossier 抽 patterns"（plan §5.2.5）。**对标不是粉丝多就值得学**——必须经过两层过滤，并按结果区分 `business_benchmark` 与 `content_sample` 两类，前者才能影响商业判断，后者只能学内容形式。

**第 1 步 · 搜索用户领域关键词**

- 取 `profile.json.niche` + `business-profile.json.creator_track` / `primary_goal` 推关键词组（3 组）
- 调 `bash agent/scripts/xhs.sh search "<关键词>"` 拉候选账号 + 候选爆款内容
- 不限于本平台：用户主动提供的他平台账号（`platform != xiaohongshu`）也可以一起评估，写入 dossier 时如实标记
- 候选数量按互动量与新近度排序取 top 10-20

**第 2 步 · 两层过滤（v3.2 核心）**

#### 第一层 · 利润证据硬门（plan §5.2.4）

利润证据 ≠ 粉丝多 / 互动高。看的是**真实商业承接证据**：

- 是否有**产品 / 服务 / 课程 / 咨询 / 社群 / 店铺 / 直播 / 明确报价**
- 评论区是否出现**购买、询价、报名、要链接、问私信、复购**等高意图信号
- 是否存在**可观察的承接路径**：主页 / 店铺 / 私信关键词 / 直播 / 社群 / 微信
- 如果能观察到**投流、团队、稳定上新或规模化交付**，可提升等级

利润证据等级（5 档，写入 dossier 的 `monetization_guess.profit_evidence_level`）：

| 等级 | 说明 | `profit_evidence_gate` | 能否成 business_benchmark |
|---|---|---|---|
| `hard` | 明确产品 / 价格 / 购买路径 / 成交，或强商业承接证据 | `pass` | 可以 |
| `medium` | 多条询价 / 购买意图 / 咨询入口，但无法确认成交 | `pass` | 可以，但 dossier `risk_notes` 必须标注「未确认成交」 |
| `weak` | 只有泛互动或疑似商业意图 | `fail` | **不行**，只能 `content_sample` |
| `none` | 无任何商业承接证据 | `fail` | **不行**，只能 `content_sample` |
| `unknown` | 数据不足 | `unknown` | **不行**，待补证据；只能 `content_sample` 或暂不入库 |

**硬门不通过 → `benchmark_type = content_sample`**：本对标只能学标题 / 封面 / 结构 / 表达 / 选题包装，**绝不**进入商业判断（不影响 `business_score` / `monetization_distance_score`）。

**硬门通过 → 进入第二层**。

#### 第二层 · 4 项辅助过滤，至少 3/4 合格才生成 business dossier（plan §5.2.4）

| 判断 | 问题 | 不合格 → |
|---|---|---|
| **路径可见** | 能不能看懂它怎么获客、转化、交付或建立信任？ | 仅 `content_sample` |
| **动作可仿** | 当前用户能不能在合理时间内模仿主要动作？（不是只有"投流 / 大团队"才跑得通的） | 仅 `content_sample` |
| **用户相近** | 它吸引的人是否接近用户想吸引的人？ | 仅 `content_sample` |
| **风险可控** | 它是否依赖违规 / 擦边 / 强投流 / 特殊资源 / 不可复制人设？ | 仅 `content_sample`，并写 `risk_notes` |

**至少 3 项合格 → `benchmark_type = business_benchmark`**；不足 3 项 → 自动降级为 `content_sample`。

> 说明：第二层过滤是为了避免「高粉丝低利润」「靠投流跑量」「靠擦边博出位」类账号污染商业 benchmark。它们的内容形式仍可以借鉴，但**不能作为商业对标**。

**第 3 步 · 筛出 1-3 个可学对象**

- 优先保留 `business_benchmark`，最多 3 个；如果一个都没过硬门，可以保留 1-2 个 `content_sample` 用作内容形式参考
- 同一变现类型（如咨询类）最多保留 2 个，避免同质化堆积
- 不要因为粉丝多就保留——粉丝数**不是单一判断依据**

**第 4 步 · 为每个对象生成 dossier**

按 `agent/schemas/benchmark.schema.json` 校验后写入 `agent/knowledge-base/benchmarks/<slug>.json`：

- `slug` 命名：`<account_name 小写连字符>-<YYYYMMDD>`（如 `aroma-girl-20260428`）
- `id` = `benchmark_<YYYYMMDD>_<slug 主体>`
- 必填字段（schema required）：`id` / `benchmark_type` / `account_name` / `platform` / `monetization_guess` / `coverage` / `evidence_level` / `created_at`
- `monetization_guess`：必填子字段 `type` / `evidence` / `profit_evidence_gate` / `profit_evidence_level` / `confidence`
- 强约束：当 `profit_evidence_level ∈ {weak, none, unknown}` 时，`profit_evidence_gate` 必须为 `fail` 或 `unknown`，且 `benchmark_type` 必须为 `content_sample`
- `why_worth_learning` / `imitable_actions` / `not_imitable_actions` / `risk_notes` 至少在 `business_benchmark` 时各填 1 条
- `coverage` 取值由证据厚度决定（详见第 6 步评分降级表）
- 写盘前 **必走 schema 校验**；校验失败不写盘，回到第 4 步重写候选对象信息

**第 5 步 · 维护 `agent/knowledge-base/benchmarks/index.md`**

人类可读索引（plan §5.2.2）。每次生成 dossier 后追加 / 更新一条：

```markdown
# Benchmarks Index

| slug | account | type | profit_evidence_level | gate | aux_pass | coverage | benchmark_score 上限 | 摘要 |
|---|---|---|---|---|---|---|---|---|
| aroma-girl-20260428 | 香气女孩 | business_benchmark | medium | pass | 4/4 | account_dossier | 100 | 咨询陪跑路径清晰，评论区询价信号 12 条 |
| big-fans-only-20260428 | 大粉无变现 | content_sample | weak | fail | 2/4 | single_post_sample | 70 | 高粉但无产品/承接，仅作标题结构参考 |
```

字段语义：

- `aux_pass`：辅助过滤的"4 项中合格几项"（如 `4/4` / `3/4`）。`content_sample` 行允许 `< 3/4` 或 `n/a`。
- `benchmark_score 上限`：依 `coverage` 取（详见第 6 步表）。
- `摘要`：1 行说人话，**禁止**「这个博主一定赚钱」类断言；只描述可观察证据 + 类型判断。

**第 6 步 · benchmark_score 评分降级（plan §5.2.5）**

不同 `coverage` 来源能贡献的分数封顶值：

| 来源 | `coverage` | 封顶分数 | 说明 |
|---|---|---|---|
| 完整 business benchmark dossier（≥10 条样本 + 主页观察 + 承接路径） | `account_dossier` | 0-100 分 | 可写入 `related_benchmark_ids` |
| 单篇爆款样本 | `single_post_sample` | 最高 70 分 | 只说明内容结构被验证 |
| 本账号历史 pattern | `internal_pattern` | 最高 60 分 | 只说明本账号历史上类似内容有效 |
| 无对标证据 | `unknown` | `benchmark_score=null` | **不参与硬性判断**，不允许伪造高置信评分 |

**第 7 步 · 通知用户**

> "我筛了 X 个对标账号：
> - business_benchmark：<列表，含 profit_evidence_level 与一句承接路径>
> - content_sample：<列表，仅作内容形式参考>
>
> 详情见 `agent/knowledge-base/benchmarks/index.md`。这些不是终身判决，后续可以补充或替换。"

#### Benchmark Seeding 降级路径（MCP 不可用，plan §5.2.5 末尾）

当 `agent/scripts/xhs.sh status` 报 MCP **不可用** / `search` 返回空 / 节流被拒：

- 业务画像（`profile.json` + `business-profile.json`）正常完成
- `agent/knowledge-base/benchmarks/` **留空**（不要伪造 dossier）
- `index.md` 写一条降级记录：`> [degraded] YYYY-MM-DD MCP 不可用，benchmark seeding 跳过；待 MCP 恢复后重跑本段。`
- `state.cold_start_done = false`
- 后续 MCP 可用时由 `00-routing.md` 把控制权交回本剧本，仅跑 Benchmark Seeding + Cold Start Seeding 两段

> 备选信息源：MCP 不可用但用户**主动提供**了对标账号名 / 链接时，可基于 LLM 知识库做"轻量 dossier"，但 `coverage` 强制 `unknown`（除非有可验证证据），`evidence_level` 至多 `weak`，`benchmark_score` 留 null；不要让 LLM 自由发挥变成幻觉。

### Cold Start Seeding

**第 5 步：冷启动播种**（MCP 就绪才跑；否则跳过本步并把 `state.cold_start_done` 留 false）

> 优先从已生成的 `agent/knowledge-base/benchmarks/<slug>.json` dossier 抽 pattern；如果 Benchmark Seeding 段降级（benchmarks/ 为空），可回退到直接抓爆款的旧路径（互动量 top 10），但 patterns 标记 `source: competitor_raw, confidence: low`。

1. 读取 `agent/knowledge-base/benchmarks/*.json`：从 `business_benchmark` 与 `content_sample` 的 `title_patterns` / `cover_patterns` / `hook_patterns` / `top_topics` 抽取候选模式
2. 缺乏 dossier 时（降级路径）：用 `agent/scripts/xhs.sh search "领域关键词1"` 搜 3 组，对结果中互动量最高的 10 条调 `agent/scripts/xhs.sh detail <note_id>` 拿完整内容
3. 分析这些素材，提取：
   - 标题模式 3-5 个（如"数字清单体：5 个 XX 工具"）
   - 正文结构 2-3 种（如"痛点→方案→效果"）
   - 高频标签 top 10
   - 互动引导话术 2-3 种
4. 把提取的模式写入 `agent/knowledge-base/patterns.md`，每个 pattern 标记：
   - 来自 dossier：`source: benchmark, confidence: low|medium`，`benchmark_id: benchmark_YYYYMMDD_<slug>`
   - 来自原始爆款（降级）：`source: competitor_raw, confidence: low`

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

- `agent/knowledge-base/profile.json` —— Profile Building 第 4 步写入；写前按 `agent/schemas/profile.schema.json` 校验；触发词原话不得入库（详见 Concept Precheck 段 + `08-compliance.md`）
- `agent/knowledge-base/business-profile.json` —— Business Profile Building 第 3 步写入；写前按 `agent/schemas/business-profile.schema.json` 校验；新博主允许大量 `unknown`
- `agent/knowledge-base/benchmarks/<slug>.json` —— Benchmark Seeding 第 4 步写入；写前按 `agent/schemas/benchmark.schema.json` 校验；强约束：`profit_evidence_level ∈ {weak, none, unknown}` 时 `profit_evidence_gate` 必须 `fail|unknown` 且 `benchmark_type=content_sample`
- `agent/knowledge-base/benchmarks/index.md` —— Benchmark Seeding 第 5 步维护；含 slug / type / profit_evidence_level / gate / aux_pass / coverage / 摘要
- `agent/knowledge-base/patterns.md` —— Cold Start Seeding 第 5 步追加（来自 dossier：`source: benchmark`；降级路径：`source: competitor_raw`）
- `agent/knowledge-base/preferences.json` —— 第 6 步写入空骨架；写前按 `agent/schemas/preferences.schema.json` 校验
- `agent/config/state.json` —— `profile_created = true`（Profile Building 完成后）；`business_profile_created = true`（Business Profile Building 完成后；新增字段）；`cold_start_done = true`（Cold Start Seeding 成功落 patterns 后）；`setup_completed = true`（环境与画像皆就绪后）
- `agent/config/runtime.env` —— 仅在用户提供 Gemini Key 时由 `image.py --set-key` 改写

**不写**：

- 任何形式的概念澄清持久化文件 —— Concept Precheck 是 onboarding playbook 判断规则，**不持久化**（plan §5.9.6 / §9.6 - v3.2 MVP 不新增对应 schema 或 KB 文件）。澄清结论只回填 `profile.json` / `business-profile.json` 字段。

## Failure Handling

- **MCP 未就绪 / list_feeds / search 不可用** → 跳过 Benchmark Seeding 与 Cold Start Seeding；画像仍正常写入；`benchmarks/` 留空（不要伪造 dossier），`index.md` 写一条 `[degraded]` 记录；`state.cold_start_done = false`，等 MCP 恢复后由路由表（`00-routing.md`）回到本剧本仅跑 Benchmark Seeding + Cold Start Seeding 段
- **Benchmark Seeding 利润证据硬门不通过** → 自动降级为 `content_sample`，**不**作为商业对标；`profit_evidence_gate` 写 `fail|unknown`，dossier 仍可生成但 `benchmark_score` 受 `coverage` 封顶
- **Benchmark schema 校验失败** → 不写 dossier；不要在 `index.md` 留下半成品行；回到候选清单重写
- **用户拒绝提供 Gemini Key** → 安装流程停在 Environment Setup 第 3 步第 2 项，不进入 Profile Building；告知用户这是强依赖
- **MCP 登录失败 / cookie 无效** → 重试一次；失败则把详细错误回报用户并交给 `09-troubleshooting.md`
- **Schema 校验失败** → 不写盘；把缺失/越界字段告诉用户并重写，**绝不**直接写入越界数据（详见 `08-compliance.md`）
- **三问对话用户未答完整** → 已答字段先暂存，缺什么再追问；不允许半填的 `profile.json` 落盘
- **Concept Precheck 两轮追问后用户仍说不清** → 允许 `unknown` 落盘，不再追问；`current_bottleneck` 置为 `unclear_concept`
- **Business Profile Building schema 校验失败** → 不写 `business-profile.json`；展示具体字段错误（含 `creator_track` 越界 / `monetization_stage` 缺失等），引导用户改；详见 `08-compliance.md` Business Profile Validation
- **business-profile 缺失** → 路由可允许进 03/04，但 `business_alignment=unknown`；不阻塞草稿生成；详见 `09-troubleshooting.md`

## Anti-Patterns
- 不擅自合并多方向（让用户决策主攻）
- profile 已存在绝不再问（覆盖必须用户主动说"更新画像"）
- 不在本节问 Telegram / IM 通讯凭证（hermes-agent 的事）
- 不绕回扫码（用户主动给 cookie 必须立即接受）
- 不让冷启动失败拖死建画像（两步可拆，state 分别标记）
- **不直接把触发词原话写进 `profile.json` / `business-profile.json`**（IP / 副业 / 私域 / 精准流量 / 干货 / 赛道 / 变现 等必须先大白话重述）
- **不把 `exploration` 当作低级状态**或失败状态——它是新博主**正确**的冷启动状态
- **不持久化概念澄清过程**（不为它新增任何独立 schema / KB 文件；澄清结论只回填画像字段）
- **不超过 6 个核心问题 + 1-2 个澄清追问**（onboarding 总问题数硬上限）
- **不强迫新博主填 `business_model_probe`**（新博主全部 `unknown`，仅老博主反推阶段必填）
- **不把粉丝数作为 benchmark 的唯一判断**：高粉丝低利润必须降级为 `content_sample`，不能作为商业对标
- **business_benchmark 必须严格走两层过滤**：第一层利润证据硬门 + 第二层至少 3/4 项辅助合格；任一不满足必须自动降级
- **MCP 不可用时不要伪造 dossier**：`benchmarks/` 宁可留空，也不要让 LLM 自由发挥；只允许在用户主动提供对标账号时做"轻量 dossier"且 `coverage=unknown`、`evidence_level<=weak`

## Cross-Refs
- → 00-routing.md（路由表决定本剧本是否被命中；含触发词与「我想换方向」的转入规则）
- → 02-onboarding-existing.md（用户其实是老博主时切过去；本剧本的 Concept Precheck 触发词在那边也复用）
- → 06-learning-loop.md（preferences.json 中 `weight` / `confidence_level` 公式与 sample_factor 语义）
- → 08-compliance.md（schema 校验细则、日期格式、Concept Precheck Rule Validation、Business Profile Validation）
- → 09-troubleshooting.md（任何步骤失败；含 business-profile 缺失 / 校验失败处理）
- → `agent/schemas/business-profile.schema.json`（Business Profile Building 写盘字段契约权威）
- → `agent/schemas/benchmark.schema.json`（Benchmark Seeding 写盘字段契约权威；含 `benchmark_type` / `monetization_guess.profit_evidence_gate` / `coverage` 等强约束）
- → `agent/knowledge-base/business-profile.json.example`（完整字段填法参考）
- → `agent/knowledge-base/benchmarks/index.md`（Benchmark Seeding 维护的人类可读索引）
- → `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.1 / §5.2 / §5.9（业务画像 + 对标 dossier + 概念澄清的设计权威）
