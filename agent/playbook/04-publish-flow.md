---
id: 04-publish-flow
title: Publish Flow
when:
  - "用户回复'发'"
  - "草稿确认后"
  - "draft_ready 事件触发"
needs:
  required:
    - agent/knowledge-base/profile.json
    - agent/policies/content-rules.md
    - agent/playbook/_shared/post-meta-schema.json
  db_tables:
    - posts
    - post_metrics
  env_vars:
    - MCP_URL
calls:
  scripts:
    - agent/scripts/xhs.sh
    - agent/scripts/db.sh
  playbooks:
    - 06-learning-loop.md
    - 08-compliance.md
    - 09-troubleshooting.md
writes:
  files:
    - agent/data/xhs.db (posts, post_metrics)
  emits:
    - post_published
preconditions:
  - "draft_ready 事件已触发"
  - "agent/config/runtime.env 含 MCP_URL"
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
---

# 04 Publish Flow

把 03 产出的 `meta.json` 推到小红书，记录 note_id，处理失败重试与草稿存档。

## Trigger

- 用户回复"发"（或等价确认词）
- `draft_ready` 事件触发
- 上游：`agent/playbook/03-daily-flow.md`

## Read This When

- 03 已完成，`/tmp/xhs-post/meta.json` 存在
- 不要直接走这个 playbook 跳过选题/草稿——必须有 meta.json 输入

## Inputs

- `/tmp/xhs-post/meta.json`（结构 → `agent/playbook/_shared/post-meta-schema.json`）
- `agent/knowledge-base/profile.json`（确认账号身份）
- `agent/policies/content-rules.md`（publish-time 终检，摘要见下文）

**Publish-time 合规摘要**（≤10 行，权威定义见 → `agent/playbook/08-compliance.md`，依据 ADR-0002 D4）：

- 标题终检：长度 15-30 字、无绝对化词、无承诺式词、emoji ≤2
- 正文终检：≤500 字、无外链、无引战词、无未成年人不当内容
- 图片终检：每页有内容、无水印冲突
- 商业内容标记：含品牌/折扣码/链接 → `is_original=false` 并据此切发布参数
- 标签终检：5-8 个、无敏感词、无 # 号
- 完整禁用词列表 / 灰区判定 → `agent/playbook/08-compliance.md`

## Procedure

1. **检查登录状态**
   ```bash
   agent/scripts/xhs.sh status
   ```
   - 已登录 → 继续
   - 未登录 → `agent/scripts/xhs.sh login` 获取二维码链接，返回给上层让用户扫码；若用户主动提议给 cookie，改用 `agent/scripts/xhs.sh import-cookie`

2. **发布**
   ```bash
   agent/scripts/xhs.sh publish /tmp/xhs-post/meta.json
   ```

3. **处理结果**
   - 成功 → 提取 note_id，记录到数据库：
     ```bash
     agent/scripts/db.sh add-post '{"date":"2026-04-15","slot":"noon","title":"XXX","content":"XXX","tags":"[...]","topic_type":"家居收纳","title_pattern":"数字清单","content_style":"清单体","status":"published"}'
     agent/scripts/db.sh update-post-status <id> published <note_id>
     ```
   - 失败 → 见下面"补充：发布失败重试 / 草稿存档"

4. **返回发布结果**："已发布！标题：XXX"，emit `post_published` 供 → `06-learning-loop.md` 后续采集 `post_metrics`

**补充：发布失败重试 / 草稿存档**

- 发布失败时**不要删** `/tmp/xhs-post/meta.json` 与图片文件，原地保留供重试
- 同时把这条草稿落库为 `status='draft'`，便于后续手动重发或日报追踪：
  ```bash
  agent/scripts/db.sh add-post '{"date":"2026-04-15","slot":"noon","title":"XXX","content":"XXX","tags":"[...]","topic_type":"家居收纳","title_pattern":"数字清单","content_style":"清单体","status":"draft"}'
  ```
- 重试策略：MCP 临时错误（超时 / 5xx）最多 1 次重试；登录态失效 → 走第 1 步重登；合规拒绝（小红书侧驳回）→ 不重试，转 `09-troubleshooting.md` 让用户改稿
- 同一草稿重发成功后，把 draft 行的 `status` 改为 `published` 并补 `note_id`，不要新建一行（避免 06 计指标时重复计数）

## Writes

- `agent/data/xhs.db`：
  - `posts`：成功 → `status='published'` + `note_id`；失败 → `status='draft'`，保留 meta.json 路径线索
  - `post_metrics`：成功后由 `06-learning-loop.md` 异步采集填充
- 事件：`post_published`（仅成功时）

## Failure Handling

- 登录态丢失 → `agent/scripts/xhs.sh login` 重登，单次失败上报上层
- MCP 网络/超时 → 1 次重试 → 仍失败转 → `agent/playbook/09-troubleshooting.md`
- 小红书侧合规拒绝 → 不重试，告诉用户原因，保留 draft 等改稿
- 任何路径下 `meta.json` 与图片**保留不删**，下次重发可直接用

## Anti-Patterns

- 不绕过 agent/scripts/xhs.sh 直接调 MCP
- 不在发布失败时丢弃草稿（保留 meta.json 供重试）
- 发布前合规摘要不超过 10 行（cross-ref → 08-compliance.md 完整规则）
- 不复述 weight 公式（cross-ref → 06-learning-loop.md）

## Cross-Refs

- → `agent/playbook/03-daily-flow.md`（上游产出 meta.json）
- → `agent/playbook/06-learning-loop.md`（post_metrics 采集 + 进化）
- → `agent/playbook/08-compliance.md`（完整合规规则，ADR-0002 D4）
- → `agent/playbook/09-troubleshooting.md`（失败诊断）
- → `agent/playbook/_shared/post-meta-schema.json`
