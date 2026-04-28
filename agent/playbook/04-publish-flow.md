---
id: 04-publish-flow
title: Publish Flow
when:
  - "用户明确回复'发'"
  - "publish_approved 事件触发"
needs:
  required:
    - agent/knowledge-base/profile.json
    - agent/policies/content-rules.md
    - agent/policies/account-safety.default.json
    - agent/playbook/_shared/post-meta-schema.json
  optional:
    - agent/knowledge-base/business-profile.json
    - agent/knowledge-base/creator-behavior-signals.md
  fallback:
    business-profile.json: add-post 不写 title_intent 与 primary_goal 联动校验,仅记录原始 title_formula_id / title_trigger
    creator-behavior-signals.md: 跳过 draft_no_publish 行为信号写入,但 add-post 主流程不受影响
  db_tables:
    - posts
    - post_metrics
    - creator_behavior_signals
  env_vars:
    - MCP_URL
calls:
  scripts:
    - agent/scripts/xhs.sh
    - agent/scripts/approval.sh
    - agent/scripts/account-safety.sh
    - agent/scripts/db.sh
  playbooks:
    - 06-learning-loop.md
    - 08-compliance.md
    - 09-troubleshooting.md
writes:
  files:
    - agent/data/xhs.db (posts, post_metrics)
    - agent/config/approvals/<id>.json (consumed)
  emits:
    - post_published
preconditions:
  - "用户明确回复'发'"
  - "approval.sh request publish 已 grant 且未过期未消费"
  - "account-safety risk_level ∈ {normal, watch}"
  - "agent/config/runtime.env 含 MCP_URL"
on_failure:
  - 09-troubleshooting.md
version: 3.2.0
last_updated: 2026-04-28
---

# 04 Publish Flow

把 03 产出的 `meta.json` 推到小红书，记录 note_id，处理失败重试与草稿存档。

> **v3.1 边界**：`draft_ready` 仅表示草稿已就绪，**不**触发本 playbook。本 playbook 必须由「用户明确回复'发'」+ approval grant 触发。详见 `docs/adr/0003-account-execution-boundary.md` §D3。

## Trigger

- 用户明确回复"发"（或等价确认词）
- `publish_approved` 事件触发（由 `approval.sh grant` 显式产生，cron 与自动 routing 都不能合成）
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

2. **请求授权 + verify approval（v3.1 硬门禁）**
   ```bash
   # 2a. 请求授权（AI 触发）
   APPROVAL_OUT=$(bash agent/scripts/approval.sh request publish /tmp/xhs-post/meta.json)
   # 输出包含 approval_id（pending），向用户展示并等待用户回复 'grant <id>' 或回复 '发'
   APPROVAL_ID=$(echo "$APPROVAL_OUT" | python3 -c "import json,sys;print(json.loads(sys.stdin.read())['approval_id'])")

   # 2b. 用户回复 '发'/确认 → grant
   bash agent/scripts/approval.sh grant "$APPROVAL_ID"

   # 2c. 校验（6 道闸：文件 / status=granted / action / hash / 未过期 / 未消费 / safety state）
   bash agent/scripts/approval.sh verify publish /tmp/xhs-post/meta.json --approval-id "$APPROVAL_ID"
   # 任一失败转 → 09-troubleshooting.md Account Safety 故障矩阵
   ```

3. **发布（带 approval-id；xhs.sh 内部还会再 verify 一次 + check safety state）**
   ```bash
   bash agent/scripts/xhs.sh publish /tmp/xhs-post/meta.json --approval-id "$APPROVAL_ID"
   # 成功后 xhs.sh 会自动 consume approval + increment daily_publish_count
   ```

4. **处理结果**
   - 成功 → 提取 note_id，记录到数据库（**v3.2+ 必须传 `title_formula_id` / `title_trigger` / `title_intent` 三字段**，由 03-daily-flow.md §2.2 第 3 步生成时确定；plan §7.6）：
     ```bash
     agent/scripts/db.sh add-post '{
       "date":"2026-04-15",
       "slot":"noon",
       "title":"XXX",
       "content":"XXX",
       "tags":"[...]",
       "topic_type":"家居收纳",
       "title_pattern":"数字清单",
       "content_style":"清单体",
       "status":"published",
       "title_formula_id":"number_anchor_steps",
       "title_trigger":"number_anchor",
       "title_intent":"trust"
     }'
     agent/scripts/db.sh update-post-status <id> published <note_id>
     ```

     字段语义（plan §5.4.5 / §7.6）：
     - `title_formula_id` — `agent/knowledge-base/title-formulas.json[].id`，没有匹配公式时填 `"manual"`
     - `title_trigger` — 该公式 `trigger`（如「损失规避」「打破已有认知」）；`manual` 时为空字符串
     - `title_intent` — `click | save | comment | trust | lead | conversion | series` 七选一；publish 入库前**必须有值**（08-compliance.md `Title Formula Validation` 强制）

   - 失败 → 见下面"补充：发布失败重试 / 草稿存档"

5. **返回发布结果**："已发布！标题：XXX"，emit `post_published` 供 → `06-learning-loop.md` 后续采集 `post_metrics`

   **不改 approval / account-safety 逻辑**（plan §7.6 末段）：v3.2 仅在 `add-post` 写入新增标题公式字段；approval grant、6 道闸、消费、cooldown 行为完全沿用 v3.1。

**补充：发布失败重试 / 草稿存档**

- 发布失败时**不要删** `/tmp/xhs-post/meta.json` 与图片文件，原地保留供重试
- 同时把这条草稿落库为 `status='draft'`，便于后续手动重发或日报追踪（同样**保留 v3.2+ 标题公式字段**）：
  ```bash
  agent/scripts/db.sh add-post '{"date":"2026-04-15","slot":"noon","title":"XXX","content":"XXX","tags":"[...]","topic_type":"家居收纳","title_pattern":"数字清单","content_style":"清单体","status":"draft","title_formula_id":"number_anchor_steps","title_trigger":"number_anchor","title_intent":"trust"}'
  ```
- 重试策略：MCP 临时错误（超时 / 5xx）最多 1 次重试；登录态失效 → 走第 1 步重登；合规拒绝（小红书侧驳回）→ 不重试，转 `09-troubleshooting.md` 让用户改稿
- 同一草稿重发成功后，把 draft 行的 `status` 改为 `published` 并补 `note_id`，不要新建一行（避免 06 计指标时重复计数）
- **`draft_no_publish` 行为信号**（v3.2+ Stage 12，plan §5.7.6 / §7.6 末段 — 可执行规则）：

  **触发条件**：用户在 03-daily-flow.md 完成草稿确认（`draft_ready` emit）后 **24 小时内**仍未进入本 playbook（无 `approval.sh request publish` / 无 grant / 无 `xhs.sh publish` 调用）→ 在下次会话开头记录 `draft_no_publish` 信号，但**不替用户自动发布**。

  **下次会话开头的检测逻辑**（LLM 在 playbook 内执行）：

  ```bash
  # 检查 24h+ 未发布的 draft（status=draft 且 created_at < now - 24h）
  bash agent/scripts/db.sh query-posts --days 14 --status draft
  # 同时查询 7-14 天内已写过的 draft_no_publish 信号，避免重复写
  bash agent/scripts/db.sh query-creator-behavior-signals --days 14 --signal-type draft_no_publish
  ```

  **写入命令**（与 03-daily-flow.md `Execution Friction Fallback` 同款）：

  ```bash
  bash agent/scripts/db.sh add-creator-behavior-signal '{
    "id": "behavior_20260428_draft_no_publish",
    "signal_type": "draft_no_publish",
    "severity": "warn",
    "observed_events": [
      {"event": "draft_generated", "count": 1, "window_days": 1, "evidence": "draft 在 24h 前生成但未发布"},
      {"event": "publish_skipped", "count": 1, "window_days": 1}
    ],
    "interpretation": "草稿在 24 小时前已确认但仍未发布。当前问题更像发布前摩擦（不是选题不够好）。",
    "next_small_action": "把这条草稿小修标题或开头后发出去；本会话不再生成新选题。",
    "cooldown_until": "2026-05-05",
    "created_at": "2026-04-28"
  }'
  ```

  **行为底线（plan §5.7.5 / §7.6 末段）**：

  - **不**自动重发草稿；用户必须显式回复"发"才进入第 2 步 approval flow
  - **不**做心理评价（禁词："拖延症 / 你在逃避 / 你自卑 / 你不想赚钱"等；08-compliance.md `Behavior Signal Output Validation` 强制）
  - cron 下次唤醒时，03-daily-flow.md 的 `Execution Friction Fallback` 读到此信号 → **不再扩展新选题**，改走兜底剧本（详见 → 03-daily-flow.md `## 2.0 Execution Friction Fallback`）
  - 写入失败 → 转 → 09-troubleshooting.md `behavior_signal_db_failed` 行；只追加 `creator-behavior-signals.md`，不阻塞本 playbook
  - 用户主动表示判断不准 → 转 → 09-troubleshooting.md `behavior_signal_misfire` 行；本会话不再提示

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
- **approval 失败**（approval_required / approval_expired / resource_changed / approval_consumed / safety_cooldown / safety_locked）→ 转 → `agent/playbook/09-troubleshooting.md` Account Safety Failure Matrix

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
