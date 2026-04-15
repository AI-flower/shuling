# 小红书内容自进化系统 — 设计规格

> 日期: 2026-04-15
> 状态: approved
> 项目: xiaohongshu-skill（现有项目升级）

## 一、系统定位

在现有小红书自动发布 Skill 基础上，增加**跨周期自进化能力**：系统能从每次发布的互动数据中学习，自动提炼爆款模式、淘汰无效策略、更新创作规则，实现"越发越好"。

### 约束条件

- 本项目是运行在智能体工具（Claude Code / Codex / OpenClaw 等）中的 **Skill**
- Skill 层只能用 Agent 自带能力（Read/Write/Edit/Bash），不能依赖数据库或向量库
- Workflow 层（Python 脚本 + launchd）已有 SQLite，可继续使用
- LLM 调用能力需可配置（支持 Claude API / OpenAI API / 兼容格式）
- 新账号冷启动，无历史数据

### 架构原则

- **Skill 层负责交互**：初始化、冷启动播种、创作时读取知识库
- **Workflow 层负责进化**：数据采集、复盘分析、知识库更新（程序化写入，不依赖 Agent）
- **文件系统即记忆**：知识库为 Markdown + JSON 文件，零外部依赖

## 二、三组件协作架构

```
┌──────────────────────────────────────────────────────────┐
│                    launchd 定时调度                        │
│                                                          │
│  08:00 research.py          ← 读 knowledge-base/         │
│  09:00 create_content.py    ← 读 knowledge-base/         │
│  11:30 publish_post.py                                   │
│  20:30 publish_post.py                                   │
│  21:30 send_preview.py                                   │
│  22:00 review.py            → 写 data/exports/           │
│                             → 周日触发进化分析             │
│                             → 程序化更新 knowledge-base/   │
│  每4h  keepalive.py         → 多时间点采集 post_metrics   │
└──────────────────────────────────────────────────────────┘

数据流：

  SQLite(post_metrics)                knowledge-base/
        │                                   ▲  │
        ▼                                   │  ▼
  review.py ──导出──→ data/exports/    Skill(创作时读取)
                          │
                          ▼
                    review.py weekly_evolution()
                    (调 llm.call_llm() 分析)
                          │
                          ▼
                    程序化写入 knowledge-base/
```

### 数据契约

| 生产者 | 消费者 | 接口 | 格式 |
|--------|--------|------|------|
| keepalive.py | review.py | SQLite post_metrics 表（含 checkpoint 字段） | T+1h/6h/24h/72h 多时间点记录 |
| review.py | weekly_evolution() | data/exports/weekly-YYYY-WNN.md | 结构化 Markdown（逐篇数据+增长曲线） |
| weekly_evolution() | Skill / research.py / create_content.py | knowledge-base/**/* | Markdown + JSON |
| Skill 冷启动 | 同上 | knowledge-base/**/* | 同上 |

## 三、知识库结构

```
knowledge-base/
  README.md              # 索引 + 当前阶段 + Top 5 有效 pattern 摘要
  patterns.md            # 活跃 pattern（≤15 条，定期淘汰）
  rules.json             # 程序可读的生成规则
  reviews/               # 周复盘（每周一个文件，保留最近 4 周）
    2026-W16.md
```

运行时生成，不提交 git（.gitignore 忽略内容文件，保留目录骨架 .gitkeep）。

### README.md 格式

```markdown
# XHS 自进化知识库

## 阶段
当前: cold-start（0/28 篇，第 0 周）

## 当前生效的 Top Pattern
<!-- weekly_evolution() 自动更新 -->
暂无

## 本周关键发现
<!-- weekly_evolution() 自动更新 -->
暂无

## 规则文件索引
- [标题规则/内容规则/风格权重](rules.json)

## 近期复盘
<!-- 最近 4 周入口 -->
暂无
```

### patterns.md 格式

```markdown
# 活跃 Pattern 库

> 最后更新: 2026-04-15 | 活跃数: 5

---

### P01 | 数字清单体标题 | confidence: low | source: competitor
- **模板**: `{数字}{量词} + {人群}必备的 + {核心词}`
- **示例**: "5个程序员必备的AI效率工具"
- **适用**: 工具推荐、资源合集类选题
- **来源**: 竞品 top15 中 7 篇使用，平均收藏 1.2k
- **自己数据**: 待验证
- **使用次数**: 0 | **平均收藏率**: null
```

### rules.json 格式

```json
{
  "version": "2026-W16",
  "phase": "cold-start",
  "post_count": 0,
  "title": {
    "max_length": 20,
    "preferred_patterns": ["P01", "P02"],
    "hook_elements": ["数字", "痛点词", "效果词"],
    "forbidden": ["AI写的", "自动生成", "GPT"]
  },
  "content": {
    "max_length": 1000,
    "structure": "pain-point-solution-effect",
    "page_count": "5-6",
    "must_have_runnable_command": true,
    "cta_style": "收藏备用"
  },
  "tags": {
    "count": "5-8",
    "strategy": "2热门 + 3精准 + 1长尾"
  },
  "angle_weights": {
    "pain-point": 0.35,
    "tutorial": 0.35,
    "discovery": 0.30
  },
  "style_weights": {
    "casual-sharing": 0.40,
    "step-by-step": 0.35,
    "comparison": 0.25
  }
}
```

### reviews/周数据格式

```markdown
# 2026-W16 周数据（04/14 - 04/20）

## 总览
- 发布: 14 篇 | 总点赞: 342 | 总收藏: 189 | 总评论: 56
- 粉丝变化: +23
- 最佳帖子: #07 收藏率 9.1%
- 最差帖子: #03 收藏率 0.8%

## 逐篇数据

### #01 | 04/14 noon
- 标题: "5个让代码效率翻倍的AI工具"
- 角度: discovery | 风格: casual-sharing
- 标题模式: P01(数字清单体)
- 预测分: 72
- 实际: 👍48 ⭐32 💬8
- 增长曲线: T+1h(12/5/2) → T+6h(28/18/5) → T+24h(45/30/7) → T+72h(48/32/8)
- 收藏率: 5.2%

## 评分校准
- 本周预测分与收藏率 Spearman 相关: 0.43
- 偏差最大: #03 预测 78 实际收藏率 0.8%
```

### Pattern 生命周期

```
competitor(冷启动)        self-data(自己数据发现)
      ↓                         ↓
 confidence: low         status: experimental
      ↓ 被验证 1 次              ↓ 被验证 1 次
 confidence: medium      confidence: medium
      ↓ 连续 3+ 次有效           ↓ 连续 3+ 次有效
 confidence: high        confidence: high

 连续 3 次差 → deprecated（移出活跃列表）
 活跃 > 15 条 → 淘汰 confidence 最低的
```

## 四、冷启动机制

### 触发条件

knowledge-base/README.md 不存在时，由 Skill 层（Agent）执行。

### 流程

1. **配置 LLM**: 询问用户选择 LLM 提供商，编辑 runtime.env
2. **竞品搜索**: MCP search_feeds 搜索 3 组关键词，每组取 top 5
3. **详情提取**: 对 top 10 调 MCP get_feed_detail
4. **模式归纳**: Agent 分析提取标题模式/正文结构/高频标签/互动话术
5. **写入知识库**: patterns.md + rules.json + README.md

## 五、LLM 配置

### runtime.env 配置项

```bash
LLM_PROVIDER=claude           # claude | openai | openai-compatible
LLM_API_KEY=sk-xxx
LLM_BASE_URL=                 # 留空用官方默认
LLM_MODEL=claude-sonnet-4-20250514
```

### 统一调用接口 llm.py

scripts/ 新增 llm.py（~40 行），根据 LLM_PROVIDER 路由到 Anthropic SDK 或 OpenAI SDK。所有脚本中的 LLM 调用统一经过 llm.call_llm(prompt, system, max_tokens)。

## 六、脚本改造

### keepalive.py: +collect_pending_metrics()

每次运行时检查已发布帖子是否需要采集 T+1h/6h/24h/72h 数据。在目标时间 ±2 小时窗口内且未采集过该时间点时触发采集。约 +30 行。

post_metrics 表新增 checkpoint 字段：
```sql
ALTER TABLE post_metrics ADD COLUMN checkpoint TEXT DEFAULT 'review';
```

### review.py: +update_knowledge_phase() +weekly_evolution()

- update_knowledge_phase(): 每日运行，更新 README.md 中的帖子计数和阶段
- weekly_evolution(): 仅周日运行，执行进化分析：
  1. 从 SQLite 导出本周数据为 Markdown → reviews/
  2. 调 llm.call_llm() 传入周数据 + 当前 patterns + rules，要求返回结构化 JSON
  3. 程序化解析 JSON，更新 patterns.md / rules.json / README.md
  4. 清理 4 周前的旧复盘文件

约 +60 行。

### research.py / create_content.py: +build_prompt_with_knowledge()

构建 prompt 时额外读取 knowledge-base/ 文件，注入当前有效 pattern 和规则。约各 +15 行。

### db.py: +checkpoint 支持

post_metrics 表增加 checkpoint 字段，新增 has_metric_at_checkpoint() 和 get_metric_check_count() 方法。约 +20 行。

## 七、SKILL.md 新增段落

在现有 SKILL.md 末尾追加「自进化知识库」段落，包含：

- **首次初始化**: LLM 配置 + 竞品分析播种流程
- **创作时的知识读取**: 启动时读 README.md，创作前读 patterns.md + rules.json
- **知识库维护说明**: 定期更新由 workflow 脚本自动完成，Skill 不负责写入复盘

Skill 层只读不写（除冷启动外），Workflow 层只写不读交互。

## 八、阶段演进

| 阶段 | 条件 | 行为特征 |
|------|------|---------|
| cold-start | 帖子 < 10 | 依赖竞品 pattern（confidence: low），鼓励探索 |
| growth | 10 ≤ 帖子 < 30 | 开始用自己数据验证 pattern，规则权重首次被数据更新 |
| mature | 帖子 ≥ 30 | 完整归因分析，pattern 库以自己数据为主，权重完全数据驱动 |

## 九、异常处理

| 场景 | 处理 |
|------|------|
| LLM 调用失败 | 跳过进化步骤，不阻塞日报和发布 |
| knowledge-base/ 文件损坏 | try/except，用默认值，不阻塞创作 |
| patterns.md 为空 | 等同 cold-start，不注入 pattern |
| 周复盘时帖子 < 3 | 跳过进化（样本不足），只做数据汇总 |
| rules.json 解析失败 | 用硬编码默认规则 |

## 十、改动清单

| 文件 | 操作 | 行数 |
|------|------|------|
| skills/xiaohongshu/SKILL.md | 追加自进化段落 | ~60 行 |
| scripts/llm.py | **新增** | ~40 行 |
| scripts/keepalive.py | 改造 | ~30 行 |
| scripts/review.py | 改造 | ~60 行 |
| scripts/research.py | 改造 | ~15 行 |
| scripts/create_content.py | 改造 | ~15 行 |
| scripts/db.py | 改造 | ~20 行 |
| config/runtime.env.example | 改造 | ~5 行 |
| install.sh | 改造 | ~15 行 |
| knowledge-base/.gitkeep + .gitignore | **新增** | ~5 行 |
| **合计** | | **~265 行** |
