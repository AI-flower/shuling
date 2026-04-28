# ADR-0002：v3.0.0 Playbook 拆分关键决议

- **Status**: Accepted
- **Date**: 2026-04-27
- **Deciders**: AI-flower（Owner）+ AI 协助分析
- **Related**: [ADR-0001 Stateful Creator Agent](0001-stateful-creator-agent.md) · [feasibility study](../plans/v3-playbook-split-feasibility.md)

## 上下文

ADR-0001 决定把 v2.4.3 的 SKILL.md（1204 行）拆成 9 个 playbook + 根入口。Stage 0 假拆分演练（feasibility study）暴露出三个 P0 拆分难点，必须在 Stage 1 scaffold 之前给出明文决议，否则后续阶段会反复返工。

本 ADR 固化这三个 P0 决议 + 2 个 P1 决议，作为 verify 门禁规则的依据。

## 决策

### D1：算法公式权威来源（P0）

**问题**：weight / confidence / ε-greedy / consecutive_rejects 等学习算法被 03/04/05/06 多个 playbook 引用，如何避免被复述多份导致版本分裂？

**决议**：

- **06-learning-loop.md 是所有学习算法的唯一权威定义文件**
- 06 文件顶部必须有显式标记：
  ```markdown
  > ⚠ **公式权威来源**：本文件是 weight / confidence / ε-greedy / consecutive_rejects 的**唯一**定义。
  > 其他 playbook 引用必须 cross-ref，禁止复述公式。
  ```
- 其他 playbook 引用算法时必须用 cross-ref 链接（例如 `→ 06-learning-loop.md#weight-formula`）
- **verify 门禁第 31 条**：扫描 `agent/playbook/0[0-9]-*.md` 中除 `06-learning-loop.md` 外的所有文件，禁止包含字符串 `(chosen+1)/(chosen+skipped+2)`、`concentration × sample_factor`、`ε-greedy`（用作非引用形式时）

**例外**：`02-onboarding-existing.md` 的"偏好 bootstrap"涉及虚拟选择记录写入，**inline 业务流程描述允许**，但公式部分必须 cross-ref。

### D2：冷启动 vs 老博主"竞品分析"互斥（P0）

**问题**：§1（新博主）和 §0c（老博主）都包含"竞品分析"步骤，但语义差异巨大：
- §1：从外部竞品账号挖 patterns，标记 `confidence=low`
- §0c：从用户自己历史挖 patterns，标记 `confidence=medium`

**决议**：

- **不抽到 `_shared/`**——业务语义差太大，强抽会失真，导致后续维护时反复调整 shared 文件破坏两边语义
- 01 和 02 各自描述自己的版本，文档上下文清晰
- 共享的只是"调用 `xhs.sh search`"这个工具调用模式，归 `agent/scripts/README.md` 处理

### D3：profile 更新权限的逻辑反转（P0）

**问题**：§1 说"profile.json 已存在则绝不再问"，但 §0c 允许"展示给用户微调"。两条规则在 v2.x SKILL.md 里靠语境区分，拆成 playbook 后必须显式化。

**决议**：

- 01 和 02 的 frontmatter 必须有显式 `preconditions` 字段：
  - `01-onboarding-new.md`: `preconditions: ["NOT EXISTS knowledge-base/profile.json"]`
  - `02-onboarding-existing.md`: `preconditions: ["state.creator_mode == 'existing'", "state.existing_import_done == false"]`
- **verify 门禁第 32 条**：任何 playbook 在 `writes.files` 中包含 `agent/knowledge-base/profile.json` 时，frontmatter 必须有非空 `preconditions` 字段
- 00-routing.md 路由表显式列出"`profile.json` 已存在 → 跳过 01 和 02，直接进 03"

### D4：内容合规规则的草稿期 vs 发布期边界（P1）

**问题**：§5 内容合规规则 35 行，被 03（草稿生成时检查）和 04（发布前最终检查）两处使用。完全 inline 会重复 35 行；完全 extract 会让 03/04 失去自包含语义。

**决议**：拆两组规则：

| 规则组 | 内容 | 检查时机 | 归属 |
|---|---|---|---|
| `compliance.draft_time_rules` | 绝对禁止 + 格式 + 风格（生成时硬约束） | 03 草稿生成步骤 1 | 03 inline（≤15 行摘要）+ cross-ref → 08 |
| `compliance.publish_time_rules` | 标题模式 + 质量标准（发布前 QA 闸门） | 04 发布前 | 04 inline（≤10 行摘要）+ cross-ref → 08 |
| `compliance.full_rules` | §5 完整正文 | 长期参考 | 08-compliance.md（唯一权威） |

**verify 第 33 条**：03 和 04 中的"compliance"段落不得超过各自规定行数（避免完整复述 §5）。

### D5：MCP 可选性分支（P1）

**问题**：§1 冷启动播种依赖 MCP（要 `xhs.sh search` 抓竞品），但 §1 整体不应该被 MCP 阻塞（画像建立可以先完成）。

**决议**：

- `01-onboarding-new.md` frontmatter 加：
  ```yaml
  needs:
    required: [profile.schema.json]
    optional:
      - mcp:
          fallback: "MCP 未就绪则跳过竞品分析步骤，仅完成画像写入与默认 preferences.json 初始化；待 MCP 就绪后再补冷启动播种"
  ```
- 降级路径写入 playbook 正文 `## Failure Handling` 段落
- **verify 第 34 条**：任何 playbook 的 `needs.optional` 必须含 `fallback` 字符串字段

## 拒绝的反提案

- ❌ "把 §2 全合并到 03-daily-flow.md"——§2.4 发布动作单独拆 04，留扩展空间
- ❌ "把 §4 自进化全合并到 05-review.md"——§4.1 是算法权威定义，必须独立 06
- ❌ "07-comment-insights.md 太薄就并到 05"——占位独立给 v3.1 留扩展位
- ❌ "把 emoji 词典留在 03 不抽 shared"——08 合规规则需要"禁用 emoji"列表，必须共享词典基线

## 后果

### 正面

- 算法版本分裂风险被门禁机制根除
- profile 写入权限有显式 preconditions 校验
- 草稿期/发布期合规规则边界清晰，03/04 各自自包含
- MCP 降级路径在 frontmatter 层面机器可校验

### 负面

- verify 门禁从 25 条扩到 34 条，实施成本增加
- playbook 作者必须理解 cross-ref 写法、preconditions 语义、optional + fallback 契约
- 03 和 04 各自 inline 一份合规摘要，存在轻微冗余（但限定行数控制规模）

## verify 门禁新增条款汇总

| # | 检查项 | 严重级 | 实现位置 |
|---|---|---|---|
| 31 | 非 06 的 playbook 不得复述算法公式字符串 | error | `ops/verify/checks/31-algorithm-uniqueness.sh` |
| 32 | 写 profile.json 的 playbook 必须有非空 preconditions | error | `ops/verify/checks/32-profile-write-precondition.sh` |
| 33 | 03/04 的 compliance 段落不得超出限定行数 | warn | `ops/verify/checks/33-compliance-inline-limit.sh` |
| 34 | needs.optional 必须有 fallback 字段 | error | `ops/verify/checks/34-optional-fallback.sh` |
