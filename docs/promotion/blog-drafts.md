# 三篇元文章大纲

> 推广 T2 阶段的"次要弹药"——不是推销薯灵，是讲 skill 工程范式，薯灵作为参考实现。
> 投放：少数派 / 掘金 / Medium / 知乎 / 个人博客
> 策略：每篇独立可传播，都指回薯灵为 case study

---

## 文章 1 · Skill-as-Brain：把业务逻辑写成 Markdown 而不是代码

**副标题**：为什么我的 1208 行 SKILL.md 比 1 万行 Python 更稳

**目标读者**：AI agent 开发者、想做 Claude skill 的工程师

**核心论点**：
当业务逻辑的"读者"是 LLM 而不是 CPU 时，Markdown 是更好的载体，不是代码。

**大纲**：

1. **问题**：做了一个小红书助手，第一版是 Python + 大 prompt，后来改坏了又改不回来
2. **顿悟**：LLM 读代码是"解读"，读 Markdown 是"阅读"。同样的业务规则，Markdown 表达 token 少、AI 理解准、人 review 快
3. **实践**：薯灵的 SKILL.md 结构
   - §0a 业务路由表（状态机的 Markdown 表达）
   - §0b JSON Schema 契约（AI 自律的工程保障）
   - §1-§8 主流程（每步是"描述性规则"而非"命令式代码"）
4. **三个意外收益**：
   - 换 AI 平台 0 成本（Claude Code / Codex / Hermes）
   - 流程改动 0 编译（`git diff SKILL.md` 就是 code review）
   - 非技术用户能看懂业务（虽然这不是目标读者）
5. **代价与边界**：
   - SKILL.md 会 token 膨胀（我的 1208 行每月烧 240 万 token，正在做瘦身）
   - AI 会偶尔"飘走"（schemas/ + §0b 校验是兜底）
   - 需要 BRAIN.HANDS.CALIB 这种为 skill 设计的版本号
6. **适用范围**：哪些业务应该这样做？（决策密集 / 规则清晰 / 用户交互复杂 → 适合；纯计算密集 / 无决策 → 仍应写代码）

**字数目标**：3000-4000 字 + 架构图 1 张

**关键金句**：
- "代码是给 CPU 执行的，Markdown 是给 LLM 阅读的。执行不等于阅读。"
- "当你的业务逻辑需要被 AI 理解、修改、回答问题时，它不该是代码。"
- "Skill-as-Brain 不是一种偏好，是 LLM-native 应用的必然形态。"

---

## 文章 2 · BRAIN.HANDS.CALIB：给 AI Skill 设计的语义化版本号

**副标题**：为什么 SemVer 不够用，skill 需要自己的 Major.Minor.Patch

**目标读者**：AI 工具链作者、Claude/OpenAI 生态开发者

**核心论点**：
SemVer（Major.Minor.Patch）是给传统软件设计的，不适配 AI skill 的变更频率和影响维度。

**大纲**：

1. **痛点**：SemVer 在 skill 上会错位
   - "我改了 prompt 算 Minor 还是 Patch？"
   - "换了 DB schema 但业务没变，Major 吗？"
   - "AI 的决策方式变了，用户需要重新适应，这不算 breaking 吗？"
2. **三段设计**：
   - **BRAIN** — SKILL.md 核心流程改变 / 自进化算法换代 / 业务能力跃迁。breaking，要写迁移。
   - **HANDS** — scripts/ 新增或重写 / DB schema 迁移 / MCP 接口替换。基本兼容，但可能需要 migrations。
   - **CALIB** — 阈值/关键词/节流参数 / bugfix / prompt 微调。无感升级。
3. **决策流程**：v2.2.0 → v2.3.0 的真实决策复盘
   - 改了什么：去 HTML 截图降级、强制 Gemini、prompt 模板化
   - 为什么不是 BRAIN+1？算法层零变化
   - 为什么不是 CALIB+1？scripts/image.py 重写 + runtime.env 必填变化
   - 结论 HANDS+1 → v2.3.0
4. **配套工程**：
   - CHANGELOG 双栏（📦 用户可见 + ⬆️ 如何升级）
   - migrations/vX.Y.Z.sh 幂等迁移
   - UPGRADE.md 集中写迁移步骤
   - RELEASING.md 写发版 SOP
5. **推广**：欢迎其他 skill 作者抄这个语义
6. **局限**：不适合 IDE 插件、不适合纯工具库、适合有"业务逻辑"的 agent/skill

**字数目标**：2000-2500 字

**关键金句**：
- "SemVer 假设软件是'工具'，skill 是'角色'。角色升级不该用工具的版本号。"
- "BRAIN 改了，用户的 AI 就变性格了——这是 breaking，不是新功能。"

---

## 文章 3 · AI agent 的小样本偏好学习：Laplace 平滑 + 集中度 × 样本因子

**副标题**：为什么 `chosen/(chosen+skipped)` 是陷阱，如何不让 AI 3 次就"收敛"

**目标读者**：做 AI 个性化 / 推荐 / 用户建模的工程师

**核心论点**：
LLM 套壳做个性化的最常见错误是"过拟合"，薯灵的 §4.1 公式组合可以系统性解决。

**大纲**：

1. **场景**：AI 问你"今天发 A 还是 B"，你选 A。AI 该多信你的偏好？
2. **朴素做法的陷阱**：`weight = chosen/(chosen+skipped)` 让 AI 第 2 次就进入"1 选模式"，完全失去多样性
3. **Laplace 平滑**：`weight = (chosen+1)/(chosen+skipped+2)` 的数学直觉（加了"中立先验")
4. **Confidence 分离**：weight 是单类型的，confidence 是整体分布的。用 `concentration × sample_factor` 分离这两个维度
5. **ε-greedy 保底**：距上次探索 ≥7 天强制追加低 weight 选项，防"口味回音室"
6. **回弹机制**：连续 2 次"换"强制 confidence 回到 0.45，防"AI 钻牛角尖"
7. **数值演示**（复用 SKILL.md §4.1 的 5 行示例表）：对同样的选择序列，朴素公式 vs 平滑公式给出的 confidence 差 0.5
8. **代码实现**（Python 5 行 + JSON Schema 约束）
9. **踩坑警告**：同样的 "chosen/skipped" 用错维度的地方（SKILL.md 原文里有 §4.1 严正提示，值得原样引用）
10. **扩展**：可以用到哪些场景（推荐系统、A/B 实验、chatbot 偏好、IDE 补全权重）

**字数目标**：4000-5000 字（偏技术深度）+ 数值对照表 + 代码片段

**关键金句**：
- "小样本判决是 LLM 个性化最容易出错的地方——2 次选择就认定口味，和没学过一样。"
- "Weight 和 Confidence 不是同一维度。混用它们是高水平 AI 实测踩过的坑（薯灵 SKILL.md §4.1 原话）。"

---

## 发布顺序建议

1. **先发文章 1（Skill-as-Brain）**——最具冲击力，奠定薯灵的"架构叙事"
2. **再发文章 2（版本号）**——精准打专业开发者，建立"skill 工程专家"定位
3. **最后发文章 3（算法）**——技术深度最高，转化最硬核的读者成 contributor

三篇之间 1-2 周间隔，避免扎堆。每篇末尾都引向 github.com/AI-flower/shuling 和 shuling.pages.dev。

---

## 我能替你做的

如果你选了主题，我可以：
- 扩写任意一篇到完整 3000-5000 字初稿
- 生成配图（mermaid 架构图 + 数值表格截图源码）
- 翻译成英文版投 Medium / Dev.to
- 起草知乎/少数派的发布配图 + 导语

告诉我从哪篇开始。
