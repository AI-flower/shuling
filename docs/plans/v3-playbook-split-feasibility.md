# v3.0.0 Playbook 拆分可行性研究

> **角色**：v3.0.0 重构 Stage 0 必产物，作为正式 Stage 1（scaffold）合入 dev 的 PR 门禁
> **产出时间**：2026-04-27
> **基线版本**：v2.4.3
> **配套 ADR**：[0001-stateful-creator-agent.md](../adr/0001-stateful-creator-agent.md) · [0002-playbook-split-decisions.md](../adr/0002-playbook-split-decisions.md)

## 一、当前 SKILL.md 全景（基线数据）

- **总行数**：1204
- **物理切分点**：13 个二级标题、29 个三级标题
- **目标**：拆成 **9 个 playbook + 根 SKILL.md（≤150 行）+ 3 类新增非 playbook 资源**（`agent/scripts/README.md` / `agent/schemas/_meta.md` / `agent/playbook/_shared/`）

### 章节 → 行数总览

| 章节 | 行号 | 行数 | 性质 |
|---|---|---|---|
| 头部 frontmatter + 核心原则 | 1-30 | 30 | 入口 |
| §0a 业务路由 | 33-57 | 25 | 路由 |
| §0b 平台识别 + schema 校验 | 60-100 | 41 | 入口契约 |
| §0c 老博主接入 | 103-207 | 105 | 业务剧本 |
| §0 安装与环境检查 | 210-294 | 85 | 业务剧本 |
| §1 首次使用：建立画像 + 冷启动 | 297-399 | 103 | 业务剧本 |
| §2.1 选题研究 | 404-447 | 44 | 业务剧本 |
| §2.2 草稿生成 | 448-638 | **191** | 业务剧本（最大单章） |
| §2.3 图片生成 | 639-738 | 100 | 业务剧本 |
| §2.4 发布 | 739-765 | 27 | 业务剧本 |
| §3 每日复盘 | 769-862 | 94 | 业务剧本 |
| §4.1 用户偏好学习（核心算法） | 869-943 | 75 | 算法 |
| §4.2 内容效果分析 | 945-967 | 23 | 算法+复盘 |
| §4.3 周深度回顾 | 969-1040 | 72 | 业务剧本 |
| §5 内容合规 | 1043-1077 | 35 | 横切规则 |
| §6 工具参考 | 1079-1157 | 79 | 静态契约（非剧本） |
| §7 数据结构参考 | 1160-1185 | 26 | 静态契约（非剧本） |
| §8 异常处理 | 1188-1204 | 17 | 横切规则 |
| **总计** | | **1170**（不含空行/分隔） | |

## 二、9 路虚拟切片映射矩阵

| Playbook | 来源章节 | 估算行数 | 拆分难度 |
|---|---|---|---|
| **00-routing.md** | §0a + 核心原则路由相关 + §0b 平台识别 | ~70 | 🟢 低 |
| **01-onboarding-new.md** | §0（含 MCP 部分）+ §1 三问对话 + 冷启动播种 | ~190 | 🟡 中 |
| **02-onboarding-existing.md** | §0c 全部 + §0 共用部分（MCP 登录） | ~140 | 🟡 中 |
| **03-daily-flow.md** | §2.1 + §2.2 + §2.3 | ~340 | 🔴 高（最大） |
| **04-publish-flow.md** | §2.4 + 发布失败 / 重试补充 | ~70 | 🟢 低 |
| **05-review.md** | §3 全部 + §4.2 复盘部分 + §4.3 周回顾 | ~190 | 🟡 中 |
| **06-learning-loop.md** | §4.1 全部 + §4.2 算法部分 + §0c 偏好 bootstrap | ~120 | 🔴 高（算法权威定义） |
| **07-comment-insights.md** | §3 中评论提炼相关（10 行）+ 新增内容 | ~50 | 🟢 低（占位极简） |
| **08-compliance.md** | §5 内容合规 + §0b schema 校验细则 | ~95 | 🟡 中 |
| **09-troubleshooting.md** | §8 异常处理矩阵 + §0 安装故障分支 | ~110 | 🟢 低 |
| **总计 playbook** | | **~1375** | （含必要重述与 cross-ref 开销） |

### 新增非 playbook 资源

| 资源 | 来源 | 估算行数 | 用途 |
|---|---|---|---|
| `agent/scripts/README.md` | §6 工具参考 | ~85 | 脚本契约文档（playbook 通过 cross-ref 引用，避免命令被复制 9 份） |
| `agent/schemas/_meta.md` | §7 数据结构参考 | ~30 | knowledge-base + SQLite 表静态契约 |
| `agent/playbook/_shared/emoji-dictionary.md` | §2.2 emoji 词典 | ~20 | 03 + 08 共享 |
| `agent/playbook/_shared/confidence-mapping.md` | §2.1+§2.2+§4.1 信心度映射 | ~25 | 03/04/05/06 共享 |
| `agent/playbook/_shared/outline-template.txt` | §2.2 大纲范例 | ~70 | 03 + 05 共享（避免咖啡范例被复制） |
| `agent/playbook/_shared/post-meta-schema.json` | §2.3 末尾 meta.json | ~12 | 03 + 04 共享 |

### 根 SKILL.md（≤150 行）结构

| 段落 | 行数 |
|---|---|
| frontmatter | 5 |
| 项目定位 | 5 |
| 启动协议（4 步） | 15 |
| 路由速查表（9 行） | 15 |
| 全局禁令（6 条） | 15 |
| 异常入口指针 | 5 |
| 版本与变更指针 | 5 |
| 缓冲（注释、链接） | 25 |
| **合计** | **~90**（在 150 限内有 60 行余量） |

## 三、关键耦合点清单

按耦合强度从高到低排列。

### 🔴 强耦合（≥3 个 playbook 同时需要）

| # | 耦合项 | 涉及 playbook | 处理决议 |
|---|---|---|---|
| 1 | weight 公式 `(chosen+1)/(chosen+skipped+2)` | 03/04/05/06 | **extract → 06-learning-loop.md 唯一权威定义；其余用 cross-ref `→ 06-learning-loop.md#weight-formula`** |
| 2 | confidence_level 算法 `concentration × sample_factor` | 03/04/05/06 | **extract → 06-learning-loop.md** |
| 3 | ε-greedy 探索（≥7 天） | 03（选题数量决策）/ 06（标记 last_exploration_at） | **extract → 06-learning-loop.md** |
| 4 | consecutive_rejects 回弹 | 03 / 05 / 06 | **extract → 06-learning-loop.md** |
| 5 | confidence 决策档（<0.5→3 选 / ≥0.5→2 选 / ≥0.75→1 选） | 03（选题数量）/ 03（草稿份数）/ 04（重试） | **extract → `_shared/confidence-mapping.md`** |
| 6 | schema 校验入口（state / profile / preferences / audit-report） | 01/02/06/08 | **extract → 08-compliance.md 唯一权威表；其余 cross-ref** |
| 7 | MCP 状态预检 | 00/01/02/03/04 | **inline 在每个 playbook + cross-ref 到 09-troubleshooting.md** |
| 8 | §5 内容合规规则 | 03（草稿生成时检查）/ 04（发布前最终检查） | **split：草稿期 inline 在 03 / 发布期 inline 在 04 / 完整规则定义留 08** |

### 🟡 中耦合（2 个 playbook 共用）

| # | 耦合项 | 涉及 | 决议 |
|---|---|---|---|
| 9 | emoji 词典 | 03 / 08（禁用规则） | extract → `_shared/emoji-dictionary.md` |
| 10 | 大纲咖啡范例（70 行） | 03 / 05（审核大纲格式） | extract → `_shared/outline-template.txt` |
| 11 | meta.json schema | 03 / 04 | extract → `_shared/post-meta-schema.json` |
| 12 | 收藏率阈值（≥5% / 2-5% / <2%） | 05（日报）/ 06（weight 调整） | inline 在 06 + cross-ref |
| 13 | "配图建议：xxx" 格式硬约束 | 03（生成大纲）/ 03（生图读取） | inline 在 03（同 playbook 内） |
| 14 | imported posts 偏好 bootstrap | 02 / 06 | **inline 在 02（业务流程）+ cross-ref → 06**（算法权威） |

### 🟢 低耦合（独立或一处一定义）

15. preflight.py 输出 schema → 09-troubleshooting.md 唯一定义
16. NoteRx 五维诊断 → 05-review.md 唯一处理
17. 评论提炼 → 07-comment-insights.md 唯一处理（极简）

## 四、§2.2 巨型章节（191 行）拆分策略

§2.2 是整个 SKILL.md 最大的单章，必须显式给拆分方案：

| 子段落 | 行号 | 行数 | 处理 |
|---|---|---|---|
| 核心心法（4 条） | 452-457 | 6 | 留 03（导言） |
| Emoji 词典 | 459-474 | 16 | **extract → `_shared/emoji-dictionary.md`** |
| 步骤 1（读规则） | 477-485 | 9 | 留 03 |
| 步骤 2（生成大纲）+ 咖啡范例 | 487-577 | 91 | 范例 **extract → `_shared/outline-template.txt`**；硬规则留 03 |
| 步骤 3（文案 JSON） | 579-619 | 41 | 留 03（标题/正文/标签硬规则） |
| 步骤 4-6（份数+返回+记录） | 620-636 | 17 | 留 03 |

**结果**：§2.2 实际进 03-daily-flow.md 的内容 ≈ 84 行（从 191 缩到 84，extract 出 107 行到 shared）。

## 五、行数失衡评估（最终预测）

| Playbook | 预测行数 | 评级 |
|---|---|---|
| 03-daily-flow.md | ~340 | ⚠ 偏重，但可接受（业务最重） |
| 01-onboarding-new.md | ~190 | ✓ 正常 |
| 05-review.md | ~190 | ✓ 正常 |
| 02-onboarding-existing.md | ~140 | ✓ 正常 |
| 06-learning-loop.md | ~120 | ✓ 正常 |
| 09-troubleshooting.md | ~110 | ✓ 正常 |
| 08-compliance.md | ~95 | ✓ 正常 |
| 00-routing.md | ~70 | ✓ 正常 |
| 04-publish-flow.md | ~70 | ✓ 正常 |
| 07-comment-insights.md | ~50 | ⚠ 偏轻（v3.0 仅占位，未来扩展） |

**结论**：✅ **不会出现"3 个 800 行 + 6 个 50 行"的严重失衡**。最大 03 ≈ 340 行，最小 07 ≈ 50 行，比例 6.8:1，**在可接受范围内**（业务重的 03 本来就该重）。

## 六、必须解决的拆分难点（优先级排序）

### P0 必须在 Stage 1 之前定结论（已固化到 ADR-0002）

1. **算法公式权威来源**：06-learning-loop.md 顶部加显式标记 "⚠ 公式权威来源：本文件是 weight / confidence / ε-greedy / consecutive_rejects 的**唯一**定义。其他 playbook 引用必须 cross-ref，禁止复述公式"。verify 第 31 条新增："其他 playbook 不得包含 `(chosen+1)/(chosen+skipped+2)` 字符串"。

2. **冷启动 vs 老博主接入的"竞品分析"互斥**：01 和 02 各自描述自己的版本，**不抽到 shared**（业务语义差太大，强抽会失真）。

3. **profile 更新权限的逻辑反转**：01 和 02 各自在 frontmatter 标注 `writes: profile.json`，但加 `preconditions` 字段：
   - 01: `profile.json NOT EXISTS`
   - 02: `creator_mode == 'existing' AND existing_import_done == false`
   verify 第 32 条："任何 playbook 写 profile.json 必须有显式 preconditions"。

### P1 在 Stage 2-4 期间解决

4. **§5 内容合规的"草稿期 vs 发布期"边界**：定义两组规则：
   - `compliance.draft_time_rules` = 绝对禁止 + 格式 + 风格（生成时检查）→ 03 inline
   - `compliance.publish_time_rules` = 标题模式 + 质量标准（发布前 QA 闸门）→ 04 inline
   - 完整规则正文 → 08

5. **MCP 可选性分支**：01 frontmatter `needs.optional: [MCP]`，含降级路径"MCP 未就绪则跳过竞品分析，仅完成画像写入"。

### P2 v3.0 收尾或 v3.1 解决

6. **07-comment-insights.md 仅 50 行**：可接受作为占位 playbook；v3.1 评论分析独立时再丰富。
7. **§4.3 周深度回顾**：暂归 05-review.md（同复盘语义）；如果未来周报扩展，再单独拆 `05b-weekly-review.md`。

## 七、可行性结论

✅ **9 路拆分可行**，建议正式开工进入 Stage 1。

### 必须前置确认的 5 个决议

1. ✅ 06-learning-loop.md 是所有学习算法的**唯一权威定义**，其他 playbook 必须 cross-ref
2. ✅ 03-daily-flow.md 接受 ~340 行（业务最重，合理）
3. ✅ 拆出 4 个 `_shared/` 资源（emoji 词典 / confidence 映射 / 大纲范例 / meta.json schema）
4. ✅ §6 工具参考独立到 `agent/scripts/README.md`（不进任何 playbook，避免命令被复制 9 份）
5. ✅ §7 数据结构独立到 `agent/schemas/_meta.md`（静态契约，不进 playbook）

### 拒绝的反提案

- ❌ "把 §2.1+§2.2+§2.3+§2.4 全合并到 03-daily-flow.md" → 拒绝。§2.4 发布动作单独拆 04，留扩展空间（重试 / 失败处理 / 草稿存档）。
- ❌ "把 §4 自进化全部合并到 05-review.md" → 拒绝。§4.1 是算法权威定义，必须独立 06，否则被多处复述风险大。
- ❌ "07-comment-insights.md 太薄就并到 05" → 拒绝。占位独立 playbook 给 v3.1 留扩展位，符合"演进而非革命"哲学。

### Stage 1 准入条件（PR checklist）

- [x] 本文档（`docs/plans/v3-playbook-split-feasibility.md`）合入 dev 分支
- [x] ADR-0001 + ADR-0002 写入 `docs/adr/`
- [ ] 9 个 playbook 文件在 `agent/playbook/` 下创建空骨架（仅 frontmatter）
- [ ] 4 个 `_shared/` 资源在 `agent/playbook/_shared/` 下创建空骨架
- [ ] `agent/scripts/README.md` 和 `agent/schemas/_meta.md` 创建空骨架
- [ ] verify 第 31/32 条已有占位脚本（实现可在 Stage 8）
