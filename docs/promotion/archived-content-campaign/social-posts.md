# 社群发布贴（中英双语，多平台）

> 按时间表 Day 4-5 T4 中文社群 → Day 14 英文社群 & Discord 发布。

---

## 1. V2EX · 分享创造节点

**标题**：把小红书博主助手写成了一个 AI Skill — 1208 行 Markdown 当大脑，Claude/Codex/Hermes 都能装

**正文**：

```
做了几个月，今天 v2.3.0 发出来了，想来 V2EX 分享下架构思路。

项目叫薯灵（ShuLing）— 小红书博主成长 AI skill。从选题、写稿、配图、发布、复盘形成完整闭环，数据驱动越用越懂你。但业务本身不是重点，真正想分享的是 **架构范式**。

核心理念：**Skill-as-Brain**
- 业务逻辑全在 SKILL.md 里（1208 行 Markdown），AI 助手读了它就是大脑
- scripts/ 只是手脚，负责 AI 做不了的物理操作（调 MCP、读写 SQLite、生成图片）
- 换 AI 平台零成本，改流程不用改代码

具体工程实践：
1. BRAIN.HANDS.CALIB 三段语义化版本号（专为 AI skill 设计）
2. JSON Schema 契约防 AI 飘走
3. preflight 双模式（给 AI 的 JSON + 给人的彩色表）
4. migrations/ 幂等迁移
5. 贝叶斯偏好学习 + ε-greedy 探索（Laplace 平滑 + 集中度 × 样本因子）

开源 MIT，Claude Code / Codex / Hermes 都能直接装。

- GitHub: https://github.com/AI-flower/shuling
- 官网: https://shuling.pages.dev（赛博 HUD 风，给 AI agent 看的 landing page）

欢迎拍砖，尤其对 skill 架构这块。
```

**Tag**：`AI` `OpenSource` `Claude` `小红书`

---

## 2. 即刻 · AI 探索者圈子

**正文**（短版，300 字以内）：

```
把小红书博主助手写成了一个纯 AI skill，刚发 v2.3.0 🎉

特别的地方不是业务（小红书工具一大堆），是架构：
⚡ 1208 行 Markdown 当大脑（Skill-as-Brain）
⚡ 业务全在 SKILL.md 里，代码只做手脚
⚡ Claude Code / Codex / Hermes 一装就能跑
⚡ 贝叶斯偏好学习 + pattern 生命周期，越用越懂你
⚡ BRAIN.HANDS.CALIB 三段版本号（专为 AI skill 设计）

开源 MIT 👉 github.com/AI-flower/shuling
官网 👉 shuling.pages.dev

适合两类人：
- 小红书博主（让 AI 帮你日更不累）
- AI skill 开发者（看个生产级架构参考）

感兴趣的朋友留言，聊聊 skill 工程怎么搞。
```

---

## 3. Twitter / X 英文（主推开发者圈）

**Thread**（3-tweet series）：

### Tweet 1 (hook)
```
I built a Xiaohongshu (RED) creator-growth AI skill in 1208 lines of Markdown.

Zero business logic in Python. All in SKILL.md.

Claude Code / Codex / Hermes agents just read it and become your creator assistant.

Here's the "Skill-as-Brain" architecture 👇 (1/3)

https://github.com/AI-flower/shuling
```

### Tweet 2 (architecture)
```
The big idea:
• SKILL.md = brain (business logic in Markdown)
• scripts/ = hands (DB I/O, MCP calls, image gen)
• knowledge-base/ = memory (profile, preferences, patterns)

Switch platforms, zero code changes. Update flow, bump SKILL.md's BRAIN version.

Semver designed FOR skills:
BRAIN.HANDS.CALIB (2/3)
```

### Tweet 3 (features + CTA)
```
Features I'm proud of:
🧠 Bayesian preference learning (Laplace smoothing + concentration × sample factor)
🎨 Two-stage Gemini 3 Pro image gen with cover-as-reference
🔒 JSON Schema contracts prevent AI drift
⚙️ Idempotent migrations

MIT licensed. Fully local. No telemetry.

shuling.pages.dev (3/3)
```

---

## 4. Hacker News · Show HN

**标题**：
```
Show HN: Shuling — A Xiaohongshu creator skill where 1208-line Markdown is the brain
```

**正文**（严谨版，HN 风）：

```
Hi HN,

I've been building a production-grade AI skill for Xiaohongshu (the Chinese lifestyle-sharing platform) creator workflow. v2.3.0 shipped this week. Sharing it because I think the architecture pattern is more interesting than the business domain.

The core idea I'm calling "Skill-as-Brain":
- All business logic lives in a single 1208-line SKILL.md file
- scripts/ directory only handles mechanical I/O (DB, MCP calls, image gen)
- knowledge-base/ is where the agent's memory lives (profile, preferences, mined patterns)

This means:
1. Switching AI platforms (Claude Code / Codex / Hermes) is zero-cost — they all just read SKILL.md
2. Updating business flow doesn't require code changes
3. Version bumps have a designed semver: BRAIN.HANDS.CALIB (flow / scripts / tuning)

Other things I took seriously:
- JSON Schema contracts for all AI-written state files (prevents drift)
- Laplace-smoothed Bayesian preference learning (handles small sample correctly)
- Idempotent migrations
- Dual-mode preflight (JSON for agents, colored table for humans)
- Two-stage Gemini 3 Pro image gen with cover-reference for multi-page style consistency

What it's not:
- Not automation / farming (compliance rules enforced)
- Not a SaaS (fully local)
- No telemetry

Repo: https://github.com/AI-flower/shuling
Site: https://shuling.pages.dev (explicitly designed for AI agents to read, not humans)

Happy to discuss the architecture, the skill engineering patterns, or the self-evolution algorithm. Fire away.
```

---

## 5. Anthropic Discord · #skills 频道

**长度**：控制在 Discord 一屏内

```
Hey everyone 👋

Shipped v2.3.0 of shuling today — a reference-grade Claude skill for Xiaohongshu (Chinese RED platform) creator workflow. Thought this community might find the architecture interesting.

🧠 **Skill-as-Brain**: 1208-line SKILL.md drives the entire business loop. `scripts/` only handles mechanical I/O. Zero business logic in code.

⚙️ **Skill-grade infra**:
- BRAIN.HANDS.CALIB semver (designed for skills)
- JSON Schema contracts to prevent AI write drift
- Dual-mode preflight (JSON for agents / table for humans)
- Idempotent migrations
- Platform adapters for Claude Code / Codex / Hermes

📊 **Self-evolution**:
- Laplace-smoothed Bayesian preference learning
- ε-greedy exploration (prevents echo chamber)
- Pattern lifecycle: experimental → medium → high
- Driven by actual post engagement (save rate)

Fully local, MIT licensed, no telemetry. Uses `xiaohongshu-mcp` + Gemini 3 Pro Image.

Repo: https://github.com/AI-flower/shuling
Deep dive: https://shuling.pages.dev

Would love feedback on:
1. Whether the Skill-as-Brain pattern generalizes to other verticals
2. How skills should handle versioning (does BRAIN.HANDS.CALIB feel right?)
3. JSON Schema contracts — overkill or justified?
```

---

## 6. 中文微信群 / 飞书群（Claude Code 中文社区）

**短版**（200 字以内，群友注意力短）：

```
给 Claude Code / Codex 装一个生产级小红书博主 skill 🎯

薯灵 v2.3.0 刚发：
- SKILL.md 1208 行 Markdown 当大脑
- 一装就能"帮我发小红书"全流程跑
- 贝叶斯偏好学习，越用越懂你
- MIT 开源，纯本地

适合两类人：
1. 小红书博主 — 日更不累
2. Claude skill 开发者 — 生产级架构参考

👉 github.com/AI-flower/shuling
👉 shuling.pages.dev

做了 2 个月 71 个 commit 8 个版本，欢迎 star/拍砖/问架构。
```

---

## 7. B 站视频脚本（6 分钟技术 vlog）

**标题建议**：《我把小红书博主助手写成了 1208 行 Markdown — Skill-as-Brain 架构解析》

**结构**：
- 0:00-0:30 **Hook**：展示效果（对 Claude 说"帮我发小红书" → 30 秒出大纲 + 图 + 发布成功）
- 0:30-1:30 **问题**：为什么传统 AI 工具套壳不够？为什么要做成 skill？
- 1:30-3:00 **架构**：Skill-as-Brain 图解，SKILL.md 的 §0a 业务路由 / §0b schema 校验 / §0c 老博主接入
- 3:00-4:30 **自进化算法**：Laplace 平滑 + confidence 公式用数值示例演示
- 4:30-5:30 **工程实践**：BRAIN.HANDS.CALIB 版本号、preflight 双模式、migrations 幂等
- 5:30-6:00 **CTA**：GitHub 链接、官网、下一个版本规划

**B 站 tag**：`编程` `AI` `开源` `Claude` `MCP` `小红书`

---

## 发布节奏建议

| 日期 | 平台 | 贴子 |
|---|---|---|
| Day 4（周一早） | V2EX | 分享创造节点长贴 |
| Day 4（周一午） | 即刻 | AI 探索者圈子短贴 |
| Day 5（周二晚） | 微信群/飞书群 | Claude 中文社区群发 |
| Day 7（周四晚） | B 站 | 技术 vlog（如果能录） |
| Day 10（周日午） | Anthropic Discord | #skills 频道 |
| Day 11（周一晚） | Twitter/X | 英文 thread |
| Day 14（周四早） | Hacker News | Show HN（流量峰值在美东周二周三，挑对时区） |

**避开**：节假日、各大厂发布会日（注意力被抢）、周五下午/周六（技术圈休假）
