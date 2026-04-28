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

## v3.1+ Account Safety Layer

为支持账号执行权收口与外部情报智能进化，新增 6 个数据契约。详见 `docs/plans/v3-account-execution-safety-hardening.md`。

| Schema | 适用文件 | 写入方 | 读取方 |
|---|---|---|---|
| `approval.schema.json` | `agent/config/approvals/<id>.json` | `approval.sh request` / `grant` | `xhs.sh publish/comment/import-cookie` 在执行前 verify |
| `account-safety-policy.schema.json` | `agent/config/account-safety.json` | `db.sh ensure-runtime-layout`（首次拷贝自 default policy）+ 用户手改 | `xhs.sh` / `account-safety.sh` / `import-existing.sh` 决定动作是否启用 |
| `account-safety-state.schema.json` | `agent/config/account-safety-state.json` | `account-safety.sh` / `xhs.sh`（每次 MCP 调用前后维护） | 所有 privileged 动作的硬门禁；`doctor.sh` 状态展示 |
| `external-intelligence-policy.schema.json` | `agent/config/external-intelligence.json` | `db.sh ensure-runtime-layout`（首次拷贝自 default policy）+ 用户手改 | `external-intel.sh` 决定预算与缓存策略 |
| `external-signal.schema.json` | `agent/knowledge-base/external-signals/<slug>-<YYYY-MM-DD>.json` | `external-intel.sh research-topic / competition-gap / comment-demand` | `03-daily-flow.md` 双因子选题评分（external_momentum / competition_gap / comment_demands） |
| `content-qa-report.schema.json` | content-qa.py stdout（不落盘） | `content-qa.py` | `03-daily-flow.md` 在生成 meta.json 前调用，score<70 触发重写 |

### 默认策略

- `agent/policies/account-safety.default.json`：默认 `draft-only` 模式，发布/评论默认禁用，cookie 导入允许，max_daily_publishes=1。
- `agent/policies/external-intelligence.default.json`：默认 `conservative` 模式，每日 search_feeds=8/list_feeds=5/get_feed_detail=15/fetch_comments=5，触发风险后冷却 1440 分钟。

### 硬约束

- `external-signal.schema.json` 通过 `patternProperties` 反向断言禁止 `full_body` / `raw_comments` / `full_comments` / `raw_post_body` / `note_body` / `raw_html` 字段，从 schema 层确保 §12.8 "不保存原始内容"。
- `approval.schema.json` 的 `id` 强制 `appr_YYYYMMDD_HHMMSS_<8hex>`，便于 `verify` 时 fail fast。
- `account-safety-state.schema.json` 的 `risk_level` enum 只允许 `normal/watch/cooldown/locked`，对应 §7.2 风险等级表。

### 用户态 vs 仓库态

`agent/config/account-safety.json`、`agent/config/account-safety-state.json`、`agent/config/approvals/*`、`agent/knowledge-base/external-signals/*` 均为用户态，`.gitignore` 已覆盖。仓库内只跟随 `.example` 模板与 `policies/*.default.json`。
