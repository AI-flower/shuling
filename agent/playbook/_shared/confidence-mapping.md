# Confidence 决策档映射（v3.0 _shared 资源）

> 被 03-daily-flow.md（选题/草稿份数）/ 04-publish-flow.md（重试）/ 05-review.md / 06-learning-loop.md 共享。
>
> ⚠ 公式权威定义见 06-learning-loop.md。本文件仅给"决策档 → 输出份数"的映射表。

## 决策档表

| confidence_level 区间 | 选题数量 | 草稿份数 | 备注 |
|---|---|---|---|
| `< 0.5` | 3 个选题 | 2 份不同风格的大纲+文案 | 低信心，多探索 |
| `0.5 ≤ x < 0.75` | 2 个选题 | 1 份大纲 + 1 份文案 + 1 个备选标题 | 中等信心，收敛中 |
| `≥ 0.75` | 基础 1 个（最佳） | 1 份大纲+文案（"发/换"二选一） | 高信心，节省用户决策 |

## ε-greedy 探索追加

- 当 `confidence_level ≥ 0.75` 且距 `last_exploration_at` ≥ 7 天（或为 `null`）：
  - 额外追加 1 个"探索项"（从 `weight < 0.3` 且最近 14 天未推过的类型里抽）
  - 推 2 个：1 主推 + 1 探索；更新 `last_exploration_at = 今天`

## consecutive_rejects 触发规则

- `consecutive_rejects ≥ 1` → 本次草稿强制出 2 份，给用户二选一余地
- `consecutive_rejects ≥ 2` → 选题强制回退到 3 个候选；同时 `confidence_level = min(confidence_level, 0.45)` 强制回到 3 选档；`consecutive_rejects` 重置为 0；下次日报里提醒用户"已展开候选范围"
- 用户正常"发"采纳一次 → `consecutive_rejects = 0`
