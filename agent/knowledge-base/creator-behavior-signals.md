# Creator Behavior Signals

> 本文件由 `agent/playbook/04-publish-flow.md`（草稿不发布时）/ `05-review.md`（连续不复盘时）/ `02-onboarding-existing.md`（老博主历史反推时）自动追加，**不要手工编辑**。
>
> 写入原则：**只描述可观察的行为事件 + 给出下一步最小动作**。
>
> - 不允许出现「你在逃避 / 你不够自律 / 你害怕失败」这类心理诊断或人格评价。
> - 不允许把执行摩擦写成用户缺点。
> - 仅引用可统计的事件：草稿次数 / 拒稿次数 / 方向变更次数 / 对标请求次数 / 跳过发布次数 / 忽略复盘次数。
>
> 详见 `agent/schemas/creator-behavior-signal.schema.json` 与 `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.7 / §9.5。

## 示范条目（safe to delete on first user write）

## behavior_20260428_draft_no_publish

- signal_type: draft_no_publish
- severity: warn
- window: 7d
- evidence:
  - draft_generated: 4
  - publish_skipped: 4
  - draft_rejected: 0
- interpretation:
  过去 7 天生成 4 条草稿，0 条进入发布确认。当前问题更像发布前摩擦，不是选题不足。
- next_small_action:
  从现有 4 条草稿中选风险最低的 1 条，小修标题和开头后发布。今天不再继续生成新方案。
- cooldown_until: 2026-05-05
- created_at: 2026-04-28
