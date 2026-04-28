# Business Patterns

> 本文件由 `agent/playbook/05-review.md` 自动追加，**不要手工编辑**。
>
> 业务 pattern = 在多次复盘中证明能带来真实业务信号（私信 / 询价 / 关注 / 购买等）的内容策略。
> 仅当 `business_reviews` 表中本 pattern 的支撑证据 `evidence_level ∈ {hard, medium}` 时，才允许从 `experimental` 晋升为 `validated`。
>
> 详见 `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.6 / §9.3。

## 示范条目（safe to delete on first user write）

## high-intent-tutorial

- confidence: experimental
- source: shuling_review
- evidence:
  - post_id: 0
  - signal: lead_signal=high
  - evidence_level: medium
- applies_when:
  - primary_goal=get_leads
  - offer_status=selling
- rule:
  用户已经有明确需求时，教程内容应给出下一步行动入口（私信关键词 / 报名链接），而不是只做收藏型清单。
- counter_example:
  同主题的纯清单贴收藏率高但 lead_signal=low，归为 anti-pattern。
