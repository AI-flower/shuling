# 反 FAQ — 推广时会被质疑的问题 + 标准回复

> 推广时一定会遇到评论区 / issue / DM 里的质疑。事先准备好回复，不要临时搪塞。
> 这些回复可以直接 copy-paste 用，也可以作为你心智上的"准备"。

---

## 质疑类 · 关于架构

### Q1: "Skill-as-Brain 不就是把代码写成 prompt 吗？有啥创新？"

**回复**：
> 好问题。**不是**。关键区别：
>
> - **Prompt**：给 LLM 的一次性指令，无状态、无版本、无结构契约
> - **SKILL.md**：持久化的业务规格，带状态机（§0a 业务路由）、JSON Schema 契约（§0b 写入校验）、版本号语义（BRAIN.HANDS.CALIB）、migrations 迁移机制
>
> 本质是**"把 agent 当成一等公民去做工程管理"**，不是写一次就完事的 prompt engineering。
>
> 如果你只是想让 AI 做一件小事，prompt 够用。如果你要做**可演化、可审计、多人协作、跨平台迁移**的 AI 业务，SKILL.md 这种"规格化"比散落的 prompt 稳太多。

---

### Q2: "1208 行 Markdown 被 LLM 读完太贵了，不如拆成 function calling"

**回复**：
> 非常对，这正是我下一个版本要解决的 P1 问题——SKILL.md 瘦身到 ≤300 行主干 + skill-chapters/ 章节外置。README.md 里有计算：hermes cron 每天 5 次 × 5000 token ≈ 月 240 万 token 白烧。
>
> 但拆成 function calling 不是答案：
> - Function calling 是**分派工具**用的，不是**表达业务状态机**用的
> - §0a 业务路由（7 条分支）用表格 3 行讲清楚的事，拆成 function call 要 5-6 个工具
> - 改流程要改 tool schema，比改 Markdown 麻烦 10 倍
>
> 所以答案是 **"章节化的 SKILL.md + 主干路由"**，不是 **"function calling 替代"**。

---

### Q3: "你的 JSON Schema 校验不是还是依赖 AI 自律吗？AI 不遵守怎么办？"

**回复**：
> 对，我诚实讲这是 **兜底而不是强制**。
>
> 三层防御：
> 1. **软约束**：SKILL.md §0b 明文要求写入前读 schema（AI 读了知道规则）
> 2. **中层警告**：schema 里有反模式禁令明文（"不要用 chosen/(chosen+skipped) 算 confidence，那是 weight 公式"这种）
> 3. **硬校验**：可选用 `python3 -m jsonschema -i file.json schema.json` 在脚本里跑
>
> 第 3 层是真校验，前两层是"让 AI 自己知道要怎么写"。实战中 AI 绝大多数时候遵守。偶尔飘走（比如把 date 写成 ISO 时间戳），schema 校验 fail，重写。
>
> 不是银弹，但**明显优于什么都不做**。

---

## 质疑类 · 关于业务

### Q4: "用 AI 发小红书是不是要被封号？"

**回复**：
> 薯灵**主动规避**风控：
>
> 1. **不自动化**：每篇都要人工"发"确认，不会 hermes cron 直接发送未审核的内容
> 2. **节流+限额**：`config` 里 throttle_profile = v1-conservative，触顶自动拒绝
> 3. **内容合规**：SKILL.md §5 + `data/content-rules.md` 禁止标题党、AI 自述、平台名提及
> 4. **不刷量**：MCP 只调"发布 / 查互动"，没有"点赞 / 关注 / 评论别人"
>
> 我自己用这个账号运营了 2 个月，数据健康。但**使用行为责任在用户**——薯灵是工具，不是免责声明。

---

### Q5: "为什么不做成 SaaS 方便普通用户？"

**回复**：
> 故意不做。三个原因：
>
> 1. **捍卫 Skill-as-Brain 叙事**——做成 SaaS 就变成"又一个小红书工具"，失去架构示范价值
> 2. **小红书 TOS**——集中处理多用户账号在灰色地带，单用户本地运行完全合规
> 3. **不想处理用户数据**——画像、历史帖、Cookie 都是用户隐私，本地存储我不经手、不背责
>
> 如果有人想做 SaaS 版，fork 走，遵守 MIT 许可。但本体会一直保持"单用户本地 skill"形态。

---

### Q6: "我不会用 Claude Code / Codex，能不能用 GPT / 通义千问 / Kimi？"

**回复**：
> 理论上可以——任何能读 Markdown 指令 + 执行 shell 命令的 AI 工具都能装。
>
> 当前明确支持的：Claude Code / Codex / Hermes。
>
> 不支持的：纯聊天界面（ChatGPT 网页版、通义千问网页版）——因为 SKILL.md 需要 AI 能**读文件 + 执行 bash + 写文件**，聊天界面一般做不到。
>
> 如果你在 Claude API 上自己搭 agent，薯灵完全兼容（就是 Claude Code 内部的那一套）。

---

## 质疑类 · 关于技术选择

### Q7: "为什么用 SQLite 不用 Postgres/MongoDB？"

**回复**：
> 薯灵是**单用户本地 skill**，SQLite 完全够用：
> - 9 张表、单文件、零运维
> - WAL 模式并发足够（AI 不会真并行写）
> - 备份就是 `cp xhs.db xhs.db.bak`
>
> 如果你要改成多用户 / 远程 / 高并发，换 Postgres 没问题——`scripts/db.sh` 抽离了 SQL 层，迁移工作量一天。

---

### Q8: "为什么只用 Gemini 不用 OpenAI DALL-E / Flux?"

**回复**：
> 经过 v2.0-v2.3 多轮测试得出的 **工程决定**：
>
> - Gemini 3 Pro Image (Nano Banana Pro) 在**中文字形**上领先明显（小红书帖 90% 都是中文标题 + 中文正文）
> - **多模态参考图**能力好（v2.3.0 的两阶段封面回流依赖它）
> - **价格合理**（免费额度 + 付费档位便宜）
>
> 不是偏见。DALL-E / Flux / SD 中文文字普遍会写乱，不适合小红书这种文字密集的场景。
>
> v2.3.0 做了 `IMAGE_GEN_PROTOCOL` 抽象，换模型只要改环境变量。但 `gemini-3-pro-image-preview` 是当前最优解。

---

### Q9: "preflight.py / db.sh 为什么不写 tests？"

**回复**：
> 这是 **roadmap 上 P1 的欠账**（见 `docs/2026-04-21-project-optimization-roadmap.md` 第 C 组）。
>
> 650 行 Bash + 391 行 Python + 526 行 Python 零测试，是**活生生的债务**。短期靠 AI 代理自己跑 smoke 来兜底，长期要补测试。
>
> 我没有掩饰这件事。薯灵的 roadmap 本身就挂在 docs/ 下公开，诚实讲代码的短板。

---

## 质疑类 · 关于推广动机

### Q10: "你是想把这个东西卖给谁？"

**回复**：
> **不卖**。MIT 开源，纯本地，没有云端，没有会员，没有广告。
>
> 推广目的：
> 1. 让更多 AI skill 开发者看到 **Skill-as-Brain 范式**，反哺我自己的思考
> 2. 让小红书博主用上 **一个不收费的 AI 助手**
> 3. 建立"做严肃 skill"的个人信誉（未来如果接 consulting 或加入 AI 团队有背书）
>
> 不为 KPI，不为 VC，纯粹因为做出来了值得被看到。

---

### Q11: "你做这个用了多久？一个人？"

**回复**：
> 2 个月左右（从 2026-02-中 到 2026-04-21 v2.3.0）。71 次提交，8 个版本。
>
> 一个人做的。业务逻辑、算法、工程基础设施、CHANGELOG、官网、推广物料全自己来。
>
> 期间大量用 Claude Code 自己——**用 Claude Code 做 Claude skill**，是一次有意思的 dogfooding。

---

## 质疑类 · 关于社区

### Q12: "这个项目会长期维护吗？"

**回复**：
> 会。已经有 roadmap 排到 v3.0.0：
> - v2.4.0 Agent-Friendly Upgrade Infrastructure（已定稿 spec）
> - v3.0.0 视频笔记 / 多账号灰度 / 竞品对标
>
> 维护节奏取决于两个信号：
> 1. 自己运营的小红书号还在用（dogfooding 不断）
> 2. GitHub issue / PR 有人进来（社区反馈）
>
> 如果哪一天不维护了，会明确 archive + 说明，不会"消失"。

---

### Q13: "我能贡献代码吗？优先哪些领域？"

**回复**：
> 欢迎！`docs/2026-04-21-project-optimization-roadmap.md` 里有 16 项诊断，按优先级：
>
> **Good First PR**（简单改）：
> - D 组：杂物清理（`SKILL.md.bak` / `image.py.bak` 删除）
> - D 组：依赖锁定（加 `requirements.txt`）
> - 195 个悬挂 checkbox 回勾
>
> **Meaningful Contribution**（中等）：
> - A1：SKILL.md 瘦身 → 主干 + 章节化
> - B 组：migrations 缺 v2.2.1 / v2.3.0 补齐
> - C 组：smoke tests for scripts/
>
> **Deep Dive**（大活）：
> - A2：db.sh 650 行 Bash → Python
> - A3：自进化闭环真实性验证（需要真实数据）
>
> 先提 issue 讨论，再开 PR。

---

## 用法

### 推广时
- **不要主动贴**：这份文档不是发给读者的，是给**你**看的，让你回复有底气
- **临场用**：遇到对应问题，找到最接近的 Q，copy 回复，稍微适配语气

### 评论区打斗的心法
1. **诚实先于聪明**：不掩饰短板，指 roadmap 承认
2. **少即是多**：每个回复 ≤ 200 字，不写小作文
3. **不要和 troll 纠缠**：明显恶意的，点赞表示"我看到了"然后不回复
4. **好问题公开回复**：能让所有读者都受益的，答好答透；小众问题私聊

### 把好的问题反哺到项目
- 评论里被问了 5 次以上的问题 → 加进 README FAQ
- 被质疑 3 次以上的设计决策 → 写成 ADR 或 blog
- 被要求 2 次以上的 feature → 进 roadmap 评估
