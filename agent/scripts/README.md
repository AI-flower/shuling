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
  "status": "published"
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

### agent/scripts/pre-submit-verify.sh — 发版前强制回归（v2.4.2+，21 项）

```bash
bash agent/scripts/pre-submit-verify.sh         # 必跑；模拟社区 verifier 行为
bash agent/scripts/pre-submit-verify.sh --json  # 给 agent / CI
```

覆盖干净 target 初装、runtime.env 覆写、target DB init + `__migrations`、preflight 全绿、upgrade-all migration 写 target 而非源、源 DB md5 未被污染等 21 项。
