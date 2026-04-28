---
id: 02-onboarding-existing
title: Existing Creator Onboarding
when:
  - "用户自述已有运营账号"
  - "creator_mode=existing"
  - "install --mode=existing-creator"
needs:
  required:
    - agent/schemas/profile.schema.json
    - agent/schemas/audit-report.schema.json
    - agent/schemas/benchmark.schema.json
calls:
  scripts:
    - agent/scripts/xhs.sh
    - agent/scripts/import-existing.sh
    - agent/scripts/audit-report.sh
    - agent/scripts/db.sh
  playbooks:
    - 06-learning-loop.md
writes:
  files:
    - agent/data/xhs.db (posts source=imported)
    - agent/data/xhs.db (creator_behavior_signals)
    - agent/knowledge-base/profile.json
    - agent/knowledge-base/business-profile.json
    - agent/knowledge-base/benchmarks/<slug>.json
    - agent/knowledge-base/benchmarks/index.md
    - agent/knowledge-base/audit-*.{md,json}
    - agent/knowledge-base/patterns.md
    - agent/knowledge-base/creator-behavior-signals.md
preconditions:
  - "state.creator_mode == 'existing'"
  - "state.existing_import_done == false"
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
---

# 02 Existing Creator Onboarding

> 跟 `01-onboarding-new.md` 中的"Profile Building"段**互斥**。老博主进这条路，**不走三问对话**，不走竞品冷启动。

## Trigger

任一满足即进本剧本：

1. 用户自述"我已经在运营小红书"、"已经有账号了"、"已经发过帖"、"我的号粉丝已经 XXX"
2. `agent/config/state.json` 中 `creator_mode == 'existing'`
3. 用户用 `bash install.sh --mode=existing-creator` 装的
4. `agent/config/state.json` 中 `existing_import_done == false` 但 `creator_mode == 'existing'`（流程未走完，由 `00-routing.md` 引回本剧本）

## Read This When

老博主第一次接入薯灵；或上次接入流程在批量导入 / 画像反推 / 体检报告任一步中断，由路由表把控制权交回本剧本。**不要因为 profile.json 缺失就跳到 01。**

## Inputs

- 用户已登录的小红书账号（`agent/scripts/xhs.sh status` 报 OK）
- MCP 的 `list_feeds` 能返回该账号的历史帖列表（v2.2.0 MVP 阶段如未完成则降级，见 Failure Handling）
- 最近 30 条 `imported` 样本（标题 + 正文前 200 字）—— 第 4 步反推画像的素材
- `agent/schemas/profile.schema.json` / `agent/schemas/audit-report.schema.json` —— 写盘前校验依据

## Procedure

**第 1 步 · 确认账号登录**（复用 `01-onboarding-new.md` 的登录策略）

- 用户主动提议 cookie → 立即接受：`bash agent/scripts/xhs.sh import-cookie '<cookie字符串>'`
- 否则 `bash agent/scripts/xhs.sh login` 扫码

**第 2 步 · 批量导入历史**

```bash
bash agent/scripts/import-existing.sh --limit 200
# 耗时：按节流 profile 约 30+ 分钟；可挂后台
# 中断续跑：bash agent/scripts/import-existing.sh --resume
```

- 如果用户帖数少（< 30），降级跳过本剧本改走 `01-onboarding-new.md` 的三问对话，但提醒用户"历史太少，画像反推置信度低"
- 如果 MCP `list_feeds` 集成未完成，必须告诉用户"此功能在 v2.2.0 MVP 阶段仅支持 `--mock` 路径"，然后回退到 `01-onboarding-new.md`

**第 3 步 · 自动分类 imported posts**

- 读 `posts WHERE source='imported' AND topic_type IS NULL`
- 小批量（每批 20 条）调 LLM（你自己）分类：
  - `topic_type` —— 从账号整体话题聚类中选（先做聚类，再套枚举）
  - `title_pattern` —— 数字清单 / 反差悬念 / 结果导向 / 问句 / 对比 / 其它
  - `content_style` —— 口语 / 干货 / 幽默 / 犀利 / 故事 / 教程
- 分类结果通过 `bash agent/scripts/db.sh update-post-meta '<json>'` 回写
- 分类不出来的标 `__unclassified__`，**不计入**偏好 bootstrap

**第 4 步 · 画像反推**

- 读最近 30 条 `imported` 样本（title + content 前 200 字）
- AI 做聚类分析，产出 `profile.json` **草案**：

```json
{
  "niche": "<推测的领域，必须从样本中来>",
  "audience": "<目标受众的具体描述>",
  "tone": "<口语/干货/幽默/犀利/...>",
  "goals": "<如有线索，留空也行>",
  "created_at": "<今日>",
  "updated_at": "<今日>"
}
```

- **必须展示给用户确认**：
  > "基于你 30 条历史帖，我推测你是 `<niche>` 方向，面向 `<audience>`，风格 `<tone>`。对吗？"
- 用户确认 / 微调 / 推翻后才写入 `agent/knowledge-base/profile.json`（先按 `agent/schemas/profile.schema.json` 校验字段）
- 如果样本跨多领域：展示多个候选方向，**让用户决策主攻**，不擅自合并

### Concept Clarification (Optional)

> 触发：用户在第 1 步登录后或第 4 步画像反推确认对话中给出模糊方向（出现「IP / 个人品牌 / 人设 / 私域 / 社群 / 流量池 / 精准流量 / 赛道 / 风口 / 红利 / 知识付费 / 课程 / 陪跑 / 变现 / 副业 / 干货」等触发词），或自述「我想换方向」/「想重新做定位」。

复用 `01-onboarding-new.md` 的 **Concept Precheck / Problem Dissolution** 同一套触发词清单 + 大白话重述表。本剧本下的差异点：

- **重述结论的落点不同**：
  - 在 `01` 里，澄清结论会回填新博主的 `profile.json`（因为画像还没建立）。
  - 在 `02` 里，画像已存在/已反推；澄清结论 **回填 `business-profile.json`**（详见下面 Business Profile Inference 段），不动 `profile.json.niche`。例如用户原话「我想做副业博主」，不更新 `niche`，但要在 `business-profile.json.primary_goal` / `offer.delivery` / `buyer.description` 里填大白话版本。
  - 不为概念澄清新增独立 schema / KB 文件，澄清结论不持久化（plan §5.9.6）。

- **不进入大改造**：用户没主动说要换方向时，不要为了一个触发词就把整套 onboarding 重做。

### Business Profile Inference

> 在画像反推确认后、生成 audit-report 之前。从历史内容反推业务画像 6 个维度（plan §5.1.5 列表前 4 条 + 商业模式探针前 3 项）。

**反推维度**（plan §5.1.5）：

1. 是否长期围绕某类产品 / 服务（→ `offer.delivery` / `offer.description`）
2. 是否频繁出现咨询、课程、资料、服务、带货、直播等信号（→ `monetization_stage` / `business_model_probe.profit_evidence`）
3. 评论区是否有购买意图、问链接、问价格、问怎么报名（→ `business_model_probe.profit_evidence_level` 与 `profit_evidence` 列表）
4. 内容是否更偏涨粉、信任、转化、售后或社群维护（→ `primary_goal` / `conversion_path.platform_role`）
5. 主页/签名/置顶是否暗示商业承接路径（→ `conversion_path.next_step`）
6. 内容观点的独特性 / 用户记忆点 / 案例资产（→ `business_model_probe.replacement_risk`）

**`creator_track` 反推规则**（与 `01` 保持一致）：

- 历史里有产品/服务并希望咨询、成交、直播、带货 → `offer_first`
- 没有明确产品但有清晰人群和长期方向 → `creator_first`
- 方向、人群、产品都不确定 → `exploration`（注意：`exploration` **不是失败状态**，而是冷启动的正确状态）

### 商业模式 7 测试轻量版

> 老博主 audit report 的硬要求（plan §5.1.5）。下列 7 测试**至少必须回答前 3 个**（利润证据 / 平台匹配 / 商业阶段）；后 4 项尽量给出，证据不足时允许 `unknown`，不强行下结论。

| # | 测试 | 问题 | 证据来源（DB / KB） | 写入字段 |
|---|---|---|---|---|
| 1 | 利润证据 | 是否有可观察的付费、询价、购买路径或商业承接？ | 评论 `comment_insights` / 私信线索 / 主页/置顶 / 直播 / 课程 / 价格信号 / 报名入口 | `business_model_probe.profit_evidence_level` + `profit_evidence[]` |
| 2 | 平台匹配 / 平台变现匹配 | 小红书流量是否适合这个变现路径？ | 客单价、决策周期、内容信任要求、低毛利商品风险 | `business_model_probe.platform_monetization_fit` |
| 3 | 商业阶段 | 博主处于哪一阶段？ | 无产品 / 有产品无人买 / 有人买但不复购 / 有复购但没规模化 / 已规模化 | `monetization_stage` + `creator_stage` |
| 4 | 定价合理性 | 定价和内容信任、交付成本、获客成本是否匹配？ | 价格区间、评论阻力、同行价格、交付方式 | `business_model_probe.pricing_risk` |
| 5 | 替代风险 | 这个账号是在沉淀信任资产，还是只是可被替代的流量位？ | 观点独特性、用户记忆点、案例资产、产品差异 | `business_model_probe.replacement_risk` |
| 6 | 转化路径 | 从笔记到下一步动作是否清楚？ | CTA、私信关键词、店铺链接、直播、社群、微信承接 | `conversion_path.next_step` + `conversion_path.notes` |
| 7 | 复购 / 规模化 | 是否有复购、转介绍或规模化迹象？ | 复购评论、社群、系列产品、团队/投流/交付规模 | `creator_stage` + `business_model_probe.model_notes` |

**利润证据等级**（写入 `profit_evidence_level`，5 档）：

- `hard`：明确产品 / 价格 / 购买路径 / 成交，或强商业承接证据
- `medium`：多条询价 / 购买意图 / 咨询入口，但无法确认成交
- `weak`：只有泛互动或疑似商业意图
- `none`：无任何商业承接证据
- `unknown`：数据不足

**禁止断言收入**：薯灵不能输出「这个博主一定赚钱 / 不赚钱」。允许的措辞示例：

```text
利润证据等级：medium
证据：评论区出现 12 次"怎么买/多少钱/链接在哪"，主页存在咨询入口。
判断：存在商业承接迹象，但无法确认真实成交。
```

### Replacement Risk Hint

> 当 `business_model_probe.profit_evidence_level ∈ {hard, medium}` **且** `business_model_probe.replacement_risk == high` 时，audit report **必须**在「商业阶段判断」段后追加替代风险提示（plan §5.1.5 末尾）。

**审计规则**（伪代码）：

```text
if profit_evidence_level in ["hard", "medium"] and replacement_risk == "high":
    audit_warning = "存在商业承接证据，但商业模式替代风险高"
    recommended_assets = ["case", "objection", "audience_language", "workflow_rule"]
```

**输出给用户的措辞**（必须用此风格，不允许人格评价 / 收入断言）：

```text
这个账号看起来有商业承接，但它更像「流量转卖位」，不是强资产型账号。
建议接下来沉淀更多无法被替代的资产：
- 真实案例（case）
- 用户反对意见（objection）
- 目标用户原话（audience_language）
- 经过验证的方法流程（workflow_rule）
```

写入位置：`risk_notes[]` 加一条 `"商业模式替代风险高，建议沉淀 case/objection/audience_language/workflow_rule 等独占资产"`。

### Behavior Signal Initial Scan

> 历史导入分类完成后，扫描以下 3 类行为模式。**命中即直接写表**，通过 `bash agent/scripts/db.sh add-creator-behavior-signal '<json>'`。JSON 必须符合 `agent/schemas/creator-behavior-signal.schema.json`。同时往 `agent/knowledge-base/creator-behavior-signals.md` 追加一条节段（参考该 .md 的「示范条目」格式）。

**老博主历史导入命中规则**：

| 信号 (`signal_type`) | 触发条件（基于 `posts` + `published_at`） | 默认 `severity` | 默认 `next_small_action` 方向 |
|---|---|---|---|
| `direction_hopping` | 14 天内 `topic_type` 变更 ≥ 3 次（聚类后 niche 漂移） | `warn` | 收敛到 1 个最有数据基础的方向，做 7 天小验证再判断 |
| `draft_no_publish` | 历史导入语境通常不直接触发——若 `posts` 里发现 `status='draft' AND published_at IS NULL` 持续 ≥ 7 天，记 `info` | `info` | 锁定一条可发布稿，减少继续改稿 |
| `planning_loop` | 用户在反推确认对话中连续多次说「再帮我看看」「再分析下」「我再想想」，但还没确认画像 | `info` | 收敛到 1 个最小动作（如先确认一个主推方向） |

**输出原则**（**严格遵守 plan §5.7.5；不达标即拒写**）：

- **只描述可观察事件 + 给出下一步最小动作**
- **不做心理诊断 / 不做人格评价 / 不把执行摩擦写成用户缺点**
- 禁词清单与同义改写检查由 `08-compliance.md` 的 **Behavior Signal Output Validation** 段统一维护（任何把执行摩擦说成用户人格 / 心理 / 道德缺陷的措辞都会被拒写）
- 仅引用可统计事件：`draft_generated` / `draft_rejected` / `direction_changed` / `benchmark_requested` / `publish_skipped` / `review_ignored`

**写表示例**：

```bash
bash agent/scripts/db.sh add-creator-behavior-signal '{
  "id": "behavior_20260428_direction_hopping",
  "signal_type": "direction_hopping",
  "severity": "warn",
  "observed_events": [
    {"event": "direction_changed", "count": 4, "window_days": 14, "evidence": "imported posts 显示 14 天内 topic_type 由「美食探店」→「读书笔记」→「职场干货」→「家居收纳」"}
  ],
  "interpretation": "过去 14 天内可观察到 4 次主题切换，每个方向单独样本不足 5 条。",
  "next_small_action": "选择一个有数据基础的方向，连续 7 天发 3 条同主题内容，再判断是否值得继续。",
  "created_at": "2026-04-28"
}'
```

**反推完成后必须展示给用户确认**（plan §5.1.5 末尾示例）：

```text
我基于你最近 30 条内容推测：
- 当前账号主要目标：建立信任 + 私信咨询
- 可能的产品形态：一对一咨询/陪跑
- 商业阶段：有产品，但复购/规模化证据不足
- 利润证据等级：medium
- 平台变现匹配：较强，小红书适合高信任咨询/陪跑类转化
- 当前瓶颈：内容有观点，但转化路径不清晰

这个判断对吗？你可以直接改。
```

用户确认 / 微调 / 推翻后才写入 `agent/knowledge-base/business-profile.json`（写前按 `agent/schemas/business-profile.schema.json` 校验，详见 `08-compliance.md` Business Profile Validation）。

### Benchmark Gap Analysis (Optional)

> 在 Business Profile Inference 与 Behavior Signal Initial Scan 之后、第 5 步生成 audit-report 之前。本段是**可选**的——`optional` 是默认状态，**不强制**用户提供对标，证据不足时直接跳过本段，**不要**为了凑差距分析而硬挤一个对标。详见 plan §5.2.6。

#### 触发条件

任一即触发；**两者皆不满足时跳过本段**：

1. 用户在 onboarding 对话中**主动提供**对标账号（账号名 / 主页链接 / 截图描述等）
2. 用户没主动提，但导入历史的 `imported posts` 与某些热门账号在**选题 / 话题聚类**上高度重合 → 可推荐 1-2 个候选给用户确认是否要做差距分析；**用户拒绝即停**，不重复追问

> 优先级：**用户主动提供**优先；自动推荐仅作为补充提示。**没提供 → optional → 直接跳本段**，不影响后续 audit-report 生成。

#### 流程

1. **生成对标 dossier**：复用 `01-onboarding-new.md` 的 **Benchmark Seeding** 段流程
   - 同样走两层过滤：第一层利润证据硬门（`hard|medium|weak|none|unknown` 5 档）+ 第二层 4 项辅助过滤（路径可见 / 动作可仿 / 用户相近 / 风险可控，至少 3/4 合格）
   - 通过 → `benchmark_type=business_benchmark`；不过 → `content_sample`
   - 写入 `agent/knowledge-base/benchmarks/<slug>.json`，按 `agent/schemas/benchmark.schema.json` 校验
   - 同步在 `agent/knowledge-base/benchmarks/index.md` 追加 / 更新一行
2. **做差距对照**：用本账号已建立的 `profile.json` + `business-profile.json` + 导入历史的 `topic_type` / `title_pattern` / `content_style` 分布与 dossier 比对

#### 差距分析格式（plan §5.2.6 末尾 6 维表）

把对标差距以**6 维表格**形式输出（不是只输出一段笼统评语）：

| 维度 | 你（基于导入历史） | 对标（基于 dossier） | 差距 / 建议 |
|---|---|---|---|
| **选题** | 你更分散：14 天 4 个 topic_type | 对标更集中：单 topic_type 占 70%+ | 收敛到 1 个最有数据基础的方向先做 7 天小验证 |
| **标题** | 偏描述（如「最近读了一本书」） | 偏冲突 / 结果承诺（如「读完这本书我赚回了 5w」） | 学对标的"数字+结果"或"反差悬念"公式 |
| **封面** | 信息密度低（无明确判断） | 首屏挂明确判断（一句结论 + 主关键词高亮） | 封面公式 imitable_action 已写入 dossier，可直接学 |
| **变现** | 没有下一步动作（CTA 缺失） | 每 3-5 条出现 1 次转化内容（咨询入口 / 报名链接 / 私信关键词） | 在系列内容中插入 1 条带承接路径的内容 |
| **可先模仿动作** | — | 标题公式 / 封面结构 / 系列化选题 | 列入下一周内容计划 |
| **不建议模仿动作** | — | 高频直播 / 强人设争议表达 / 强投流 | 不进入计划；如对标有明显风险（违规/擦边）写 `risk_notes` |

> 对标如果是 `content_sample`（未过利润证据硬门），变现行允许写「对标本身利润证据不足，**不能**作为商业对标，仅供内容形式参考」，并把"变现"那一行的差距判断**留空**或标 `n/a`。

#### 写入位置

- **差距分析输出**：作为新增段落追加到 `agent/knowledge-base/audit-<YYYY-MM-DD>.md`（已有文件，第 5 步由 `audit-report.sh` 生成的人类可读骨架）。本段在 `audit-*.md` 中以 `## 对标差距分析` 标题起新节段，附带 dossier 引用：「对标 dossier：`agent/knowledge-base/benchmarks/<slug>.json`」
- **dossier 落地**：`agent/knowledge-base/benchmarks/<slug>.json` 写盘前按 `agent/schemas/benchmark.schema.json` 校验
- **index.md 维护**：与 `01-onboarding-new.md` Benchmark Seeding 第 5 步格式一致

> 本 wave 不强制改 `audit-report.sh`：差距分析段落由 AI 在跑完 `audit-report.sh` 后**追加**到 `.md` 文件即可，无需脚本侧增强；脚本侧增强留给后续 wave。

#### 关键纪律

- **不强制**：用户没主动提对标，且自动推荐被拒 → 跳过本段；audit-report 仍正常出，不影响 `state.business_profile_created`
- **不只看粉丝**：高粉丝低利润必须降级为 `content_sample`，不能影响"变现"那一行的判断
- **不断言收入**：「对标博主一定赚钱 / 这个差距导致你赚不到钱」类措辞**禁止**；只能输出可观察证据 + 可模仿动作 + 不建议模仿动作
- **重复对标先合并**：同一对标若 7 天内已生成过 dossier，直接复用；不要重复写 `<slug>-<日期>.json`
- **dossier 缺失则差距分析跳过**：schema 校验失败或 MCP 不可用 → 不生成差距分析段，audit-report 正常出

**第 5 步 · 挖 patterns 种子 + 出体检报告**

```bash
bash agent/scripts/audit-report.sh --extract-patterns
# 产出:
#   agent/knowledge-base/audit-<YYYY-MM-DD>.json   机器可读
#   agent/knowledge-base/audit-<YYYY-MM-DD>.md     人类可读骨架
```

- AI 读 JSON → 对 `extract_patterns.pattern_candidates` 做二次抽象（标题结构 / 情绪钩子 / 核心结构），**重复 ≥ 3 次的模式**写入 `agent/knowledge-base/patterns.md`（**confidence=medium**，因为是用户自己的历史验证）
- `anti_pattern_candidates` 同样抽象 → `agent/knowledge-base/anti-patterns.md`（confidence=medium）
- AI 对 JSON 做归因分析（为什么 Top/Bottom 这样）→ 填 `ai_narrative` 字段并追加到配套 `.md` 文件
- AI 的 `ai_narrative` 必须按 `agent/schemas/audit-report.schema.json` 的 `ai_narrative` 子 schema 写（`written_at / top_reasoning / bottom_reasoning / action_items[] / watch_signals[]`）

**流程结束后写 state.json**：

```json
{
  "creator_mode": "existing",
  "existing_import_done": true,
  "profile_created": true,
  "business_profile_created": true,
  "cold_start_done": true,
  "setup_completed": true,
  "setup_date": "<今日>"
}
```

注意：

- `cold_start_done=true` 是因为 patterns.md 已经从用户自己历史挖到了种子，不必再跑竞品冷启动。
- `business_profile_created=true` 在 Business Profile Inference 段用户确认后写入；如果用户拒绝或证据不足允许只写 `false`，由 03-daily-flow.md 在缺失时按 `business_alignment=unknown` 兜底。

### 偏好 bootstrap（本剧本自动做）

- 对每条分类后的 imported post 写一条"隐式选择"记录：
  - `choice_type` = `topic` / `title_pattern` / `content_style` 三次
  - 虚拟 `offered_count = 3`，`chosen_label = <本帖的分类值>`，`skipped_labels = ["__implicit_unknown__", "__implicit_unknown__"]`
  - 通过 `bash agent/scripts/db.sh log-choice '<json>'` 写入 `user_choices` 表
- `preferences.json` 由日常学习循环从 `user_choices` 聚合 —— **见 `06-learning-loop.md` 关于 `total_choices` 封顶 50 与 `sample_factor` 处理**（避免 170 条历史让 `sample_factor` 直接 = 1.0 → 立即进 1 选档；预留后续真实用户选择的学习空间）

### 关键纪律

- **不要走 01 的三问对话**：用户已经用行为回答了所有问题
- **不要让用户从零填画像**：AI 反推 + 用户确认 / 微调
- **多方向账号不擅自合并**：展示给用户让他决策主攻方向
- **import 中断必可续**：`--resume`，不重来
- **失败单条跳过**：不让 1 条脏数据中断 199 条好数据
- **imported posts 不纳入每日复盘**：`05-review.md` 复盘只看 `source='shuling'`（不然老博主历史帖会被当成"今日新发"反复分析）；需要时用 `audit-report.sh --include-organic`

### 与 00-routing.md 业务路由的协同

路由表扩展：

| 当前状态 | 下一步 |
|---------|------|
| `creator_mode=existing` 且 `existing_import_done=true` 且 `setup_completed=true` | 直接进 `03-daily-flow.md`（imported 历史已生效） |
| `creator_mode=existing` 且 `existing_import_done=false` | 进入本剧本继续未完成步骤（不要跳回 `01-onboarding-new.md`） |
| `creator_mode=new` 或 `unset` | 走原路径（`01-onboarding-new.md` → `03-daily-flow.md`） |

## Writes

- `agent/data/xhs.db`
  - `posts` 表追加 `source='imported'` 行（第 2 步）
  - `posts` 表 `topic_type / title_pattern / content_style` 字段回写（第 3 步）
  - `user_choices` 表追加隐式选择记录（偏好 bootstrap）
  - `creator_behavior_signals` 表追加（Behavior Signal Initial Scan 命中时；通过 `bash agent/scripts/db.sh add-creator-behavior-signal '<json>'` 写入；JSON 符合 `agent/schemas/creator-behavior-signal.schema.json`）
- `agent/knowledge-base/profile.json` —— 第 4 步用户确认后写入；按 `agent/schemas/profile.schema.json` 校验
- `agent/knowledge-base/business-profile.json` —— Business Profile Inference 段用户确认后写入；按 `agent/schemas/business-profile.schema.json` 校验；含商业模式 7 测试前 3 项的判断结果
- `agent/knowledge-base/benchmarks/<slug>.json` —— Benchmark Gap Analysis 触发时写入；按 `agent/schemas/benchmark.schema.json` 校验；与 01-onboarding-new.md Benchmark Seeding 共用同一 schema 与两层过滤逻辑
- `agent/knowledge-base/benchmarks/index.md` —— Benchmark Gap Analysis 触发时维护索引行
- `agent/knowledge-base/creator-behavior-signals.md` —— Behavior Signal Initial Scan 命中时追加节段（格式见该 .md 头部说明 + 示范条目）
- `agent/knowledge-base/audit-<YYYY-MM-DD>.json` / `.md` —— 第 5 步生成；`audit-report.sh` 已扩展输出业务画像推测、商业模式轻量测试、利润证据与平台匹配等段（见 `agent/scripts/audit-report.sh`）；Benchmark Gap Analysis 触发时由 AI 在 .md 末尾追加 `## 对标差距分析` 段（不需脚本侧增强）
- `agent/knowledge-base/patterns.md` / `anti-patterns.md` —— 第 5 步追加（confidence=medium）
- `agent/config/state.json` —— 流程末尾写入完整 milestone 块（含 `business_profile_created`，见上）

**不写**：

- 任何形式的概念澄清持久化文件 —— Concept Clarification 段是 onboarding playbook 判断规则，**不持久化**（plan §5.9.6 / §9.6 - v3.2 MVP 不新增对应 schema 或 KB 文件）。澄清结论只回填 `business-profile.json` 字段。

## Failure Handling

- **import 中断**（网络 / 节流 / 用户中断）→ `bash agent/scripts/import-existing.sh --resume`，**不重来**；已成功的行不重复写入
- **MCP `list_feeds` 未完成 / 返回空** → 告知用户当前阶段仅支持 `--mock`，回退到 `01-onboarding-new.md` 三问对话
- **用户帖数 < 30** → 降级到 `01-onboarding-new.md`；提醒"画像反推置信度低"
- **单条解析失败** → 跳过该条；记录到 `request_log`；不让 1 条脏数据中断剩余批次
- **画像反推用户全盘推翻** → 不要硬塞；改用 `01-onboarding-new.md` 的三问对话补齐 `niche / audience / tone`，但 imported 历史保留（源仍为 `existing`）
- **business-profile 反推证据不足 / 用户拒绝确认** → 不写 `business-profile.json`；写 `state.business_profile_created=false`；audit report 段标记 `degraded`，不阻塞后续 03-daily-flow（详见 `09-troubleshooting.md`）
- **`business_model_probe.replacement_risk` 评估证据不足** → 标 `unknown`，**不强制下结论**；audit report 该段写「数据不足以判断替代风险，建议接下来 7 天注意评论中的具体反对意见与购买信号」
- **行为信号扫描误触发**（用户主动表示不准确） → 不写表；本次会话内不再提示同类信号
- **`add-creator-behavior-signal` 写表失败 / `creator_behavior_signals` 表缺失** → 仅追加 `creator-behavior-signals.md`，不阻塞 onboarding；记录到 `degraded`
- **Benchmark Gap Analysis 用户没提供对标 / 自动推荐被拒 / MCP 不可用** → **跳过本段**；audit-report 仍正常出，不影响 `state.business_profile_created`；不要硬挤一个对标
- **Benchmark schema 校验失败** → 不写 `benchmarks/<slug>.json`；不在 `index.md` 留下半成品行；差距分析段也不追加到 audit-*.md
- **schema 校验失败** → 不写 `profile.json` / `business-profile.json` / `audit-*.json` / `benchmarks/<slug>.json`；详见 `08-compliance.md`

## Anti-Patterns
- 不走 §1 三问对话
- 不让用户从零填画像
- 多方向不擅自合并
- imported posts 不纳入每日复盘
- import 中断必可续
- **行为信号输出绝不带人格评价**（禁词与同义改写清单由 `08-compliance.md` Behavior Signal Output Validation 维护，命中即拒写）
- **不断言用户收入**：不输出「这个博主一定赚钱 / 一定不赚钱」；只能给可观察的利润证据等级 + 证据列表
- **不持久化概念澄清过程**：不为它新增任何独立 schema / KB 文件；澄清结论只回填 `business-profile.json` 字段
- **替代风险证据不足时只能 unknown**：不强行下「替代风险高/低」结论
- **`business_model_probe` 字段允许大量 `unknown`**：证据不足时不要为了好看就硬填；`unknown` 是合法状态
- **Benchmark Gap Analysis 是 optional**：用户不主动提供且自动推荐被拒就跳过；不强制凑差距分析
- **不把粉丝数当作唯一判断**：差距分析里的对标必须经过两层过滤；高粉丝低利润降级为 `content_sample`，"变现"那一行允许留空 / `n/a`

## Cross-Refs
- → 00-routing.md（路由表决定本剧本是否被命中以及何时切回 03；含「我想换方向」触发概念澄清的规则）
- → 01-onboarding-new.md（帖数过少 / `list_feeds` 不可用时的降级路径；本剧本 Concept Clarification 段复用 01 的触发词清单 + 大白话重述表）
- → 03-daily-flow.md（流程结束后默认入口）
- → 05-review.md（夜间复盘只看 `source='shuling'` 的纪律来源）
- → 06-learning-loop.md（偏好 bootstrap 公式来源 + `sample_factor` 封顶处理）
- → 08-compliance.md（schema 校验细则、Concept Precheck Rule Validation、Business Profile Validation）
- → 09-troubleshooting.md（任何步骤失败；含 audit report 反推失败、replacement_risk 证据不足等故障行）
- → `agent/schemas/business-profile.schema.json`（Business Profile Inference 写盘字段契约权威）
- → `agent/schemas/creator-behavior-signal.schema.json`（Behavior Signal Initial Scan 写表 JSON 字段契约权威）
- → `agent/schemas/benchmark.schema.json`（Benchmark Gap Analysis 写盘字段契约权威；与 01 共用）
- → `agent/knowledge-base/benchmarks/index.md`（差距分析涉及的对标 dossier 索引）
- → `agent/scripts/audit-report.sh`（业务画像推测、商业模式轻量测试等段的报告生成器；本 wave 不增强，差距分析由 AI 追加到 audit-*.md）
- → `agent/knowledge-base/creator-behavior-signals.md`（人类可读节段格式参考）
- → `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.1 / §5.2 / §5.7 / §5.9（业务画像反推、商业模式 7 测试、对标 dossier、行为信号、概念澄清的设计权威）
