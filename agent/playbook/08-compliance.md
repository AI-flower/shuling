---
id: 08-compliance
title: Content Compliance
when:
  - "草稿生成前后规则检查"
  - "发布前 QA 闸门"
  - "schema 写入前校验"
needs:
  required:
    - agent/policies/content-rules.md
    - agent/schemas/state.schema.json
    - agent/schemas/profile.schema.json
    - agent/schemas/business-profile.schema.json
    - agent/schemas/preferences.schema.json
    - agent/schemas/audit-report.schema.json
    - agent/schemas/creator-behavior-signal.schema.json
    - agent/schemas/draft-diagnosis.schema.json
    - agent/schemas/title-formula.schema.json
    - agent/schemas/content-asset.schema.json
    - agent/schemas/business-review.schema.json
    - agent/schemas/benchmark.schema.json
calls:
  scripts:
    - agent/scripts/validate.py
writes:
  files: []
preconditions: []
on_failure:
  - 09-troubleshooting.md
version: 3.2.0
last_updated: 2026-04-28
---

# 08 Content Compliance

## Trigger

- 03-daily-flow.md 草稿生成前/后（草稿期硬约束）
- 04-publish-flow.md 调 `xhs.sh publish` 前（发布期 QA 闸门）
- 任何写入 `agent/config/state.json` / `agent/knowledge-base/profile.json` / `agent/knowledge-base/preferences.json` / `agent/knowledge-base/audit-*.json` 之前（schema 校验）
- 01/02 写画像或偏好初值之前

## Read This When

- 任何 playbook 即将向 JSON 文件落盘前必读本节 Schema Validation
- 03 生成大纲/正文/标签之前必读 Draft Time Rules
- 04 调 publish 之前必读 Publish Time Rules
- 06 写 patterns.md / anti-patterns.md 时按 schema-degraded mode 兜底（见 09-troubleshooting.md）

## Inputs

- 待校验的 JSON 文件路径（state / profile / preferences / audit-report）
- 当前草稿对象（titles / copywriting / tags / outline）
- 待发布的 meta.json（标题、正文、标签、图片路径数组）

## Procedure

### Schema Validation

**写入前必校验**：每次写入 `agent/config/state.json` / `agent/knowledge-base/profile.json` / `agent/knowledge-base/preferences.json` 之前，先读对应 JSON Schema，确保字段名、类型、枚举值符合约定：

| 目标文件 | Schema |
|---|---|
| `agent/config/state.json` | `agent/schemas/state.schema.json` |
| `agent/knowledge-base/profile.json` | `agent/schemas/profile.schema.json` |
| `agent/knowledge-base/business-profile.json` | `agent/schemas/business-profile.schema.json` |
| `agent/knowledge-base/preferences.json` | `agent/schemas/preferences.schema.json` |
| `agent/knowledge-base/audit-*.json` | `agent/schemas/audit-report.schema.json` |
| `agent/knowledge-base/title-formulas.json[]` | `agent/schemas/title-formula.schema.json` |
| `agent/data/xhs.db::creator_behavior_signals.signal_json` | `agent/schemas/creator-behavior-signal.schema.json` |
| `agent/data/xhs.db::content_assets.asset_json` | `agent/schemas/content-asset.schema.json` |
| `agent/data/xhs.db::business_reviews.review_json` | `agent/schemas/business-review.schema.json` |
| draft-diagnosis 对象（playbook 内部，不强制落盘） | `agent/schemas/draft-diagnosis.schema.json` |
| benchmark dossier `agent/knowledge-base/benchmarks/*.json` | `agent/schemas/benchmark.schema.json` |

**关键纪律**：

- **日期字段一律 `YYYY-MM-DD`**（如 `created_at / updated_at / setup_date`），不要用 `createdAt`、ISO 时间戳或本地化格式
- **必填字段不得缺**：`profile.json` 必须有 `niche / audience / tone / created_at`；`preferences.json` 必须有 `dimensions / total_choices / confidence_level / updated_at`
- **`weight` 值范围 `[0.0, 1.0]`**；越界先回查公式权威定义再写（cross-ref → [`06-learning-loop.md` Bayesian-Laplace Weight Formula](06-learning-loop.md#bayesian-laplace-weight-formula)）
- **`confidence_level` 不是 weight**，两者算法不同；详细公式权威见 [`06-learning-loop.md` Confidence Level](06-learning-loop.md#confidence-level)
- **`dimension` 只能是 `topic` / `style` / `title_pattern`**，别造新维度；要加维度走 BRAIN 版本号并更新 schema

可选验证命令（环境有 `jsonschema` 包时）：

```bash
python3 -m jsonschema -i agent/knowledge-base/profile.json agent/schemas/profile.schema.json
python3 -m jsonschema -i agent/knowledge-base/business-profile.json agent/schemas/business-profile.schema.json
```

### Concept Precheck Rule Validation（v3.2+）

> 触发位置：`01-onboarding-new.md` 的 Profile Building 第 4 步即将写盘前 / `02-onboarding-existing.md` 的 Concept Clarification 段。详见 plan §5.9。

**触发词清单**（onboarding 中如果用户原话出现下列任一词，**即命中本规则**）：

```text
IP / 个人品牌 / 人设
私域 / 社群 / 流量池
精准流量 / 精准获客
赛道 / 风口 / 红利
知识付费 / 课程 / 陪跑
变现 / 副业 / 干货
```

**校验规则**：

| 字段 | 不允许出现的原话 |
|---|---|
| `profile.json.niche` | 触发词清单任一词的原话（含「副业博主」「IP 博主」「干货号」这类直接拼接） |
| `profile.json.audience` | 「精准流量」「精准获客」「私域用户」等 |
| `profile.json.tone` | 「干货」「干货向」（不是真正的语气描述） |
| `profile.json.goals` | 「IP」「人设」「变现」「私域」「赛道」（这些是问题，不是目标） |
| `business-profile.json.primary_goal` | 触发词清单任一词的原话（必须用 schema 限定的枚举值之一：`grow_followers / build_trust / get_leads / drive_sales / prepare_live / product_research / unknown`） |
| `business-profile.json.offer.description` | 仅出现「卖知识付费」「做私域」这类未拆解的措辞 |
| `business-profile.json.buyer.description` | 「精准流量」「精准获客」类原话 |

**违反时**：

- **不写盘**（即使其他字段都合规）。
- 提示用户重述：「你说的『XXX』太宽，先不用这个词。我们用大白话拆一下：……」（具体重述参考 `01-onboarding-new.md` 的「黑话→大白话重述表」）。
- 重述后允许 `unknown`，不要为了好看强填。
- 两轮追问后仍未消解 → 允许 `unknown` 落盘，本次 onboarding 不再继续追问。

**重要**：澄清结论 **不单独写文件**（不创建 `concept-clarifications.md`、不写 `concepts/*.json`），只回填 `profile.json` / `business-profile.json` 的字段。详见 plan §5.9.6 / §9.6。

### Business Profile Validation（v3.2+）

> 触发位置：写入 `agent/knowledge-base/business-profile.json` 之前。`01-onboarding-new.md` 的 Business Profile Building 段 / `02-onboarding-existing.md` 的 Business Profile Inference 段调用前必跑本节。

**关键纪律**：

- 写前必须用 `agent/schemas/business-profile.schema.json` 校验；schema 校验失败 **不写盘**（沿用 v2.4.0 后的纪律）。
- `creator_track` 必须为 `creator_first | offer_first | exploration` 之一；其他值越界即拒写。`exploration` **不是失败状态**——是冷启动正确状态，UI / 提示文案不允许把它说成「低级」「未完成」。
- `offer_status == "none"` 时允许，**不阻塞**。`offer.name` / `offer.description` 可为空字符串，但 `offer` 对象本身必须存在；`offer.price_range` / `offer.delivery` 可填 `unknown`。
- `business_model_probe.profit_evidence_level` 缺失时默认 `unknown`，不强制下结论；`profit_evidence` 数组可为空（新博主普遍空）。
- `business_model_probe.replacement_risk` 证据不足时只能填 `unknown`，**不允许强行 high/low**（plan §5.1.5）。
- `creator_stage` 必须为 schema 枚举之一（`new / has_posts / has_followers / has_leads / has_sales / has_repeat_sales`）；新博主默认 `new`。
- `current_bottleneck` 必填；新博主默认 `unclear_concept`，老博主反推后按证据填具体瓶颈或 `unknown`。
- 日期字段（`created_at` / `updated_at`）必须 `YYYY-MM-DD`，沿用上文「关键纪律」。

**onboarding 命中触发词时**（再强调一次）：

- **不能**直接把触发词原话写入 `primary_goal` / `niche` / `offer.description` 等字段；必须先走 Concept Precheck 段大白话重述。
- 违反时按 Concept Precheck Rule Validation 拒写。

**`offer_first` 账号的下游约束**（plan §7.10）：

- `creator_track == "offer_first"` 时，03-daily-flow Topic Value Gate 中 `monetization_distance_score < 45` 的选题不能直接 `recommend`，必须降级为 `explore`。本约束在 03 实现，但 `business-profile.json` 是 03 读取的输入；本节仅校验 `creator_track` 字段合法性。

### Behavior Signal Output Validation（v3.2+）

> 触发位置：`02-onboarding-existing.md` Behavior Signal Initial Scan 段、`05-review.md` 复盘命中行为信号、`04-publish-flow.md` 草稿不发布命中等任何调用 `bash agent/scripts/db.sh add-creator-behavior-signal '<json>'` 之前。

**Schema 校验**：JSON 必须符合 `agent/schemas/creator-behavior-signal.schema.json`。

**输出原则硬约束**（plan §5.7.5）：

- `interpretation` / `next_small_action` **不允许出现以下词或同义改写**：
  - 「逃避」「自卑」「不想赚钱」「拖延症」「心理咨询」「人格」「性格缺陷」
  - 「不够自律」「害怕失败」「躺平」「内耗」「精神内耗」
  - 任何把执行摩擦说成用户人格 / 心理 / 道德缺陷的措辞
- 仅允许引用可统计事件：`draft_generated` / `draft_rejected` / `direction_changed` / `benchmark_requested` / `publish_skipped` / `review_ignored`。
- `next_small_action` 必须是「**当天可完成的具体动作**」，不能是「再想想」「再准备一下」这类空头建议。
- 违反时 **不写表 / 不写 .md**；返回结构化错误给调用方，由调用方重写。

### Draft Diagnosis Schema Validation（v3.2+）

> 触发位置：`03-daily-flow.md` §2.2.5 Draft Diagnosis 输出 JSON 之前 / 任何写入或传递 `draft-diagnosis` 对象的位置。详见 plan §5.5.3。

**Schema 校验**：JSON 必须符合 `agent/schemas/draft-diagnosis.schema.json`（结构权威）。

**v3.2 关键纪律**（plan §5.5.3）：

- **没有 `evidence` 的维度，`confidence` 不得 > `low`**——dimension 对象 `evidence: []` 时 `confidence` 必须为 `"low"`（schema 校验失败 → **拒写**）
- **`business_alignment` 必须引用 `business-profile.json.primary_goal` 或 `conversion_path.next_step`**——`evidence` 数组中若无任一对应字符串引用 → **拒写**
- **`human_signal` 必须参考 `profile.json` 用户历史风格**——`evidence` 中必须能追溯到 `profile.json` 字段名 / tone / niche 引用，不能只写「真人感」之类通用模板
- **`fix_priority="high"` 项数 ≥ 1**——除非 `decision="pass"` 否则至少 1 项 high；`decision != "pass"` 但全部 high=0 → **拒写**
- **写入前**：`draft-diagnosis` 不强制落盘（plan §5.5.5 — playbook 内部使用），但**校验同样必跑**
- **`ai_fingerprint_hits[].type` 必须是 enum 内 10 类之一**（uniform_rhythm / gnomic_endings / synonym_substitution / translation_tone / hook_pain_promise / not_x_but_y / term_stacking / smooth_emotion_curve / fake_reader_voice / empty_blessing），不要造新类型
- **`decision` 低分不硬阻塞发布**——只有命中合规风险才阻塞（合规由 Draft Time Rules 处理）

可选验证命令（环境有 `jsonschema` 包时）：

```bash
python3 -m jsonschema -i <draft-diagnosis.json> agent/schemas/draft-diagnosis.schema.json
```

### Title Formula Validation（v3.2+）

> 触发位置：`03-daily-flow.md` §2.2 第 3 步生成标题候选之后 / `04-publish-flow.md` `add-post` 入库前 / `content-qa.py` 检测项 11-12。详见 plan §5.4 / §7.10。

**v3.2 关键纪律**（plan §7.10）：

- **标题候选没 `formula_id` → 降级 `formula_id="manual"`**（**允许**，但 publish 入库前必须有 `intent`）。03 不强制每个候选都来自 24 条公式，但用户面前展示时必须能解释为什么。
- **标题候选没 `intent` → 降级 `intent="click"`**（**allowed but flagged 低置信**）。**publish 入库前**（即 `db.sh add-post` 调用前）必须显式有 `intent`，否则 → **拒写**。
- **`intent` 必须是 enum 内 7 类之一**：`click | save | comment | trust | lead | conversion | series`；越界即拒写。
- **`intent` 与 `business-profile.primary_goal` 的优先级匹配**（plan §5.4.4）：
  - `primary_goal=grow_followers` → 主推标题 `intent` 应为 `click` / `save`
  - `primary_goal=build_trust` → 主推标题 `intent` 应为 `trust` / `series`
  - `primary_goal=get_leads` → 主推标题 `intent` 应为 `lead` / `comment`，但**禁止过度承诺**（绝对化词、保证类承诺命中 Draft Time Rules 即拒）
  - `primary_goal=drive_sales` → 主推标题 `intent` 可为 `conversion`，但必须经合规 + 真实供给检查
- **同一 `formula_id` 在最近 N 条内连续出现** → `content-qa.py` 检测项 11 触发 `warn`（不是 hard fail，但提示用户/agent 换公式）
- **同一 `title_trigger` 在最近 N 条内连续出现** → `content-qa.py` 检测项 12 触发 `warn`，提示「账号可能正在模板化」
- **N 阈值**：来自 `agent/knowledge-base/title-formulas.json[].constraints.cooldown_posts`（多数为 3-4）。`content-qa.py` 默认按 N=3（formula）/ N=4（trigger）作为兜底。
- **新增公式时必须先扩 `title-formulas.json` + 通过 schema 校验**（`agent/schemas/title-formula.schema.json`），不允许 03 playbook 临时造公式名。

可选验证命令：

```bash
python3 -m jsonschema -i <one-formula.json> agent/schemas/title-formula.schema.json
python3 agent/scripts/content-qa.py --draft /tmp/xhs-post/meta.json --json | jq '.warnings[] | select(.check | startswith("title_formula"))'
```

### Draft Time Rules（草稿期硬约束）

**生成草稿前必读** `agent/policies/content-rules.md`。以下是核心规则：

**绝对禁止**：

- 不提及任何平台名或导流信息
- 不提及区块链/虚拟货币/Web3/NFT
- 不写"用 AI 写小红书"类主题
- 不出现费用/价格信息
- 不加篇数编号

**格式要求**：

- 标题 ≤ 20 字
- 正文 ≤ 1000 字
- 标签 5-8 个

**写作风格**：

- 口语化、有真人感
- 适量 emoji，不过度（emoji 总量控制 cross-ref → `_shared/emoji-dictionary.md`）
- 痛点 → 解决方案 → 效果展示结构
- 不能读起来像 AI 生成

### Publish Time Rules（发布前 QA 闸门）

**标题模式**（优先使用 patterns.md 中 `confidence ≥ medium` 的）：

- 数字清单体："5 个 XX 工具"
- 反差悬念体："被吹上天，普通人到底怎么用？"
- 结果导向体："3 分钟搞定 500 行数据"
- 身份共鸣体："打工人" / "一人公司"
- 保姆级体："手把手" / "0 基础"

**质量标准**：

- 教程类必须有可操作步骤（完整命令，不能只写"安装依赖"）
- 每页 3-5 个信息点
- 不能整页只有标题无内容

### External Signal Storage Rules（v3.1+）

外部情报采样（`external-intel.sh research-topic / competition-gap / comment-demand`）写入 `agent/knowledge-base/external-signals/<hash>.json` 与可选辅助索引 `external_signals` 表时，必须遵守以下边界。**verify 第 42 条扫描，违反即 fail**。

**只允许保存**：

- `note_id`（小红书原内容引用，不是正文）
- `topic`（采样主题）/ `signal_type`（angle / pattern / comment_demand / white_space）
- `summary` / `common_angles` / `overused_patterns` / `comment_demands` / `white_space`（≤ 200 字摘要）
- `confidence`（0-1）/ `sample_size`（采样数量）
- `observed_at` / `expires_at`

**禁止保存**（schema 硬禁，写盘前必校验）：

- `full_body / body_text / content`（笔记正文）
- `raw_comments / full_comments / comments_list`（完整评论列表）
- `raw_post_body / note_body / raw_html`（任何形式原文 dump）
- `cookies / tokens / auth_*`（任何凭证字段）
- 任何超过 200 字的非 summary 字段

**写盘前必校验**：

```bash
# external-intel.sh 内部已自检；外部代码写 external-signals/*.json 也必须校验
python3 -m jsonschema -i <signal.json> agent/schemas/external-signal.schema.json
```

详细规则与 TTL 表 → `docs/runbooks/external-intelligence.md` §6 / verify 第 42 条。

## Writes

本剧本不直接写入；仅返回 `pass / fail` + 错误清单给调用方。

## Failure Handling

- Schema 校验失败 → 返回结构化错误（字段名 + 期望类型 + 实际值）给调用方，由调用方决定回退或重写
- Draft Time Rules 命中绝对禁止项 → 拒绝该草稿，要求 03 重新生成
- Publish Time Rules 命中质量问题 → 阻塞发布，回 03 修订
- 不自行修复用户文本（避免越权改写用户内容）；on_failure 跳 09-troubleshooting.md

## Anti-Patterns

- 不允许 03/04 完整复述本文件规则（仅允许 ≤15 行/≤10 行摘要 + cross-ref）
- 日期字段一律 YYYY-MM-DD
- weight 值必须在 [0.0, 1.0]
- confidence_level 不是 weight，不要混用
- dimension 只能是 topic/style/title_pattern

## Cross-Refs

被 01-onboarding-new.md / 02-onboarding-existing.md / 03-daily-flow.md / 04-publish-flow.md / 05-review.md / 06-learning-loop.md / 07-comment-insights.md 引用。

- → `_shared/emoji-dictionary.md`（emoji 总量控制基线）
- → 06-learning-loop.md（weight/confidence 公式权威）
- → 09-troubleshooting.md（schema 校验失败兜底；含 v3.2 故障矩阵）
- → `docs/runbooks/external-intelligence.md`（外部信号存储边界 + 风险分层 + 失败降级）
- → `agent/schemas/external-signal.schema.json`（external signal 字段契约 + 硬禁字段）
- → `agent/schemas/business-profile.schema.json`（v3.2 Business Profile Validation 字段契约权威）
- → `agent/schemas/creator-behavior-signal.schema.json`（v3.2 行为信号字段契约权威）
- → `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.1 / §5.7 / §5.9 / §7.10（业务画像 / 行为信号 / 概念澄清的 compliance 设计来源）
