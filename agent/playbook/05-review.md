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
  db_tables:
    - posts
    - post_metrics
    - comment_insights
    - note_diagnosis
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
preconditions:
  - state.setup_completed == true
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
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

## Writes

- `agent/knowledge-base/evolution-log.md`（每日追加变更摘要）
- `agent/knowledge-base/patterns.md` / `anti-patterns.md` / `image-patterns.md` / `image-anti-patterns.md`
- `agent/knowledge-base/reviews/<YYYY-W##>.md`（周快照，仅周日）
- `post_metrics` / `note_diagnosis` 表（由调用脚本写入）

## Failure Handling

- NoteRx Key 缺失（`NOTERX_API_KEY` 未设）：跳过五维诊断不报错，仅做收藏率 + 评论维度的复盘
- `fetch-metrics.sh` 单条失败：记录后跳过，不阻塞其他帖子
- AI 模型 API 报错最多 1 次重试（详见 08-cross-cutting）
- `preferences.json` schema 不匹配：触发 09-troubleshooting

## Anti-Patterns

- 不复述 weight/confidence 公式（cross-ref → 06-learning-loop.md）
- imported posts 不纳入每日复盘（仅 source='shuling'）
- 不让用户看到 confidence 数值（用文字提示）
- NoteRx Key 缺失时跳过五维诊断不报错

## Cross-Refs

- → 06-learning-loop.md（算法权威：weight / confidence / pattern 晋级阈值）
- → 07-comment-insights.md（评论提炼）
- → 09-troubleshooting.md
