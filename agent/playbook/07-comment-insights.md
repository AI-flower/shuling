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
calls:
  scripts:
    - agent/scripts/db.sh
    - agent/scripts/external-intel.sh
writes:
  files:
    - agent/data/xhs.db (comment_insights)
preconditions: []
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
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

v3.1 极简骨架（评论统一走 `external-intel.sh`，不直调 `fetch-comments.sh`）：

1. 调 `bash agent/scripts/external-intel.sh comment-demand <note_id> --limit 30` 提炼评论需求（内部走 `xhs.sh detail`，继承节流/限额/风险关键词识别）
2. external-intel.sh 输出已是结构化 `comment_demands` 摘要 + note_id 引用 + confidence；AI 在此基础上再分桶：
   - 高频提问（"怎么安装 X"、"在哪买"）
   - 高频吐槽（"封面太花"、"步骤跳了"）
   - 用户内容需求信号（"能不能出一期 Y"）
3. 把提炼结果写入 `comment_insights` 表（每条带 `note_id` + `insight_type` + `text` + `count`）；**不写评论原文**（schema 硬禁 `raw_comments`，verify 42 强制）
4. 把发现的潜在选题信号回报给 03-content-creation（作为下一轮选题候选）

## Writes

- `comment_insights` 表（每帖多行：高频提问 / 吐槽 / 选题信号）

## Failure Handling

- `external-intel.sh comment-demand` 节流触顶（429 / quota）或预算耗尽：降级到只读 `comment_insights` 已存数据，不阻塞复盘流程
- `external-intel.sh comment-demand` 退出 30 / 31（cooldown / 风险信号）：转 → `09-troubleshooting.md` Account Safety Matrix
- 拉到空评论：直接返回，不写入

## Anti-Patterns

- v3.0 不引入新评论分析逻辑（保持极简，给 v3.1 扩展位）

## Cross-Refs

- 被 05-review.md 引用
- → 09-troubleshooting.md
