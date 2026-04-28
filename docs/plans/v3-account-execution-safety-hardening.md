# v3.0 Account Execution Safety Hardening Plan

> **Status**: Proposed
> **Date**: 2026-04-28
> **Scope**: v3.0 重构后的账号执行权收口、安全门禁、cron 语义修正、外部情报智能进化、内容质量风控与工程一致性修复
> **Related**:
> - [ADR-0001 Stateful Creator Agent](../adr/0001-stateful-creator-agent.md)
> - [ADR-0002 Playbook Split Decisions](../adr/0002-playbook-split-decisions.md)
> - [v3 Playbook Split Feasibility](v3-playbook-split-feasibility.md)

## 0. 背景与核心判断

v3.0 重构后，薯灵已经从单文件 Skill 变成三层结构：

```text
SKILL.md      协议适配层
agent/        业务内核
ops/          部署运维层
```

这解决了结构、路径、迁移、playbook progressive disclosure 等问题，但还留下一个更关键的产品安全边界：

> 薯灵是否默认拥有用户小红书账号的写权限？

如果系统可以在没有用户明确确认的情况下调用：

- `agent/scripts/xhs.sh publish`
- `agent/scripts/xhs.sh comment`
- `agent/scripts/xhs.sh import-cookie`
- `import-existing.sh --override-quota`
- cron 触发的发布流程

那么即使对外文案改成"创作助手"，真实行为仍接近"AI 托管账号"。

本计划的目标不是削弱自动化能力，而是重新定义自动化边界：

> **全自动运营大脑 + 受控账号执行层。**

自动完成：

- 选题
- 起稿
- 生图
- 复盘
- 评论洞察
- 偏好学习
- 账号诊断建议

必须受控：

- 发布笔记
- 发表评论
- 导入 Cookie
- 批量拉取历史内容
- 关闭节流 / 关闭限额
- 启用 cron

## 1. 总目标

### 1.1 产品目标

1. 保留薯灵的核心价值：长期记忆、自学习、自动选题、自动起稿、自动复盘。
2. 把账号写操作从"普通脚本能力"降级为"高风险授权动作"。
3. 让默认体验从"AI 托管账号"变成"AI 运营大脑 + 真人确认执行"。
4. 让用户能明确选择运行模式，而不是被默认带入全自动账号托管。
5. 让薯灵不只在内部偏好数据里自循环，而是通过低风险外部情报采样理解赛道变化。

### 1.2 工程目标

1. 发布、评论、Cookie 导入必须有脚本层硬门禁。
2. `draft_ready` 只能表示草稿准备好，不能触发发布。
3. cron 模板只能生成草稿 / 复盘，不默认发布或评论。
4. 风险事件可记录、可降级、可恢复。
5. 外部数据获取必须预算化、缓存化、可降级，不允许变成高频爬取。
6. verify 门禁能阻止安全边界回退。

### 1.3 非目标

1. 不移除 `publish_content` 能力。
2. 不移除评论读取和评论洞察能力。
3. 不把薯灵改成纯手动工具。
4. 不试图绕过平台风控。
5. 不承诺"不会封号"。

## 2. 核心原则

1. **draft_ready != publish_allowed**
   草稿生成完成只表示等待审核，不表示允许发布。

2. **账号写操作全部是 privileged mutation**
   `publish`、`comment`、`import-cookie`、`override-quota` 都必须经过授权或安全状态检查。

3. **脚本层强制，而不是只靠 playbook 文案**
   AI 可能误读文档，cron prompt 可能误触发，因此 `xhs.sh` 必须拒绝非法调用。

4. **cron 只能唤醒大脑，不能默认动账号**
   定时任务可以生成候选、草稿、复盘报告，但不能默认发布。

5. **评论默认禁用**
   评论更接近模拟真人互动，比发布更敏感，默认只生成回复建议。

6. **节流与限额不可在生产模式轻易关闭**
   `XHS_DISABLE_THROTTLE=1`、`XHS_DISABLE_QUOTA=1` 只允许开发模式。

7. **风险状态必须可观测**
   429、captcha、risk、forbidden、登录失败、发布失败等都应写入 account safety state。

8. **安全降级优先于继续执行**
   风险不明时继续生成草稿，不继续发布或评论。

9. **外部情报是采样系统，不是爬虫系统**
   外部数据用于提炼赛道信号、竞品密度、评论需求和差异化切口；默认低频、少量、可缓存，不追求全量。

10. **内部偏好与外部趋势必须双因子决策**
    内部数据回答"适不适合这个博主"，外部数据回答"现在值不值得做"。任何选题都不能只看一边。

## 3. 目标架构

新增 **Account Safety Layer**：

```text
SKILL.md
  ↓
agent/playbook/
  ↓
agent/scripts/
  ├── xhs.sh                 小红书 MCP 统一入口
  ├── approval.sh            一次性用户授权
  ├── account-safety.sh      风险策略、状态机、cooldown
  ├── external-intel.sh      外部情报低风险采样与缓存
  ├── content-qa.py          内容模板化 / AI 味质量检查
  └── db.sh
  ↓
xiaohongshu-mcp
```

发布链路变为：

```text
03-daily-flow
  ↓
生成 meta.json + 图片
  ↓
emit draft_ready
  ↓
等待用户确认
  ↓
approval.sh request publish /tmp/xhs-post/meta.json
  ↓
approval.sh grant <request_id>
  ↓
xhs.sh publish /tmp/xhs-post/meta.json --approval-id <id>
  ↓
account-safety.sh verify publish
  ↓
publish_content
```

评论链路变为：

```text
07-comment-insights
  ↓
读取评论并生成回复建议
  ↓
等待用户确认
  ↓
approval.sh request comment <note_id> <content>
  ↓
xhs.sh comment <note_id> <content> --approval-id <id>
```

默认情况下，最后一步不可用。

## 4. 文件改造清单

### 4.1 新增文件

```text
agent/scripts/approval.sh
agent/scripts/account-safety.sh
agent/scripts/external-intel.sh
agent/scripts/content-qa.py

agent/schemas/approval.schema.json
agent/schemas/account-safety-policy.schema.json
agent/schemas/account-safety-state.schema.json
agent/schemas/external-intelligence-policy.schema.json
agent/schemas/external-signal.schema.json
agent/schemas/content-qa-report.schema.json

agent/policies/account-safety.default.json
agent/policies/external-intelligence.default.json

agent/config/account-safety.json
agent/config/account-safety-state.json
agent/config/approvals/.gitkeep
agent/knowledge-base/external-signals/.gitkeep

docs/adr/0003-account-execution-boundary.md
docs/runbooks/account-safety.md
docs/runbooks/external-intelligence.md

ops/verify/checks/35-publish-requires-approval.sh
ops/verify/checks/36-comment-disabled-by-default.sh
ops/verify/checks/37-cron-no-auto-publish.sh
ops/verify/checks/38-disable-throttle-dev-only.sh
ops/verify/checks/39-account-safety-schema.sh
ops/verify/checks/40-no-cookie-in-docs-or-logs.sh
ops/verify/checks/41-external-intel-budget.sh
ops/verify/checks/42-external-signals-no-raw-dumps.sh
```

### 4.2 修改文件

```text
SKILL.md
README.md
UPGRADE.md
docs/architecture.md

agent/playbook/03-daily-flow.md
agent/playbook/04-publish-flow.md
agent/playbook/07-comment-insights.md
agent/playbook/08-compliance.md
agent/playbook/09-troubleshooting.md

agent/scripts/xhs.sh
agent/scripts/import-existing.sh
agent/scripts/db.sh
agent/scripts/preflight.py
agent/scripts/README.md

ops/cron/hermes.yaml.example
ops/cron/claude-code.md
ops/cron/README.md
ops/doctor.sh
ops/verify/pre-submit-verify.sh
ops/verify/checks/README.md
```

## 5. 运行模式体系

新增 `agent/config/account-safety.json`，用于表达用户选择的运行边界。

### 5.1 模式定义

| 模式 | 说明 | 默认 |
|---|---|---|
| `draft-only` | 只选题、起稿、生图、复盘，不发布不评论 | 是 |
| `supervised` | 用户确认后允许发布 | 推荐生产模式 |
| `read-only-research` | 只搜索、拉详情、读评论、分析，不生成发布动作 | 老博主导入前 |
| `ops-maintenance` | 只跑迁移、doctor、preflight、verify | 运维模式 |

### 5.2 默认策略

```json
{
  "mode": "draft-only",
  "publishing_enabled": false,
  "commenting_enabled": false,
  "cookie_import_enabled": true,
  "bulk_import_enabled": false,
  "cron_publish_enabled": false,
  "max_daily_publishes": 1,
  "max_daily_comments": 0,
  "require_approval_for_publish": true,
  "require_approval_for_comment": true,
  "cooldown_on_risk_signal": true
}
```

首次安装后不允许自动发布。用户必须显式切到 `supervised` 并确认发布策略。

## 6. Approval 授权机制

### 6.1 存储位置

```text
agent/config/approvals/
```

该目录是用户态，必须 `.gitignore`。

### 6.2 approval 数据结构

```json
{
  "id": "appr_20260428_153000_abcd1234",
  "action": "publish",
  "resource": "/tmp/xhs-post/meta.json",
  "resource_hash": "sha256:...",
  "created_at": "2026-04-28T15:30:00Z",
  "expires_at": "2026-04-28T16:00:00Z",
  "granted_by": "user",
  "consumed_at": null,
  "status": "granted"
}
```

### 6.3 命令契约

```bash
bash agent/scripts/approval.sh request publish /tmp/xhs-post/meta.json
bash agent/scripts/approval.sh grant <request_id>
bash agent/scripts/approval.sh verify publish /tmp/xhs-post/meta.json --approval-id <approval_id>
bash agent/scripts/approval.sh consume <approval_id>
bash agent/scripts/approval.sh revoke <approval_id>
bash agent/scripts/approval.sh list
```

### 6.4 校验规则

`verify` 必须检查：

1. approval 文件存在。
2. `status == granted`。
3. action 匹配。
4. resource hash 匹配。
5. 未过期。
6. 未消费。
7. 当前 account safety state 不在 `cooldown` / `locked`。

任一失败则拒绝执行。

### 6.5 一次性原则

成功发布或评论后必须调用：

```bash
bash agent/scripts/approval.sh consume <approval_id>
```

同一 approval 不可复用。

## 7. Account Safety 状态机

### 7.1 状态文件

```text
agent/config/account-safety-state.json
```

示例：

```json
{
  "risk_level": "normal",
  "mode": "draft-only",
  "daily_publish_count": 0,
  "daily_comment_count": 0,
  "last_publish_at": null,
  "last_comment_at": null,
  "cooldown_until": null,
  "cooldown_reason": null,
  "last_risk_event": null,
  "updated_at": "2026-04-28"
}
```

### 7.2 风险等级

| 等级 | 允许动作 |
|---|---|
| `normal` | 按 policy 和 approval 执行 |
| `watch` | 允许草稿；发布前强提醒 |
| `cooldown` | 禁止 publish / comment / import-cookie |
| `locked` | 只允许 doctor / preflight / read-only |

### 7.3 风险事件

`xhs.sh` 需要识别响应中的风险信号：

```text
429
captcha
verify
risk
forbidden
blocked
login required
cookie invalid
rate limit
风控
验证
频繁
异常
```

命中后写入：

```json
{
  "event": "risk_signal",
  "tool": "publish_content",
  "hint": "captcha required",
  "created_at": "2026-04-28T15:30:00Z"
}
```

### 7.4 cooldown 规则

自动进入 `cooldown`：

1. 发布失败连续 2 次。
2. 评论失败 1 次。
3. MCP 返回风险关键词。
4. 登录态连续失败。
5. 当天发布数达到上限。
6. 用户手动暂停。

cooldown 期间：

- 允许 search / detail / status。
- 允许生成草稿。
- 允许复盘。
- 拒绝 publish / comment / import-cookie。

## 8. `xhs.sh` 改造

### 8.1 必须 source 路径和公共库

当前 `xhs.sh` 应补齐：

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_paths.sh"
. "$SCRIPT_DIR/_common.sh"
```

### 8.2 publish 门禁

`publish` 参数改为：

```bash
bash agent/scripts/xhs.sh publish /tmp/xhs-post/meta.json --approval-id <id>
```

无 approval 时返回：

```json
{
  "ok": false,
  "error": "approval_required",
  "message": "发布需要用户确认授权。"
}
```

### 8.3 comment 门禁

默认：

```json
{
  "ok": false,
  "error": "comment_disabled",
  "message": "评论默认禁用。请先启用 SHULING_ENABLE_COMMENT=1 并提供 approval。"
}
```

即使启用环境变量，也必须有 approval。

### 8.4 import-cookie 门禁

Cookie 导入需要：

1. 当前不在 cooldown。
2. policy 允许 cookie import。
3. 优先支持 `@file` 输入。
4. 文档不鼓励用户把完整 cookie 贴进长期会话。

### 8.5 节流绕过限制

加入：

```bash
if [ "${XHS_DISABLE_THROTTLE:-0}" = "1" ] && [ "${SHULING_DEV_MODE:-0}" != "1" ]; then
  echo '{"ok":false,"error":"dev_mode_required","message":"禁止在非开发模式关闭节流"}'
  exit 2
fi

if [ "${XHS_DISABLE_QUOTA:-0}" = "1" ] && [ "${SHULING_DEV_MODE:-0}" != "1" ]; then
  echo '{"ok":false,"error":"dev_mode_required","message":"禁止在非开发模式关闭限额"}'
  exit 2
fi
```

## 9. Playbook 改造

### 9.1 `03-daily-flow.md`

修改重点：

- `draft_ready` 只表示草稿完成。
- 输出必须包含“等待用户确认”。
- 不允许调用 `04-publish-flow.md` 自动发布。
- 只允许提示用户：

```text
回复“发”将进入发布授权流程。
```

`writes.emits` 保留 `draft_ready`，但增加说明：

```text
draft_ready is non-mutating and never authorizes publish.
```

### 9.2 `04-publish-flow.md`

修改重点：

- 删除 `draft_ready 事件触发`。
- `when` 改成：

```yaml
when:
  - "用户明确回复'发'"
  - "publish_approved 事件触发"
```

- `preconditions` 增加 approval 校验。
- Procedure 第 2 步改为：

```bash
bash agent/scripts/approval.sh verify publish /tmp/xhs-post/meta.json --approval-id "$APPROVAL_ID"
bash agent/scripts/xhs.sh publish /tmp/xhs-post/meta.json --approval-id "$APPROVAL_ID"
```

### 9.3 `07-comment-insights.md`

修改重点：

- 明确本 playbook 默认只生成回复建议。
- 不自动调用 `xhs.sh comment`。
- 如果用户要求评论：
  - 跳转到 approval flow。
  - 默认提示评论功能未启用。

### 9.4 `09-troubleshooting.md`

新增 Account Safety 故障矩阵：

| 状态 | 行为 |
|---|---|
| approval missing | 引导用户授权 |
| approval expired | 重新生成 request |
| cooldown | 展示原因和恢复时间 |
| locked | 只允许 doctor |
| comment disabled | 提供回复建议，不发出 |

## 10. Cron 改造

### 10.1 Hermes 模板

当前语义：

```yaml
prompt: "使用 shuling skill：执行午间发布流程"
```

改为：

```yaml
prompt: "使用 shuling skill：生成午间候选草稿，等待用户确认，不要发布"
```

建议完整模板：

```yaml
jobs:
  - name: shuling-noon-draft
    schedule: "0 12 * * *"
    skill: shuling
    prompt: "使用 shuling skill：生成午间候选草稿，等待用户确认，不要发布"

  - name: shuling-evening-draft
    schedule: "0 19 * * *"
    skill: shuling
    prompt: "使用 shuling skill：生成晚间候选草稿，等待用户确认，不要发布"

  - name: shuling-review
    schedule: "0 23 * * *"
    skill: shuling
    prompt: "使用 shuling skill：执行夜间复盘，不要发布或评论"

  - name: shuling-weekly-review
    schedule: "0 22 * * 0"
    skill: shuling
    prompt: "使用 shuling skill：执行周日深度回顾，不要发布或评论"
```

### 10.2 Verify

新增 `37-cron-no-auto-publish.sh`，禁止 cron 模板出现：

```text
执行午间发布流程
执行晚间发布流程
自动发布
publish flow
xhs.sh publish
```

允许出现：

```text
生成草稿
等待用户确认
不要发布
复盘
```

## 11. 内容质量与 AI 托管感检查

新增 `agent/scripts/content-qa.py`。

### 11.1 检查目标

不是为了绕过平台，而是避免内容长期机械化、模板化。

### 11.2 检查项

1. 最近 30 篇标题相似度。
2. 连续使用同一标题模板。
3. 正文开头重复。
4. 标签组合重复。
5. emoji 过密。
6. 高频 AI 味词汇。
7. 图片页结构重复。
8. 连续多篇清单体。

### 11.3 输出

```json
{
  "ok": true,
  "score": 82,
  "warnings": [
    "最近 10 篇有 6 篇使用数字清单体",
    "标题开头重复率偏高"
  ]
}
```

`03-daily-flow` 在生成 meta.json 前调用；如果 `score < 70`，要求重写草稿或提示用户确认风险。

## 12. 外部情报智能进化

### 12.1 问题

只靠内部数据，薯灵会越来越懂"这个用户怎么选"，但不会越来越懂"小红书生态正在发生什么"。

内部数据能回答：

- 这个博主喜欢什么选题
- 这个博主拒绝什么风格
- 这个账号历史上什么内容表现好
- 哪些 pattern 应该继续用

但内部数据不能回答：

- 当前赛道有什么新需求
- 同赛道 top 内容在用什么角度
- 哪些标题模板已经过饱和
- 评论区最近反复问什么
- 某个话题是不是正在升温

因此，薯灵要更智能，必须引入外部活水。但外部数据获取本身带来账号风控风险，所以不能做成高频抓取系统。

本计划把外部数据能力定义为：

> **External Intelligence：低频采样、结构化归纳、缓存复用、风险预算、失败降级的外部情报层。**

### 12.2 智能分工

| 智能类型 | 数据来源 | 回答的问题 |
|---|---|---|
| 内部偏好智能 | 用户选择、历史帖、复盘、评论 | 这个博主适合什么 |
| 外部生态智能 | 热点、同赛道内容、评论需求、竞品结构 | 现在市场正在看什么 |

最终选题必须同时满足：

```text
适合这个博主 + 现在值得做 + 还有差异化空间
```

### 12.3 外部数据风险分层

| 层级 | 来源 | 风险 | 默认策略 |
|---|---|---|---|
| L0 | 用户手动提供链接 / 截图 / 导出的榜单 | 最低 | 默认允许 |
| L1 | WebSearch / 新闻 / 节日 / 行业趋势 | 低 | 默认允许 |
| L2 | 小红书低频 search / recommend | 中 | 预算内允许 |
| L3 | 小红书 detail / 少量评论拉取 / top 内容深读 | 中高 | 需要情报预算 + safety normal |
| L4 | 高频批量抓取、全量评论、持续监控 | 高 | v3 禁止，dev mode 才可实验 |

v3 默认只启用 L0-L2。L3 需要：

1. account safety state 是 `normal`。
2. external intelligence budget 足够。
3. 本次 session 未触发风险信号。
4. 采样目标明确，不做无目的浏览。

L4 不进入生产默认能力。

### 12.4 外部情报策略文件

新增：

```text
agent/policies/external-intelligence.default.json
agent/config/external-intelligence.json
```

默认策略：

```json
{
  "mode": "conservative",
  "prefer_user_supplied_sources": true,
  "never_collect_full_comment_history": true,
  "never_store_raw_post_body": true,
  "daily_budget": {
    "search_feeds": 8,
    "list_feeds": 5,
    "get_feed_detail": 15,
    "fetch_comments": 5
  },
  "per_session_budget": {
    "search_feeds": 3,
    "get_feed_detail": 5,
    "fetch_comments": 2
  },
  "cooldown_minutes_after_risk": 1440
}
```

### 12.5 统一入口

新增：

```text
agent/scripts/external-intel.sh
```

命令：

```bash
bash agent/scripts/external-intel.sh research-topic "租房收纳" --budget conservative
bash agent/scripts/external-intel.sh competition-gap "租房收纳"
bash agent/scripts/external-intel.sh comment-demand <note_id> --limit 30
bash agent/scripts/external-intel.sh cache-get "租房收纳"
bash agent/scripts/external-intel.sh cache-prune
```

所有外部情报采样都必须走这个脚本，不允许 playbook 直接散落调用：

```bash
agent/scripts/xhs.sh search ...
agent/scripts/xhs.sh detail ...
agent/scripts/fetch-comments.sh ...
```

`external-intel.sh` 内部再按预算和 safety state 决定是否调用 `xhs.sh`。

### 12.6 采样原则

外部智能不是"抓更多"，而是"小样本高质量归纳"。

默认采样：

1. 每个主题最多 3 个搜索关键词。
2. 每个关键词最多读 5 条搜索结果。
3. 每次最多深读 3-5 条代表性内容。
4. 每次最多抽取 20-30 条评论。
5. 不保存完整原文，只保存摘要信号。

输出结构：

```json
{
  "topic": "租房收纳",
  "observed_at": "2026-04-28",
  "sample_size": {
    "search_results": 12,
    "details": 4,
    "comments": 25
  },
  "competition_density": "medium",
  "common_angles": [
    "小户型收纳",
    "租房党低成本",
    "衣柜分区"
  ],
  "overused_patterns": [
    "10个收纳神器",
    "租房党必买"
  ],
  "comment_demands": [
    "不打孔怎么装",
    "预算100以内",
    "小房间怎么放"
  ],
  "white_space": [
    "按动线整理，而不是按物品整理"
  ],
  "confidence": 0.68
}
```

### 12.7 外部信号缓存

新增：

```text
agent/knowledge-base/external-signals/
```

或 DB 表：

```sql
CREATE TABLE IF NOT EXISTS external_signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    topic TEXT NOT NULL,
    source_type TEXT,
    signal_type TEXT,
    summary TEXT,
    confidence REAL,
    sample_size INTEGER,
    observed_at TEXT NOT NULL,
    expires_at TEXT
);
```

缓存 TTL：

| 信号类型 | TTL |
|---|---|
| 热点趋势 | 1-3 天 |
| 竞品结构 | 7 天 |
| 评论需求 | 7-14 天 |
| evergreen pattern | 30 天 |

同一主题命中缓存时优先使用缓存，不重复请求小红书 MCP。

### 12.8 不保存原始内容

禁止长期保存：

- 完整小红书正文
- 完整评论列表
- 非用户账号的完整画像
- 大量 note 原文快照

允许保存：

- note_id 引用
- 采样数量
- 结构化标签
- 摘要信号
- 置信度
- 过期时间

这是降低风险、降低存储复杂度和避免内容库复制的关键边界。

### 12.9 双因子选题决策

`03-daily-flow.md` 的选题评分应从纯内部偏好升级为内部 + 外部双因子：

```text
final_score =
  0.35 * audience_fit
+ 0.25 * external_momentum
+ 0.20 * competition_gap
+ 0.15 * creator_preference
+ 0.05 * freshness
```

字段说明：

| 字段 | 来源 | 含义 |
|---|---|---|
| `audience_fit` | profile.json | 是否适合账号受众 |
| `external_momentum` | external_signals | 外部是否升温 |
| `competition_gap` | external_signals | 是否还有差异化空间 |
| `creator_preference` | preferences.json / user_choices | 用户是否愿意做 |
| `freshness` | xhs.db posts | 最近是否重复 |

这样薯灵不会只在内部水池里转，也不会盲目追热点。

### 12.10 失败降级

外部情报失败时：

1. 不阻断草稿生成。
2. 降级使用内部 `profile.json`、`preferences.json`、`patterns.md`。
3. 明确标注本轮缺少外部情报：

```text
本轮未获取外部趋势数据，使用账号历史偏好生成候选。
```

命中风险信号时：

1. 停止本次外部采样。
2. 写 account safety risk event。
3. 进入 cooldown。
4. 只保留已获得的摘要信号，不继续请求详情或评论。

### 12.11 Playbook 调整

`03-daily-flow.md`：

- Topic Research 阶段先查 external signal cache。
- cache miss 时调用 `external-intel.sh research-topic`。
- 选题评分使用双因子公式。
- 风险或预算不足时降级内部记忆。

`05-review.md`：

- 复盘时把评论需求转成 external/internal mixed signals。
- 不把评论原文长期存储。

`07-comment-insights.md`：

- 保持评论读取低频。
- 只输出需求信号和回复建议。
- 不自动评论。

`08-compliance.md`：

- 增加外部数据保存边界：只存摘要，不存原文。

### 12.12 Verify

新增：

```text
41-external-intel-budget.sh
42-external-signals-no-raw-dumps.sh
```

检查：

1. `external-intel.sh` 存在。
2. `external-intelligence.default.json` 可解析。
3. daily/per-session budget 不超过 conservative 上限。
4. playbook 不直接散落调用 `xhs.sh search/detail` 做外部研究，必须走 `external-intel.sh`。
5. `agent/knowledge-base/external-signals/` 不包含大体量 raw dump。
6. 外部 signal JSON 不含 `full_body`、`raw_comments`、`full_comments` 等字段。

## 13. Cookie 与 Secret 安全

### 13.1 输入路径

推荐：

```bash
bash agent/scripts/xhs.sh import-cookie @/path/to/cookie.txt
```

不推荐：

```bash
bash agent/scripts/xhs.sh import-cookie '<完整 cookie>'
```

原因：完整 cookie 容易进入对话历史、shell history 或日志。

### 13.2 Doctor 检查

`ops/doctor.sh` 增加：

1. `runtime.env` 权限建议 `600`。
2. `xhs.db` 权限建议 `600`。
3. `agent/config/approvals/` 不可 group/world writable。
4. 检查 git index 中是否存在 runtime 文件。

### 13.3 Verify 扫描

新增 `40-no-cookie-in-docs-or-logs.sh`，扫描：

```text
web_session=
xsec_token
a1=
webId=
Cookie:
sk-
AIza
```

对 `agent/config/runtime.env.example` 中的占位符放行，对真实长串阻断。

## 14. 老博主批量导入保护

### 14.1 问题

`import-existing.sh` 是高读请求场景。即使不写账号，也可能触发异常访问。

### 14.2 改造

1. 默认 `--limit` 从 200 调到 50。
2. 引入 plan/run 模式：

```bash
bash agent/scripts/import-existing.sh plan --limit 200
bash agent/scripts/import-existing.sh run --batch 50
```

3. 每批之间强制 cooldown。
4. `--override-quota` 改名：

```bash
--unsafe-override-quota
```

5. 只允许：

```bash
SHULING_DEV_MODE=1 bash agent/scripts/import-existing.sh --unsafe-override-quota
```

6. 非 TTY 下禁止 unsafe override。

## 15. 工程一致性收口

本次顺带收口 v3 重构后的几个一致性问题：

1. `xhs.sh` source `_paths.sh` / `_common.sh`。
2. `import-existing.sh` 中旧路径 `$SKILL_DIR/scripts/xhs.sh` 改成 `$SHULING_SCRIPTS_DIR/xhs.sh`。
3. `docs/architecture.md` 中 `agent/platform/...` 改成 `docs/runbooks/platform/...`。
4. `VERSION` 是 YAML 元数据，所有脚本只用 `read_version()`，不直接 `cat VERSION`。
5. 如果本版不落地 `throttle.yaml` / `quota.yaml`，文档不要承诺；如果落地，`xhs.sh` 从 policy 读取。

## 16. Verify 门禁扩展

现有 v3 verify 已经到 34 条。本计划新增 35-42：

| # | Check | 目的 |
|---|---|---|
| 35 | publish requires approval | `xhs.sh publish` 无 approval 必须失败 |
| 36 | comment disabled by default | `xhs.sh comment` 默认必须失败 |
| 37 | cron no auto publish | cron 模板不能触发发布 |
| 38 | disable throttle dev only | 非 dev mode 不允许关节流/限额 |
| 39 | account safety schema | policy/state/approval schema 可解析 |
| 40 | no cookie in docs or logs | 阻止 cookie/API key 误提交 |
| 41 | external intel budget | 外部情报策略预算不超过 conservative 上限 |
| 42 | external signals no raw dumps | 外部信号缓存不能保存原文/全量评论 dump |

`ops/verify/pre-submit-verify.sh --strict` 必须跑 42/42。

## 17. 文档改造

### 17.1 新增 ADR

`docs/adr/0003-account-execution-boundary.md`

内容：

1. 为什么 v3.0 后还需要账号执行权收口。
2. 为什么 `draft_ready` 不能触发发布。
3. 为什么 publish/comment/import-cookie 是 privileged mutation。
4. 为什么评论默认禁用。
5. 为什么 cron 默认 draft-only。
6. 为什么这是产品边界，不是文案优化。

### 17.2 新增 Runbook

`docs/runbooks/account-safety.md`

内容：

1. 模式说明。
2. 如何开启 supervised mode。
3. 如何授权一次发布。
4. 如何查看 cooldown。
5. 如何解除 cooldown。
6. 如何安全导入 cookie。
7. 如何安全批量导入历史。

新增 `docs/runbooks/external-intelligence.md`：

1. 外部情报和爬虫的区别。
2. L0-L4 风险分层。
3. 如何配置外部情报预算。
4. 如何解释 external signal 输出。
5. 外部情报失败时如何降级。
6. 为什么不保存原文和全量评论。

### 17.3 README 调整

定位改成：

```text
薯灵是 Stateful Creator Agent：自动完成外部情报采样、选题、起稿、生图、复盘和学习；账号发布与互动默认由用户确认授权。
```

避免：

```text
全自动发布
全自动托管账号
自动评论
```

### 17.4 UPGRADE 调整

写清楚：

1. v3.0 safety hardening 后，`xhs.sh publish` 需要 approval。
2. 评论默认禁用。
3. cron 模板不再发布，只生成草稿。
4. 旧自动化脚本如果直接调用 publish，需要迁移到 approval flow。
5. 外部情报采样新增预算和缓存；旧脚本不能绕过 `external-intel.sh` 高频调用 `xhs.sh search/detail`。

## 18. 实施阶段

### Stage 1: 文档与边界决策

Commit:

```text
docs(v3.0): define account execution boundary
```

改动：

- 新增 ADR-0003。
- 新增本计划文档。
- 更新 README / docs/architecture。

验收：

- 文档明确 `draft_ready != publish_allowed`。
- 文档明确全自动脑 + 人控手。

### Stage 2: Account Safety 数据契约

Commit:

```text
feat(v3.0): add account safety policy and state schemas
```

改动：

- 新增 schemas。
- 新增 default policy。
- `db.sh ensure-runtime-layout` 创建 state 文件。
- `doctor.sh` 读取 safety state。

验收：

- JSON schema parse 通过。
- fresh install 自动生成 account-safety 文件。

### Stage 3: Approval 硬门禁

Commit:

```text
feat(v3.0): require approval for account mutations
```

改动：

- 新增 `approval.sh`。
- 修改 `xhs.sh publish/comment/import-cookie`。
- 修改 04 / 07 / 09 playbook。

验收：

- 无 approval 发布失败。
- approval 过期失败。
- approval hash 不匹配失败。
- approval 使用后不可复用。

### Stage 4: Cron Draft-Only

Commit:

```text
fix(v3.0): make cron draft-only by default
```

改动：

- 修改 `ops/cron/hermes.yaml.example`。
- 修改 `ops/cron/README.md`。
- 修改 `03-daily-flow.md`。

验收：

- cron 模板不含自动发布语义。
- `draft_ready` 不进入 publish。

### Stage 5: Risk Cooldown

Commit:

```text
feat(v3.0): add account safety cooldown
```

改动：

- 新增 `account-safety.sh`。
- `xhs.sh` 识别风险响应。
- `doctor.sh` 展示风险状态。

验收：

- 模拟 429 后进入 cooldown。
- cooldown 下 publish/comment 拒绝。

### Stage 6: External Intelligence MVP

Commit:

```text
feat(v3.0): add external intelligence budgeted sampling
```

改动：

- 新增 `external-intel.sh`。
- 新增 external intelligence policy/schema。
- 新增 `external_signals` 缓存位置或 DB 表。
- 修改 `03-daily-flow.md` 使用双因子选题评分。
- 新增 `docs/runbooks/external-intelligence.md`。

验收：

- cache hit 不重复请求 MCP。
- budget 不足时降级内部记忆。
- 命中风险信号后停止采样并写 cooldown。
- external signal 不保存原文或全量评论。

### Stage 7: Content QA and Secret Safety

Commit:

```text
feat(v3.0): add content QA and secret safety checks
```

改动：

- 新增 `content-qa.py`。
- 新增 cookie/key verify。
- 修改 docs/runbooks/mcp-setup.md。

验收：

- 重复标题/标签能 warn。
- 假 cookie fixture 被 verify 阻断。

### Stage 8: Verify 35-42

Commit:

```text
test(v3.0): add account execution and intelligence safety gates
```

改动：

- 新增 checks 35-42。
- 更新 `pre-submit-verify.sh`。
- 更新 `ops/verify/checks/README.md`。

验收：

- 42/42 通过。
- `--strict` 下 warn 阻断。

## 19. 最终验收清单

- [ ] `bash agent/scripts/xhs.sh publish /tmp/xhs-post/meta.json` 无 approval 时失败。
- [ ] 过期 approval 失败。
- [ ] hash 不匹配 approval 失败。
- [ ] approval 成功使用一次后不可复用。
- [ ] `bash agent/scripts/xhs.sh comment <id> "text"` 默认失败。
- [ ] `SHULING_ENABLE_COMMENT=1` 但无 approval 仍失败。
- [ ] `XHS_DISABLE_THROTTLE=1` 在非 dev mode 失败。
- [ ] `XHS_DISABLE_QUOTA=1` 在非 dev mode 失败。
- [ ] cron 模板不再出现"执行发布流程"。
- [ ] `draft_ready` 不会触发 publish。
- [ ] cooldown 状态下 publish/comment/import-cookie 全部拒绝。
- [ ] `doctor.sh` 能显示 account safety 状态。
- [ ] `content-qa.py` 能识别模板化草稿并 warn。
- [ ] `external-intel.sh research-topic` 能在预算内生成 external signal。
- [ ] external signal cache 命中时不重复请求 MCP。
- [ ] 外部情报预算不足时降级内部记忆，不阻断草稿。
- [ ] 命中风险信号时停止外部采样并进入 cooldown。
- [ ] external signal 不保存 `full_body` / `raw_comments` / `full_comments`。
- [ ] `03-daily-flow.md` 使用内部偏好 + 外部趋势双因子评分。
- [ ] `pre-submit-verify.sh --strict` 42/42 全绿。
- [ ] README 不宣传自动评论 / 自动发布。
- [ ] UPGRADE 写清旧自动化脚本迁移方式。

## 20. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 用户觉得发布多了一步 | 体验变慢 | approval 有效期 30 分钟，一次确认只增加关键动作前的一步 |
| 老自动化脚本被破坏 | upgrade 摩擦 | UPGRADE 给迁移示例，v3.0 支持明确错误提示 |
| AI 仍误调用 publish | 脚本层拒绝 | `xhs.sh` 无 approval 直接 fail |
| 用户强行关节流 | 账号风险 | 非 dev mode 拒绝 |
| 评论能力变弱 | 功能感下降 | 保留回复建议，真实评论需显式开启 |
| cooldown 误伤 | 暂停发布 | doctor 显示原因，支持人工解除 |
| 外部情报采样触发风控 | search/detail/comment 拉取被限制 | 预算化采样、缓存复用、命中风险即停止并 cooldown |
| 外部信号污染账号定位 | 盲目追热点 | 双因子评分，内部 audience_fit 权重最高 |
| external signals 变成内容库复制 | 合规和存储风险 | 只存摘要、标签、样本数、note_id，不存原文和全量评论 |

## 21. 最终定位

优化完成后的产品定位：

```text
薯灵是 Stateful Creator Agent：
自动完成外部情报采样、选题、创作、生图、复盘和学习；
账号发布与互动默认由用户确认授权。
```

能力边界：

| 自动 | 受控 | 默认禁用 |
|---|---|---|
| 外部情报低频采样 | 发布 | 评论 |
| 选题 | Cookie 导入 | 关闭节流 |
| 起稿 | 外部情报 L3 采样 | 关闭节流 |
| 生图 | 批量导入 | 关闭限额 |
| 复盘 | cron 启用 | 高频抓取 |
| 学习 | supervised mode | 全自动账号托管 |

这次优化的本质不是文案调整，而是两件事：

1. 把账号执行权从 agent 的普通能力里拆出来，放进可审计、可授权、可降级的安全边界。
2. 把外部数据获取从"随手抓"改成"预算化情报采样"，让薯灵既能接外部活水，又不退化成高风险爬虫。
