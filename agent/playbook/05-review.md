---
id: 05-review
title: Daily Review and Weekly Recap
when:
  - "夜间 cron 触发复盘"
  - "用户说'看看昨天的数据'"
  - "用户说'复盘'"
  - "周日加餐周深度回顾"
needs:
  required:
    - agent/knowledge-base/preferences.json
    - agent/knowledge-base/patterns.md
    - agent/knowledge-base/anti-patterns.md
  optional:
    - agent/knowledge-base/business-profile.json
    - agent/knowledge-base/business-patterns.md
    - agent/knowledge-base/business-anti-patterns.md
    - agent/knowledge-base/asset-ledger.md
    - agent/knowledge-base/creator-behavior-signals.md
  fallback:
    business-profile.json: business_attribution_review 段降级到 unknown;sales/lead 信号一律标 unknown,不参与 next_action 决策
    business-patterns.md: 仅写 patterns.md;business pattern 此次 review 跳过晋级
    business-anti-patterns.md: 跳过 anti-pattern 写入,日报标注 anti-pattern update skipped
    asset-ledger.md: 跳过 Asset Ledger Update 段,日报标 asset write degraded,不阻塞 metrics 采集
    creator-behavior-signals.md: 跳过 Behavior Signal Roundup 段,只输出业务归因和资产沉淀
  db_tables:
    - posts
    - post_metrics
    - comment_insights
    - note_diagnosis
    - business_reviews
    - content_assets
    - creator_behavior_signals
  env_vars:
    - NOTERX_API_KEY
calls:
  scripts:
    - agent/scripts/db.sh
    - agent/scripts/fetch-post-data.sh
    - agent/scripts/noterx-diagnose.sh
    - agent/scripts/external-intel.sh
  playbooks:
    - 06-learning-loop.md
    - 07-comment-insights.md
    - 09-troubleshooting.md
writes:
  files:
    - agent/knowledge-base/evolution-log.md
    - agent/knowledge-base/reviews/<YYYY-W##>.md
    - agent/knowledge-base/patterns.md
    - agent/knowledge-base/anti-patterns.md
    - agent/knowledge-base/asset-ledger.md
    - agent/knowledge-base/business-patterns.md
    - agent/knowledge-base/business-anti-patterns.md
preconditions:
  - state.setup_completed == true
on_failure:
  - 09-troubleshooting.md
version: 3.2.0
last_updated: 2026-04-28
---

# 05 Daily Review and Weekly Recap

## Trigger

- hermes cron 夜间（建议 22:00）触发复盘
- 用户主动说"复盘一下" / "看看昨天的数据" → 立即跑
- 周日复盘加餐：在每日复盘后追跑一次"周深度回顾"

## Read This When

需要把当天发布帖子的真实表现回写到知识库；需要决定明天创作策略时；需要给用户一份日报/周报时。

## Inputs

- `posts` 表（今日 `source='shuling'` 的发布帖；imported 不纳入）
- `post_metrics`（互动数据）
- `note_diagnosis`（NoteRx 五维诊断结果）
- `generated_images`（图片维度分析）
- `agent/knowledge-base/preferences.json` / `patterns.md` / `anti-patterns.md`

## Procedure

### Daily Review

每天晚上执行。目标：拉今天发的所有帖子的真实数据 + 第三方诊断分数 → 大脑综合判断 → **当晚立即更新** patterns/rules，让明天的创作变得更聪明。

1. **查询今日已发布的帖子**

   ```bash
   bash agent/scripts/db.sh query-posts --today --status published
   ```

   返回 JSON 数组，每条含 `id, note_id, title, topic_type, title_pattern, content_style`。仅 `source='shuling'`（imported 不纳入复盘）。

2. **逐篇拉互动数据**

   ```bash
   bash agent/scripts/fetch-metrics.sh <post_id> <note_id>
   ```

   脚本已写入 `post_metrics` 表，并把 `{likes, saves, comments, shares}` 回吐。

3. **逐篇提炼评论需求**（v3.1+：走 `external-intel.sh`，不直调 `fetch-comments.sh`）

   ```bash
   # external-intel.sh 内部走 xhs.sh detail 拉评论 + 提需求高频词，不存评论原文
   bash agent/scripts/external-intel.sh comment-demand <note_id> --limit 30
   ```

   返回 `comment_demands` 摘要（高频提问 / 吐槽 / 选题信号）+ note_id 引用 + sample_size + confidence；**禁存评论原文**（schema 硬禁 `raw_comments`，verify 42 强制）。详见 07-comment-insights.md + → `docs/runbooks/external-intelligence.md`。

4. **逐篇 NoteRx 诊断**

   先查是否已诊断过：

   ```bash
   bash agent/scripts/db.sh query-diagnosis --post-id <id>
   ```

   返回空数组就跑：

   ```bash
   bash agent/scripts/noterx-diagnose.sh <post_id> "<title>" \
       --content "<正文>" --tags "标签1,标签2" \
       --category tech --image-count 6
   ```

   返回 5 维评分 + grade（S/A/B/C/D）+ issues（仅 `--full` 时有）+ suggestions。脚本已写入 `note_diagnosis` 表。

   **--full 决策**：默认只跑 pre-score（< 50ms 零成本）。**只在帖子收藏率 ≥ 5% 或 ≤ 1%（极好极差两端）时**追加 `--full` 拿详细 issues，避免 token 浪费。

5. **综合分析（自己想）**

   把上面 3 份数据合在一起，对每篇帖子回答：

   - 收藏率 = saves / max(likes, 1)
   - 真实表现 vs NoteRx 预测分是否对齐？偏差大说明 NoteRx 在这个领域的校准需要修正
   - 评论里反复出现的痛点 → 是否值得变成新选题
   - NoteRx 给的 issues 里，哪些是 **结构性问题**（如"标题缺少数字钩子"），哪些是 **本帖特殊**？结构性问题应该回写到 patterns.md
   - **图片维度**：从 `generated_images` 拉本帖所有 prompt + 比对 NoteRx 的 `visual_score`：
     ```bash
     sqlite3 agent/data/xhs.db "SELECT image_index, prompt FROM generated_images WHERE post_id=<id> ORDER BY image_index;"
     ```
     - `visual_score ≥ 80` 且收藏率正常 → 该帖的 prompt 共性提炼为新 image pattern
     - `visual_score ≤ 40` → 该帖的 prompt 反模式，记入 image-anti-patterns
     - 评论里有人吐槽图（"封面太花/字太多/看不清"）→ 立即标 anti-pattern

6. **当晚更新知识库**（"每天进化"的核心，不要攒到周末）

   - **`patterns.md`**：收藏率 ≥ 5% 的帖子标题/正文 pattern 没记录就追加；活跃 ≤ 15 条；晋级/降级数值阈值见 06-learning-loop.md
   - **`preferences.json`**：weight ±0.1（公式权威 → 06-learning-loop.md）；同步重新计算 confidence_level
   - **`image-patterns.md`**（如有图片信号）：visual_score ≥ 80 → 提炼共性，confidence 从 experimental 起；连续 3 次 visual_score ≥ 75 → 升级；连续 3 次 ≤ 50 → 移到 image-anti-patterns；活跃 ≤ 10 条
   - **`evolution-log.md`**：追加一段，包含：日期 / 改了什么（含图片维度）/ 为什么改 / 数据依据

## Business Attribution Review（v3.2+，plan §5.6 / §7.7 / §8.1 — 业务归因复盘）

> 本节在第 6 步知识库更新之后**先做归因**，再做下面的 Asset Ledger Update（先归因后沉淀，避免归因结论丢失）。**LLM 在 playbook 内执行**：读 `posts / post_metrics / comment_insights / note_diagnosis`，组装 `business_reviews` JSON，调 `db.sh add-business-review` 落库。**不调外部 API**。

### 7 类业务信号（plan §5.6.1）

每篇当天发布的帖子，对照下表给出 7 个 `signalLevel ∈ {high, normal, low, unknown}`：

| 信号 | 字段 | 含义 |
|---|---|---|
| 流量信号 | `traffic_signal` | 浏览量 / 互动量是否进入账号本周 top 30%（excellent）、中位（normal）、明显低于历史（low） |
| 收藏信号 | `save_signal` | 收藏率 ≥ 5% = high；2-5% = normal；< 2% = low |
| 信任信号 | `trust_signal` | 评论里是否出现「跟着学」「受用」「关注了」「讲得真懂」类**多次**正向叙述（≥ 2 条原话评论） |
| 咨询信号 | `lead_signal` | 私信 / 评论求联系方式 / 求模板 / 求咨询入口出现次数 |
| 购买信号 | `sales_signal` | 评论或私信中出现明确购买/报名/付费意图原话 |
| 争议信号 | `controversy_signal` | 评论里出现「割韭菜」「广告吧」「误导」类反对/质疑 |
| 无效互动 | `traffic_signal=high + save/trust/lead/sales 全部 low` | 高流量但所有业务信号都低 → 见 §5.6.5 反模式规则 |

### 12 类归因维度（plan §5.6.2）

每篇帖子选一条**主归因** `main_attribution`（enum 必须命中以下之一）：

`topic` / `title` / `cover` / `opening` / `content_depth` / `format` / `benchmark` / `offer` / `audience` / `conversion_path` / `timing` / `unknown`

**evidence_level 硬规则（plan §5.6.2 末尾 — Stage 11 核心硬规则）**：

- `evidence_level ∈ {hard, medium, weak, unknown}`：
  - `hard` = 同时有 metrics + comment 原话 + （可选）DM 截图佐证
  - `medium` = metrics + 至少 1 条 comment / DM 原话佐证
  - `weak` = 仅 metrics 趋势或仅 LLM 推断
  - `unknown` = 数据不足
- **`sales_signal` 和 `lead_signal` 在 `evidence_level ∈ {weak, unknown}` 时不允许标 `high`**——这是 schema 层硬规则（business-review.schema.json `lead_signal / sales_signal` 字段 description），写入前必须自检。命中即降级到 `medium`，否则 `db.sh add-business-review` 落库虽然不会报错（DB 没做约束），但 verify 会拒。**没有 hard/medium 证据，sales/lead 一律不能高。**
- `evidence[]` 数组：每条至少一个 `{type, source, weight}`，`type ∈ {metrics, comment, dm, manual, llm_inference}`，`weight ∈ {high, medium, low}`。

### 4 个复盘规则示例（plan §5.6.5）

复盘时按下列 4 条**反模式规则**优先识别（命中即直接给 `business_interpretation` + `next_action`，省一轮推理）：

| 命中条件 | 归因（main_attribution） | business_interpretation | next_action |
|---|---|---|---|
| `save_signal=high` 且 `lead/sales/trust 全部 low` | `content_depth` | 知识收藏型内容：用户收藏但无下一步意图，离付费路径远。可作为涨粉/品牌信任内容保留，**不**作为转化 pattern 晋级 | 下次同主题加一个明确行动入口（「想要模板评论区扣 1」/「私信发表格」），用一次实验把该选题从 anti-pattern 转为 pattern |
| `traffic_signal=low` 且 `lead_signal=high` 或评论求模板/咨询 ≥ 1 | `audience` 或 `conversion_path` | 低流量高意图：受众虽小但需求精准，是潜在变现入口 | 沉淀 `audience_language` / `offer_signal` 资产；下次出 1 条专门服务该受众的进阶内容 |
| `controversy_signal=high` 且 `trust_signal=low` | `opening` 或 `audience` | 高争议低信任：开头/选题与受众预期错位，引发质疑而非共鸣 | 24h 内**不**写入 anti-pattern（避免一时情绪噪音变长期反模式）；72h 后再看评论走势复审 |
| `traffic_signal=high` 且 `lead/sales/trust 全部 low` 且 `save_signal` 也低 | `topic` 或 `audience` | 高流量低关注：吃了平台流量分发，但内容与目标受众无关 | `business-anti-patterns.md` 追加；下次该 topic_type 推荐降权 |

写入业务模式时**只引用可观察事实**（评论原话、收藏率、私信次数），**不**写「用户害怕成功」等心理判断（08-compliance.md `Behavior Signal Output Validation` 同款禁词清单也适用此处文案）。

### 写入双轨（DB + MD）

每篇帖子归因完成后，**同时**写入 DB（程序查）+ MD（人读）：

```bash
# 1) 落 DB（business_reviews 表，Wave 1 已建命令；evidence_level / confidence / evidence[] 已支持）
bash agent/scripts/db.sh add-business-review '{
  "post_id": 123,
  "reviewed_at": "2026-04-28",
  "performance_tier": "mixed",
  "traffic_signal": "normal",
  "save_signal": "high",
  "trust_signal": "low",
  "lead_signal": "low",
  "sales_signal": "low",
  "controversy_signal": "low",
  "main_attribution": "content_depth",
  "evidence_level": "medium",
  "evidence": [
    {"type": "metrics", "source": "post_metrics:123", "weight": "high"},
    {"type": "comment", "source": "comment_insights:123", "weight": "medium"}
  ],
  "confidence": "medium",
  "business_interpretation": "知识收藏型内容；高收藏 + 无下一步意图，离付费路径远",
  "next_action": "next_post_add_offer_cta"
}'
```

```markdown
# 2) 同步追加到 agent/knowledge-base/business-patterns.md（达成 pattern）或 business-anti-patterns.md（高流量低价值 / 泛干货 / 错受众等）

## review_20260428_post123_high_save_low_lead

- post_id: 123
- main_attribution: content_depth
- signals:
  - save_signal: high
  - lead_signal: low
  - sales_signal: low
- evidence_level: medium
- interpretation:
  收藏率高 + 评论无下一步意图 → 知识收藏型内容
- next_action:
  下次同主题加一个明确行动入口（「想要模板评论区说模板」），用一次实验把该选题从 anti-pattern 转为 pattern
- created_at: 2026-04-28
```

**写入硬规则**：

- `evidence_level` **必填**（schema required）；缺失 → `db.sh add-business-review` 失败，转 → 09-troubleshooting `business review 写入失败` 行
- `sales_signal=high` 或 `lead_signal=high` 时，`evidence_level` **必须** ∈ `{hard, medium}`，否则降级为 `medium`/`normal`
- 写入失败**不阻塞日报**（plan §7.11 / 09-troubleshooting.md `business review 写入失败` 行）：在 evolution-log.md 标记 `degraded: business review write failed`，继续完成 daily review

### 业务 pattern 不进入 06 confidence 算法（plan §6.3 方案 A）

业务归因结论只影响：
- `business-patterns.md` / `business-anti-patterns.md` 文件（人读 + 下次选题打分参考）
- `business_reviews` 表（程序查 + 周报抽离）
- 03-daily-flow.md 选题打分时的 `goal_alignment_score / monetization_distance_score` 输入

**不**直接修改 `preferences.json` 的 weight / confidence_level（详见 → 06-learning-loop.md `## v3.2 Business Pattern Boundary`）。

### 用户日报输出格式（plan §5.6.6）

用户看到的不是 JSON，而是简明业务归因段（每条帖子 1-3 句，自然语言）：

```text
📊 今日业务归因（2026-04-28）

「30 天 0 起色，是不是赛道选错」
  收藏 92 / 互动平稳 / 评论 4 条求模板（lead_signal=high；evidence=medium）
  → 这条把目标读者带到了"想要进一步动作"的位置；下次直接给一个清晰的下一步入口（如评论区扣 1 发模板）。

「7 个普通人小红书必看的工具」
  收藏 184 / 互动正常 / 但 0 条求咨询、0 条求购买
  → 知识收藏型内容（save_signal=high, lead/sales=low）。涨粉有效，但离变现远。
  → 下次同主题加 CTA 做 A/B 验证，看能否从 anti-pattern 转 pattern。
```

不要把整个 JSON dump 给用户。

## Asset Ledger Update（v3.2+，plan §5.8 / §7.7）

> 本节在 Business Attribution Review 之后执行。**慢做环节**（plan §5.8.5 慢方法审计）：每条 asset 必须能说明 `reuse_plan`，避免台账变垃圾桶（plan §12.8 风险缓解）。

### 何时沉淀 asset

每篇当天发布的帖子，跑完上面 5 步综合分析后，对照下面 10 类资产判断（plan §5.8.4）：

| 资产类型 | 触发条件（业务信号） | 写入字段重点 |
|---|---|---|
| `topic_seed` | 评论/私信/复盘出现新选题候选 | `content` = 候选标题 + 来源；`reuse_plan` = 下次选题时引用 |
| `series_arc` | 单篇帖能扩展出 3-5 条系列 | `content` = 系列骨架；`reuse_plan` = 下次 build_trust 选题时拉链 |
| `title_evidence` | 某 `formula_id` / `trigger` 被发布数据验证（如收藏率 ≥ 5% + lead_signal=high） | `content` = 公式 + 命中场景；`reuse_plan` = 影响 03-daily-flow 标题候选排序 |
| `audience_language` | 评论原话准确描述目标读者痛点 | `content` = 用户原话；`reuse_plan` = 下次开头 / 封面措辞 |
| `faq` | 高频问题（同类问题被 ≥ 3 次提出） | `content` = 问题；`reuse_plan` = 转成教程/答疑/直播脚本 |
| `case` | 自己或用户的具体案例可复用 | `content` = 案例摘要；`reuse_plan` = 增强 human_signal |
| `objection` | 用户不买/不信的理由 | `content` = 反对意见；`reuse_plan` = 服务转化内容 |
| `offer_signal` | 用户明确想要模板/咨询/产品 | `content` = 索要原话；`reuse_plan` = 更新 business-profile.offer 假设 |
| `benchmark_insight` | 对标账号可模仿的具体动作 | `content` = 动作描述；`reuse_plan` = 更新 benchmarks/<id>.json |
| `workflow_rule` | 验证过的创作/复盘规则 | `content` = 规则；`reuse_plan` = 更新 playbook/knowledge-base 文档 |

### 写入双轨

每条沉淀的资产，**同时**写入 DB（程序查）+ MD（人读）：

```bash
# 1) 写 DB（content_assets 表，由 v3.2 migration 建好）
bash agent/scripts/db.sh add-content-asset '{
  "id": "asset_20260428_audience_language_no_result",
  "asset_type": "audience_language",
  "source": {
    "post_id": 123,
    "comment_id": null,
    "benchmark_id": "",
    "manual_note": "评论区原话"
  },
  "content": "发了 30 条还是没起色，不知道是标题问题还是方向问题",
  "why_it_matters": "目标读者描述痛点的原话，比「账号运营困难」更适合放进开头/封面",
  "reuse_plan": "下次 build_trust 选题用作开头场景；可扩成「如何判断没起色」系列",
  "confidence": "medium",
  "created_at": "2026-04-28"
}'
```

```markdown
# 2) 同步追加到 agent/knowledge-base/asset-ledger.md（人类可读，section 格式见 plan §9.4）

## asset_20260428_audience_language_no_result

- type: audience_language
- source: comment / post_id=123
- confidence: medium
- content:
  "发了 30 条还是没起色，不知道是标题问题还是方向问题"
- why_it_matters:
  目标读者描述痛点的原话，比「账号运营困难」更适合放进开头或封面。
- reuse_plan:
  下次 build_trust 选题可用作开头场景；也可扩展成「如何判断没起色的原因」系列。
- created_at: 2026-04-28
- last_used_at: null
```

### Asset 沉淀硬规则

- **每条 asset 必须有 `reuse_plan`**——不能只描述「这是个素材」，必须说清下次怎么复用（plan §12.8 风险缓解）
- **schema 校验**：写入前必须符合 `agent/schemas/content-asset.schema.json`（08-compliance.md `Schema Validation` 强制）
- **confidence 起点**：单一来源 / 语义推测 = `low`；单次明确信号 = `medium`；多次出现 / 经过发布验证 = `high`
- **`asset_type` 必须是 enum 内 10 类**之一；不要造新类型
- **写入失败不阻塞日报**：`add-content-asset` 失败 → 在 evolution-log.md 标记 `degraded: asset-ledger write failed`，继续完成 daily review

### 与 03-daily-flow.md 的接续

资产沉淀后，下次 03-daily-flow.md §2.1 第 5 步打分时：

- `query-content-assets --type <type> --days 30` 可查到本资产 → `asset_score_mode` 从 `prediction` 升级到 `evidence`
- `related_asset_ids` 可引用本资产 ID
- 这是「慢方法复利」的核心闭环（plan §5.8.6）

7. **生成日报输出**

   ```
   📊 今日数据（2026-04-17）

   午间「标题A」: ❤️ 89  ⭐ 132  💬 15
       NoteRx: B 76 (内容 80 / 视觉 75 / 增长 70 / 反应 78)
   晚间「标题B」: ❤️ 203  ⭐ 47   💬 8
       NoteRx: A 82 (内容 85 / 视觉 80 / 增长 78 / 反应 84)

   💡 今日洞察
   - 「标题A」收藏率 148%，清单类内容继续验证有效
   - 「标题B」NoteRx 评分高但实际收藏率低，可能 NoteRx 校准在这个细分场景偏乐观
   - 评论里有 4 人问"怎么安装 X"，明天可以做一篇手把手教程

   🧬 知识库更新
   - patterns.md：「数字+痛点」标题 confidence experimental → medium
   - preferences.json：tech-tools weight 0.65 → 0.75

   📈 本周累计：发布 8 条 | 总赞 1.2k | 总收藏 890
   ```

   **不要在日报里包含"@用户"或"telegram://"等渠道字样**——hermes 自己负责送达。

### Content Effect Analysis

每日复盘时，对每篇今日帖子：

1. 从 DB 读取元数据（topic_type / title_pattern / content_style）
2. 从 DB 读取互动数据（likes / saves / comments）
3. 计算收藏率 = saves / max(likes, 1)

业务规则（数值阈值仅作为业务边界，权重调整公式权威 → 06-learning-loop.md）：

- **收藏率 ≥ 5%** → 表现优秀：标题模式进 `patterns.md`（confidence: experimental），对应 weight 上调（详见 06）
- **收藏率 2-5%** → 表现正常，不做调整
- **收藏率 < 2%** → 表现较差：weight 下调（详见 06）；同类型连续 3 次 < 2% → 进 `anti-patterns.md`

weight ±0.1 的具体公式与 confidence_level 的重算逻辑：见 06-learning-loop.md（不复述）。

### Comment Demands → External Signals (v3.1+)

复盘第 3 步「拉评论原文」+ 第 5 步「综合分析」之后，把评论里反复出现的需求**转成结构化 external signal**，供下一轮选题（03 §2.1 第 0 步）双因子打分使用。**不存评论原文**。

```bash
# 不直接调 fetch-comments.sh 做需求归纳；统一走 external-intel.sh comment-demand
bash agent/scripts/external-intel.sh comment-demand <note_id> --limit 30
```

`external-intel.sh comment-demand` 输出：

- 写到 `agent/knowledge-base/external-signals/<hash>.json`（仅摘要 + note_id 引用 + sample_size + confidence；禁字段 `full_body / raw_comments / full_comments`）
- 命中风险信号即停 + 写 `account-safety-state.last_risk_event`（详见 → `docs/runbooks/external-intelligence.md`）

**边界**：

- 复盘**不**把评论原文长期存储到 `comment_insights` 之外的位置
- 写 `comment_insights` 时只存提炼后的高频提问 / 吐槽 / 选题信号（v3.0 已有契约），不写整段评论
- 评论需求 → external_signals 的转换是**一次性**的；复盘完成后只保留 signal，不保留中间评论

### Weekly Recap

每周日的复盘流程中，作为日常复盘的"加餐"。

**与每日复盘的区别**：每日复盘已经做了 patterns/rules 的实时调整。周回顾不再做硬调整，而是**抽离出一周的全景**给用户看：方向是否在收敛、有哪些反复出现的高频问题、要不要换打法。

**步骤**：

1. **读 evolution-log.md**：获取本周追加的所有变更
   ```bash
   tail -200 agent/knowledge-base/evolution-log.md
   ```

2. **导出本周数据**
   ```bash
   bash agent/scripts/db.sh query-posts --days 7
   ```
   对每篇帖子拉历史 metrics：
   ```bash
   bash agent/scripts/db.sh query-metrics --post-id <id>
   ```

3. **跨日整合分析**（自己做）
   - 哪种 topic_type + content_style 组合本周表现最稳定？
   - 哪些 pattern 已经被反复验证可以晋升 high？
   - 用户在评论区是否有积累的需求未满足？
   - NoteRx 评分与实际收藏率的相关性如何？是否存在"NoteRx 系统偏差"应该被你内化？

4. **写入周快照**：`agent/knowledge-base/reviews/<YYYY-W##>.md`

   v3.2+ 周报必须包含**业务经营 4 段**（plan §7.7 — 在原有"收敛信号 / 待验证 / 用户需求积压 / NoteRx 校准"基础上增列）：

   ```markdown
   # 2026-W17 周回顾

   ## 一句话总结
   本周发布 14 条，最稳定方向是 `tech-tools` + `清单体`。

   ## 收敛信号
   - 「数字 + 痛点」标题已连续 5 次收藏率 ≥ 5% → 升 high

   ## 待验证
   - 反差悬念体试了 2 次效果分化，下周再观察 1 次

   ## 用户需求积压
   - 8 条评论问"安装步骤"，下周必出一条手把手教程

   ## NoteRx 校准
   - tech 品类下 NoteRx 系统性偏低 ~5 分，明天起人为加权

   ## 本周业务信号（v3.2+，business_reviews 聚合 — plan §7.7）
   - lead_signal=high 的帖子：3 条（全部 `evidence_level=medium`）
   - sales_signal=high 的帖子：0 条
   - controversy_signal=high 的帖子：1 条（已挂 24h 观察）
   - high_save_low_lead 帖子：4 条 → 偏向收藏型内容，本周变现路径未拉近

   ## 本周最高价值内容（v3.2+ — plan §7.7）
   - 「30 天 0 起色，是不是赛道选错」: lead_signal=high + 评论 4 条求模板（evidence=medium）
     → 沉淀资产：audience_language ×1、offer_signal ×1
     → 下周复用方向：拓 1 条「如何判断没起色」系列，结尾配模板私信 CTA

   ## 高流量低价值内容（v3.2+ — plan §7.7）
   - 「7 个普通人小红书必看的工具」: 收藏 184 / 但 0 求咨询、0 求购买（save=high, lead/sales=low）
     → 已写入 `business-anti-patterns.md` 作为「高流量低价值」候选
     → 处置：保留作为涨粉/品牌信任内容，但下次同主题加 CTA 做 A/B 验证

   ## 下周账号经营动作（v3.2+ — plan §7.7）
   - 把"求模板"信号转成 1 个明确 offer 入口（评论扣 1 / 私信关键词）
   - 出 1 条对标账号已验证、本账号还没碰过的转化型选题
   - 不再扩增"百科式工具盘点"频道（高流量低价值已 2 次命中）
   ```

5. **生成周报输出**

   ```
   📈 本周成长报告（W17 / 2026-04-12 ~ 2026-04-18）

   发布 14 条 | 总赞 2.1k | 总收藏 1.5k | 粉丝 +47

   🏆 最佳：「小户型收纳的 5 个省空间办法」收藏率 9.1%
      → 清单体 + 每个方法写了"替你省哪一步"
   📉 最差：「收纳盒怎么选」收藏率 0.8%
      → 百科式开头，用户第一屏看不到"跟我有什么关系"

   🧬 你正在形成的风格（已写入 agent/knowledge-base/）
   - 受众最吃"方法清单 + 场景化推荐"（连续 3 周验证）
   - "避坑"类标题点击率高但转化低
   - 你偏好选实操教程类 > 单品种草类

   🎯 下周建议
   - 继续清单体（已晋升 high confidence）
   - 出一条回应评论高频需求的手把手教程
   - 「反差悬念体」再试 1 次再决定保留/淘汰
   ```

## Behavior Signal Roundup（v3.2+，plan §5.7 / §7.7 / §9.5 — 执行摩擦诊断尾部段）

> 本节在每日复盘和周报输出**之后**执行（不阻塞前面的归因 / 资产 / 周报段）。复盘结束前对**近 7 天** `creator_behavior_signals` 表做一次扫描，命中信号在日报末尾输出"行为观察"段，并按需追加到 `creator-behavior-signals.md`。

### 触发逻辑

```bash
# 拉近 7 天行为信号
bash agent/scripts/db.sh query-creator-behavior-signals --days 7 --limit 20
```

> 03-daily-flow.md 的 `## Execution Friction Fallback` 是**当次会话即时**写入信号（`signal_type ∈ {planning_loop, direction_hopping, draft_no_publish, benchmark_overstudy, perfectionism, external_blame}`）；本节是复盘扫描，**只读 + 汇总**，不重复写。

### 输出格式（plan §5.7.5 输出原则严格执行 — 只描述事实，不评价人格）

如果近 7 天有任何 `severity=warn` 或 `blocker` 的信号未 `resolved_at`，在日报末尾追加：

```text
🔍 本周行为观察（仅描述可观察事实，不评价人格）

- 过去 7 天生成 4 条草稿，0 条进入发布确认。当前更像发布前摩擦，不是选题不足。
  下一步建议：从现有 4 条草稿里挑一条风险最低的，小修标题和开头后发出去。
- 过去 14 天 3 次要求"换方向"，但每次都没有完整发布过该方向 3 条以上内容。
  下一步建议：先把当前方向跑满 3 条再决定要不要换。
```

**禁词清单（08-compliance.md `Behavior Signal Output Validation` 同款）**：

- 不出现「逃避 / 自卑 / 不想赚钱 / 拖延症 / 心理咨询 / 人格 / 性格缺陷 / 害怕成功」等心理诊断词
- 不出现「你这是逃避问题」「你在自我设限」类人格评价句式
- 不出现「拖延症」类临床词
- 命中即由 08-compliance.md 拒写；本节产出文案前自检一遍

### 写入 `creator-behavior-signals.md`（plan §9.5 格式）

如果信号是**新发现的**（数据库里前 7 天没出现过同类型 + 同窗口），追加一段到 `creator-behavior-signals.md`，结构与 03-daily-flow.md `Execution Friction Fallback` 写入命令一致（不重复写命令，cross-ref → 03-daily-flow.md）。

**已存在同类型信号**：仅刷新 `cooldown_until`，不新写一段，避免文件膨胀。

## Writes

- `agent/knowledge-base/evolution-log.md`（每日追加变更摘要）
- `agent/knowledge-base/patterns.md` / `anti-patterns.md` / `image-patterns.md` / `image-anti-patterns.md`
- `agent/knowledge-base/business-patterns.md` / `business-anti-patterns.md`（v3.2+ 由 Business Attribution Review 写入）
- `agent/knowledge-base/asset-ledger.md`（v3.2+ 由 Asset Ledger Update 写入；DB 端 `content_assets` 表）
- `agent/knowledge-base/creator-behavior-signals.md`（v3.2+ 由 Behavior Signal Roundup 在新发现信号时写入）
- `agent/knowledge-base/reviews/<YYYY-W##>.md`（周快照，仅周日；v3.2+ 包含本周业务信号 / 最高价值内容 / 高流量低价值 / 下周经营动作 4 段）
- `business_reviews` 表（v3.2+ 由 `db.sh add-business-review` 落库）
- `content_assets` 表（v3.2+ 由 `db.sh add-content-asset` 落库）
- `post_metrics` / `note_diagnosis` 表（由调用脚本写入）

## Failure Handling

- NoteRx Key 缺失（`NOTERX_API_KEY` 未设）：跳过五维诊断不报错，仅做收藏率 + 评论维度的复盘
- `fetch-metrics.sh` 单条失败：记录后跳过，不阻塞其他帖子
- AI 模型 API 报错最多 1 次重试（详见 08-cross-cutting）
- `preferences.json` schema 不匹配：触发 09-troubleshooting
- `db.sh add-business-review` 失败：在 evolution-log.md 标记 `degraded: business review write failed`，**不阻塞**日报；详见 09-troubleshooting `business review 写入失败` 行
- `db.sh add-content-asset` 失败：在 evolution-log.md 标记 `degraded: asset-ledger write failed`，**不阻塞**日报；详见 09-troubleshooting `asset-ledger 写入失败` 行

## Anti-Patterns

- 不复述 weight/confidence 公式（cross-ref → 06-learning-loop.md）
- imported posts 不纳入每日复盘（仅 source='shuling'）
- 不让用户看到 confidence 数值（用文字提示）
- NoteRx Key 缺失时跳过五维诊断不报错
- **`sales_signal=high` 或 `lead_signal=high` 时，没有 `evidence_level ∈ {hard, medium}` 的证据，禁止落库 high**（plan §5.6.2 末尾硬规则；schema description 已注明）
- **业务 pattern 不进入 06 confidence 算法**（plan §6.3 方案 A）；v3.2 业务 pattern 只影响 `business-patterns.md` / `business-anti-patterns.md` + 03 选题打分 `goal_alignment_score / monetization_distance_score`，**不**改 `preferences.json` weight
- 不输出心理诊断词（「逃避 / 自卑 / 不想赚钱 / 拖延症」等；08-compliance.md `Behavior Signal Output Validation` 强制）
- 控制争议信号 24h 内不写入 `business-anti-patterns.md`（避免一时情绪噪音变长期反模式）
- 业务归因日报段用自然语言展示，不 dump JSON

## Cross-Refs

- → 06-learning-loop.md（算法权威：weight / confidence / pattern 晋级阈值；本 playbook 业务 pattern 的边界详见 06 `## v3.2 Business Pattern Boundary`）
- → 07-comment-insights.md（评论提炼；强业务信号 evidence 是本节 Business Attribution Review 的输入）
- → 03-daily-flow.md（Execution Friction Fallback 写入信号；本节 Behavior Signal Roundup 仅扫描汇总）
- → 09-troubleshooting.md（business review / asset-ledger / behavior signal 写入失败兜底）
- → `agent/schemas/business-review.schema.json`（evidence_level / evidence[] / sales/lead high 硬规则字段契约）
- → `agent/schemas/content-asset.schema.json`
- → `agent/schemas/creator-behavior-signal.schema.json`
- → `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.6 / §5.7 / §5.8 / §7.7 / §8.1（设计来源）
