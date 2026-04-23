---
title: 已有账号接入模式（Existing Creator Onboarding）
status: archived
archive_reason: completed
moved_from: docs/features/existing-creator-onboarding.md
moved_at: 2026-04-23
original_date: 2026-04-21
released_in: v2.2.0
---

> **归档说明**（2026-04-23 v2.4.0 docs 重组）：
> 本文档已归档。原因：completed — 已作为 v2.2.0 "Existing Creator Support" 特性发版落地。
> 如需了解当前状态请参阅：`CHANGELOG.md` v2.2.0 条目与根目录 `SKILL.md` 中的账号接入流程。

---

# 已有账号接入模式（Existing Creator Onboarding）

> v2.2.0 "Existing Creator Support" 主要特性设计文档
> 状态：设计稿 · 2026-04-21

## 1. 背景与动机

薯灵 v1.x ~ v2.1.x 面向**从零起步的新博主**设计：

- `SKILL.md §1` 通过对话三问（领域 / 受众 / 风格）建立 `profile.json`
- `patterns.md` 冷启动靠竞品分析
- `preferences.json` 完全来自 `user_choices`（用户在薯灵内的每次选择）
- 所有复盘与自进化只看"通过薯灵发的帖"（`posts` 表）

对**已经在运营小红书、有 30 ~ 1000+ 存量帖**的老博主：

- 让其从零填画像是侮辱：他的 200 条帖就是最真实的画像
- 强制跑"新手冷启动"丢弃了最宝贵的信号：历史收藏率分布、已验证有效的标题模式、受众构成
- 首条通过薯灵发的帖质量显著低于老博主自己的日常水准，用户会流失

**本特性目标**：让老博主跑完 `install.sh` 后，在 10–20 分钟内完成存量接入，系统立刻具备他 **6 个月以上**的历史记忆，第一条薯灵发帖即达到或超过其历史 P50 水平。

---

## 2. 用户故事

> **故事 1**：小艺运营"AI 工具测评"账号 8 个月，已发 170 条，收藏率 3–8%，粉丝 1.2 万。她听说薯灵能帮她提效，装完后说"我已经在做小红书了，帮我看看怎么优化"。系统应该：
>
> 1. 不问她领域/受众/风格（自动从历史推出）
> 2. 出一份她的账号体检报告（告诉她哪些做对、哪些做错、明日该做什么）
> 3. 后续每次薯灵帮她出的选题/草稿，都基于她 170 条的规律而不是通用套路

> **故事 2**：老王发了 60 条美食探店，收藏率波动很大（有 10% 的爆款也有 0.5% 的糊帖）。他想要"把爆款模式固化下来"。系统应该从他的 TOP 10% 中提取标题模式/结构模式/情绪钩子，填进 `patterns.md (confidence=medium)`，并对连续差的 BOTTOM 10% 产出 `anti-patterns.md`。

> **故事 3**：小林已发 500+ 条跨领域内容（读书+职场），自己也拿不准主赛道该收敛到哪。系统应该看他历史主题分布 × 收藏率矩阵，建议保留/砍掉哪些主题。

---

## 3. 整体流程

```
  install.sh 完成
        │
        ▼
   ┌────────────────────────┐
   │  §0a 业务路由 tick     │
   │  state.creator_mode?   │
   └──┬─────────────┬───────┘
      │unset        │new_creator
      ▼             ▼
  询问用户        §1 新博主流程（原路径）
  "新号还是老号?"
      │老号
      ▼
   ┌─────────────────────────┐
   │  §0c 已有账号接入模式    │
   │  5 步流程：              │
   │                          │
   │  1. 确认账号登录         │
   │  2. 历史内容批量导入     │← import-existing.sh
   │  3. 画像反推             │← AI 读样本聚类
   │  4. Patterns 种子挖掘    │← AI 分析 TOP/BOTTOM
   │  5. 偏好 bootstrap       │← import-existing 写 user_choices
   │  6. 出账号体检报告       │← audit-report.sh
   └──┬──────────────────────┘
      ▼
  state.creator_mode = 'existing'
  state.existing_import_done = true
  state.profile_created = true
  state.cold_start_done = true
      │
      ▼
  §2 日常流程（正常每日发布/复盘），
  所有决策已具备历史记忆加权
```

**关键分叉点**：

- `state.creator_mode` ∈ `{new, existing, unset}`
- `existing` 分支完全跳过 §1 的三问对话与竞品冷启动
- 两条路径不可回退（避免清空已建立的数据）

---

## 4. 核心能力拆解

### 4.1 历史内容批量导入（`import-existing.sh`）

**输入**：用户登录态（cookies 已就绪）

**处理**：

1. `xhs.sh user <self_id>` 拉取账号基础信息（粉丝/获赞/发布数 `total_posts`）
2. 分页拉取所有已发帖（默认 last 200，可 `--limit` 调）
3. 每条逐个 `xhs.sh detail <note_id>` 拉完整数据（正文/标签/互动/发布时间）
4. 从评论里抽取前 20 条写入 `comment_insights`（延续现有 spam 过滤）
5. 写入 DB：`posts(source='imported', status='published', published_at=原发布时间)`

**重要：节流遵守现有 profile**

- `get_feed_detail` MIN_GAP=10s + 50/日
- 200 条导入实际需要 **~30 分钟**（按 10s gap），需在 UI 提示用户"大约 30 分钟，可以挂着"
- 提供 `--batch-size N` 控制单次批量（默认 50/次），`--resume` 支持断点续拉

**边界**：

- 日限额会挡住大批量导入 → 加 `--override-quota` 开关（只此场景可用，仍写 request_log 留痕）
- 中断后 `import_state.json` 记录进度（已拉 note_id 列表）
- 失败的单条跳过不中断主流程，记入 `import_errors.log`

### 4.2 画像反推

**触发**：`import-existing.sh` 完成 ≥30 条后，AI 读取样本做反推。

**AI 执行协议**（不在脚本里做，由 SKILL.md §0c 规定）：

```
1. 读 posts WHERE source='imported' 的最近 30 条 title + content 前 200 字
2. 聚类：
   - 主题关键词 → niche（选出现频次 top 3 中最具体的）
   - 用户群画像线索（"程序员必看"、"宝妈救星"等） → audience
   - 语气/句式 → tone（口语 / 干货 / 幽默 / 犀利）
3. 产出 profile.json 草案
4. 展示给用户："基于你 30 条历史帖，我推测你是 <niche> 方向，面向 <audience>，风格 <tone>。对吗？"
5. 用户确认或微调 → 写入 profile.json
```

**关键纪律**（写入 SKILL.md §0c）：

- AI 不得凭空造 niche，必须从样本中来
- 如果样本跨多个领域（如读书+职场），展示 "你有 M 个方向，建议主攻 X"，**让用户决策**不要擅自合并
- 不要强制扩展 schema/profile.schema.json 的字段，保持现有结构

### 4.3 Patterns 种子挖掘

**执行**：`audit-report.sh --extract-patterns` 输出结构化候选 → AI 写入 `patterns.md`。

**算法**：

```
候选集 = posts(source='imported') × metrics
按收藏率降序排序
取 TOP 20%（最少 5 条，最多 30 条）
AI 对每条提取：
  - 标题结构（数字清单 / 反差悬念 / 结果导向 / 问句 / 对比 / ...）
  - 开头三行的情绪钩子
  - 核心结构（痛点→方案→效果 / 清单→每条点评 / 故事→道理 / ...）
对重复 ≥3 次的模式：
  - 写入 patterns.md（confidence=medium，因为是用户自己的历史）
  - 标注 source="historical-import"
  - 标注验证样本数 n
对 BOTTOM 10%（收藏率 < P20）：
  - 同样提取并写入 anti-patterns.md（confidence=medium）
```

**为什么初始 confidence=medium 而非 experimental**：

- 新博主冷启动的 patterns 来自竞品，给 experimental 合理
- 老博主的 historical patterns 是他**自己的历史验证**，比竞品更可信
- 但也不给 high（因为平台算法会变，3 个月前的模式不一定现在管用）

### 4.4 偏好 bootstrap

**执行**：`import-existing.sh` 末尾自动做。

**算法**：

```
将历史已发视为"隐式选择"：
- 每条 imported post 贡献 1 条 user_choices 记录
  - choice_type 分别为 topic / title_pattern / content_style
  - 虚拟 offered_count = 假设有 3 个候选，他选了这个（因为我们不知道真实候选空间）
  - chosen_item = 本帖的 topic_type / title_pattern / content_style
  - skipped_items = ["__unknown__"] * 2（占位）
- 对同一维度按出现频次累加 chosen
- skipped 给 chosen * 0.3（粗略近似，表示"有其他可能但他选了这个"）

结果：
- weight = (chosen + 1) / (chosen + skipped + 2) 仍符合 Laplace 平滑
- confidence 按正常公式算
- 强制 total_choices = min(实际样本, 50)
  - 避免 170 条历史 → sample_factor=1.0 → 直接进 1 选档
  - 50 条时 sample_factor=1.0 但 concentration 真实反映历史集中度
  - 预留后续 50 条"增量选择"的学习空间
```

**边界**：

- 历史记录里可能没有 `topic_type / title_pattern / content_style` 三维分类
- 方案：在 import 之后，AI 对每条 imported post **自动分类**（小批量 LLM 调用），结果写回 posts 表
- 分类失败的帖子标 `topic_type='__unclassified__'`，不计入偏好 bootstrap

### 4.5 账号体检报告（`audit-report.sh`）

**输出**：`knowledge-base/audit-<YYYY-MM-DD>.md`（人类可读 markdown）+ `audit-<YYYY-MM-DD>.json`（机器可读，按 `schemas/audit-report.schema.json`）

**包含 8 个维度**：

| # | 维度 | 算法 | 用途 |
|---|---|---|---|
| 1 | **账号快照** | 粉丝 / 总获赞 / 总发布 / 距上次更新天数 | 定位当前水平 |
| 2 | **流量趋势** | 最近 90 天每日发布量 × 收藏率 散点 | 看状态起伏 |
| 3 | **Top 5 帖** | 按收藏率降序，附 AI 归因 | "做对了什么" |
| 4 | **Bottom 5 帖** | 按收藏率升序（排除发布<7天的） | "做错了什么" |
| 5 | **主题分布** | topic_type 计数 × avg 收藏率 矩阵 | 看应收敛哪些主题 |
| 6 | **标题模式命中率** | 按 title_pattern 聚合，平均收藏率 | 哪些 pattern 管用 |
| 7 | **评论需求积压** | 未回评论 × 高频关键词 | 找内容机会 |
| 8 | **风险信号** | 流量断层 / 掉粉 / 连续低表现 / 连续发布密度异常 | 预警 |

**脚本分工**：

- `audit-report.sh` 负责**读 DB + 计算**（纯统计，不调 AI）→ 输出 JSON
- AI 读 JSON 做归因分析（为什么 Top/Bottom 这样）和建议生成
- AI 写 audit-*.md 含"本周 3 个行动建议"

---

## 5. 数据模型变化

### 5.1 `posts` 表新增 `source` 字段

```sql
ALTER TABLE posts ADD COLUMN source TEXT DEFAULT 'shuling';
```

值域：

| 值 | 含义 |
|---|---|
| `shuling` | 通过薯灵创作并发布（v2.1.x 默认行为） |
| `imported` | v2.2.0+ 老博主接入时批量拉取的历史帖 |
| `manual` | 用户手动 `add-post` 但非薯灵流程（保留给未来） |

### 5.2 新增 `historical_stats` 表（账号快照）

```sql
CREATE TABLE IF NOT EXISTS historical_stats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  snapshotted_at TEXT NOT NULL,            -- ISO 8601
  followers INTEGER,
  total_likes INTEGER,
  total_posts INTEGER,
  imported_posts_count INTEGER,
  earliest_post_at TEXT,
  latest_post_at TEXT,
  meta_json TEXT                            -- 额外字段扩展位
);
```

用途：

- import 时记录一次初始快照
- audit-report 每次跑时记录一次，形成纵向趋势
- 供未来 "每周账号变化对比" 能力使用

### 5.3 新增 `import_state.json`（运行时态，非 DB）

`$XHS_CACHE_DIR/import-state.json`：

```json
{
  "started_at": "2026-04-21T14:00:00Z",
  "target_count": 200,
  "completed": ["67c1...", "67c2...", "..."],
  "failed": [{"note_id": "67c3...", "reason": "quota_block", "at": "..."}],
  "last_progress_at": "2026-04-21T14:15:30Z"
}
```

用途：

- `--resume` 依据
- 中断续跑
- 失败审计

---

## 6. SKILL.md 新增 §0c

```markdown
## 0c. 已有账号接入模式（existing creator mode）

### 触发条件

以下任一满足时进入：

1. 用户自述"我已经在运营小红书"、"已经有账号了"、"已经发过帖"
2. `state.creator_mode == 'existing'`（已确认为老博主）
3. `install.sh --mode=existing-creator` 触发

### 5 步流程

1. 确认账号登录（与 §0 复用）
2. 跑 `scripts/import-existing.sh --limit 200`（不够 200 就拉全部）
3. 导入完成后，读 30 条样本做画像反推 → 写 profile.json（§4.2）
4. 对 imported posts 自动分类（topic_type/title_pattern/content_style）→ 调 `audit-report.sh --extract-patterns` → 写入 patterns.md & anti-patterns.md
5. 调 `audit-report.sh` 产出 `audit-<YYYY-MM-DD>.md` → 给用户看

### 关键纪律

- 不要走 §1 的三问对话——已有数据比问话更准
- 不要让用户从零填画像——让 AI 反推后给用户**确认/微调**，不是让用户凭空写
- 多方向账号：不合并，让用户决策主攻方向
- import 中断：`--resume` 续跑，不重新开始
- 完成后置 state：`creator_mode='existing' / existing_import_done=true / profile_created=true / cold_start_done=true`（同时跳过冷启动和画像）
```

---

## 7. install.sh 扩展

在 §6 "可选配置" 之前插入一段：

```bash
# ─── 7.4 创作者模式选择 ─────────────────────────────────
printf "\n${BOLD}=== 创作者模式 ===${RESET}\n\n"
printf "你是新创作者还是已经在运营小红书？\n"
printf "  1) 新创作者（从零起步）\n"
printf "  2) 已有账号（建议——你的历史内容就是最好的画像）\n"
prompt "  选择 [1/2，默认 1]: " creator_mode "1"

if [ "$creator_mode" = "2" ]; then
    # 写入 state.creator_mode = 'existing'
    # 提示用户："装完后跟 AI 说'我已经在运营小红书'触发接入流程"
fi
```

支持 `--mode=existing-creator` 跳过 prompt。

---

## 8. 风险与边界

| 风险 | 缓解 |
|---|---|
| 日限额卡住大批量导入 | `--override-quota` 开关（只此场景可用），写 request_log 留痕 |
| 老账号发了几年，部分老帖已删除 | 失败单条跳过，`import_errors.log` 记录；不中断主流程 |
| 导入中 cookie 过期 | 每 50 条做一次 `status` 健康检查，失效则暂停并提示重登 |
| 多方向账号画像反推失败（niche 跨度大） | AI 必须在展示给用户时明确说"你有 M 个方向，我建议 X"，不擅自合并 |
| 历史帖没 topic_type 分类 | AI 小批量二次分类，失败标 `__unclassified__` 不计偏好 |
| imported posts 数量不够（<10） | 降级：仍跑 §1 对话画像，但提示"历史太少无法反推" |
| 隐私：用户评论可能含私人信息 | comment_insights 存储前做 PII 扫描（沿用 spam 过滤词典）|

---

## 9. 验收标准

**MVP 达成条件**（本 PR 范围）：

- [x] 设计文档（本文）
- [ ] `migrations/v2.2.0.sh` 加 `posts.source` + 建 `historical_stats`
- [ ] `scripts/import-existing.sh` 骨架可跑通（MCP 调用 + DB 写入），带 `--dry-run / --limit / --resume`
- [ ] `scripts/audit-report.sh` 骨架可跑通，输出 JSON + md
- [ ] `schemas/audit-report.schema.json`
- [ ] `SKILL.md §0c` 写入
- [ ] `install.sh --mode=existing-creator` 支持
- [ ] VERSION bump v2.2.0 + CHANGELOG / UPGRADE / README

**后续完整版**（不在本 PR 范围，单独迭代）：

- [ ] 历史帖自动分类的 AI prompt 模板
- [ ] audit-report 的 90 天趋势图（PNG 输出，而不仅 markdown 表）
- [ ] 周报加入"本周 vs 历史基线"对比
- [ ] 建议改写重发老帖的 `rewrite-suggest.sh`（Layer 2）

---

## 10. 与现有模块的兼容性

- `§0a 业务路由`：新增 `state.creator_mode` 分支，不改原有 4 行状态表行为
- `§1 首次使用`：保持不变，老博主不走这条
- `§2 每日流程`：保持不变，历史数据通过 preferences 加权生效
- `§3 每日复盘`：query-posts 默认只查 `source='shuling'`（不然老博主的历史帖会被当成"今日新发"反复分析）；加 `--include-imported` 开关给 audit-report 用
- `§4 自进化`：偏好学习在 bootstrap 后正常继续迭代
- `§5 合规规则`：完全复用
- 版本语义：**HANDS+1** = v2.2.0（新脚本 + DB schema 扩展，非流程重构）
