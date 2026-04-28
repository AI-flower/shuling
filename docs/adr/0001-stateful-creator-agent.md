# ADR-0001：薯灵 v3.0.0 重构为 Stateful Creator Agent

- **Status**: Accepted
- **Date**: 2026-04-27
- **Deciders**: AI-flower（Owner）+ AI 协助分析
- **Supersedes**: 无（v2.x 没有显式架构 ADR）
- **Related**: [ADR-0002 Playbook 拆分决议](0002-playbook-split-decisions.md) · [feasibility study](../plans/v3-playbook-split-feasibility.md)

## 上下文

v2.4.3 之前，薯灵的物理结构是"标准 Skill 包"：根目录平铺 `SKILL.md / scripts/ / data/ / config/ / knowledge-base/ / migrations/ / upgrade-hooks/`，安装时 `install.sh` 把整棵树 rsync 到 target（`~/.hermes/skills/shuling` 等）。

这种结构在 v2.x 累积出几个根本性张力：

1. **职责混淆**：`scripts/` 既是 skill 内含手脚（target 运行时需要），又是仓库构建/发版工具（target 不需要）；`docs/` 既有用户文档（target 不需要），又有 platform 适配（target 可能需要）。
2. **源 vs target 路径漏洞**：v2.4.2 一次性修了 5 个 bug，全部围绕"`scripts/db.sh` / `migrations/v*.sh` / `_guard.sh` 在被 install.sh 调用时不知道自己在操作源还是 target"。结构性问题没解。
3. **SKILL.md 1204 行单文件**：AI 每次进项目都吞完整剧本，token 成本高、决策不准、修改时易踩跨章节耦合。
4. **install.sh 失效路径**：用户只 `git pull` 不跑 `install.sh` 就没法升级 schema 或 runtime 布局；v2.4.0 引入 `__migrations` 表 + `_guard.sh` 是缓解但没有自愈入口。
5. **业务认知偏置**：v2.x SKILL.md 默认示例（"AI 工具推荐 / GitHub trending / 程序员"）让画像反推被 prompt 污染；中性化是 v2.4.x 系列在做但不彻底的事。

继续往 v2.5 迭代会让这些张力进一步累积；本 ADR 决定借 v3.0 一次性重构。

## 决策

**薯灵 v3.0.0 不再追求"标准 Skill 包"，而是 Stateful Creator Agent with Skill Bridge。**

三层心智模型：

```
Claude Code / Codex / Hermes / OpenClaw  ← 宿主平台
            ↓
SKILL.md  ← 协议适配层（≤150 行，桥梁、入口、路由、全局约束）
            ↓
agent/    ← 业务内核（playbook + scripts + schemas + prompts + policies + migrations + runtime state）
            ↓
ops/      ← 部署运维层（install / cron / verify / layout-migrations）
```

### 三层职责边界

| 层 | 物理目录 | 职责 | 是否进 target |
|---|---|---|---|
| 协议层 | `SKILL.md` + `agents/` | 对接宿主 agent 平台 | ✅ |
| 业务内核 | `agent/` | 长期运营大脑 + 手脚 + 记忆 + 迁移 | ✅ |
| 部署运维 | `ops/` | 安装、cron、验证、发版维护 | ❌（仅源仓库） |
| 工程支撑 | `build/ docs/ site/ marketing/ legacy/ dist/ dev/` | 构建工具、文档、营销、归档、本地痕迹 | ❌ |

### 12 条总原则（v3.0 全程必须遵守）

1. **根 SKILL.md 只做入口**：识别意图、初始化、路由、全局约束。
2. **agent/ 是业务本体**：playbook、scripts、schemas、prompts、policies、migrations、runtime state 都归这里。
3. **ops/ 只做部署维护**：install、layout migration、cron 模板、verify。
4. **用户态数据永远不覆盖**：`agent/data/xhs.db`、`agent/config/runtime.env`、`agent/knowledge-base/`。
5. **v3.0 允许 target 布局 major migration**，但必须 copy-first、幂等、可回滚。
6. **legacy 可保留历史偏置；active runtime/docs 必须通用化**。
7. **Active vs Inactive 显式分区**：active = 根 SKILL.md + agents/ + agent/ + ops/ + build/；inactive = docs/ + site/ + marketing/ + legacy/ + dist/。verify 门禁的代码引用一致性规则只对 active 区域生效。
8. **演进而非革命**：所有 v2.x 已有基础设施（`__migrations` 表、`_guard.sh`、`upgrade-hooks` 单参数+JSON 契约、`pre-submit-verify.sh`）必须在 v3.0 中找到对应位置，不允许"重写为 v3 新机制"。
9. **路径单一来源**：所有"运行时文件路径"在仓库内只有一个权威定义（`agent/scripts/_paths.sh`），脚本一律 source 它，禁止 hardcode。
10. **schema breaking = BRAIN +1**：`agent/schemas/*.schema.json` 不向后兼容时强制升 BRAIN 位，对齐 SKILL.md 的版本纪律。
11. **每个剧本可独立运行**：playbook 之间不允许"读上一段对话上下文"的隐性依赖；状态必须落地 `agent/data/xhs.db` 或 `agent/knowledge-base/`。
12. **降级路径强制**：每个引入的新机制必须给出"如果该机制不可用怎么办"。例如 `ensure-schema` 失败时如何让 db.sh 仍可读不可写，而不是整体 crash。

## 后果

### 正面

- **AI token 成本下降**：playbook 按需加载，不再每次吞 1200 行。
- **结构性解决源/target 隔离问题**：`agent/` 自包含，`ops/` 只在源端，路径混淆从根上消失。
- **runtime 自愈**：`ensure-runtime-layout` + `ensure-schema` 让 `git pull` 用户也能升级。
- **playbook 可机器校验**：frontmatter（`when / needs / calls / writes / on_failure`）让依赖图、引用一致性、preconditions 全部能被 verify 门禁覆盖。
- **package 干净**：dist 只剩 `SKILL.md / VERSION / agents/ / agent/` 4 个顶级条目，社区 verifier 一眼判定为标准 skill。

### 负面 / 成本

- **breaking change**：v2 → v3 是 target 布局 major migration，必须 BRAIN +1。所有 v2.x 用户升级前需要备份。
- **学习曲线**：贡献者需要理解三层心智模型、playbook frontmatter 规范、四类 migration 归属决策树。
- **新增工程量**：30 条 verify 门禁（v2.x 是 21 条）、`ensure-*` 自愈、layout-migrations、disaster-recovery、ADR、feasibility study、playbook 拆分演练。
- **破坏向后兼容**：`scripts/xhs.sh` → `agent/scripts/xhs.sh`；自定义脚本路径需修改。stub 兼容窗口仅 v3.0 → v3.2。

### 中性

- 当前 v2.4.x 的 BSL 1.1 协议、节流/限额参数、JSON Schema 契约全部保留，零变化。
- BRAIN.HANDS.CALIB 版本纪律延续。

## 备选方案及拒绝原因

| 备选 | 含义 | 拒绝原因 |
|---|---|---|
| **v2.5 渐进重构** | 不动布局，只在 SKILL.md 内部加章节锚点拆分 | 不解决源/target 路径漏洞、不解决 install.sh 失效路径、AI token 成本不变 |
| **v3.0 仅拆 SKILL.md，目录不动** | playbook 留在根，目录保持 v2 | playbook 散落在根目录、与 scripts/ docs/ 平级语义模糊；后续仍需要再做一次重构 |
| **v3.0 一步到位拆远程服务** | agent 改为 daemon，runtime 走 RPC | 偏离 skill 定位、破坏所有现有平台兼容、工程量爆炸 |
| **保留 v2 布局 + 加 agent/ 镜像** | 双布局并存，逐步迁移 | 双倍维护负担、用户混乱、verify 门禁难写 |

## 退出条件（何时考虑 v4.0）

任一满足即触发 v4.0 议题：

- playbook 数量 >20，路由表无法在 SKILL.md 50-150 行内表达
- 多平台元数据（agents/）超过 5 个，需要平台抽象层
- 数据规模超过 SQLite 单文件能力（>100k posts / multi-account）
- 需要把 agent 从"用户本机进程内 skill"升级为"远程服务"

显式记 v4.0 候选议题，避免 v3.x 中后期反复争论"要不要重构"。

## 实施路线（10 个 commit + 2 个硬门）

详见 [feasibility study §K](../plans/v3-playbook-split-feasibility.md)：

```
0. docs(v3.0.0): playbook split feasibility study  ← Stage 0 硬门
1. chore(v3.0.0): scaffold agent-powered layout
2. refactor(v3.0.0): introduce _paths.sh and migrate path refs
3. refactor(v3.0.0): move runtime files into agent core
4. feat(v3.0.0): add ensure-runtime-layout and ensure-schema self-healing
5. refactor(v3.0.0): split SKILL.md into bridge and 9 playbooks
6. feat(v3.0.0): relocate installer and add layout migration
7. refactor(v3.0.0): archive legacy skill docs and marketing assets
8. feat(v3.0.0): add package and verification gates (30 checks)
9. docs(v3.0.0): rewrite README upgrade architecture release notes
10. test(v3.0.0): canary upgrade test on a v2.4.3 fixture  ← 发版前硬门
```
