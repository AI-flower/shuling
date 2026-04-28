# 外部情报运行手册（External Intelligence Runbook）

> 适用版本：v3.1.0+（v3.1 Account Safety Hardening 后）。
> v3.0 用户阅读本文是为 v3.1 升级做准备；脚本与命令在 v3.1 Stage 6 落地后才会生效。
>
> 相关：[ADR-0003 账号执行权与外部情报安全边界](../adr/0003-account-execution-boundary.md) ·
> [v3 Account Execution Safety Hardening Plan §12](../plans/v3-account-execution-safety-hardening.md) ·
> [账号安全运行手册](account-safety.md)

## 1. 外部情报 vs 爬虫的区别

外部情报（External Intelligence）和爬虫看上去都在「读小红书」，但两件事根本不同。

| 维度 | 爬虫 | 薯灵的外部情报 |
|---|---|---|
| 目标 | 全量复制 / 持续监控 / 数据资产积累 | 小样本归纳 / 回答具体问题 / 一次性洞察 |
| 频率 | 高频、周期性、自动化 | 低频、按需、命中缓存即停 |
| 存储 | 完整原文 + 完整评论列表 + 用户画像 | 仅摘要信号 + 标签 + note_id 引用 + 置信度 |
| 触发 | 不停跑 | 选题阶段、复盘阶段、用户主动询问 |
| 风险面 | 触发风控 / 数据合规 / 长期监控 | 与人工浏览同量级 |
| 失败处理 | 失败重试到成功 | 命中风险信号即停 + 进入 cooldown |

薯灵的外部情报层定义为：**低频采样、结构化归纳、缓存复用、风险预算、失败降级的外部情报系统**。

## 2. L0-L4 风险分层

外部数据来源按风险等级分五档。v3.1 默认只启用 L0-L2，L3 需要显式条件，L4 在生产模式禁用。

| 层级 | 来源 | 风险 | 默认策略 |
|---|---|---|---|
| L0 | 用户手动提供链接 / 截图 / 导出的榜单 | 最低 | 默认允许 |
| L1 | WebSearch / 新闻 / 节日 / 行业趋势（不经过小红书） | 低 | 默认允许 |
| L2 | 小红书 search / list（关键词级） | 中 | 预算内允许 |
| L3 | 小红书 detail / 少量评论拉取 / top 内容深读 | 中高 | 需要预算 + safety state == `normal` + 本 session 未触发风险 |
| L4 | 高频批量抓取 / 全量评论 / 持续监控 | 高 | v3.x 禁用，仅 `SHULING_DEV_MODE=1` 可实验 |

判定矩阵：

```
L3 是否允许 = (budget.daily_remaining > 0) AND
              (budget.session_remaining > 0) AND
              (account-safety-state.risk_level == "normal") AND
              (本 session 未触发任何风险信号)
```

任一条件不满足即降级到 L0-L2，绝不向 L3 升级。

## 3. 配置外部情报预算

策略文件位置：

- `agent/policies/external-intelligence.default.json`：仓库内默认策略（不可覆盖）
- `agent/config/external-intelligence.json`：用户态 override（可编辑）

默认 conservative 策略：

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

### 3.1 调整预算

```bash
# 推荐：编辑 user override（不会被升级覆盖）
$EDITOR agent/config/external-intelligence.json

# 例如把日 search_feeds 从 8 降到 5：
{
  "daily_budget": {
    "search_feeds": 5
  }
}
# 部分字段会与 default 合并，未指定的字段沿用默认。
```

### 3.2 不可超过的硬上限

无论 user override 怎么写，verify 第 41 条会校验 `agent/policies/external-intelligence.default.json` 的总预算不超过：

| 字段 | 硬上限 |
|---|---|
| `daily_budget.search_feeds` | 15 |
| `daily_budget.get_feed_detail` | 30 |
| `daily_budget.fetch_comments` | 10 |
| `per_session_budget.fetch_comments` | 5 |

超过即 verify fail。`agent/config/external-intelligence.json`（用户态）可以更保守，不能更激进。

## 4. 解释 external signal 输出

`external-intel.sh research-topic` 的输出统一结构：

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

字段含义：

| 字段 | 用途 |
|---|---|
| `sample_size` | 本次实际采样数量；用于评估置信度 |
| `competition_density` | 该主题的内容密度（low / medium / high）；high 说明红海，需要切角度 |
| `common_angles` | 当前主流的内容角度；用作避坑参考 |
| `overused_patterns` | 已被过度使用的标题/结构；写新稿时回避 |
| `comment_demands` | 评论区反复提出的具体问题；最强差异化机会信号 |
| `white_space` | 算法识别的尚未被覆盖的角度；高价值但需要 confidence 二次校验 |
| `confidence` | 本次归纳的可信度（0-1）；< 0.5 时建议人工复核 |

03-daily-flow 的双因子选题评分公式：

```text
final_score =
  0.35 × audience_fit
+ 0.25 × external_momentum
+ 0.20 × competition_gap
+ 0.15 × creator_preference
+ 0.05 × freshness
```

`external_momentum` 与 `competition_gap` 都来自 external signal。`audience_fit` 仍占最大权重——薯灵不会因为外部很火就放弃账号定位。

## 5. 失败降级

外部情报采样不是发布阻塞条件。一旦失败，03-daily-flow 不停止，只是切换到内部信号。

### 5.1 降级触发条件

| 触发 | 行为 |
|---|---|
| `external-intel.sh` 返回 non-zero | 草稿生成继续，标注「本轮未获取外部趋势数据」 |
| daily_budget 耗尽 | 优先读缓存；缓存 miss 时降级 |
| per_session_budget 耗尽 | 同上 |
| MCP 返回风险关键词 | **立即停止本次外部采样** + 写 risk event + 进入 cooldown |
| safety state 不是 `normal` | 不发起 L3 采样，只用 L0-L2 + 缓存 |

### 5.2 降级输出标注

降级路径下 03-daily-flow 在草稿元数据里加：

```json
{
  "external_intelligence": {
    "available": false,
    "fallback_reason": "budget_exhausted",
    "fallback_source": "internal_profile + preferences + patterns"
  }
}
```

AI 在向用户展示草稿时必须明确说明「本轮无外部情报」，**不允许伪装成有外部数据**。

### 5.3 风险信号触发的特殊路径

如果 MCP 调用过程中收到 429 / captcha / 风控 / 频繁 / 异常等关键词：

1. `external-intel.sh` 立即终止本次采样
2. 已获得的部分摘要信号仍可使用（不是丢弃）
3. 写 `account-safety-state.json` 的 `last_risk_event`
4. 进入 `cooldown`（默认 24 小时）
5. 09-troubleshooting.md 提示用户

cooldown 期间外部情报降级到 L0-L1（用户提供 + WebSearch），不再访问小红书。

## 6. 为什么不保存原文和全量评论

### 6.1 三个理由

1. **风险面**：长期保存全量评论 / note 原文等于建立外部内容数据库，触碰平台 ToS 与数据合规底线。
2. **存储复杂度**：v3 单 SQLite 文件设计不适合存大量第三方原文；ADR-0001 的 v4.0 退出条件之一就是「数据规模超过 SQLite 单文件能力」，保存原文会快速触发这个条件。
3. **价值密度**：薯灵需要的是「这个主题现在的需求/角度/红海度」，不是「这条笔记当时怎么写的」。前者归纳后是 200 字摘要，后者是 5KB 原文。归纳出的摘要复用率远高于原文。

### 6.2 允许保存的字段

`agent/knowledge-base/external-signals/` 或 `external_signals` DB 表只保存：

- `note_id`（小红书原内容引用，不存正文）
- `topic`（采样主题）
- `signal_type`（angle / pattern / comment_demand / white_space）
- `summary`（≤ 200 字摘要）
- `confidence`（0-1）
- `sample_size`（采样数量）
- `observed_at` / `expires_at`

### 6.3 禁止保存的字段（verify 第 42 条强制）

- `full_body` / `body_text` / `content`（笔记正文）
- `raw_comments` / `full_comments` / `comments_list`（完整评论）
- `cookies` / `tokens` / `auth_*`（任何凭证字段）
- 任何超过 200 字的非 summary 字段

verify 第 42 条扫描 `agent/knowledge-base/external-signals/*.json` 与 `external_signals` 表，命中即 fail。

### 6.4 缓存 TTL

| 信号类型 | TTL | 理由 |
|---|---|---|
| 热点趋势 | 1-3 天 | 时效性强 |
| 竞品结构 | 7 天 | 中期变化 |
| 评论需求 | 7-14 天 | 用户需求变化慢 |
| evergreen pattern | 30 天 | 长期有效 |

过期后由 `external-intel.sh cache-prune` 清理（推荐每周跑一次，或由 cron 触发）。

## 7. 命令速查

```bash
# 主题研究（cache 优先 + 预算化采样）
bash agent/scripts/external-intel.sh research-topic "租房收纳" --budget conservative

# 竞品差异化分析（只读 search + list）
bash agent/scripts/external-intel.sh competition-gap "租房收纳"

# 评论需求提炼（限制条数，不存原文）
bash agent/scripts/external-intel.sh comment-demand <note_id> --limit 30

# 缓存命中查询（不发起请求）
bash agent/scripts/external-intel.sh cache-get "租房收纳"

# 清理过期缓存
bash agent/scripts/external-intel.sh cache-prune

# 查看预算余额
bash agent/scripts/external-intel.sh budget-status
```

所有命令在 v3.1 Stage 6 后落地。所有 playbook 必须通过 `external-intel.sh` 入口访问外部数据，不允许 03/05/07 直接散落调用 `xhs.sh search/detail`（verify 第 41 条强制）。
