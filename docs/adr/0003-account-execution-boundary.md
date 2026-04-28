# ADR-0003：账号执行权与外部情报安全边界

- **Status**: Accepted
- **Date**: 2026-04-28
- **Deciders**: AI-flower（Owner）+ AI 协助分析
- **Supersedes**: 无（v3.0.0 之前没有显式的 privileged mutation 边界 ADR）
- **Related**:
  - [ADR-0001 Stateful Creator Agent](0001-stateful-creator-agent.md)（特别是第 12 条「降级路径强制」原则）
  - [ADR-0002 Playbook 拆分决议](0002-playbook-split-decisions.md)
  - [v3 Account Execution Safety Hardening Plan](../plans/v3-account-execution-safety-hardening.md)

## 上下文

ADR-0001 在 v3.0.0 完成「标准 Skill 包 → Stateful Creator Agent」的物理重构：SKILL.md 收敛到 ≤150 行协议适配层、agent/ 内核三层分离、用户态 copy-first 自愈、34 条 verify 门禁。结构性问题被解决了，但 **产品安全边界** 没有被同时收口。

v3.0 之后，薯灵默认仍然可以在没有用户显式确认的情况下调用：

- `agent/scripts/xhs.sh publish`
- `agent/scripts/xhs.sh comment`
- `agent/scripts/xhs.sh import-cookie`
- `agent/scripts/import-existing.sh --override-quota`
- cron job 模板里包含「执行午间发布流程」「执行晚间发布流程」字样
- `XHS_DISABLE_THROTTLE=1` / `XHS_DISABLE_QUOTA=1` 在生产模式下也可生效

这些在 v2.x 时代是「自动化能力」，但在 ADR-0001 把薯灵正式定位为 Stateful Creator Agent 之后会带来三个新张力：

1. **agent 自主调用 mutation 的语义权重变了**：v2.x 是「脚本被显式触发」，v3.0 起 AI 助手会按 routing 表自动跳到对应 playbook，发布、评论、cookie 导入这类对账号有不可逆影响的动作不再适合默认开放给 agent 决策路径。
2. **draft_ready 事件被 routing 误读的风险**：03-daily-flow 完成草稿后会 emit `draft_ready`，按 v3.0 routing 表 04-publish-flow 的 `when` 包含「draft_ready 事件触发」字样。如果不显式收口，未来加任何 cron prompt 改动都可能形成「定时生成 → 自动发布」的隐式回路。
3. **外部数据采样从「点状调用」演化为「持续行为」**：v3.0 把选题、复盘、评论提炼分到 03/05/07 三个 playbook，每个都会用到 `xhs.sh search/detail/list-feeds`。如果不引入预算与缓存层，agent 自身的频率会不知不觉从「人工触发的偶发查询」漂移成「按剧本自动跑的定期采样」，对账号风控形成新的风险面。

继续把这些问题留给 v3.x 文案层规避（README 改口径、playbook 加注释）只是延缓而非解决——AI 可能误读自然语言注释，cron prompt 可能被用户改回「自动发布」语义，verify 没有门禁阻止回退。本 ADR 决定把账号写操作和外部数据采样作为 **产品边界** 一次性收口。

## 决策

**v3.1.0 起，账号写操作（publish / comment / import-cookie / 关闭节流限额 / 批量历史导入 unsafe override）与超 L2 风险的外部数据采样不再是 agent 的普通能力，而是 privileged mutation，必须经过显式授权或安全状态检查后才允许执行。**

### D1：privileged mutation 的定义

下列动作被定义为 privileged mutation，脚本层硬门禁拒绝未授权调用，**不依赖 playbook 文案约束**：

| 动作 | 入口 | 默认状态 | 解锁方式 |
|---|---|---|---|
| 发布笔记 | `xhs.sh publish` | `require_approval_for_publish=true` | 一次性 approval + safety state ∈ {`normal`, `watch`} |
| 发表评论 | `xhs.sh comment` | `commenting_enabled=false` | 显式 policy + 一次性 approval |
| 导入 Cookie | `xhs.sh import-cookie` | `cookie_import_enabled=true`，但禁止 `cooldown` / `locked` | safety state 检查 |
| 批量导入历史 unsafe override | `import-existing.sh --unsafe-override-quota` | 仅 `SHULING_DEV_MODE=1` + TTY | dev mode + 交互确认 |
| 关闭节流 | `XHS_DISABLE_THROTTLE=1` | 非 dev mode 拒绝 | `SHULING_DEV_MODE=1` |
| 关闭限额 | `XHS_DISABLE_QUOTA=1` | 非 dev mode 拒绝 | `SHULING_DEV_MODE=1` |
| 外部情报 L3 采样 | `external-intel.sh research-topic` 中 detail/comment 部分 | 预算化 + safety normal | budget 充足 + safety state == `normal` |
| 外部情报 L4 高频抓取 | 无入口 | 全面禁用 | v3.x 不开放，仅 dev mode 可实验 |

非 privileged 的能力保持 v3.0 行为：选题、起稿、生图、复盘、评论洞察（只读）、偏好学习、账号诊断建议、L0-L2 外部情报采样。

### D2：为何 v3.0 后仍需要再收口

ADR-0001 在第 12 条原则里写了「降级路径强制」：每个引入的新机制必须给出「不可用怎么办」。ADR-0003 是这条原则的逆方向延伸——每个高风险动作必须给出「默认状态是什么 + 谁能解锁 + 解锁后怎么消费」。v3.0 的三层重构只回答了第一个问题（结构上把它们放进了 agent/scripts/），没有回答后两个。本 ADR 通过 approval.sh + account-safety state machine + external-intel.sh 三个新机制给出统一答案。

### D3：为何 `draft_ready` 不能触发 publish

03-daily-flow 完成草稿后 emit `draft_ready` 是 v3.0 的设计意图，但 `draft_ready` 的语义只是「草稿已生成、等待审核」，不是「允许发布」。当前 04-publish-flow.md 的 `when` 字段中「draft_ready 事件触发」会让自动 routing 路径误把生成等价于授权。本 ADR 决定：

- `draft_ready` 是 non-mutating event，仅用于通知用户和 logging。
- 04-publish-flow 的 `when` 必须移除 `draft_ready 事件触发`，改为 `用户明确回复"发"` + `publish_approved 事件触发`。
- `publish_approved` 事件只能由 `approval.sh grant` 显式产生，cron 与自动 routing 都不能合成。

### D4：为何 publish/comment/import-cookie 是 privileged mutation

| 动作 | 影响范围 | 不可逆程度 | 平台风险面 |
|---|---|---|---|
| publish | 账号公开内容 + 平台计数 | 高（删除留痕） | 高（计入小红书账号画像） |
| comment | 账号公开互动 + 评论区 | 中（可删但留痕） | 高（频繁评论易触发风控） |
| import-cookie | 长期登录态 | 中（cookie 失效即清） | 关键凭证泄露面 |

三者都满足「公开可见 + 平台风控权重高 + 用户必须事后承担后果」。把它们留在 agent 的普通能力面板上是把「会失败的产品决定」推给 AI 推理；把它们升级为 privileged mutation 是把决定权交还给账号 owner。

### D5：为何评论默认禁用

评论比发布更接近「模拟真人互动」，平台风控对评论的速率、相似度、设备指纹三维都比发布更敏感。同时评论的产出价值在 v3.0 阶段（选题/创作闭环为主）远低于其风险面。因此本 ADR 决定：

- `commenting_enabled` 默认 `false`，即使在 `supervised` 模式下也需要显式开启 `SHULING_ENABLE_COMMENT=1` 环境变量后才能进入 approval 流程。
- 07-comment-insights.md 默认只输出回复建议，不调用 `xhs.sh comment`。
- 即使 `SHULING_ENABLE_COMMENT=1` 也仍然需要 approval，环境变量只是解除「全面禁用」状态，不是绕过 approval。

### D6：为何 cron 默认 draft-only

cron 模板是用户主动安装的自动化入口，但 cron prompt 用自然语言写给 AI 看（例如 `prompt: "执行午间发布流程"`）。一旦自然语言出现「发布」「执行流程」字样，AI 会按 routing 进入 04-publish-flow，而 cron 触发的会话里通常没有 TTY 也没有用户在线，approval 不可能产生 → 形成「定时回路」。

本 ADR 决定 cron 模板默认语义只能生成草稿和复盘，不能默认调用发布或评论：

- `ops/cron/hermes.yaml.example` 与 `ops/cron/launchd.plist.example` 等四套模板的 prompt 必须包含「不要发布」「等待用户确认」字样。
- verify 第 37 条门禁阻止 cron 模板出现「执行发布流程」「自动发布」「publish flow」「xhs.sh publish」等关键字。

### D7：为何这是产品边界，不是文案优化

本 ADR 不是为了把 README 里的「全自动发布」文案改成「Stateful Creator Agent」。文案优化只能影响新用户的预期，不能阻止：

- AI 助手按 routing 误调用 publish（agent 行为）
- cron prompt 被用户改回「自动发布」（运维行为）
- 老自动化脚本直接调 `xhs.sh publish`（外部代码行为）
- AI 在长会话里逐步漂移到「省略确认步骤」（统计行为）

只有把 mutation 从「普通脚本能力」降级为「需要 approval 验证的脚本调用」，并由 `xhs.sh` 内部的硬校验拒绝未授权请求，才能让边界对所有上游路径都生效。这是产品安全模型的变更，不是文案变更。

### D8：与 ADR-0001 第 12 条「降级路径强制」的承接

ADR-0001 第 12 条要求每个新机制必须给出「不可用怎么办」。本 ADR 引入的三个新机制对应给出：

| 新机制 | 不可用怎么办 |
|---|---|
| `approval.sh` | 不可用时所有 publish/comment 调用拒绝；agent 必须降级为输出草稿和回复建议；09-troubleshooting.md 引导用户检查 approvals 目录权限 |
| `account-safety.sh` 状态机 | state 文件不可读时强制视为 `cooldown`；不允许「读取失败 = normal」的乐观假设 |
| `external-intel.sh` | 预算耗尽 / safety 非 normal / 命中风险信号时降级为内部 `profile.json` + `preferences.json` + `patterns.md` 三件套，明确标注「本轮无外部情报」，**不阻断草稿生成** |

降级路径在 09-troubleshooting.md 显式记录，并由 verify 第 41-42 条门禁强制约束外部情报缓存不能保存原文。

## 后果

### 正面

- **publish/comment 默认安全**：任何上游路径（AI、cron、自动化脚本、误操作）都无法绕过 approval。
- **draft_ready 与 publish_allowed 解耦**：草稿生成和发布授权是两个独立事件，cron 自动化不再隐式形成回路。
- **风险事件可观测**：`account-safety-state.json` 把 429、captcha、风控关键词等信号集中记录，doctor 可直接展示，不需要翻 request_log。
- **外部情报有边界**：薯灵能接外部活水（赛道趋势、竞品角度、评论需求）但不会退化成爬虫。
- **verify 门禁防回退**：35-42 条新增门禁让「关掉 approval」「cron 改回自动发布」「外部信号缓存原文」等回退动作在发版前就被拦下。

### 负面 / 成本

- **breaking change**：v3.0 → v3.1 用户必须重新理解「发布要确认」。`UPGRADE.md` 的 v3.0 → v3.1 章节给出迁移示例。
- **老自动化脚本失效**：直接调用 `xhs.sh publish` 的 cron job、CI 任务、第三方集成都会被拒绝；用户必须迁移到 approval flow。
- **AI 助手对话流程多一步**：每次发布前 AI 必须先 emit approval request，再等用户回复「发」，再 consume approval；体验上从「一句话发帖」变成「两轮确认发帖」。
- **外部情报失败概率提升**：因为预算化 + 缓存优先，命中 cache miss + budget 不足时草稿生成时只有内部信号；这是设计意图，但用户感知是「有时候 AI 不知道外部正在流行什么」。
- **verify 门禁从 34 条扩到 42 条**：实施成本和维护负担同步增加。

### 中性

- v3.0 的三层架构、playbook frontmatter、路径单一来源、算法权威唯一性等纪律全部保留，零变化。
- BSL 1.1 协议、节流/限额参数、JSON Schema 契约延续。
- BRAIN.HANDS.CALIB 版本纪律延续。

## 备选方案及拒绝原因

| 备选 | 含义 | 拒绝原因 |
|---|---|---|
| **只在 README 改口径** | 把「全自动发布」改成「Stateful Creator Agent」，脚本不动 | 不能阻止 AI / cron / 老脚本绕过；本质是文案优化不是产品边界 |
| **playbook 文案约束** | 在 04-publish-flow.md 加「必须等待用户确认」段落 | AI 可能误读、长会话漂移、verify 无法机器校验 |
| **环境变量开关** | 加 `SHULING_REQUIRE_APPROVAL=1` 默认 false | 默认不安全；用户多数不会主动开 |
| **完全禁用 publish** | 移除 `xhs.sh publish` 子命令 | 违反非目标 1（不移除 publish 能力） |
| **审计日志事后追责** | 不前置 approval，只 log 所有 publish 动作 | 事后追责无法防止账号已经被误发；不可逆动作必须前置授权 |

## 退出条件（何时考虑放宽边界）

任一满足时可在新 ADR 中重新评估：

- 平台风控模型变更，使评论/发布的连续动作风险显著下降
- approval 流程被证明在 90%+ 场景下增加摩擦但零拦截价值（即用户从未拒绝过 approval）
- 引入更细粒度的能力分级（如「仅评论自己笔记 = 低风险」），可在保持安全的前提下默认启用部分子集
- v3.x 期间没有出现一例 approval 阻挡到误发布的真实事件，且无任何账号风控事件，可在 v4.0 评估是否引入「会话级一次授权多次发布」的折中模式

显式记录退出条件，避免 v3.x 中后期反复争论「approval 是不是太烦了」。

## 实施路线（参考 v3.1 plan 的 8 stage）

详见 [v3.1 Account Safety Implementation Plan](../plans/v3.1-account-safety-implementation-plan.md)：

```
Stage 1  docs(v3.0): define account execution boundary           ← 本 ADR + 文档铺垫
Stage 2  feat(v3.1): add account safety policy and state schemas
Stage 3  feat(v3.1): require approval for account mutations
Stage 4  fix(v3.1):  make cron draft-only by default
Stage 5  feat(v3.1): add account safety cooldown
Stage 6  feat(v3.1): add external intelligence budgeted sampling
Stage 7  feat(v3.1): add content QA and secret safety checks
Stage 8  test(v3.1): add account execution and intelligence safety gates  ← 35-42 条 verify
```

每个 stage 完成时 `bash ops/verify/pre-submit-verify.sh --strict` 必须全绿（v3.0 是 34 条，v3.1 完成时是 42 条）。
