# agent/scripts/ 脚本契约文档（v3.0+）

> 此文档是所有 playbook 调用脚本的**唯一权威参考**。Playbook 不得复述命令清单，必须 cross-ref 本文件。

## 通用契约

- 退出码：0 = 成功 / 1 = auto-fixable / 2 = need-user
- JSON 输出：`--json` 输出单行 JSON 给 agent；缺省给人读
- 路径：所有脚本必须 source `agent/scripts/_paths.sh`，禁止 hardcode
- 用户态保护：脚本不得覆盖 `agent/data/xhs.db` / `agent/config/runtime.env` / `agent/knowledge-base/`

## 脚本清单

### agent/scripts/xhs.sh — 小红书 MCP 统一入口

```bash
bash agent/scripts/xhs.sh search "关键词"              # 搜索内容，返回 JSON
bash agent/scripts/xhs.sh recommend                    # 获取推荐流，返回 JSON
bash agent/scripts/xhs.sh detail <note_id>             # 帖子详情+互动+评论，返回 JSON
bash agent/scripts/xhs.sh publish <meta.json路径>      # 发布图文笔记，返回 JSON
bash agent/scripts/xhs.sh comment <note_id> "内容"     # 发表评论
bash agent/scripts/xhs.sh status                       # 登录状态，返回 JSON
bash agent/scripts/xhs.sh login                        # 获取登录二维码链接
bash agent/scripts/xhs.sh import-cookie '<cookie>'     # 导入用户提供的 cookie 串
bash agent/scripts/xhs.sh user <user_id>               # 用户主页信息
bash agent/scripts/xhs.sh log --summary                # request_log 聚合（v2.1.1+）
```

环境变量：`MCP_URL`（默认 `http://localhost:18060/mcp`）

### agent/scripts/image.py — 图片生成（强制 Gemini，无 HTML 降级）

```bash
python3 agent/scripts/image.py --check                       # 检查 API Key，exit 0=可用，2=未配置
python3 agent/scripts/image.py --set-key "API_KEY"           # 配置 Gemini Key
python3 agent/scripts/image.py \
    --page-type "封面|内容|总结" \
    --page-content "<该页大纲原文>" \
    --outline-file /tmp/xhs-post/outline.txt \
    --topic "<用户原始主题原文>" \
    --output /tmp/xhs-post/page-N.png \
    [--reference /tmp/xhs-post/page-1.png] \
    [--short]
```

环境变量：`IMAGE_GEN_API_KEY`、`IMAGE_GEN_MODEL`（推荐 `gemini-3-pro-image-preview` / Nano Banana Pro）

参数硬规则：

- `--page-type` 只能是 `封面 / 内容 / 总结` 三选一
- `--page-content` 必须是大纲该页**完整原文**（含 `配图建议：xxx` 行）
- `--outline-file` 必传（让模型看全篇上下文）
- 非封面页**必须** `--reference <封面路径>`，多页风格统一的核心
- `--short` 切到极简版 prompt（仅当 API 上下文受限）

### agent/scripts/db.sh — SQLite CRUD + ensure-runtime-layout + ensure-schema

```bash
bash agent/scripts/db.sh init                                       # 初始化数据库（11 表 + post_sources enum，幂等）
bash agent/scripts/db.sh add-post '<json>'                          # 记录帖子，输出 {"id": N}
bash agent/scripts/db.sh add-metrics '<json>'                       # 记录互动数据
bash agent/scripts/db.sh log-choice '<json>'                        # 记录用户选择
bash agent/scripts/db.sh query-posts [--today|--days N|--status S]  # 查询帖子
bash agent/scripts/db.sh query-metrics --post-id N                  # 查询互动数据
bash agent/scripts/db.sh query-preferences                          # 查询偏好统计
bash agent/scripts/db.sh update-post-status <id> <status> [note_id] # 更新状态
bash agent/scripts/db.sh update-post-meta '<json>'                  # 回写分类（topic_type/title_pattern/...）
bash agent/scripts/db.sh add-diagnosis '<json>'                     # 写入 NoteRx 诊断
bash agent/scripts/db.sh query-diagnosis --post-id N                # 查最新诊断
bash agent/scripts/db.sh query-undiagnosed [--days N]               # 列已发布未诊断的帖子
bash agent/scripts/db.sh query-external-signals [--topic X] [--days N] [--limit N]
                                                                    # v3.1+ external_signals 辅助索引

# v3.2+ Creator Business Intelligence
bash agent/scripts/db.sh add-business-review '<json>'              # 业务归因复盘（05-review）
bash agent/scripts/db.sh query-business-review --post-id N         # 查某帖最新业务复盘
bash agent/scripts/db.sh query-business-reviews [--days N --limit N]
bash agent/scripts/db.sh add-content-asset '<json>'                # 内容资产单元（asset-ledger）
bash agent/scripts/db.sh query-content-assets [--type T --days N --limit N]
bash agent/scripts/db.sh add-creator-behavior-signal '<json>'      # 执行摩擦行为信号
bash agent/scripts/db.sh query-creator-behavior-signals [--days N --signal-type T --limit N]
```

环境变量：`SHULING_DB`（指定 DB 路径，v2.4.2+，install / migration 调用 target DB 时必传）

`add-post` 输入 JSON 范例：

```json
{
  "date": "2026-04-15",
  "slot": "noon",
  "title": "XXX",
  "content": "XXX",
  "tags": "[\"标签1\",\"标签2\"]",
  "topic_type": "家居收纳",
  "title_pattern": "数字清单",
  "content_style": "清单体",
  "status": "published",
  "title_formula_id": "loss_stop_doing",
  "title_trigger": "loss_aversion",
  "title_intent": "click"
}
```

`title_formula_id` / `title_trigger` / `title_intent`（v3.2+）可选；缺省落 NULL，不影响旧调用方。`update-post-meta` 同样支持回写这 3 个字段。

`add-business-review` 输入 JSON 范例（v3.2+，结构对齐 `agent/schemas/business-review.schema.json`）：

```json
{
  "post_id": 123,
  "reviewed_at": "2026-04-28T12:00:00Z",
  "performance_tier": "mixed",
  "traffic_signal": "high",
  "save_signal": "high",
  "trust_signal": "normal",
  "lead_signal": "low",
  "sales_signal": "unknown",
  "controversy_signal": "low",
  "main_attribution": "content_depth",
  "evidence_level": "medium",
  "confidence": "medium",
  "evidence": [
    {"source": "comment", "text": "「收藏了」高频", "weight": "medium"}
  ],
  "business_interpretation": "知识收藏型内容，适合涨粉/信任，不直接做转化 pattern",
  "next_action": "series"
}
```

`add-content-asset` 输入 JSON 范例（结构对齐 `agent/schemas/content-asset.schema.json`）：

```json
{
  "id": "asset_20260428_audience_language_no_result",
  "asset_type": "audience_language",
  "source": {"post_id": 123, "manual_note": ""},
  "content": "发了 30 条还是没起色，不知道是标题问题还是方向问题",
  "why_it_matters": "目标读者描述痛点的原话",
  "reuse_plan": "build_trust 选题做开头场景",
  "confidence": "medium",
  "created_at": "2026-04-28"
}
```

`add-creator-behavior-signal` 输入 JSON 范例（结构对齐 `agent/schemas/creator-behavior-signal.schema.json`）：

```json
{
  "id": "behavior_20260428_draft_no_publish",
  "signal_type": "draft_no_publish",
  "severity": "warn",
  "observed_events": [
    {"event": "draft_generated", "count": 4, "window_days": 7},
    {"event": "publish_skipped", "count": 4, "window_days": 7}
  ],
  "interpretation": "过去 7 天 4 条草稿，0 条进入发布确认",
  "next_small_action": "从现有 4 条里选风险最低的 1 条小修后发布",
  "created_at": "2026-04-28"
}
```

`log-choice` 输入 JSON 范例：

```json
{
  "choice_type": "topic",
  "offered_count": 3,
  "chosen_index": 2,
  "chosen_label": "办公室收纳",
  "skipped_labels": "[\"通勤穿搭\",\"周末亲子活动\"]"
}
```

### agent/scripts/preflight.py — 环境自检

```bash
python3 agent/scripts/preflight.py              # AI 读的 JSON 格式（默认）
python3 agent/scripts/preflight.py --human      # 人类彩色表格
```

退出码：0 = 全绿 / 1 = auto-fixable / 2 = need-user

输出 JSON 含 `setup_completed` / `state` / `checks[]`，每个 check 含 `status` / `action` / `install_cmd` / `fix_cmd` / `ask`。详细使用见 09-troubleshooting.md。

### agent/scripts/validate.py — JSON Schema drift 校验（v2.4.0+）

```bash
python3 agent/scripts/validate.py
```

校验 `agent/schemas/` 与运行时 JSON 结构一致。发版前应保持全绿。

### agent/scripts/fetch-metrics.sh — 拉互动数据

```bash
bash agent/scripts/fetch-metrics.sh <post_id> <note_id> [xsec_token]
```

调 `xhs.sh detail` 提取 likes/saves/comments/shares，写入 `post_metrics` 表（`checkpoint='daily'`）并输出 JSON。供每日复盘批量调用。

### agent/scripts/fetch-comments.sh — 拉评论原文

```bash
bash agent/scripts/fetch-comments.sh <note_id> [xsec_token] [--limit 50]
```

调 `xhs.sh detail` 提取评论数组，**过滤垃圾评论**（纯 emoji / ≤2 字 / 含"加微/私聊/免费领/http"），输出 `[{author, text, like_count}]` JSON 数组。**LLM 分析由你来做**，脚本只做物理过滤。

### agent/scripts/noterx-diagnose.sh — NoteRx 第三方诊断

```bash
# 默认只跑 pre-score（< 50ms，零成本）
bash agent/scripts/noterx-diagnose.sh <post_id> "<title>" \
    --content "<正文>" --tags "标签1,标签2" \
    --category tech --image-count 6

# 加 --full 跑完整 5-Agent 诊断（60-90s，仅在两端跑：极好或极差）
bash agent/scripts/noterx-diagnose.sh <post_id> "<title>" --content "..." --full

# --test 模式：只测 API 连通性，不写 DB
bash agent/scripts/noterx-diagnose.sh --test
```

调 `noterx.muran.tech` 拿 5 维评分 + grade + issues + suggestions，写入 `note_diagnosis` 表。环境变量：`NOTERX_API_URL`、`NOTERX_TIMEOUT_PRE`（默认 15s）、`NOTERX_TIMEOUT_FULL`（默认 150s）。

支持的 category：`tech`/`food`/`fashion`/`travel`/`beauty`/`fitness`/`lifestyle`/`home`，未指定走 `lifestyle`。

### agent/scripts/audit-report.sh — 老博主体检报告（v2.2.0+）

```bash
bash agent/scripts/audit-report.sh --extract-patterns
# 产出:
#   agent/knowledge-base/audit-<YYYY-MM-DD>.json   机器可读
#   agent/knowledge-base/audit-<YYYY-MM-DD>.md     人类可读骨架
```

可选 `--include-organic` 把 `source != 'shuling'` 的历史帖也纳入分析。

### agent/scripts/import-existing.sh — 老博主批量导入（v2.2.0+）

```bash
bash agent/scripts/import-existing.sh --limit 200
bash agent/scripts/import-existing.sh --resume    # 中断续跑，幂等
```

按节流 profile 批量拉取并写入 `posts` 表（`source='imported'`）；耗时约 30+ 分钟，可挂后台。

### agent/scripts/content-qa.py — 内容质量与 AI 托管感检查（v3.0+）

```bash
python3 agent/scripts/content-qa.py                                      # 默认人类彩色表格
python3 agent/scripts/content-qa.py --json                               # 单行 JSON（agent 解析）
python3 agent/scripts/content-qa.py --draft /tmp/xhs-post/meta.json      # 同时检查待发草稿
python3 agent/scripts/content-qa.py --last-n 30 --threshold 70           # 自定义历史窗口和阈值
python3 agent/scripts/content-qa.py --db /path/to/xhs.db --json          # 显式指定 DB
```

供 03-daily-flow.md 在生成 meta.json 前调用，分析最近 N 篇已发布帖 + 当前草稿，检测 8 项 AI 托管感信号：

1. 标题 trigram Jaccard 相似度（≥0.6 算重复）
2. 同一 `title_pattern` 连续 ≥5 次
3. 正文前 30 字相似度（≥0.6）
4. 最近 10 篇标签组合（≥5 个相同 tag）重复
5. 单页 emoji ≥6 个
6. 高频 AI 味词汇命中率（"赋能/闭环/抓手/yyds/绝绝子" 等）
7. `generated_images.gen_strategy` 连续 ≥5 篇
8. 连续 ≥4 篇清单体（`content_style='清单'` / `title_pattern='数字清单'`）

参数：

- `--db <path>` xhs.db 路径（默认按 `SHULING_DB` env > `SHULING_AGENT_ROOT` > 脚本父目录推导）
- `--draft <meta.json>` 待发草稿路径（可选，未提供时只查历史）
- `--last-n <int>` 分析窗口（默认 30）
- `--threshold <int>` score 阈值（默认 70，低于此值 exit 1）
- `--json` 单行 JSON 输出
- `--human` 彩色表格（默认）

退出码：0 = score ≥ threshold / 1 = score < threshold（提示重写）/ 2 = DB 不存在或参数错误。

JSON 输出形状（与 `agent/schemas/content-qa-report.schema.json` 对齐）：

```json
{
  "ok": true,
  "score": 82,
  "warnings": [
    {"check": "title_similarity", "severity": "warn", "message": "...", "samples": [...]}
  ],
  "checked_at": "2026-04-28",
  "target_post_id": null,
  "sample_size": {"recent_posts": 30, "image_strategies": 30, "draft_present": true}
}
```

DB 缺失或 posts 表为空 → score=100, warnings=[]，附 `note: "no history yet"`。

纯 stdlib（json/sqlite3/re/argparse），不引入新 pip 依赖；不调 LLM API（规则引擎，非 AI 检测）。

fixture（`agent/scripts/content-qa-fixtures/`）：`repetitive.meta.json` 应触发多项 warn；`clean.meta.json` 在干净 DB 下 score=100。

### agent/scripts/external-intel.sh — 外部情报低风险采样（v3.1+）

> 见 `docs/runbooks/external-intelligence.md` / `docs/plans/v3-account-execution-safety-hardening.md` §12

```bash
bash agent/scripts/external-intel.sh research-topic "<主题>" [--budget conservative|balanced|aggressive]
                                  # 主题外部研究：search → 深读（≤3-5）→ 提炼信号 → 落 cache
bash agent/scripts/external-intel.sh competition-gap "<主题>"
                                  # 仅 search，输出 competition_density + white_space
bash agent/scripts/external-intel.sh comment-demand <note_id> [--limit 30]
                                  # 评论需求提炼（≤30 条评论，**不存原文**）
bash agent/scripts/external-intel.sh cache-get "<主题>"
                                  # 查 cache（不发起请求）
bash agent/scripts/external-intel.sh cache-prune
                                  # 清理 expires_at < today 的过期 cache
bash agent/scripts/external-intel.sh budget-status
                                  # 查看预算余额（daily + per-session + cooldown）
```

**契约**：

- 必须走 `xhs.sh`（继承节流/限额/风险关键词识别），绝不裸调 MCP
- 写盘前用 `agent/schemas/external-signal.schema.json` 自校验；硬禁字段 `full_body / raw_comments / full_comments / raw_post_body / note_body / raw_html`（verify 42）
- safety state 为 `cooldown` / `locked` 时**完全停止**采样（exit 30）
- 命中风险信号 → 调 `account-safety.sh record-event external_intel "<hint>"` + exit 31，已采样部分仍保留
- 预算耗尽 / MCP 失败 → 输出 `degraded:true`，exit 0（caller 降级到内部记忆）

**输出形状**（单行 JSON）：

```json
{"ok":true,"cache_hit":false,"topic":"租房收纳","signal":{...external-signal.schema...},"budget_used":{"search_feeds":1,"get_feed_detail":3},"session_id":"pid-12345"}
```

**预算策略**：默认 conservative（`agent/policies/external-intelligence.default.json`），用户态 override `agent/config/external-intelligence.json` 只能更保守不能更激进（verify 41）。

**退出码**：0 = ok / cache hit / degraded；1 = usage；2 = policy 解析失败；20 = schema 校验失败；30 = cooldown / locked；31 = 风险信号触发本次采样中止。

**计数器位置**：`agent/data/external-intel-counters.json`（用户态，已 .gitignore）；按 `SHULING_SESSION_ID` 或 PID 分桶。

### agent/scripts/pre-submit-verify.sh — 发版前强制回归（v2.4.2+，21 项）

```bash
bash agent/scripts/pre-submit-verify.sh         # 必跑；模拟社区 verifier 行为
bash agent/scripts/pre-submit-verify.sh --json  # 给 agent / CI
```

覆盖干净 target 初装、runtime.env 覆写、target DB init + `__migrations`、preflight 全绿、upgrade-all migration 写 target 而非源、源 DB md5 未被污染等 21 项。
