---
id: 07-comment-insights
title: Comment Insights
when:
  - "复盘流程触发评论提炼"
  - "用户说'看看评论'"
needs:
  db_tables:
    - comment_insights
    - posts
    - content_assets
  optional:
    - agent/knowledge-base/business-profile.json
    - agent/knowledge-base/asset-ledger.md
  fallback:
    business-profile.json: 评论提炼仍输出 9 类信号,但 evidence weight 不与 primary_goal 联动
    asset-ledger.md: audience_language / faq / objection / offer_signal 只写 content_assets 表,不追加 markdown
calls:
  scripts:
    - agent/scripts/db.sh
    - agent/scripts/external-intel.sh
writes:
  files:
    - agent/data/xhs.db (comment_insights, content_assets)
    - agent/knowledge-base/asset-ledger.md
preconditions: []
on_failure:
  - 09-troubleshooting.md
version: 3.2.0
last_updated: 2026-04-28
---

# 07 Comment Insights

> **v3.1 边界**：本 playbook **只读评论 + 输出回复建议**，**不**自动调用 `xhs.sh comment`。评论是 privileged mutation（默认禁用），见 `docs/adr/0003-account-execution-boundary.md` §D5。

## Comment Action Boundary

- 默认行为：拉评论原文 → AI 提炼信号 → 写 `comment_insights` 表 → 输出回复建议给用户。
- **不**自动 `xhs.sh comment`。即使用户说"帮我回 XX"，也要先：
  1. 确认 `agent/config/account-safety.json` 中 `commenting_enabled=true`（默认 false）。
  2. 确认 `SHULING_ENABLE_COMMENT=1`（环境变量解除全面禁用）。
  3. 走 approval flow：`approval.sh request comment <note_id>:<回复内容>` → 用户 grant → `xhs.sh comment <note_id> "<内容>" --approval-id <id>`。
  4. 任一前置不满足 → 只输出回复建议文本，不发出。
- comment 失败 1 次即进 cooldown 30min（见 §7.4 cooldown 规则）；保守起见，本 playbook 默认根本不触发 comment。

## Comment Read Boundary（v3.1+）

- **评论读取必须低频**：日预算遵循 `agent/policies/external-intelligence.default.json` 的 `daily_budget.fetch_comments`（默认 5）+ `per_session_budget.fetch_comments`（默认 2）。
- **不直接调 `fetch-comments.sh`**：所有评论需求提炼必须走 `bash agent/scripts/external-intel.sh comment-demand <note_id> --limit 30`（verify 41 强制）。
  - external-intel.sh 内部仍调 `xhs.sh detail`，继承节流 / 限额 / 风险关键词识别
  - 命中风险信号即写 `account-safety-state.last_risk_event` + 进 cooldown
- **输出仅含**需求信号 + 回复建议，**禁存评论原文**：external-signal.schema.json 硬禁 `raw_comments / full_comments`（verify 42 强制）。
- 复盘流程的「评论需求转 external signal」边界详见 → `agent/playbook/05-review.md` Comment Demands 段 + → `docs/runbooks/external-intelligence.md` §6。

## Trigger

- 复盘流程触发评论提炼（由 05-review 调用）
- 用户主动说"看看评论" / "最近评论里大家在说什么"

## Read This When

每日复盘的第 3 步（评论原文阅读 + 提炼），或用户临时想了解某条/最近发布帖的评论反馈。

## Inputs

- `posts.note_id`（要拉评论的目标帖）
- `comment_insights` 表（已存评论缓存，用于降级）

## Procedure

v3.2 评论提炼从 3 类扩展为 **9 类业务维度**（plan §7.9）。评论统一走 `external-intel.sh`，不直调 `fetch-comments.sh`。

1. **拉评论需求摘要**

   ```bash
   bash agent/scripts/external-intel.sh comment-demand <note_id> --limit 30
   ```

   内部走 `xhs.sh detail`，继承节流/限额/风险关键词识别。输出结构化 `comment_demands` 摘要 + note_id 引用 + confidence。

2. **AI 在结构化摘要上分 9 类业务维度**（plan §7.9）：

   | 维度 | 信号举例 | 下游消费 |
   |---|---|---|
   | `purchase_intent` 购买意图 | "在哪买"「多少钱」「有链接吗」 | 直接进 `lead_signal=high` 候选；写 asset `offer_signal` |
   | `consultation_intent` 咨询意图 | "能不能私信"「能不能咨询」「能帮我看看吗」 | 进 `lead_signal=medium`；写 asset `offer_signal` |
   | `template_request` 求链接/求模板 | "求模板"「我也想要这个」「文档发我」 | 写 asset `offer_signal`；触发 03 系列考虑 |
   | `trust_boost` 信任增强 | "讲得真懂"「跟着学了 3 个月」「关注了」 | 写 asset `case` / `audience_language`（如带具体故事） |
   | `trust_damage` 信任损伤 | "广告吧"「割韭菜」「车轱辘话」 | 写 asset `objection`；触发 business-anti-pattern 候选 |
   | `controversy_misread` 争议/误解 | "你这是误导"「我做了反而效果差」 | 进 `controversy_signal`；不立刻写 asset，留 24h 观察 |
   | `audience_phrase_asset` 用户原话资产 | 用户描述痛点的具体原话 | 写 asset `audience_language` |
   | `frequent_objection` 高频反对意见 | "就是道理懂可是做不到"「时间不够」 | 写 asset `objection` |
   | `latent_product_demand` 潜在产品需求 | "你应该出个课"「能不能做陪跑」 | 写 asset `offer_signal`；提示更新 business-profile.offer |

3. **把提炼结果写入 `comment_insights` 表**（每条带 `note_id` + `insight_type` + `text` + `count`）；**不写评论原文**（schema 硬禁 `raw_comments`，verify 42 强制）

   v3.2 MVP 保留 `comment_insights` 现有结构粗糙性（plan §7.9 末段）：业务维度信号塞进 `content_requests` JSON 字段。完整版本可未来新增 `comment_business_signals` 表，但 v3.2 暂不强制。

4. **强业务信号 → asset-ledger 沉淀**（plan §7.9 末段）

   下列 4 类信号必须**同步**写入 asset-ledger（DB + MD 双轨；契约 → `agent/playbook/05-review.md` Asset Ledger Update / `agent/schemas/content-asset.schema.json`）：

   | 评论信号 | 资产类型 | 触发条件 |
   |---|---|---|
   | 评论原话准确描述痛点 | `audience_language` | 同一表述被 ≥ 2 条评论使用 |
   | 高频问题（同类问题 ≥ 3 次） | `faq` | 同 faq 类问题被 ≥ 3 人问 |
   | 购买犹豫 / 反对意见 | `objection` | 同一反对理由被 ≥ 2 人提出 |
   | 索要模板/服务/产品 | `offer_signal` | 任意一次明确索要（强信号） |

   **强业务信号 → business_reviews.evidence 输入（v3.2 Stage 11，plan §5.6.2）**：

   `purchase_intent` / `consultation_intent` / `template_request` / `latent_product_demand` 这 4 类**强业务信号**，在写入 asset-ledger 的同时，也作为 05-review.md `Business Attribution Review` 的 `evidence[]` 数组输入。每条命中评论必须按 `business-review.schema.json` 的 evidence 子结构写入：

   ```json
   {
     "type": "comment",
     "source": "comment_insights:<note_id>:<insight_type>",
     "weight": "high|medium|low",
     "excerpt": "评论原话片段（≤ 50 字，不存评论原文长串）"
   }
   ```

   `weight` 分级（plan §5.6.2 末段 + 7.9 末段）：

   - `weight=high`：购买/咨询入口出现 ≥ 1 次明确原话（如「在哪买 / 多少钱 / 能不能私信咨询 / 模板发我」）
   - `weight=medium`：同类强业务信号被 ≥ 2 人提出但**用词暧昧**（如「这个看起来不错 / 想要这种」）
   - `weight=low`：仅 LLM 推断（无明确原话，如对评论语气分析得到「可能想咨询」）

   **没有 `weight ∈ {high, medium}` 的 comment evidence + 没有 `metrics` evidence ⇒ 05-review.md 写入 `sales_signal/lead_signal=high` 会被 schema description 硬规则拒绝**。本节负责**生产可信 evidence**，让 05 归因有抓手。

   **写入 comment_insights.content_requests 时**：除了原有 9 类业务维度，**强业务信号 4 类**还要把上面这个 evidence 子对象塞进去（JSON 字段，便于 05 直接读取）。

   写入示例（详细字段约束见 → 05-review.md Asset Ledger Update）：

   ```bash
   bash agent/scripts/db.sh add-content-asset '{
     "id": "asset_20260428_offer_signal_template_request",
     "asset_type": "offer_signal",
     "source": {"post_id": 456, "comment_id": "c789", "benchmark_id": "", "manual_note": "评论求模板"},
     "content": "能不能发个模板我照着写",
     "why_it_matters": "明确表达索要内容，可作为 offer 假设的轻验证信号",
     "reuse_plan": "更新 business-profile.offer.description；下次相关选题加「模板可索取」CTA",
     "confidence": "medium",
     "created_at": "2026-04-28"
   }'
   ```

5. **把潜在选题信号回报给 03-daily-flow.md**（作为下一轮选题候选）

## Writes

- `comment_insights` 表（每帖多行：9 类业务维度信号）
- `content_assets` 表 + `asset-ledger.md`（强业务信号沉淀）

## Failure Handling

- `external-intel.sh comment-demand` 节流触顶（429 / quota）或预算耗尽：降级到只读 `comment_insights` 已存数据，不阻塞复盘流程
- `external-intel.sh comment-demand` 退出 30 / 31（cooldown / 风险信号）：转 → `09-troubleshooting.md` Account Safety Matrix
- 拉到空评论：直接返回，不写入

## Anti-Patterns

- v3.0 不引入新评论分析逻辑（保持极简，给 v3.1 扩展位）
- v3.2+ 不存评论原文（schema 硬禁 `raw_comments`）
- v3.2+ 强业务信号必须同步写 asset-ledger，不能只塞进 `comment_insights.content_requests`
- v3.2+ `controversy_misread` 24h 内不写 asset（避免一时情绪噪音变成长期资产）
- v3.2+ asset 写入失败不阻塞 comment_insights 写入（degraded mode）

## Cross-Refs

- 被 05-review.md 引用
- → 03-daily-flow.md（评论选题信号回到选题候选；audience_language 资产用于开头/封面措辞）
- → 05-review.md（Asset Ledger Update 段是 asset 写入的契约权威）
- → 08-compliance.md（asset 写入前 schema 校验；外部信号存储边界）
- → 09-troubleshooting.md
- → `agent/schemas/content-asset.schema.json`
- → `agent/schemas/external-signal.schema.json`
- → `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.8 / §7.9（设计来源）
