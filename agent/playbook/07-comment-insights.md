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
    - agent/scripts/fetch-comments.sh
    - agent/scripts/db.sh
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

## Trigger

- 复盘流程触发评论提炼（由 05-review 调用）
- 用户主动说"看看评论" / "最近评论里大家在说什么"

## Read This When

每日复盘的第 3 步（评论原文阅读 + 提炼），或用户临时想了解某条/最近发布帖的评论反馈。

## Inputs

- `posts.note_id`（要拉评论的目标帖）
- `comment_insights` 表（已存评论缓存，用于降级）

## Procedure

v3.0 极简骨架（v3.1 留独立扩展位）：

1. 调 `bash agent/scripts/fetch-comments.sh <note_id> --limit 30` 拉评论（脚本已过滤垃圾评论）
2. AI 自己读评论原文，提炼：
   - 高频提问（"怎么安装 X"、"在哪买"）
   - 高频吐槽（"封面太花"、"步骤跳了"）
   - 用户内容需求信号（"能不能出一期 Y"）
3. 把提炼结果写入 `comment_insights` 表（每条带 `note_id` + `insight_type` + `text` + `count`）
4. 把发现的潜在选题信号回报给 03-content-creation（作为下一轮选题候选）

## Writes

- `comment_insights` 表（每帖多行：高频提问 / 吐槽 / 选题信号）

## Failure Handling

- `fetch-comments.sh` 节流触顶（429 / quota）：降级到只读 `comment_insights` 已存数据，不阻塞复盘流程
- 拉到空评论：直接返回，不写入

## Anti-Patterns

- v3.0 不引入新评论分析逻辑（保持极简，给 v3.1 扩展位）

## Cross-Refs

- 被 05-review.md 引用
- → 09-troubleshooting.md
