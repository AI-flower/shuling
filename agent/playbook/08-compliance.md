---
id: 08-compliance
title: Content Compliance
when:
  - "草稿生成前后规则检查"
  - "发布前 QA 闸门"
  - "schema 写入前校验"
needs:
  required:
    - agent/policies/content-rules.md
    - agent/schemas/state.schema.json
    - agent/schemas/profile.schema.json
    - agent/schemas/preferences.schema.json
    - agent/schemas/audit-report.schema.json
calls:
  scripts:
    - agent/scripts/validate.py
writes:
  files: []
preconditions: []
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
---

# 08 Content Compliance

## Trigger

- 03-daily-flow.md 草稿生成前/后（草稿期硬约束）
- 04-publish-flow.md 调 `xhs.sh publish` 前（发布期 QA 闸门）
- 任何写入 `agent/config/state.json` / `agent/knowledge-base/profile.json` / `agent/knowledge-base/preferences.json` / `agent/knowledge-base/audit-*.json` 之前（schema 校验）
- 01/02 写画像或偏好初值之前

## Read This When

- 任何 playbook 即将向 JSON 文件落盘前必读本节 Schema Validation
- 03 生成大纲/正文/标签之前必读 Draft Time Rules
- 04 调 publish 之前必读 Publish Time Rules
- 06 写 patterns.md / anti-patterns.md 时按 schema-degraded mode 兜底（见 09-troubleshooting.md）

## Inputs

- 待校验的 JSON 文件路径（state / profile / preferences / audit-report）
- 当前草稿对象（titles / copywriting / tags / outline）
- 待发布的 meta.json（标题、正文、标签、图片路径数组）

## Procedure

### Schema Validation

**写入前必校验**：每次写入 `agent/config/state.json` / `agent/knowledge-base/profile.json` / `agent/knowledge-base/preferences.json` 之前，先读对应 JSON Schema，确保字段名、类型、枚举值符合约定：

| 目标文件 | Schema |
|---|---|
| `agent/config/state.json` | `agent/schemas/state.schema.json` |
| `agent/knowledge-base/profile.json` | `agent/schemas/profile.schema.json` |
| `agent/knowledge-base/preferences.json` | `agent/schemas/preferences.schema.json` |
| `agent/knowledge-base/audit-*.json` | `agent/schemas/audit-report.schema.json` |

**关键纪律**：

- **日期字段一律 `YYYY-MM-DD`**（如 `created_at / updated_at / setup_date`），不要用 `createdAt`、ISO 时间戳或本地化格式
- **必填字段不得缺**：`profile.json` 必须有 `niche / audience / tone / created_at`；`preferences.json` 必须有 `dimensions / total_choices / confidence_level / updated_at`
- **`weight` 值范围 `[0.0, 1.0]`**；越界先回查公式权威定义再写（cross-ref → [`06-learning-loop.md` Bayesian-Laplace Weight Formula](06-learning-loop.md#bayesian-laplace-weight-formula)）
- **`confidence_level` 不是 weight**，两者算法不同；详细公式权威见 [`06-learning-loop.md` Confidence Level](06-learning-loop.md#confidence-level)
- **`dimension` 只能是 `topic` / `style` / `title_pattern`**，别造新维度；要加维度走 BRAIN 版本号并更新 schema

可选验证命令（环境有 `jsonschema` 包时）：

```bash
python3 -m jsonschema -i agent/knowledge-base/profile.json agent/schemas/profile.schema.json
```

### Draft Time Rules（草稿期硬约束）

**生成草稿前必读** `agent/policies/content-rules.md`。以下是核心规则：

**绝对禁止**：

- 不提及任何平台名或导流信息
- 不提及区块链/虚拟货币/Web3/NFT
- 不写"用 AI 写小红书"类主题
- 不出现费用/价格信息
- 不加篇数编号

**格式要求**：

- 标题 ≤ 20 字
- 正文 ≤ 1000 字
- 标签 5-8 个

**写作风格**：

- 口语化、有真人感
- 适量 emoji，不过度（emoji 总量控制 cross-ref → `_shared/emoji-dictionary.md`）
- 痛点 → 解决方案 → 效果展示结构
- 不能读起来像 AI 生成

### Publish Time Rules（发布前 QA 闸门）

**标题模式**（优先使用 patterns.md 中 `confidence ≥ medium` 的）：

- 数字清单体："5 个 XX 工具"
- 反差悬念体："被吹上天，普通人到底怎么用？"
- 结果导向体："3 分钟搞定 500 行数据"
- 身份共鸣体："打工人" / "一人公司"
- 保姆级体："手把手" / "0 基础"

**质量标准**：

- 教程类必须有可操作步骤（完整命令，不能只写"安装依赖"）
- 每页 3-5 个信息点
- 不能整页只有标题无内容

## Writes

本剧本不直接写入；仅返回 `pass / fail` + 错误清单给调用方。

## Failure Handling

- Schema 校验失败 → 返回结构化错误（字段名 + 期望类型 + 实际值）给调用方，由调用方决定回退或重写
- Draft Time Rules 命中绝对禁止项 → 拒绝该草稿，要求 03 重新生成
- Publish Time Rules 命中质量问题 → 阻塞发布，回 03 修订
- 不自行修复用户文本（避免越权改写用户内容）；on_failure 跳 09-troubleshooting.md

## Anti-Patterns

- 不允许 03/04 完整复述本文件规则（仅允许 ≤15 行/≤10 行摘要 + cross-ref）
- 日期字段一律 YYYY-MM-DD
- weight 值必须在 [0.0, 1.0]
- confidence_level 不是 weight，不要混用
- dimension 只能是 topic/style/title_pattern

## Cross-Refs

被 01-onboarding-new.md / 02-onboarding-existing.md / 03-daily-flow.md / 04-publish-flow.md / 06-learning-loop.md 引用。

- → `_shared/emoji-dictionary.md`（emoji 总量控制基线）
- → 06-learning-loop.md（weight/confidence 公式权威）
- → 09-troubleshooting.md（schema 校验失败兜底）
