---
id: 06-learning-loop
title: Self-Evolution Learning Loop
when:
  - "用户做出选题/草稿选择"
  - "复盘后触发权重更新"
  - "imported posts 偏好 bootstrap"
needs:
  required:
    - agent/knowledge-base/preferences.json
    - agent/schemas/preferences.schema.json
  db_tables:
    - user_choices
    - posts
    - post_metrics
calls:
  scripts:
    - agent/scripts/db.sh
writes:
  files:
    - agent/knowledge-base/preferences.json
    - agent/knowledge-base/evolution-log.md
preconditions: []
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
authority: formulas
---

# 06 Self-Evolution Learning Loop

> ⚠ **公式权威来源**：本文件是 weight / confidence / ε-greedy / consecutive_rejects 的**唯一**定义。
> 其他 playbook 引用必须 cross-ref，禁止复述公式。

## Trigger

- 每次用户做出选题/草稿选择（"发"或"换"）
- 每日复盘流程结束后（由 05-review 触发权重更新）
- 老博主接入流程（02-creator-onboarding §0c）做"偏好 bootstrap"

## Read This When

需要更新 `preferences.json` 中的 weight / confidence_level / consecutive_rejects 时；需要决定下一轮推几个选题/草稿时；任何触及"信心度"或"探索保底"行为时。

## Inputs

- `agent/knowledge-base/preferences.json`（当前 weight / confidence_level / total_choices / last_exploration_at / consecutive_rejects）
- `user_choices` 表（历史选择 log）
- 复盘环节传入的"收藏率信号"（来自 05-review）

## Procedure

设计目标：小样本不冒进、口味稳时快收敛、口味飘时能回头、永远留一条探索通道。

每次用户做选择时执行如下：

1. 读取 `preferences.json`
2. 被选中的选项 → 对应类型 `chosen + 1`
3. 被跳过的选项 → 对应类型 `skipped + 1`
4. 追加一条 `choice_log`：`{date: "YYYY-MM-DD", dimension: "topic|style|title_pattern", chosen: "X", skipped: ["Y","Z"]}`
5. 计算每类型的 weight（见下文公式）
6. 计算整体 confidence_level（见下文公式）
7. 写回 `preferences.json`，同步更新 `updated_at` 与 `total_choices`

### Bayesian-Laplace Weight Formula

逐类型权重，Laplace 贝叶斯平滑，避免小样本直接判定：

```
weight = (chosen + 1) / (chosen + skipped + 2)
```

校验数值：

- 0 选 0 跳 → 0.50（中立先验）
- 2 选 0 跳 → 0.75（样本少自动保守，而不是裸 1.0）
- 10 选 0 跳 → 0.92
- 2 选 3 跳 → 0.43

### Confidence Level

整体信心度：基于分布集中度 × 样本因子。

```
top1 = 最高 weight 的类型
top2 = 第二高 weight 的类型（若只有 1 个类型则 top2 = 0）
concentration = (weight_top1 + weight_top2) / Σ weight_all
sample_factor = min(total_choices / 10, 1.0)
confidence_level = round(concentration × sample_factor, 2)
```

**严正提示**：这里是 **concentration × sample_factor**，**不要** 用 `chosen/(chosen+skipped)` 再算一遍——那是 **weight 的公式**，与 confidence 不是同一维度。混用会导致 N 选 M 永远触不到阈值、收敛机制失效。此处专门列出是因为高水平 agents 实测会踩这个坑。

可选时间衰减（降低口味漂移反应延迟）：计算 weight 前，对 `choice_log` 里 30 天前的记录，每超出 14 天对应的 chosen/skipped 贡献乘 0.5。若嫌麻烦可先跳过，30 帖子内影响有限。

数值示例（对照校验实现正确）：

| 场景（topic 维度：ai_tools / coding / news） | weight_ai_tools | weight_coding | weight_news | confidence_level |
|---|---|---|---|---|
| 初始（0/0, 0/0, 0/0） | 0.50 | 0.50 | 0.50 | 0.00（sample=0） |
| 3 次全选 ai_tools | 0.80 | 0.20 | 0.20 | 0.25（concentration 0.83 × 0.3） |
| 10 次全选 ai_tools | 0.92 | 0.08 | 0.08 | 0.92 |
| 10 次：6 ai_tools + 4 coding | 0.58 | 0.42 | 0.08 | 0.92（top1+top2 集中度高） |
| 10 次：3 / 3 / 4 平均分给 3 类 | 0.33 | 0.33 | 0.42 | 0.69（分散→低信心） |

任何实现如果算出和上表偏差 > 0.03，先回头核对公式，不要上线。

### ε-greedy Exploration (≥7 days)

选项递减 + 探索保底：

```
if confidence_level ≥ 0.75:
    基础：推 1 个选题 + 1 份草稿（"发/换"）
    若距 last_exploration_at ≥ 7 天（或为 null）:
        额外追加 1 个"探索项"（从 weight < 0.3 且最近 14 天未推过的类型里抽）
        → 推 2 个：1 主推 + 1 探索；更新 last_exploration_at = 今天
elif confidence_level ≥ 0.5:
    推 2 个选题 + 1 份草稿（附备选标题）
else:
    推 3 个选题 + 2 份草稿
```

### consecutive_rejects Rebound

用户"换"信号处理：

```
每次"换":
    consecutive_rejects += 1
    confidence_level -= 0.10    # 原 0.05 太温柔，回弹慢
    本次临时扩展选项（+2 个选题或 +1 份草稿）

if consecutive_rejects ≥ 2:
    confidence_level = min(confidence_level, 0.45)   # 强制回到 3 选档
    consecutive_rejects = 0
    在下次日报里提醒用户："连续两次没选中，已帮你展开候选范围"

每次用户"发"（正常采纳）:
    consecutive_rejects = 0
```

### Pattern Lifecycle

复盘环节由 05-review 喂入收藏率信号，本文件负责把信号映射成 weight 调整与 pattern 流转：

- **收藏率 ≥ 5%** → 表现优秀
  - 该帖标题模式提炼到 `patterns.md`（confidence: experimental）
  - 对应 topic_type / content_style 的 `weight + 0.1`（上限 1.0）
- **收藏率 2-5%** → 表现正常，不做调整
- **收藏率 < 2%** → 表现较差
  - 对应 weight `- 0.1`（下限 0.0）
  - 同类型连续 3 次 < 2% → 移入 `anti-patterns.md`

晋级/降级判定：

- 已存在 pattern 连续 3 次以上收藏率 ≥ 5% → confidence 升级（experimental → medium → high）
- 已存在 pattern 连续 3 次 < 2% → 移到 `anti-patterns.md`
- `patterns.md` 活跃 ≤ 15 条，超出时淘汰 confidence 最低的

### 偏好 Bootstrap（imported posts 接入）

老博主接入（§0c）时，对每条分类后的 imported post 自动写一条"隐式选择"：

- `choice_type` = `topic` / `title_pattern` / `content_style` 三次
- 虚拟 `offered_count = 3`，`chosen_label = <本帖的分类值>`，`skipped_labels = ["__implicit_unknown__", "__implicit_unknown__"]`
- 通过 `bash agent/scripts/db.sh log-choice '<json>'` 写入 `user_choices` 表
- `preferences.json` 由本文件常规逻辑从 `user_choices` 聚合，**强制 total_choices 封顶 50**（避免 170 条历史让 sample_factor 直接 = 1.0 → 立即进 1 选档；预留后续真实用户选择的学习空间）

## Writes

- `agent/knowledge-base/preferences.json`（weight / confidence_level / total_choices / last_exploration_at / consecutive_rejects / choice_log）
- `agent/knowledge-base/evolution-log.md`（追加一段：日期 / 改了什么 / 为什么改 / 数据依据）
- `user_choices` 表（仅 bootstrap 路径）

## Failure Handling

- `preferences.json` 缺失或 schema 不匹配：按 `agent/schemas/preferences.schema.json` 重建中立先验，不阻断主流程
- 计算结果偏离上表 > 0.03：停止写回，回到公式核对，不要上线错误数值
- bootstrap 写入失败：跳过该单条记录，不让 1 条脏数据中断 199 条好数据

## Anti-Patterns

- weight 和 confidence 不能混用（前者类型级，后者整体分布）
- consecutive_rejects ≥2 时强制 confidence=0.45（不允许中间反弹）
- 时间衰减可选但 30 帖子内影响有限（不要悄悄删）

## Cross-Refs

- 被 03 / 04 / 05 / 02 引用
