# agent/schemas/ 数据契约文档（v3.0+）

> 静态契约，不进任何 playbook。Playbook 通过 cross-ref 引用。

## agent/knowledge-base/ 文件

| 文件 | 用途 | 更新时机 |
|------|------|---------|
| `agent/knowledge-base/profile.json` | 博主画像（领域/受众/风格） | 首次使用时创建（01）/ 老博主反推（02） |
| `agent/knowledge-base/preferences.json` | 用户偏好（自动学习） | 每次用户选择时（06） |
| `agent/knowledge-base/patterns.md` | 有效文字 pattern 库（≤15 条） | 每日/每周进化时 |
| `agent/knowledge-base/anti-patterns.md` | 已淘汰的文字 pattern | 连续失效时 |
| `agent/knowledge-base/image-patterns.md` | 有效图片 prompt pattern 库（≤10 条） | 每日复盘时基于 NoteRx visual_score |
| `agent/knowledge-base/image-anti-patterns.md` | 已淘汰的图片 prompt pattern | 连续 visual_score ≤ 50 时 |
| `agent/knowledge-base/evolution-log.md` | 进化日志（含文字+图片两条线） | 每日 |
| `agent/knowledge-base/audit-<YYYY-MM-DD>.{json,md}` | 老博主体检报告 | `audit-report.sh` 产出 |
| `agent/knowledge-base/reviews/<YYYY-W##>.md` | 周深度回顾 | 每周日 |

## SQLite 表（agent/data/xhs.db，11 张）

| 表 | 用途 |
|----|------|
| `posts` | 帖子记录（标题/内容/标签/状态/类型/风格/source） |
| `post_metrics` | 互动数据时序（likes/saves/comments/shares） |
| `user_choices` | 用户选择记录（用于偏好学习） |
| `topic_candidates` | 选题候选记录 |
| `comment_insights` | 评论分析结果（助手写入） |
| `note_diagnosis` | NoteRx 诊断分数与 issues |
| `generated_images` | 图片生成历史（model/path/status/prompt） |
| `request_log` | MCP 请求日志（节流 / 限额聚合） |
| `historical_stats` | 历史聚合统计 |
| `__migrations` | migration 台账，防重跑（v2.4.0+） |
| `post_sources`（enum） | `shuling` / `imported` / 其它来源标记 |

## Schema 文件清单

| Schema | 适用文件 |
|---|---|
| state.schema.json | agent/config/state.json |
| profile.schema.json | agent/knowledge-base/profile.json |
| preferences.schema.json | agent/knowledge-base/preferences.json |
| audit-report.schema.json | agent/knowledge-base/audit-*.json |
| playbook-frontmatter.schema.json | agent/playbook/*.md frontmatter |

## 版本治理

schema 不向后兼容时强制升 BRAIN 位（见 RELEASING.md 决策树）。
