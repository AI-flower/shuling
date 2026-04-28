---
id: 03-daily-flow
title: Daily Flow (Topic → Draft → Image)
when:
  - "用户问今天发什么"
  - "用户说帮我写一条"
  - "cron 触发午间档/晚间档"
needs:
  required:
    - agent/knowledge-base/profile.json
    - agent/knowledge-base/preferences.json
    - agent/knowledge-base/patterns.md
    - agent/knowledge-base/title-formulas.json
    - agent/policies/content-rules.md
    - agent/playbook/_shared/emoji-dictionary.md
    - agent/playbook/_shared/confidence-mapping.md
    - agent/playbook/_shared/outline-template.txt
  optional:
    - agent/knowledge-base/business-profile.json
    - agent/knowledge-base/business-patterns.md
    - agent/knowledge-base/business-anti-patterns.md
    - agent/knowledge-base/asset-ledger.md
    - agent/knowledge-base/creator-behavior-signals.md
    - agent/knowledge-base/benchmarks/index.md
  fallback:
    business-profile.json: 不阻塞;goal_alignment_score / monetization_distance_score / business_score 一律 null;decision 仍可走 content_score 主导
    business-patterns.md: 跳过业务 pattern 引用,选题 reasoning_json 不附 business pattern 证据
    business-anti-patterns.md: 跳过反模式拦截,不影响选题生成,但日报标注 anti-pattern check skipped
    asset-ledger.md: asset_score_mode=prediction;只输出 expected_assets,不引用 related_asset_ids
    creator-behavior-signals.md: 跳过 Execution Friction Fallback 命中检测,默认走标准选题流程
    benchmarks/index.md: benchmark_score=null;decision 不读对标证据,仅用 content_score + asset_score 判断
  db_tables:
    - posts
    - user_choices
    - topic_candidates
    - content_assets
  env_vars:
    - IMAGE_GEN_API_KEY
    - MCP_URL
calls:
  scripts:
    - agent/scripts/db.sh
    - agent/scripts/xhs.sh
    - agent/scripts/image.py
    - agent/scripts/external-intel.sh
    - agent/scripts/content-qa.py
  playbooks:
    - 04-publish-flow.md
    - 06-learning-loop.md
    - 08-compliance.md
    - 09-troubleshooting.md
writes:
  files:
    - agent/data/xhs.db (user_choices, topic_candidates)
  emits:
    - draft_ready  # non-mutating: never authorizes publish (Stage 4 + Stage 3 boundary)
preconditions:
  - state.setup_completed == true
  - state.cold_start_done == true
on_failure:
  - 09-troubleshooting.md
version: 3.2.0
last_updated: 2026-04-28
---

# 03 Daily Flow

每天执行两次（午间档 + 晚间档），每次走完完整流程：选题研究 → 草稿生成 → 图片生成。下游 04 接管发布。

**核心心法**（贯穿 §2.2 草稿生成全流程）：

1. **图为主，文为辅**：小红书用户在信息流里只看封面 → 点进去主要划图 → 正文很多人不看。所以**图片才是信息载体**（每页装一个完整信息点），正文只是"上下文胶水 + 收藏理由"。
2. **结构化卡片，不写大段文字**：每页 4-8 行就够，留白多，不堆砌。
3. **emoji 是结构标记，不是装饰**：用语义 emoji 引导视觉锚点（→ `agent/playbook/_shared/emoji-dictionary.md`）。
4. **禁用 markdown**（小红书不渲染）：直接用纯文本 + emoji + 简单符号（• / ✅ / ⚠️）。

## Trigger

- 用户主动："今天发什么 / 帮我写一条 / 我要发小红书"
- cron：午间档（默认 12:00）和晚间档（默认 19:30）由 hermes cron 唤起
- 上游 `02-cold-start.md` 完成后 `cold_start_done == true` 起，本 playbook 进入常规调度

## Read This When

- `state.setup_completed == true` 且 `state.cold_start_done == true`
- 不要在选题阶段调用 publish（那是 → `04-publish-flow.md` 的职责）
- 不要重复问画像；`profile.json` 已存在则直接读

## Inputs

- `agent/knowledge-base/profile.json` — 博主画像（领域 / 受众）
- `agent/knowledge-base/preferences.json` — 偏好权重 + 当前 `confidence_level`
- `agent/knowledge-base/patterns.md` — 文字 pattern 库
- `agent/knowledge-base/title-formulas.json` — 标题公式库（24 条；v3.2+ 标题候选必须追溯到 `formula_id`）
- `agent/knowledge-base/image-patterns.md`（可选） — 图片 pattern 库
- `agent/knowledge-base/external-signals/<topic>.json`（可选；由 `external-intel.sh` 写）— 外部情报摘要（趋势 / 竞品密度 / 评论需求 / white_space）
- `agent/knowledge-base/business-profile.json`（可选；v3.2+） — 业务画像（`creator_track / primary_goal / conversion_path / current_bottleneck`）；缺失时走 `business_alignment=unknown` 兜底
- `agent/knowledge-base/business-patterns.md`（可选；v3.2+） — 已验证业务 pattern（区别于 `patterns.md`）
- `agent/knowledge-base/business-anti-patterns.md`（可选；v3.2+） — 业务反模式（高流量低价值、错受众等）
- `agent/knowledge-base/asset-ledger.md`（可选；v3.2+） — 内容资产台账，决定 `asset_score_mode`
- `agent/knowledge-base/creator-behavior-signals.md`（可选；v3.2+） — 执行摩擦信号；命中 `draft_no_publish / planning_loop / perfectionism` 时本 playbook 走兜底分支
- `agent/knowledge-base/benchmarks/index.md`（可选；v3.2+） — 对标账号索引（决定 `benchmark_score` 是否有证据）
- `agent/policies/content-rules.md` — 合规规则（draft-time 摘要见下文）
- 用户原始主题（如已选定）

**Draft-time 合规摘要**（≤15 行，权威定义见 → `agent/playbook/08-compliance.md`）：

- 标题/正文不出现绝对化词（"最 / 第一 / 唯一 / 国家级"等）
- 不做医疗、金融、法律、考试通过、减肥效果等承诺
- 不出现引战、擦边、政治敏感、未成年人不当内容
- 引用他人作品/观点要标明来源
- 商业内容（含品牌名 / 链接 / 折扣码）按"是否带货"做标记，让 §2.4 决定是否切到 `is_original=false`
- 不抄袭其他平台原文，转述也要重写
- emoji 总量受控（标题 1-2 个；正文每段 ≤1 个）
- 完整规则、禁用词列表、灰区判定 → `agent/playbook/08-compliance.md`

## Procedure

### 2.0 Execution Friction Fallback（v3.2+ Stage 12 — plan §5.7 / §5.7.7 / §7.2 / §7.5）

> **每次进入 03-daily-flow.md 的入口先做这一步**。LLM 在 playbook 内执行（不调脚本之外的 API）：扫近 7-14 天 `creator_behavior_signals` + `posts` + `user_choices`，判断是否命中"执行摩擦"信号。命中时**不再默认生成 3 个新选题**，改走兜底剧本。命中信号同步落库（`db.sh add-creator-behavior-signal`）+ 追加到 `creator-behavior-signals.md`。

#### 触发条件（plan §5.7.7 表）

按下表逐项检查；命中**任一**即触发兜底：

| 命中条件 | `signal_type` | severity | 窗口 |
|---|---|---|---|
| 连续 3 天问「今天发什么」但**没有**进入 04 的发布动作 | `draft_no_publish` | warn | 3 天 |
| 连续 3 次拒绝选题或草稿（`user_choices` 中 chosen_label 全为「换」/ 拒绝信号） | `planning_loop` 或 `perfectionism`（按上下文选） | warn | 单次会话 / 3 次 |
| 7 天内 ≥ 2 次明确要求「换方向」/「重做画像」/「换赛道」 | `direction_hopping` | warn | 7 天 |
| 连续要求更多对标账号 / 更多方案，但本人没有产出（`benchmark_requested ≥ 3` + 0 publish in 7d） | `benchmark_overstudy` | warn | 7 天 |
| 用户明确说「我先想想」/「我再准备一下」/「等我整理好再发」 且**已有可发布草稿** | `planning_loop` | info | 单次会话 |
| （可选）用户把失败完全归因外部（「平台限流 / 推荐机制不公 / 评论区都是黑粉」），且 ≥ 2 次出现 | `external_blame` | info | 14 天 |

> **同一会话只触发一次**。命中后本会话内不再触发新选题生成；下次会话重新评估。

#### 兜底剧本（plan §5.7.7 中段）

命中后**不再默认生成 3 个新选题**。输出**温和兜底问题**（plan §5.7.5 输出原则严格执行）：

```text
我注意到这周你已经拒了 5 条选题/草稿。
我先不继续推新选题了。
现在更像是两个问题之一：
1. 选题确实不对；
2. 发布前有别的卡点。
你更接近哪一个？如果只是发布前卡住，我建议今天只从已有草稿里选一条低风险内容发出去。
```

具体兜底分支（按 `signal_type` 分流）：

- **`draft_no_publish`** → 列出最近 7 天 `posts.status=draft` 中风险最低的 1 条（短、无敏感词、有现成图）；问「今天先发这一条好吗？」；不再追加新草稿。
- **`planning_loop` / `perfectionism`** → 取消新选题生成；只对**用户上一条已生成草稿**做最高优先级 1 项修改（draft-diagnosis fix_priority=high 第 1 条），不展开 6 维 / top-3。
- **`direction_hopping`** → 不更新 `profile.json` / `business-profile.json`；输出当前方向的发布次数 + 收藏率分布（≤ 5 句），让用户对照判断是否真的需要换方向。
- **`benchmark_overstudy`** → 不再拉新对标；输出「你已经看了 N 个对标，平均每个能给你 3 条可执行点；先把 X 个对标的可执行点里你最有把握的 1 条做出来再说。」
- **`external_blame`** → **不**反驳用户判断；只追问 1 个具体可执行问题（如「最近发布的 3 条里，第 1 条评论区前 5 条说了什么」），把对话从外部归因拉回**本账号可控因素**。

#### 产品底线（plan §5.7.5 / §5.7.7 末尾 — Stage 12 输出纪律）

- **不使用「你在逃避」「你自卑」「你不想赚钱」「拖延症」类判断**——禁词清单与 08-compliance.md `Behavior Signal Output Validation` 一致
- **不输出心理诊断**——本节不是心理咨询；只描述可观察行为和下一步最小动作
- **不把执行摩擦写成用户缺点**——`creator-behavior-signals.md` 写入文案必须只引用可统计事件（`draft_generated / publish_skipped / draft_rejected / benchmark_requested / direction_changed / review_ignored` 等）
- **只描述可观察行为和下一步最小动作**——`interpretation` 字段必须能被 08-compliance.md 的禁词扫描通过；命中即由 08 拒写

#### 命中信号写入（plan §5.7.6 / §9.5）

```bash
# DB 落库（Wave 1 已建命令）
bash agent/scripts/db.sh add-creator-behavior-signal '{
  "id": "behavior_20260428_draft_no_publish",
  "signal_type": "draft_no_publish",
  "severity": "warn",
  "observed_events": [
    {"event": "draft_generated", "count": 4, "window_days": 7},
    {"event": "publish_skipped", "count": 4, "window_days": 7},
    {"event": "draft_rejected", "count": 0, "window_days": 7}
  ],
  "interpretation": "过去 7 天生成 4 条草稿，0 条进入发布确认。当前问题更像发布前摩擦，不是选题不足。",
  "next_small_action": "从现有 4 条草稿中选风险最低的 1 条，小修标题和开头后发布。今天不再继续生成新方案。",
  "cooldown_until": "2026-05-05",
  "created_at": "2026-04-28"
}'
```

同步追加到 `agent/knowledge-base/creator-behavior-signals.md`（人类可读，结构见 plan §9.5；首屏示范条目已展示该格式）。

**写入失败**（`add-creator-behavior-signal` 返回非 0 / 表缺失）：转 → 09-troubleshooting.md `behavior_signal_db_failed` 行；只追加 MD，不阻塞兜底剧本输出。

**用户主动表示判断不准确**（"我没有逃避，是真的没空"等）→ 转 → 09-troubleshooting `behavior_signal_misfire` 行；本会话不再提示同类信号。

### 2.1 Topic Research

**步骤**：

1. **读取知识库**
   - `agent/knowledge-base/profile.json` → 了解博主领域和受众
   - `agent/knowledge-base/preferences.json` → 了解用户偏好权重和当前信心度
   - `agent/knowledge-base/patterns.md` → 了解有效 pattern

2. **外部情报采样**（v3.1+，§12 / 双因子选题前置）

   先查 cache，cache miss 再按预算调用 `external-intel.sh`。**不要**直接散调 `xhs.sh search/detail/recommend` 做外部研究（verify 41 强制；详见 → `docs/runbooks/external-intelligence.md`）。

   ```bash
   # 候选主题逐个查/采样
   bash agent/scripts/external-intel.sh cache-get "<候选主题>" || \
       bash agent/scripts/external-intel.sh research-topic "<候选主题>" --budget conservative
   ```

   失败降级（见下文 Failure Handling 段）：脚本输出 `degraded:true` / 退出 30/31 时不阻断本流程，**仅用内部记忆**（profile + preferences + patterns）继续，并在用户反馈里明确标注「本轮未获取外部趋势数据」。

3. **获取候选选题**（按博主领域选择通用数据源）

   - 用 WebSearch 搜索该领域的最新热点、季节节点、用户需求和趋势变化（L0-L1，无小红书风险）
   - 回看最近评论与 `comment_insights`，把高频提问、吐槽和需求转成候选选题
   - 用上一步 `external-intel.sh` 的 `common_angles` / `comment_demands` / `white_space` 作为补充候选源
   - 如果该领域有明确外部信号源，可补充 1-2 个垂直来源（如电商榜单、节假日热点、城市活动、招聘趋势、品牌新品），但不要默认绑定任何单一行业或平台来源

4. **去重过滤**
   - 调 `agent/scripts/db.sh query-posts --days 30` 获取最近发布过的帖子
   - 排除已发布过的选题

5. **对每个候选评分（v3.2 价值闸门，6 维 + 决策规则）**

   v3.2 不再用单一 `final_score`，而是分 6 维评分，再由可解释规则给出 `recommend / explore / avoid`。详见 plan §5.3。

   **6 个分（每个候选都要打）**：

   | 分 | 范围 | 来源 | 含义 |
   |---|---:|---|---|
   | `audience_score` | 0-30 | `profile.json` + `business-profile.json.buyer` | 是否匹配目标读者 |
   | `writeability_score` | 0-25 | 自评 | 是否能写成具体可视化的内容（不空泛、有抓手） |
   | `competition_score` | 0-25 | `external-signal.competition_density / white_space` | 竞品密度低 + 有差异化空间得高分 |
   | `preference_score` | 0-20 | `preferences.json` + `user_choices` | 用户历史偏好；公式权威 → `06-learning-loop.md` |
   | `goal_alignment_score` | 0-100 | `business-profile.json.primary_goal / current_bottleneck` | 是否服务当前账号目标或当前阶段 |
   | `monetization_distance_score` | 0-100 | `business-profile.json.conversion_path / offer_status` | 离真实付费/询价/购买/产品验证有多近 |

   **`monetization_distance_score` 的 4 档**（plan §5.3.2）：

   | 距离 | 说明 | 分数参考 |
   |---|---|---:|
   | 1 步 | 内容直接引导询价、报名、私信、购买、直播或店铺 | 85-100 |
   | 2-3 步 | 内容建立购买前信任，解决关键反对意见，或强绑定产品问题 | 65-85 |
   | 4-5 步 | 内容能沉淀用户语言、FAQ、案例或产品需求，但不直接转化 | 45-65 |
   | 5 步以上 | 只是泛知识、泛收藏、泛情绪互动，离付费路径很远 | 0-45 |

   **复合分**（不是新维度，是组合）：

   ```text
   content_score = audience_score + writeability_score + competition_score + preference_score   # 0-100
   business_score = 0.5 * goal_alignment_score + 0.5 * monetization_distance_score              # 0-100
   ```

   **`benchmark_score` 0-100 / null**（来自 `benchmarks/*.json` 或类似主题样本；证据缺失时 `null`，**不参与硬性判断**，仅显示「证据缺失」）。降级表见 plan §5.2.5。

   **`asset_score` 0-100 + `asset_score_mode` 三模式**（plan §5.3.2 + §5.8.6）：

   | 场景 | `asset_score_mode` | 取分依据 | 必填字段 |
   |---|---|---|---|
   | `asset-ledger.md` 为空 / `query-content-assets` 返回 0 行 | `prediction` | 仅根据 `expected_assets` 预测 | `expected_assets[]`，`related_asset_ids=[]` |
   | 已有资产台账 | `evidence` | 必须引用既有资产 | `related_asset_ids[]` 至少 1 项 |
   | 冷启动过渡期（少量资产） | `mixed` | 二者并存 | `expected_assets[]` + `related_asset_ids[]` |

   `prediction` 模式下的 `asset_score` 只能支持 `explore / recommend` 弱判断；后续必须经由 `05-review.md` Asset Ledger Update 写入 ledger 才能升级为 `evidence`。冷启动用户**不会**因 ledger 为空而全部 `asset_score=0`。

   ```bash
   # 查询当前 ledger 是否为空，决定 mode
   bash agent/scripts/db.sh query-content-assets --limit 1
   ```

   **数据缺失降级**：

   - `external-signal.json` 缺：`competition_score` 取 12（中性占位），并在选题列表末尾标注「本轮未获取外部趋势数据」
   - `business-profile.json` 缺：`goal_alignment_score` / `monetization_distance_score` 取 50（中性），并标注 `business_alignment=unknown`，**不阻塞**选题流程（08-compliance.md `business-profile 为空` 规则）
   - `benchmarks/` 为空：`benchmark_score=null`，显示「证据缺失」

6. **应用决策规则（plan §5.3.3）**

   `creator_track` 来自 `business-profile.json.creator_track`（缺失时按 `exploration` 处理）。决策规则：

   ```text
   content_score = audience_score + writeability_score + competition_score + preference_score
   business_score = 0.5 * goal_alignment_score + 0.5 * monetization_distance_score
   business_fit = business_score >= 60
   benchmark_fit = benchmark_score != null and benchmark_score >= 50
   asset_fit = asset_score >= 50
   monetization_far = monetization_distance_score < 45

   if creator_track == "offer_first" and monetization_far:
       decision = "explore"           # 强制降级：即使内容分高，离变现太远不能直接 recommend
   elif content_score >= 70 and business_fit and (benchmark_fit or asset_fit):
       decision = "recommend"
   elif content_score >= 60 and (business_fit or benchmark_fit or asset_fit):
       decision = "explore"
   else:
       decision = "avoid"
   ```

   `creator_track` 联动补充：

   - **`offer_first`**：`monetization_distance_score < 45` 时 **强制降级 explore**（即使内容分很高），因为没有变现路径配套；plan §5.3.2
   - **`creator_first`**：允许变现远，但必须能沉淀 `trust_asset` / `audience_language` / `problem_validation`（即 `expected_assets` 至少 1 项 + `business_score ≥ 60` 才能 `recommend`）；plan §5.3.2
   - **`exploration`**：重点看是否能验证人群 / 问题，不强求转化，但不能伪装成高业务价值（`monetization_distance_score` 不能虚标 ≥ 65）；plan §5.3.2

7. **冷启动 / 数据稀缺时的退化**（plan §5.3.2 + §5.8.6）

   - `asset-ledger` 为空 → `asset_score_mode="prediction"`，只输出 `expected_assets`（10 类资产，见 plan §5.8.4 / `agent/schemas/content-asset.schema.json` enum）
   - 有少量 ledger → `asset_score_mode="mixed"`，同时给 `expected_assets` + `related_asset_ids`
   - 已有完整台账 → `asset_score_mode="evidence"`，必须引证 `related_asset_ids`
   - `business-profile.json` 缺 → 标注 `business_alignment=unknown`，不阻塞，但 `recommend` 必须降级
   - `benchmarks/` 为空 → `benchmark_score=null`，规则中 `benchmark_fit = false`

8. **决定输出选题数量**：根据 `confidence_level` 决定输出 1/2/3 个候选；信心度→数量的映射、`last_exploration_at` 探索项追加、`consecutive_rejects` 强制回退三套规则统一在 → `agent/playbook/_shared/confidence-mapping.md`。weight 与 confidence 公式权威定义在 → `agent/playbook/06-learning-loop.md`。

9. **返回选题列表（人类可读 + 写入 topic_candidates 表）**

   **给用户看的人类可读版本**（plan §5.3.4 — 慢做环节，每个推荐选题至少输出 2 句 reasoning）：

   ```text
   选题 1：普通人做小红书最大的问题不是不会写

   内容分：82
   目标对齐：82
   变现距离：70（2-3 步：建立购买前信任）
   业务分：76
   对标分：68
   资产分：72（mixed：预计沉淀 series_arc + audience_language；引用 asset_20260420_audience_language_no_result）
   决策：推荐

   为什么值得做（≥ 2 句 reasoning）：
   1. 这条把用户从「文案技巧焦虑」带到「账号经营判断」，与当前 build_trust 目标对齐；变现距离 2-3 步，能解决购买前的信任反对意见。
   2. 对标账号里类似主题有稳定互动；能复用既有 audience_language 资产，并扩成 3 条系列。
   ```

   - 如果 1 个：附加"回复'换'我再找一个"
   - 如果本轮**缺少外部数据**：列表末尾追加「本轮未获取外部趋势数据，使用账号历史偏好生成候选。」
   - 输出后等待用户回应

   **写入 `topic_candidates` 表**（每个候选都写一行；`reasoning_json` 留作完整 audit trail）：

   ```bash
   # AI 在内存中先组装 reasoning_json（含 6 维分 + score_sources + expected_assets + related_asset_ids + creator_track + target_goal）
   # 字段契约见 plan §5.3.4 落库版本。
   REASONING_JSON='{"audience_score":26,"writeability_score":22,"competition_score":18,"preference_score":16,"goal_alignment_score":82,"monetization_distance_score":70,"monetization_distance_steps":3,"benchmark_score":68,"asset_score":72,"asset_score_mode":"mixed","score_sources":{"business":"business-profile","benchmark":"account_dossier","asset":"mixed"},"expected_assets":["series_arc","audience_language"],"related_asset_ids":["asset_20260420_audience_language_no_result"],"target_goal":"build_trust","creator_track":"creator_first","reason":"…"}'
   TODAY="$(date -u +%Y-%m-%d)"
   sqlite3 agent/data/xhs.db "INSERT INTO topic_candidates (
     date, source, title, score, business_score, goal_alignment_score,
     monetization_distance_score, benchmark_score, asset_score, decision, reasoning_json
   ) VALUES (
     '$TODAY', 'shuling', '<选题主题>', <content_score>, 76, 82, 70, 68, 72, 'recommend',
     '$(echo "$REASONING_JSON" | sed "s/'/''/g")'
   );"
   ```

   `score` 列存复合的 `content_score`（保持向后兼容）；新维度走各自专列；整个评分对象 JSON 序列化进 `reasoning_json` 列，便于后续审计。

10. **记录用户选择**
    ```bash
    agent/scripts/db.sh log-choice '{"choice_type":"topic","offered_count":3,"chosen_index":2,"chosen_label":"办公室收纳","skipped_labels":"[\"通勤穿搭\",\"周末亲子活动\"]"}'
    ```

### 2.2 Draft Generation

用户选定选题后，**分两步**生成草稿：先出大纲（决定每页装什么信息 + 配图建议），再出文案（标题/正文/标签的最终文本）。这是借鉴 RedInk 的核心范式——**不是写一篇推文，是写一组卡片**。

> Emoji 词典（按语义用，不要乱花；标题 1-2 个、正文每段 ≤1 个、不要 4 个 emoji 排排坐）→ `agent/playbook/_shared/emoji-dictionary.md`

**第 1 步：读取规则**

```bash
cat agent/policies/content-rules.md  # 合规
cat agent/knowledge-base/patterns.md 2>/dev/null  # 文字 pattern 库
cat agent/knowledge-base/profile.json  # 博主画像
```

**第 2 步：生成大纲**（每页一个信息点 + 配图建议）

按下面的格式输出 6-9 页大纲。**严格用 `<page>` 分隔**，每页第一行写类型 `[封面] / [内容] / [总结]`，**最后一行**写"配图建议：xxx"（图像生成会读这一行）。

> 完整范例（手冲咖啡，~70 行）→ `agent/playbook/_shared/outline-template.txt`，照这个结构仿写。

**大纲硬规则**：

- 6-9 页（封面 1 + 内容 4-7 + 总结 1）
- 每页只装**一个**信息点（步骤/工具/技巧/对比）
- 每页 4-8 行，超过 10 行就拆页
- 列表用 `•` 不用 `-`（小红书更常见）
- 数字+单位连写（`92-96℃` 不要 `92 - 96 ℃`）
- emoji 按词典用，不堆砌
- **禁止**任何 markdown（`#` `**` `[]()` 都不要）
- 最后一行强制 `配图建议：xxx`

**第 3 步：基于大纲生成最终文案**（标题公式驱动 + 正文 + 标签）

> **v3.2+ 标题公式驱动**：每个标题候选必须**追溯到**一条 `agent/knowledge-base/title-formulas.json` 中的 `formula_id`，不再用旧的「数字/疑问/惊叹/对比/痛点」5 类硬编码规则。详见 plan §5.4。

**第 3.0 步：加载公式 + 选公式**

```bash
# 加载 24 条公式
cat agent/knowledge-base/title-formulas.json
# 查询最近 5 篇帖子的 formula_id / trigger，决定哪些进 cooldown
sqlite3 agent/data/xhs.db "SELECT id, title, title_formula_id, title_trigger, title_intent FROM posts ORDER BY datetime(created_at) DESC LIMIT 5;"
```

**选公式的优先级（intent 联动 `business-profile.primary_goal`，plan §5.4.4）**：

| `primary_goal` | intent 优先级 | 备注 |
|---|---|---|
| `grow_followers` | `click ≥ save` 优先 | 引流为主，标题钩子要硬 |
| `build_trust` | `trust ≥ series` 优先 | 建专业度；click 退到第二位 |
| `get_leads` | `lead ≥ comment` 优先 | 引导私信/索取资料；**避免过度承诺**（08-compliance.md） |
| `drive_sales` | `conversion ≥ trust` 优先 | 必须经合规 + 真实供给检查 |
| `prepare_live` / `product_research` / `unknown` | `click + comment` 中性 | 走探索模式 |

**Cooldown 纪律**（plan §5.4.4 末段）：

- 同一 `formula_id` 在最近 N=3 条内连续出现 → **降权**该公式（除非该 formula 的 `constraints.cooldown_posts` 明确给了不同 N，以 JSON 中的值为准）。
- 同一 `trigger` 连续超阈值 → **提示**用户「账号可能正在模板化」，让用户决定要不要换 trigger。
- 阈值由 `title-formulas.json` 中各公式的 `constraints.cooldown_posts` 给出。

**没匹配公式时的降级**：

- `formula_id="manual"`（保留字面量），`trigger=""`，`intent="click"` 默认（标低置信）。
- 落盘时不阻塞，但 publish 入库前必须有 `intent`（08-compliance.md `Title Formula Validation` 强制）。

**第 3.1 步：输出 3 个**结构化 JSON 标题候选**（plan §5.4.5）**：

```json
{
  "titles": [
    {
      "text": "普通人别再这样做小红书",
      "formula_id": "loss_stop_doing",
      "trigger": "损失规避",
      "intent": "click",
      "why": "这条是避坑内容，先指出错误动作引点击"
    },
    {
      "text": "做小红书 30 天才明白：内容多≠账号好",
      "formula_id": "conflict_misread_advice",
      "trigger": "打破已有认知",
      "intent": "trust",
      "why": "用「我」+「时间」承接判断，建立专业度"
    },
    {
      "text": "为什么写得越多，账号反而越没起色",
      "formula_id": "conflict_belief_backfire",
      "trigger": "打破已有认知",
      "intent": "click",
      "why": "反常识 hook，配合避坑系列"
    }
  ],
  "copywriting": "正文 200-300 字，开头 hook，分段 2-4 行，emoji 适度，结尾互动引导",
  "tags": ["主标签", "热门 1", "热门 2", "精准 1", "精准 2", "长尾"]
}
```

**标题硬规则**（3 个候选；plan §5.4.5）：
- 每个候选**必须**有 `text / formula_id / trigger / intent / why` 五字段
- `text` 长度遵循该公式 `constraints.max_chars`（多数 ≤ 22；不超 30）
- 选 3 个候选时，**至少 2 个不同 `formula_id`**（避免单公式过载）
- 1-2 个 emoji（与该公式 best_for 场景匹配）
- 第一个是主推；其 `intent` 必须与 `primary_goal` 优先级匹配
- 命中 cooldown 的公式必须给出降权理由或换公式
- **结尾行动**与 `business-profile.conversion_path.next_step` 对齐（plan §7.5；不是结尾互动一句话泛祝福）

**meta.json 兼容性**：发布 meta（→ `_shared/post-meta-schema.json`）保留**最终字符串标题**字段；`formula_id / trigger / intent` 由 `04-publish-flow.md` 通过 `add-post` 写入 `posts.title_formula_id / title_trigger / title_intent` 列（plan §5.4.5 末段）。

**正文硬规则**（200-300 字，**不超 500**）：
- 开头 1-2 行 **hook**（共鸣痛点 / 悬念 / 反直觉），抓住"不滑走"那 3 秒
- 中段分 2-3 个小段，每段 2-4 行，**段间空一行**
- 适度 emoji（每段最多 1 个，结构标记优先用 💡⚠️✅）
- 结尾 1 行**互动引导**（`你们也试试？` / `评论区聊聊` / `还有什么坑没踩过的？`）
- **不写大纲已经在图里的内容**（图说步骤、文说感受/原因/补充）
- **禁用 markdown**

**标签硬规则**（5-8 个，**不带 # 号**，逗号分隔或数组）：
- 第 1 个是**主标签**（领域核心词）
- 2-3 个**热门大标签**（流量入口）
- 2-3 个**精准小众标签**（目标受众）
- 1 个**长尾标签**（差异化）

### 2.2.5 Draft Diagnosis（草稿五维诊断 + AI 味检测）

> v3.2+ 新增（plan §5.5）。**LLM 在 playbook 内执行**，**不调脚本**、**不调外部 API**。前置：草稿文案已生成；后置：用户确认前必跑。

**执行顺序**（plan §5.5.5）：

```text
生成 meta.json（标题 + 正文 + 标签 + 大纲）
  ↓
content-qa.py --draft <meta.json>          ← 规则检测（脚本，10+2 项）
  ↓
draft-diagnosis（本节）                    ← LLM 语义诊断
  ↓
合规 pass + QA 可接受 + draft-diagnosis decision ∈ {pass, user_confirm} → 展示给用户
```

**(a) 先跑 content-qa.py 规则检测**

```bash
# 草稿先临时落盘到 /tmp 再跑 QA（避免依赖图片）
mkdir -p /tmp/xhs-post
echo '<draft JSON: title/content/tags>' > /tmp/xhs-post/meta.json
python3 agent/scripts/content-qa.py --draft /tmp/xhs-post/meta.json --json
# exit 0 = score >= 70 通过；1 = warn；2 = 配置错误
```

警告（warn）不阻塞但作为后续诊断的输入。

**(b) LLM 在 playbook 内做六维语义诊断**

输出符合 `agent/schemas/draft-diagnosis.schema.json` 的 JSON 对象。**6 维度**（plan §5.5.2）：

| 维度 | 问题 |
|---|---|
| `clarity` | 是否一句话说清楚核心观点？ |
| `title_cover_fit` | 标题/封面是否给出明确点击理由（与正文承诺一致）？ |
| `expression_efficiency` | 是否绕、空、堆术语、信息密度低？ |
| `cognitive_gap` | 是否提供读者不知道的新判断、新方法或新案例？ |
| `human_signal` | 是否有真人经验、具体细节、判断痕迹（**参考 `profile.json` 历史风格**，不用通用「真人感」模板）？ |
| `business_alignment` | 是否服务 `business-profile.json.primary_goal` 或 `conversion_path.next_step`？ |

每个维度输出 `score / issue / evidence / fix / fix_priority / confidence`。

**诊断硬规则**（plan §5.5.3 — schema 写盘前 08-compliance.md 也强制校验）：

- 没有 `evidence` 的维度，`confidence` 最高只能是 `low`
- `human_signal` 必须参考 `profile.json` 中用户历史风格，**不能套通用「真人感」模板**
- `business_alignment` 必须**引用** `business-profile.json.primary_goal` 或 `conversion_path.next_step`；`business-profile` 缺失 → `confidence=low + score=50` 中性
- 用户**只看到 `fix_priority="high"` 的 1-3 项**（避免诊断噪音压低发布频率，plan §5.5.6）

**AI 味检测 10 项**（plan §5.5.4，由 LLM 按本节逐项判断；后续可抽部分进 `content-qa.py`）：

1. `uniform_rhythm` — 排比过均匀
2. `gnomic_endings` — 每段都收束成金句
3. `synonym_substitution` — 同义词刻意替换
4. `translation_tone` — 中文翻译腔
5. `hook_pain_promise` — 开头套路化（钩子 + 痛点 + 承诺）
6. `not_x_but_y` — 过度使用「不是 X，而是 Y」
7. `term_stacking` — 术语堆叠
8. `smooth_emotion_curve` — 情绪曲线太光滑
9. `fake_reader_voice` — 虚构读者声音
10. `empty_blessing` — 结尾空泛祝福

每条命中输出 `{type, severity, sample, reason}`，写入 `ai_fingerprint_hits[]`。

**输出对象示例**（结构权威 → `agent/schemas/draft-diagnosis.schema.json`）：

```json
{
  "ok": true,
  "overall_score": 78,
  "decision": "user_confirm",
  "dimensions": {
    "clarity": {"score": 82, "issue": "", "evidence": ["开头一句点出'不是不会写'"], "fix": "", "fix_priority": "low", "confidence": "medium"},
    "title_cover_fit": {"score": 80, "issue": "", "evidence": ["主推标题与正文承诺对齐"], "fix": "", "fix_priority": "low", "confidence": "medium"},
    "expression_efficiency": {"score": 70, "issue": "第 3 页信息密度低", "evidence": ["第 3 页只罗列 3 条结论"], "fix": "补一个对比案例", "fix_priority": "high", "confidence": "medium"},
    "cognitive_gap": {"score": 76, "issue": "", "evidence": ["对比常见误读"], "fix": "", "fix_priority": "low", "confidence": "low"},
    "human_signal": {"score": 72, "issue": "开头像通用模板", "evidence": ["参考 profile.json: 用户偏第一人称叙事"], "fix": "把开头换成一个具体场景", "fix_priority": "high", "confidence": "medium"},
    "business_alignment": {"score": 88, "issue": "", "evidence": ["引用 business-profile.primary_goal=build_trust"], "fix": "结尾改成'想要模板的评论区说模板'", "fix_priority": "high", "confidence": "high"}
  },
  "ai_fingerprint_hits": [
    {"type": "empty_blessing", "severity": "warn", "sample": "祝你早日找到自己的节奏", "reason": "结尾空泛祝福；与 conversion_path.next_step 不匹配"}
  ],
  "summary": "建议小修后再发：补具体场景 + 改结尾行动入口",
  "checked_at": "2026-04-28"
}
```

**(c) 把 fix_priority=high 的 1-3 项展示给用户**（plan §5.5.6）

不要把完整 JSON 扔给用户。用户看到（人类可读）：

```text
发布前诊断：建议小修后再发

主要问题（top 3）：
1. 第 3 页信息密度低，读者看完不知道具体怎么做。
2. 开头像通用模板，建议换一个具体场景。
3. 这条服务"建立信任"，但结尾引导写成了泛互动。

我建议：
- 把开头换成一个具体场景
- 第 3 页补一个对比案例
- 结尾改成"想要模板的评论区说模板"
```

**(d) 根据 decision 走分支**

- `pass` → 继续 §2.2 第 4 步（决定份数）
- `user_confirm` → 展示诊断 + 用户回复"还是发"才继续；回复"改"则回到第 3 步重生成
- `revise` → 自动按 `fix_priority=high` 改写后再走一次诊断（最多 1 轮，避免无限循环）
- `regenerate` → 大纲层重写（回到第 2 步生成大纲）

> **不阻塞合规**：`draft-diagnosis` 低分**不硬阻塞**发布，除非命中合规风险（这部分由 08-compliance.md `Draft Time Rules` 处理）。08-compliance.md 的 Draft Diagnosis Schema Validation 仅做 schema 形态检查。

**第 4 步：决定输出份数**：信心度→份数映射 + `consecutive_rejects ≥ 1` 强制 2 份等回退规则 → `agent/playbook/_shared/confidence-mapping.md`。weight/confidence 公式 → `agent/playbook/06-learning-loop.md`。

**摩擦兜底**（plan §7.5 Execution Friction Fallback）：如本次循环命中 `creator-behavior-signals.md` 中的 `draft_no_publish` 或 `perfectionism`，**不**继续生成更多备选、不再生成新选题；只修最高优先级 1 项问题，引导用户对**已有草稿**做发布动作。

**第 5 步：返回给用户**

把大纲（用户看结构）+ 文案（用户看最终文字）+ 诊断 top 3（如有）一起展示。
- 如果 2 份："选 1 还是 2？"
- 如果 1 份："回复'发'确认，或'换'重新生成"

**第 6 步：记录用户选择**

```bash
agent/scripts/db.sh log-choice '{"choice_type":"draft","offered_count":2,"chosen_index":1,"chosen_label":"清单体","skipped_labels":"[\"教程体\"]"}'
```

> **下一步：第 2.3 节图像生成**会**直接吃这份大纲**——每页的"配图建议"行会成为该页图像的 prompt。所以大纲写得越具体、越视觉化，图越好。

### 2.3 Image Generation

用户确认草稿后，生成配图。

> **核心范式（向 RedInk 5.2k⭐ 学的）**：中文 prompt 模板 + "小红书"锚词 + 两阶段参考图。**不翻译成英文**、**不禁止 AI 画文字**、**每张图都带完整大纲**。这三条是让生图"像小红书"的根因。

**步骤**：

1. **准备工作区 + 整篇大纲落盘**

   生图模板需要"整篇大纲原文"作为上下文，所以先把 2.2 节生成的大纲写到文件里：
   ```bash
   mkdir -p /tmp/xhs-post
   # 把 2.2 节最终确认的大纲原文（含所有 <page> 分隔 + 配图建议行）写进去
   cat > /tmp/xhs-post/outline.txt <<'OUTLINE_EOF'
   <整篇大纲原文粘贴到这里>
   OUTLINE_EOF
   ```

2. **读图片 pattern 库（可选增益）**
   ```bash
   cat agent/knowledge-base/image-patterns.md 2>/dev/null  # 没有就跳过
   ```
   - 如有 `confidence ≥ medium` 的 pattern → 把 pattern 描述**追加到该页 `--page-content` 末尾**（不是替换 prompt，是作为补充视觉线索）
   - 没有就跳过——模板里的"小红书爆款图文风格"锚词已经足够
   - confidence 阈值定义 → `agent/playbook/06-learning-loop.md`

3. **检查图片生成能力**
   ```bash
   python3 agent/scripts/image.py --check
   ```
   - 返回 0 → 走 AI 生图（下面的第 4 步）
   - 返回 2 → **硬停**。告诉用户："图像生成 API Key 未配置，薯灵需要图像生成 API（Gemini 或 OpenAI gpt-image-2，二选一）才能继续"，不要尝试降级任何 HTML 截图路径

4. **AI 生图路径**（中文模板驱动，两阶段生成）

   **强制使用结构化 CLI**（加载 `agent/prompts/image_prompt.txt`，自动注入 4 变量）：

   ```bash
   # 阶段 a：封面（无参考图）
   python3 agent/scripts/image.py \
       --page-type "封面" \
       --page-content "$(extract_page_content_from_outline 1)" \
       --outline-file /tmp/xhs-post/outline.txt \
       --topic "<用户原始主题原文>" \
       --output /tmp/xhs-post/page-1.png

   # 阶段 b：每张内容页带封面作参考图
   python3 agent/scripts/image.py \
       --page-type "内容" \
       --page-content "$(extract_page_content_from_outline 2)" \
       --outline-file /tmp/xhs-post/outline.txt \
       --topic "<用户原始主题原文>" \
       --output /tmp/xhs-post/page-2.png \
       --reference /tmp/xhs-post/page-1.png

   # 总结页
   python3 agent/scripts/image.py \
       --page-type "总结" \
       --page-content "<总结页大纲原文>" \
       --outline-file /tmp/xhs-post/outline.txt \
       --topic "<用户原始主题原文>" \
       --output /tmp/xhs-post/page-N.png \
       --reference /tmp/xhs-post/page-1.png
   ```

   **参数硬规则**：
   - `--page-type` **只能是** `封面` / `内容` / `总结` 三选一（模板按这三型激活不同子约束）
   - `--page-content` = 2.2 节大纲里该页的**完整原文**（包括 `配图建议：xxx` 那一行，一起喂进去）
   - `--outline-file` = **必传**。让模型看到全篇上下文，自动协调跨页视觉
   - `--topic` = 用户原始输入，给模型定方向
   - 非封面页**必须** `--reference <封面路径>`，这是多页风格统一的核心

   **提示词理念**（跟 RedInk 对齐，**不要违反**）：
   - **禁止自己写英文 prompt**——模板已经是中文的 77 行完整约束
   - **禁止说"不要包含文字"**——Gemini 3 Pro 的中文字形渲染已过关，强制"文字必须完整呈现"反而更像小红书
   - **禁止用 `IMAGE_BRAND_STYLE` 拼前缀**——模板里"小红书爆款图文风格"这个锚词就是品牌风格的最高表达
   - **推荐模型**：`gemini-3-pro-image-preview`（Nano Banana Pro，中文文字 + multimodal 参考图都最准）

   **极短 prompt 兜底**（仅当 API 上下文受限）：加 `--short` 切到 `agent/prompts/image_prompt_short.txt`（6 行极简版）。

   **记录**：每张图生成后，写到 `generated_images` 表（自进化的数据基础）：
   ```bash
   sqlite3 agent/data/xhs.db "INSERT INTO generated_images (post_id, image_index, prompt, image_path, gen_model, gen_strategy, gen_status) VALUES (<post_id>, <0/1/2...>, '<该页 page_content 原文，不用存整个渲染后 prompt>', '<绝对路径>', '<model 名>', 'ai', 'success');"
   ```
   存 `page_content`（短）而不是整个渲染后 prompt（长且重复），既节省空间又便于 pattern 学习。

5. **组装 meta.json**

   将草稿内容和图片路径组装为发布数据，写入 `/tmp/xhs-post/meta.json`。完整字段定义（title / content / tags / images / is_original 等） → `agent/playbook/_shared/post-meta-schema.json`。

## Writes

- `agent/data/xhs.db`：
  - `user_choices`（topic 选择 + draft 选择）
  - `topic_candidates`（v3.2+：每个候选 6 维分 + decision + reasoning_json）
  - `generated_images`（每张图一行）
- `/tmp/xhs-post/`（每次运行新建）：
  - `outline.txt`（整篇大纲原文）
  - `page-1.png ... page-N.png`
  - `meta.json`（→ 04 直接消费；含 v3.2 标题公式字段供 04 落库）
- 事件：`draft_ready` 触发 → `04-publish-flow.md`

## Failure Handling

- 任何 `agent/scripts/xhs.sh` / `agent/scripts/image.py` 调用非零退出 → 转 → `09-troubleshooting.md`
- `image.py --check` 返回 2 → **硬停**，提示用户配置图像生成 API Key（Gemini 或 OpenAI gpt-image-2），不降级 HTML
- WebSearch / `external-intel.sh` 节流或预算耗尽 → 用现有 `comment_insights` + `patterns.md` 兜底，本轮少出 1 个候选可接受
- AI 模型 API 报错最多 1 次重试（→ `agent/playbook/09-troubleshooting.md`）

**外部情报失败降级**（v3.1+，§12.10）：

- `external-intel.sh` 返回非零（exit 1/2/20）或输出 `degraded:true` → **不阻断**草稿生成；选题打分时 `external_momentum` / `competition_gap` 取中性 0.5，使用内部 `profile.json` + `preferences.json` + `patterns.md` 兜底
- `external-intel.sh` 退出 30（cooldown / locked）→ 转 → `09-troubleshooting.md` Account Safety Matrix；本轮强制使用内部记忆
- `external-intel.sh` 退出 31（采样过程中触发风险信号）→ 已写 `account-safety-state.last_risk_event`，自动进 cooldown；提示用户后停止外部采样
- 任一上述情况下，选题输出**必须明确标注**：`本轮未获取外部趋势数据，使用账号历史偏好生成候选。` 不允许伪装成有外部数据

## Anti-Patterns

- 不在选题阶段调用 publish_content
- 不复述 weight/confidence 公式（cross-ref → 06-learning-loop.md）
- 不跳过合规检查（必读 agent/policies/content-rules.md）
- 不复述 emoji 词典（cross-ref → _shared/emoji-dictionary.md）
- 不在本文件 inline 大纲咖啡范例（cross-ref → _shared/outline-template.txt）
- 不在本文件 inline meta.json 字段表（cross-ref → _shared/post-meta-schema.json）
- 不自己写英文图像 prompt、不禁止 AI 画文字、不拼 `IMAGE_BRAND_STYLE` 前缀
- 不把信心度→数量映射规则在本文件抄第二遍（cross-ref → _shared/confidence-mapping.md）
- `draft_ready` 只表示草稿就绪，**不**自动触发 04-publish-flow.md；必须等用户显式回复"发"并走 approval 流程（→ `docs/runbooks/account-safety.md`）
- **不直接散调 `xhs.sh search/recommend/detail` 或 `fetch-comments.sh` 做外部研究**——必须走 `external-intel.sh`（v3.1+，verify 41 强制）
- **不存外部内容原文**——external-signals 只保存摘要、标签、note_id 引用、置信度；禁字段 `full_body / raw_comments / full_comments / raw_post_body / note_body / raw_html`（v3.1+，verify 42 强制）
- **不用旧的「数字/疑问/惊叹/对比/痛点」5 类硬规则生成标题**——v3.2+ 必须追溯到 `title-formulas.json` 的 `formula_id`；不可解释只记 `formula_id="manual"` 但 `intent` 必填
- **draft-diagnosis 由 LLM 在 playbook 内执行，不调脚本**（plan §5.5.5）；不要把诊断写成另一个 CLI 调用
- **draft-diagnosis 用户输出只展示 `fix_priority=high` 的 1-3 项**（plan §5.5.6）；不要把完整 6 维 JSON dump 给用户
- **没有 `evidence` 的诊断维度 confidence ≤ low**（plan §5.5.3）；08-compliance.md `Draft Diagnosis Schema Validation` 强制
- **`asset_score_mode=evidence` 时必须引用 `related_asset_ids`**；冷启动 ledger 为空必须用 `prediction` 模式，不能强填证据

## Cross-Refs

- → `agent/playbook/04-publish-flow.md`（草稿确认后接管发布；v3.2+ 接收 title_formula_id/title_trigger/title_intent 写入 posts 表）
- → `agent/playbook/05-review.md`（asset-ledger 由复盘沉淀；本 playbook 选题用作 evidence）
- → `agent/playbook/06-learning-loop.md`（weight / confidence 公式权威 + creator_preference 维度）
- → `agent/playbook/07-comment-insights.md`（评论强业务信号写入 asset-ledger）
- → `agent/playbook/08-compliance.md`（完整合规规则 + Title Formula Validation + Draft Diagnosis Schema Validation）
- → `agent/playbook/09-troubleshooting.md`（脚本失败 / 节流 / 重试 / Account Safety Matrix / v3.2 故障矩阵）
- → `agent/playbook/_shared/emoji-dictionary.md`
- → `agent/playbook/_shared/outline-template.txt`
- → `agent/playbook/_shared/confidence-mapping.md`
- → `agent/playbook/_shared/post-meta-schema.json`
- → `agent/knowledge-base/title-formulas.json`（v3.2+ 标题公式库，24 条）
- → `agent/knowledge-base/asset-ledger.md`（资产台账，决定 asset_score_mode）
- → `agent/schemas/title-formula.schema.json`（公式字段契约）
- → `agent/schemas/draft-diagnosis.schema.json`（诊断字段契约）
- → `agent/schemas/content-asset.schema.json`（资产字段契约）
- → `agent/schemas/business-profile.schema.json`（business-profile 字段契约）
- → `docs/runbooks/external-intelligence.md`（外部情报采样契约 + 双因子选题字段含义）
- → `agent/scripts/external-intel.sh`（research-topic / cache-get / budget-status 的契约）
- → `agent/scripts/content-qa.py`（v3.2+ 扩 12 项检测：含 title formula/trigger 重复）
- → `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.3 / §5.4 / §5.5 / §5.8（设计来源）
