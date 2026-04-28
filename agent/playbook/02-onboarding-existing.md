---
id: 02-onboarding-existing
title: Existing Creator Onboarding
when:
  - "用户自述已有运营账号"
  - "creator_mode=existing"
  - "install --mode=existing-creator"
needs:
  required:
    - agent/schemas/profile.schema.json
    - agent/schemas/audit-report.schema.json
calls:
  scripts:
    - agent/scripts/xhs.sh
    - agent/scripts/import-existing.sh
    - agent/scripts/audit-report.sh
    - agent/scripts/db.sh
  playbooks:
    - 06-learning-loop.md
writes:
  files:
    - agent/data/xhs.db (posts source=imported)
    - agent/knowledge-base/profile.json
    - agent/knowledge-base/audit-*.{md,json}
    - agent/knowledge-base/patterns.md
preconditions:
  - "state.creator_mode == 'existing'"
  - "state.existing_import_done == false"
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
---

# 02 Existing Creator Onboarding

> 跟 `01-onboarding-new.md` 中的"Profile Building"段**互斥**。老博主进这条路，**不走三问对话**，不走竞品冷启动。

## Trigger

任一满足即进本剧本：

1. 用户自述"我已经在运营小红书"、"已经有账号了"、"已经发过帖"、"我的号粉丝已经 XXX"
2. `agent/config/state.json` 中 `creator_mode == 'existing'`
3. 用户用 `bash install.sh --mode=existing-creator` 装的
4. `agent/config/state.json` 中 `existing_import_done == false` 但 `creator_mode == 'existing'`（流程未走完，由 `00-routing.md` 引回本剧本）

## Read This When

老博主第一次接入薯灵；或上次接入流程在批量导入 / 画像反推 / 体检报告任一步中断，由路由表把控制权交回本剧本。**不要因为 profile.json 缺失就跳到 01。**

## Inputs

- 用户已登录的小红书账号（`agent/scripts/xhs.sh status` 报 OK）
- MCP 的 `list_feeds` 能返回该账号的历史帖列表（v2.2.0 MVP 阶段如未完成则降级，见 Failure Handling）
- 最近 30 条 `imported` 样本（标题 + 正文前 200 字）—— 第 4 步反推画像的素材
- `agent/schemas/profile.schema.json` / `agent/schemas/audit-report.schema.json` —— 写盘前校验依据

## Procedure

**第 1 步 · 确认账号登录**（复用 `01-onboarding-new.md` 的登录策略）

- 用户主动提议 cookie → 立即接受：`bash agent/scripts/xhs.sh import-cookie '<cookie字符串>'`
- 否则 `bash agent/scripts/xhs.sh login` 扫码

**第 2 步 · 批量导入历史**

```bash
bash agent/scripts/import-existing.sh --limit 200
# 耗时：按节流 profile 约 30+ 分钟；可挂后台
# 中断续跑：bash agent/scripts/import-existing.sh --resume
```

- 如果用户帖数少（< 30），降级跳过本剧本改走 `01-onboarding-new.md` 的三问对话，但提醒用户"历史太少，画像反推置信度低"
- 如果 MCP `list_feeds` 集成未完成，必须告诉用户"此功能在 v2.2.0 MVP 阶段仅支持 `--mock` 路径"，然后回退到 `01-onboarding-new.md`

**第 3 步 · 自动分类 imported posts**

- 读 `posts WHERE source='imported' AND topic_type IS NULL`
- 小批量（每批 20 条）调 LLM（你自己）分类：
  - `topic_type` —— 从账号整体话题聚类中选（先做聚类，再套枚举）
  - `title_pattern` —— 数字清单 / 反差悬念 / 结果导向 / 问句 / 对比 / 其它
  - `content_style` —— 口语 / 干货 / 幽默 / 犀利 / 故事 / 教程
- 分类结果通过 `bash agent/scripts/db.sh update-post-meta '<json>'` 回写
- 分类不出来的标 `__unclassified__`，**不计入**偏好 bootstrap

**第 4 步 · 画像反推**

- 读最近 30 条 `imported` 样本（title + content 前 200 字）
- AI 做聚类分析，产出 `profile.json` **草案**：

```json
{
  "niche": "<推测的领域，必须从样本中来>",
  "audience": "<目标受众的具体描述>",
  "tone": "<口语/干货/幽默/犀利/...>",
  "goals": "<如有线索，留空也行>",
  "created_at": "<今日>",
  "updated_at": "<今日>"
}
```

- **必须展示给用户确认**：
  > "基于你 30 条历史帖，我推测你是 `<niche>` 方向，面向 `<audience>`，风格 `<tone>`。对吗？"
- 用户确认 / 微调 / 推翻后才写入 `agent/knowledge-base/profile.json`（先按 `agent/schemas/profile.schema.json` 校验字段）
- 如果样本跨多领域：展示多个候选方向，**让用户决策主攻**，不擅自合并

**第 5 步 · 挖 patterns 种子 + 出体检报告**

```bash
bash agent/scripts/audit-report.sh --extract-patterns
# 产出:
#   agent/knowledge-base/audit-<YYYY-MM-DD>.json   机器可读
#   agent/knowledge-base/audit-<YYYY-MM-DD>.md     人类可读骨架
```

- AI 读 JSON → 对 `extract_patterns.pattern_candidates` 做二次抽象（标题结构 / 情绪钩子 / 核心结构），**重复 ≥ 3 次的模式**写入 `agent/knowledge-base/patterns.md`（**confidence=medium**，因为是用户自己的历史验证）
- `anti_pattern_candidates` 同样抽象 → `agent/knowledge-base/anti-patterns.md`（confidence=medium）
- AI 对 JSON 做归因分析（为什么 Top/Bottom 这样）→ 填 `ai_narrative` 字段并追加到配套 `.md` 文件
- AI 的 `ai_narrative` 必须按 `agent/schemas/audit-report.schema.json` 的 `ai_narrative` 子 schema 写（`written_at / top_reasoning / bottom_reasoning / action_items[] / watch_signals[]`）

**流程结束后写 state.json**：

```json
{
  "creator_mode": "existing",
  "existing_import_done": true,
  "profile_created": true,
  "cold_start_done": true,
  "setup_completed": true,
  "setup_date": "<今日>"
}
```

注意：`cold_start_done=true` 是因为 patterns.md 已经从用户自己历史挖到了种子，不必再跑竞品冷启动。

### 偏好 bootstrap（本剧本自动做）

- 对每条分类后的 imported post 写一条"隐式选择"记录：
  - `choice_type` = `topic` / `title_pattern` / `content_style` 三次
  - 虚拟 `offered_count = 3`，`chosen_label = <本帖的分类值>`，`skipped_labels = ["__implicit_unknown__", "__implicit_unknown__"]`
  - 通过 `bash agent/scripts/db.sh log-choice '<json>'` 写入 `user_choices` 表
- `preferences.json` 由日常学习循环从 `user_choices` 聚合 —— **见 `06-learning-loop.md` 关于 `total_choices` 封顶 50 与 `sample_factor` 处理**（避免 170 条历史让 `sample_factor` 直接 = 1.0 → 立即进 1 选档；预留后续真实用户选择的学习空间）

### 关键纪律

- **不要走 01 的三问对话**：用户已经用行为回答了所有问题
- **不要让用户从零填画像**：AI 反推 + 用户确认 / 微调
- **多方向账号不擅自合并**：展示给用户让他决策主攻方向
- **import 中断必可续**：`--resume`，不重来
- **失败单条跳过**：不让 1 条脏数据中断 199 条好数据
- **imported posts 不纳入每日复盘**：`05-review.md` 复盘只看 `source='shuling'`（不然老博主历史帖会被当成"今日新发"反复分析）；需要时用 `audit-report.sh --include-organic`

### 与 00-routing.md 业务路由的协同

路由表扩展：

| 当前状态 | 下一步 |
|---------|------|
| `creator_mode=existing` 且 `existing_import_done=true` 且 `setup_completed=true` | 直接进 `03-daily-flow.md`（imported 历史已生效） |
| `creator_mode=existing` 且 `existing_import_done=false` | 进入本剧本继续未完成步骤（不要跳回 `01-onboarding-new.md`） |
| `creator_mode=new` 或 `unset` | 走原路径（`01-onboarding-new.md` → `03-daily-flow.md`） |

## Writes

- `agent/data/xhs.db`
  - `posts` 表追加 `source='imported'` 行（第 2 步）
  - `posts` 表 `topic_type / title_pattern / content_style` 字段回写（第 3 步）
  - `user_choices` 表追加隐式选择记录（偏好 bootstrap）
- `agent/knowledge-base/profile.json` —— 第 4 步用户确认后写入；按 `agent/schemas/profile.schema.json` 校验
- `agent/knowledge-base/audit-<YYYY-MM-DD>.json` / `.md` —— 第 5 步生成
- `agent/knowledge-base/patterns.md` / `anti-patterns.md` —— 第 5 步追加（confidence=medium）
- `agent/config/state.json` —— 流程末尾写入完整 milestone 块（见上）

## Failure Handling

- **import 中断**（网络 / 节流 / 用户中断）→ `bash agent/scripts/import-existing.sh --resume`，**不重来**；已成功的行不重复写入
- **MCP `list_feeds` 未完成 / 返回空** → 告知用户当前阶段仅支持 `--mock`，回退到 `01-onboarding-new.md` 三问对话
- **用户帖数 < 30** → 降级到 `01-onboarding-new.md`；提醒"画像反推置信度低"
- **单条解析失败** → 跳过该条；记录到 `request_log`；不让 1 条脏数据中断剩余批次
- **画像反推用户全盘推翻** → 不要硬塞；改用 `01-onboarding-new.md` 的三问对话补齐 `niche / audience / tone`，但 imported 历史保留（源仍为 `existing`）
- **schema 校验失败** → 不写 `profile.json` / 不写 `audit-*.json`；详见 `08-compliance.md`

## Anti-Patterns
- 不走 §1 三问对话
- 不让用户从零填画像
- 多方向不擅自合并
- imported posts 不纳入每日复盘
- import 中断必可续

## Cross-Refs
- → 00-routing.md（路由表决定本剧本是否被命中以及何时切回 03）
- → 01-onboarding-new.md（帖数过少 / `list_feeds` 不可用时的降级路径）
- → 03-daily-flow.md（流程结束后默认入口）
- → 05-review.md（夜间复盘只看 `source='shuling'` 的纪律来源）
- → 06-learning-loop.md（偏好 bootstrap 公式来源 + `sample_factor` 封顶处理）
- → 08-compliance.md（schema 校验细则）
- → 09-troubleshooting.md（任何步骤失败）
