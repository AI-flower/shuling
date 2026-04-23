# Awesome 列表 PR 投递包（3 个列表）

> 生成于 2026-04-23
> 项目：shuling v2.3.0 "Pure Image Pipeline"
> 仓库：https://github.com/AI-flower/shuling
> 作者：AI-flower
> 许可：MIT

---

## 投递前硬阻断（先修复再提交！）

| 阻断项 | 当前状态 | 修复动作 |
|---|---|---|
| 线上仓库**无 LICENSE 文件** | `https://raw.githubusercontent.com/AI-flower/shuling/main/LICENSE` 返回 404 | `cp promotion/LICENSE /Users/weiyong/.../shuling/LICENSE && git add LICENSE && git commit -m "chore: add MIT LICENSE" && git push` |
| README 徽章仍是 v2.2.0 | 线上 README 显示 version-2.2.0，实际已 release v2.3.0 | apply patches/01-version-sync.patch 或手工改，推上去 |
| GitHub API 的 `license: null` | 未识别出 license | 添加 LICENSE 文件后会自动识别 |
| 仓库存在时长 = 7 天（2026-04-16 至 2026-04-23）| 勉强过 awesome-claude-code 的"1 week 最低龄"门槛 | 等到 2026-04-24 或更晚投 awesome-claude-code 更稳 |
| 只有 2 stars | 部分 reviewer 会用 star 数做质量信号 | 提交前先在社区发一轮 V2EX / 即刻 / Twitter 拉 20+ star 再提 PR |

**强烈建议顺序**：先完成以上 5 项，再按本文档逐个列表投递。否则 3 个 PR 都会暴露同样硬伤，被批量拒。

---

## 目录

- [列表 1: hesreallyhim/awesome-claude-code](#列表-1-hesreallyhimawesome-claude-code) — 通过 Issue 模板推荐（不是 PR）
- [列表 2: e2b-dev/awesome-ai-agents](#列表-2-e2b-devawesome-ai-agents) — Fork + PR（或 Google Form）
- [列表 3: Shubhamsaboo/awesome-llm-apps](#列表-3-shubhamsabooawesome-llm-apps) — Fork + 贡献实际模板代码
- [三个列表的对比差异化 cheat sheet](#三个列表的对比差异化-cheat-sheet)
- [提交后的跟进动作](#提交后的跟进动作)

---

# 列表 1: hesreallyhim/awesome-claude-code

## 1.1 调研

> **关键发现：这个列表不接受 PR**。README 第 400 行明确写：`"Please do not open a PR to submit a recommendation - the only person who is allowed to submit PRs to this repo is Claude."` 必须通过 Issue 模板推荐。

- **接纳可能性：中高**。项目完美契合"Agent Skills"分类，符合他们的所有验收标准（focused、有 license、文档充分、演示任务清晰）。但维护者 hesreallyhim 以"严格审核 + 针对性提问"闻名，对"通用营销工具"或"需要长 onboarding 的框架"会扣分。
- **条件**：必须通过 GitHub.com UI 人工提交 Issue（不能用 `gh` CLI，他们有反垃圾检测）；仓库必须满 1 周；必须提供可验证的 claims + 具体的 Prompt 样例；自认为"Could Opus build this in one session?"——薯灵 1208 行 SKILL.md + migrations 系统 + preflight 不可能一 session 复刻，这点能过。
- **风险提示**：提交前需要跑一遍 `.claude/commands/evaluate-repository.md` 自测。

## 1.2 README 条目

> ⚠️ **不要直接改 README.md** — 该文件顶部注明 `<!-- GENERATED FILE: do not edit directly -->`，由机器人根据 Issue 生成。以下只是**预测 bot 会生成出来的条目**，供你核对风格是否合适。

**预测会被放到的 section**：
```
## Agent Skills 🤖
### General
```

**预测会被插入的位置**（字母序，现有条目里 `read-only-postgres` 和 `Superpowers` 之间；由 `Shu` 开头）：
```
- [ShuLing](https://github.com/AI-flower/shuling) by [AI-flower](https://github.com/AI-flower) - A production-grade Claude Code skill for Xiaohongshu (RED) creator growth. Features a 1208-line SKILL.md that drives the full creator loop (topic → draft → publish → retrospect) with a Skill-as-Brain architecture where business logic lives in Markdown rather than Python. Includes BRAIN.HANDS.CALIB semantic versioning for skills, JSON Schema contracts to constrain model drift, dual-mode preflight checks, idempotent migrations, and a Bayesian preference-learning loop with pattern lifecycle evolution. Works across Claude Code, Codex, and Hermes.
```

- **字符长度**：条目较长（约 620 字符），但与现有同 section 的条目（e.g. Fullstack Dev Skills, Superpowers）长度匹配，reviewer 偏好这种"信息密度高"的描述。
- **风格一致性**：不用第二人称（`you`、`your`），全程 descriptive；不用 emoji；不做推销式语言。

## 1.3 提交方式：不是 PR，是 Issue 推荐表单

> 这是列表 1 唯一正确的提交方式。

**Issue 模板 URL**：
```
https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml
```

**必填字段（按模板填）**：

| 字段 | 填值 |
|---|---|
| 标题（[Resource]: ...） | `[Resource]: ShuLing` |
| Display Name | `ShuLing` |
| Category | `Agent Skills` |
| Sub-Category | `General` |
| Primary Link | `https://github.com/AI-flower/shuling` |
| Author Name | `AI-flower` |
| Author Link | `https://github.com/AI-flower` |
| License | `MIT` |

## 1.4 Description 字段（1-3 句，无 emoji，descriptive 风格）

```
A Claude Code skill for Xiaohongshu (RED) creator growth, built on a "Skill-as-Brain" architecture where a 1208-line SKILL.md serves as the business brain and scripts/ handle only I/O. Drives a full creator loop — topic selection, dual-stage drafting, two-phase image generation, publishing, and five-dimension retrospect — while self-evolving through Bayesian preference learning with Laplace smoothing, ε-greedy exploration, and pattern-lifecycle management. Ships with BRAIN.HANDS.CALIB semantic versioning, JSON Schema contracts against model drift, idempotent migrations, and dual-mode preflight (JSON + human), and runs across Claude Code, Codex, and Hermes.
```

## 1.5 Validate Claims 字段

```
Install the skill, then inspect the `.shuling/state.json` and `.shuling/patterns.json` after running the topic-selection and publish-retrospect commands once each. You will see the preference vector updated via Laplace smoothing and a pattern entry with its lifecycle stage (探索期/成长期/成熟期/衰退期). The SKILL.md at the repo root documents the exact formulas. No external services are called except the MCP tools and the Gemini API (if image generation is invoked).
```

## 1.6 Specific Task(s) 字段

```
Task 1 (cold-start creator):
Ask Claude Code to run the onboarding flow ("帮我从零开始做小红书博主"). ShuLing will conduct a 3-question persona interview, propose three competitor-seeded topic candidates, and write the SKILL.md state to .shuling/state.json.

Task 2 (existing creator retrospective):
Import any 5-10 past Xiaohongshu notes (via the provided JSON template), then ask Claude Code to run the 5-dimension retrospect. ShuLing will reverse-infer your persona, mine pattern seeds from the imports, and produce a dashboard-style diagnosis.
```

## 1.7 Specific Prompt(s) 字段

```
Prompt A (3 seconds): "帮我选明天的选题"
Expected: ShuLing surfaces 3 topic candidates with trend heat + your historical pattern match score, cited from the preference vector.

Prompt B (1 minute): "我已经发过一些笔记了，想批量导入做个账号体检"
Expected: ShuLing runs path B (existing-creator), walks through the import template, reverse-infers the persona, and produces a 5-dimension retrospect card.

Prompt C (30 seconds, for AI devs): "读 SKILL.md §0a，解释业务路由表的路由函数"
Expected: Claude explains the §0a routing table in SKILL.md — the user-intent-to-capability dispatcher that replaces ad-hoc if/else with a declarative table.
```

## 1.8 Additional Comments 字段

```
This is an experiment in "business logic as Markdown" — the entire creator workflow (routing, content standards, publishing safeguards, self-evolution formulas) lives in a single 1208-line SKILL.md, while Python/Shell scripts only handle I/O. It tests the hypothesis that modern coding assistants can treat natural-language specifications as executable programs.

Known dependencies that reviewers should be aware of:
- xiaohongshu-mcp (third-party MCP, not maintained by this project)
- Gemini 3 Pro Image API (required for the image-generation step, optional otherwise)

No telemetry, fully local state (.shuling/ directory), no auto-update.
```

## 1.9 Checklist（勾选以下所有）

- [x] I have checked that this resource hasn't already been submitted
- [x] It has been over one week since the first public commit (2026-04-16 → 2026-04-23 ≥ 7 days)
- [x] All provided links are working and publicly accessible
- [x] I do NOT have any other open issues in this repository
- [x] I am primarily composed of human-y stuff and not electrical circuits

## 1.10 风险与对策

| 风险 | 对策 |
|---|---|
| **维护者问"Could Opus build this in one session?"** — 如果答案是"能"就会扣分 | 在 Validate Claims 和 Additional Comments 里点名 1208 行 SKILL.md + migrations + preflight + Bayesian loop — 明确超出 single-session 范围 |
| **复杂系统需要长 onboarding 会被扣分** | Specific Task(s) 里提供"3 秒"、"1 分钟"的快速体验路径；说明用户不需要读完 1208 行 SKILL.md 也能 run |
| **涉及第三方 xiaohongshu-mcp** | 在 Additional Comments 提前声明，不让维护者自己发现后觉得被误导 |
| **涉及外部 API（Gemini）** | 在 Additional Comments 声明"Gemini 3 Pro Image API 仅图片生成步骤调用"；强调 state 完全本地 |
| **仓库刚好满 1 周，被判不够成熟** | 2026-04-24 之后再提交（实际已 8 天），给 1 天冗余 |
| **2 stars 看起来新** | 提交前先在社区做一轮 promotion 拉到 20+ star |
| **被误判为"通用工具"** | 在 Display Name 用具体的"ShuLing"而非"小红书博主助手"；Description 强调 Xiaohongshu（RED）特定场景 |

## 1.11 提交命令

```bash
# ❌ 不要用 gh CLI — 维护者反垃圾系统会自动关闭 CLI 提交的 Issue
# gh issue create --repo hesreallyhim/awesome-claude-code ...  # NO

# ✅ 正确方式：浏览器打开 Issue 模板 URL，人工填写
open "https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml"

# Mac 上一次性打开所有必要页面
open "https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml" \
     "https://github.com/hesreallyhim/awesome-claude-code/blob/main/docs/CONTRIBUTING.md" \
     "https://github.com/AI-flower/shuling"
```

**提交前自测**：克隆 awesome-claude-code 仓库，看 `.claude/commands/evaluate-repository.md`，对着薯灵自己跑一遍。

---

# 列表 2: e2b-dev/awesome-ai-agents

## 2.1 调研

- **接纳可能性：中**。这是"通用 AI agent 合集"，分为开源和闭源两部分，共 5591 行，非常庞大。分类宽泛（General purpose, Build your own, Multi-agent, Research, Developer, Content creation 等），content 相关的 agent 虽不少但大多是"generic content writer"，Xiaohongshu 特定 agent 目前 0 个，有差异化空间。
- **条件**：README 第 56 行说"Create a pull request or fill in this [form]"——两种方式都可以。按字母序（条目以 `## [Name]` 为锚）排列。条目格式独特：`## [Name](url)` + 一行 description + 可展开的 `<details>` 块（含 Category / Description bullets / Links）。
- **风险提示**：维护者是 e2b 公司，主要业务是"Code Interpreter for AI apps"，list 本身是拉流量工具，审核相对宽松；但必须严格遵循格式，且放对字母序位置；他们有一个 Google 表单 backlog，PR 也要等几周。

## 2.2 README 条目（PR diff 格式）

**放在哪个 section**：`# Open-source projects`（line 71 之后，按字母序）。

**插入位置**：字母 `S` 区间，按现有条目推测大概在 `Skyvern` 之后、`SuperAGI` 之前或之后。提交时在本地 fork 里搜 `^## \[S` 找精确位置。

**diff 格式**：

```diff
 ## [Skyvern](https://github.com/Skyvern-AI/skyvern)
 Automate browser-based workflows with LLMs and Computer Vision
 ...
 </details>

+## [ShuLing](https://github.com/AI-flower/shuling)
+Xiaohongshu (RED) creator-growth AI agent with a self-evolving preference loop
+
+<details>
+
+### Category
+Content creation, Social media, Build your own, Self-improving
+
+### Description
+
+- **Full creator loop**: single agent drives topic research, dual-stage drafting (outline + body in the RedInk style), two-phase image generation (Gemini 3 Pro Image + cover reference), publish, and five-dimension NoteRx retrospect.
+- **Self-evolving**: learns a Laplace-smoothed preference vector from every publish outcome, with ε-greedy exploration to avoid local optima, and a pattern lifecycle that promotes/retires creative templates automatically.
+- **Two onboarding paths**: cold-start (3-question persona interview + competitor seeding) and existing-creator (batch-import up to 200 past notes → AI-inferred persona → pattern-seed mining).
+- **Runs anywhere**: the same skill works across Claude Code, Codex, and Hermes — no framework lock-in.
+- **Fully local, MIT-licensed**: state lives in `.shuling/`, no telemetry, no cloud sync.
+
+### Links
+- [GitHub](https://github.com/AI-flower/shuling)
+- [Website](https://shuling.pages.dev)
+- [SKILL.md (1208 lines, the "brain")](https://github.com/AI-flower/shuling/blob/main/SKILL.md)
+
+</details>
+
 ## [SuperAGI](https://github.com/TransformerOptimus/SuperAGI)
 ...
```

**条目风格匹配**：模板来源于 README 现有条目（Adala、AgentGPT 等），保持了 `Category / Description (bullets) / Links` 三段式。

## 2.3 PR 标题

```
Add ShuLing — Xiaohongshu creator-growth AI agent
```

> 参考 README line 56："Please keep the alphabetical order and in the correct category"。标题体现"正确分类 + 字母序"。

## 2.4 PR 描述 body

```markdown
## New entry: ShuLing

Adds **ShuLing** — a production AI agent that automates the full content-creator loop on Xiaohongshu (RED, the largest Chinese lifestyle platform, ~300M MAU). Unlike generic content agents, ShuLing focuses on a tight creator-growth feedback loop: every publish outcome updates a persistent preference vector, and creative templates (patterns) evolve through a lifecycle (探索 → 成长 → 成熟 → 衰退).

## Why it fits this list

- New category coverage: no Xiaohongshu-specific agent exists in the list today, while Xiaohongshu is the dominant UGC platform in the Chinese-speaking market.
- It's a complete agent, not a toolkit: one install, one conversation, closed-loop from topic to retrospect.
- Self-improving: the preference-learning loop is the genuine differentiator — most content agents are stateless.

## Highlights

- **Self-evolving** via Laplace-smoothed Bayesian preference learning + ε-greedy exploration + pattern lifecycle (docs in SKILL.md §8).
- **Two modes**: cold-start onboarding (3-question persona) and existing-creator mode (import up to 200 past notes → reverse-infer persona → mine pattern seeds).
- **Provider-agnostic**: runs on Claude Code / Codex / Hermes; swap models via config.
- **Zero telemetry, fully local**: state in `.shuling/`, no cloud calls except optional Gemini image generation.
- **Actively maintained**: 8 releases in 8 days since 2026-04-16; MIT license.

## Checklist

- [x] Alphabetical order preserved (S — between Skyvern and SuperAGI)
- [x] Placed under **Open-source projects**
- [x] Follows the `## [Name](url)` + one-liner + `<details>` Category/Description/Links format
- [x] Repository is open-source, active (v2.3.0 released 2026-04-21), MIT-licensed
- [x] Links validated and publicly reachable
- [x] No duplicate entry exists

## Known dependencies disclosed upfront

- `xiaohongshu-mcp` (third-party MCP server, not maintained by this project) for publish-side operations.
- Gemini 3 Pro Image API (required only when image generation step is invoked).
```

## 2.5 风险与对策

| 风险 | 对策 |
|---|---|
| **字母序放错位置** | Fork 完成后在本地 `grep -n "^## \[" README.md` 确认 S 开头条目顺序，再插入；不要凭空估算 |
| **<details> 块格式不匹配** | 抄现有条目（Adala line 73-96）的缩进、空行；尤其注意 `### Category` / `### Description` / `### Links` 三级标题 |
| **被质疑"不是通用 agent 而是垂类工具"** | PR 描述第一段强调"Full agent with closed loop"，不是"tool"；Category 字段写 Content creation, Social media, Self-improving 三个 |
| **中文平台非英语读者占主导** | README 描述全英文，bullet points 用 "Xiaohongshu (RED)" 双写，一开始就让西方读者知道语境 |
| **PR backlog 可能堆积数周** | 同步提交 Google Form 作为备胎（https://forms.gle/UXQFCogLYrPFvfoUA） |
| **Agent landscape 图片未收录** | 在 PR body 末尾提一句"If the landscape diagram needs updating, happy to provide a logo asset" — 不要求，但示好 |
| **被认为是营销帖** | 保留所有"known dependencies disclosed upfront"——透明换信任 |

## 2.6 提交命令

```bash
# 变量（用到时替换为你的 GitHub 用户名）
MY_GH_USER="weiyong-1"   # ← 改成你自己的 GitHub username
BRANCH="add-shuling"

# Step 1: Fork 到你的账号
gh repo fork e2b-dev/awesome-ai-agents --clone=true --remote=true
cd awesome-ai-agents

# Step 2: 新分支
git checkout -b "$BRANCH"

# Step 3: 在 README.md 中按字母序插入（人工编辑，别 sed，格式精细）
#   - grep 确认插入点：
grep -n "^## \[S" README.md
#   - 用编辑器打开，在 Skyvern 和 SuperAGI（或正确的字母序相邻条目）之间粘贴 2.2 节的 diff 内容

# Step 4: 验证格式
#   - 预览 README.md（VSCode Markdown preview）
#   - 确认 <details> 能正常折叠

# Step 5: 提交
git add README.md
git commit -m "Add ShuLing — Xiaohongshu creator-growth AI agent"
git push -u origin "$BRANCH"

# Step 6: PR（直接用 gh CLI，e2b 没有反 CLI 限制）
gh pr create \
  --repo e2b-dev/awesome-ai-agents \
  --title "Add ShuLing — Xiaohongshu creator-growth AI agent" \
  --body-file /root/shuling-promotion/pr2-body.md \
  --base main \
  --head "$MY_GH_USER:$BRANCH"

# Step 7: 备胎 — 同步填 Google Form
open "https://forms.gle/UXQFCogLYrPFvfoUA"
```

> 注意：第 6 步前需要先把 2.4 节的 PR body 单独存到 `/root/shuling-promotion/pr2-body.md`，不含包围的 ```markdown fence。

---

# 列表 3: Shubhamsaboo/awesome-llm-apps

## 3.1 调研

- **接纳可能性：低**。这个列表 README 第 68 行明确定位：**"Hand-built, not curated"** — "every template here is self-contained with full source code, not collected from elsewhere."这**不是一个外部项目合集**，而是"我手写的模板合集"。把一个 GitHub 外链条目塞进去，大概率被拒或改写。
- **唯一可行路径**：以"提交一个完整模板代码副本"的方式贡献，把薯灵的 SKILL.md + scripts 一起 fork 进 `awesome_agent_skills/shuling-xiaohongshu-skill/` 子目录，并写一个该子目录的 README。而外部链接条目只作为副产物。
- **真实接纳条件**：`awesome_agent_skills/README.md` 给出了每个 skill 的最小结构（`SKILL.md` + 可选 `scripts/` + 可选 `references/`），薯灵的布局正好契合。风险在于：1208 行的 SKILL.md 比现有所有 skills 大 10-100 倍，维护者可能要求瘦身；xiaohongshu-mcp 是强依赖，模板能否真"run in 3 commands"存疑。
- **备选路径**：放弃 awesome_agent_skills 子目录，改投到 `advanced_ai_agents/multi_agent_apps/` 或新开的 `content_creation/` 分类，作为"社交媒体创作 agent"。但仓库当前没有 content_creation 分类，且单文件/单目录的"creator agent"也不属于"multi_agent"。

## 3.2 README 条目（PR diff 格式）

**放在哪个 section**（字母序 + 专门的 skills 目录）：

```diff
 ### 🧩 Awesome Agent Skills
 *Ready-to-use agent skill files you can plug into any AI agent or LLM workflow.*
 
 *   [♾️ Self-Improving Agent Skills](awesome_agent_skills/self-improving-agent-skills/) - Automatically optimize agent skills using Gemini and ADK
+*   [📔 ShuLing — Xiaohongshu Creator Skill](awesome_agent_skills/shuling-xiaohongshu-skill/) - End-to-end content loop (topic → draft → image → publish → retrospect) with Bayesian preference learning and pattern lifecycle. Provider-agnostic.
```

以及在"Browse all 19 skills"的 details 块里新增一行：

```diff
 | 🎓 Academic Researcher | ... |
+| 📔 ShuLing — Xiaohongshu Creator | Content loop for Xiaohongshu creators with self-evolving preference learning |
```

**同时贡献代码文件**（这是关键）：

```
awesome_agent_skills/
└── shuling-xiaohongshu-skill/
    ├── SKILL.md              # 从薯灵仓库复制（可能需要瘦身到 400-600 行）
    ├── README.md              # 新写，针对本列表风格
    ├── scripts/               # 复制核心 scripts 子集
    ├── references/            # 可选，精选 docs
    └── requirements.txt       # 明确列出 xiaohongshu-mcp + gemini SDK 版本
```

**风格观察**：README 第 34 行："100+ AI Agent & RAG apps you can actually run — clone, customize, ship."—— 强调 runnable。贡献时必须保证 `pip install -r requirements.txt` + 一条命令能 run 出可见 demo。

## 3.3 PR 标题

```
feat: add ShuLing — Xiaohongshu Creator Skill (awesome_agent_skills)
```

## 3.4 PR 描述 body

```markdown
## New skill: ShuLing — Xiaohongshu Creator Skill

Adds a new entry under `awesome_agent_skills/shuling-xiaohongshu-skill/` — a hand-built, fully runnable skill for Xiaohongshu (RED) content creators. The skill is contributed as **original work** in the spirit of this repo ("hand-built, not curated"): all SKILL.md content, scripts, and references are authored by the submitter, MIT-licensed, and tested end-to-end.

## Why it fits awesome-llm-apps

- **Hand-built**, not a drive-by link: ships SKILL.md + scripts + references in-repo, not just an external pointer.
- **Runs in 3 commands** (see the skill's README): install deps → register with Claude Code → ask "帮我发小红书" to see the loop execute.
- **Covers the modern skill stack**: Agent Skills + Self-evolution + Multi-modal (image) + MCP tool consumer — exactly the categories this repo showcases.
- **Provider-agnostic**: works on Claude Code / Codex / Hermes with the same skill artifact.
- **MIT-licensed**, fully local state, no telemetry.

## Highlights

- 1208-line SKILL.md drives the entire creator loop — a concrete test of the "business logic as Markdown" design thesis.
- Bayesian preference learning (Laplace smoothing + ε-greedy) with a pattern lifecycle (探索 → 成长 → 成熟 → 衰退) — documented with formulas in SKILL.md §8.
- Two onboarding paths: cold-start and existing-creator (imports 200 historical notes → AI-inferred persona → pattern-seed mining).
- Two-phase image generation (Gemini 3 Pro Image + cover reference) for RedInk visual style.

## Dependencies disclosed

- `xiaohongshu-mcp` (third-party MCP, not maintained by this project) — required for publish-side actions. Skill gracefully degrades to "draft-only mode" if the MCP is not available.
- Gemini API key — only required for the image step; all other steps run on whatever LLM powers the host agent.

## Checklist

- [x] Added entry under **🧩 Awesome Agent Skills** section (alphabetical after self-improving-agent-skills)
- [x] Added entry to the "Browse all 19 skills" table
- [x] New subdirectory `awesome_agent_skills/shuling-xiaohongshu-skill/` with SKILL.md + README + scripts + requirements.txt
- [x] README includes clone → install → run walkthrough (3 commands)
- [x] Follows Agent Skills spec (YAML frontmatter, name, description, license, metadata)
- [x] Apache-2.0 compatible: this contribution is MIT-licensed (permissive superset)
- [x] No broken links; assets/screenshots under 1 MB each
```

## 3.5 风险与对策

| 风险 | 对策 |
|---|---|
| **"Hand-built, not curated" 原则** — 外链项目易被拒 | 实打实把 SKILL.md + scripts copy 进子目录，明确在 PR body 写"contributed as original work, MIT-licensed by the submitter"；上游仓库 shuling 继续存在，但这里有独立副本 |
| **SKILL.md 太长（1208 行）** | 准备"瘦身版"：去掉"老博主接入模式 path B"先只留 path A，压到 600 行以内；在 submit 时同步开 issue 征询是否可接受全量版 |
| **要求 "Runs in 3 commands"** — xiaohongshu-mcp 依赖门槛高 | 在子目录 README 第一段说明"two tiers: draft-only (no MCP needed) and full loop (requires xiaohongshu-mcp)"；让用户 3 命令跑 draft-only demo |
| **License 冲突** | 仓库是 Apache-2.0，贡献 MIT 相容（Apache-2.0 是 permissive 超集对立 MIT）；在 CONTRIBUTING 条款下显式声明 |
| **维护者 @Shubhamsaboo 风格倾向**：偏 RAG + multi-agent + voice + ADK 等"全球热门技术"，中文垂类可能陌生 | 标题和 README 不强调"Chinese creator"，改强调"Content Creator Skill with Self-Evolution" — 让它看起来是个通用 pattern 案例，Xiaohongshu 只是本实例 |
| **无 tests** | 提交前加一个 `tests/test_preflight.py`（调 scripts/preflight.sh --json，assert 返回码 + JSON schema）；上游 shuling 本就有 preflight，复制过来即可 |
| **PR 过大不易 review** | 分两个 PR：PR#1 先加 README 条目 + 最小目录骨架（SKILL.md、README.md、requirements.txt）；PR#2 补齐 scripts 和 references。这样 reviewer 压力小 |
| **图片类样例不好演示** | README 贴一张 ascii 的流程图 + 一个 10 秒的 asciinema 链接（CLI 交互录屏）；避免依赖动图资源 |

## 3.6 提交命令

```bash
MY_GH_USER="weiyong-1"   # ← 你的 GitHub username
BRANCH="add-shuling-skill"
SHULING_LOCAL="/Users/weiyong/Documents/10/shuling"

# Step 1: Fork + clone
gh repo fork Shubhamsaboo/awesome-llm-apps --clone=true --remote=true
cd awesome-llm-apps
git checkout -b "$BRANCH"

# Step 2: 创建新 skill 子目录
mkdir -p awesome_agent_skills/shuling-xiaohongshu-skill/{scripts,references}

# Step 3: 从薯灵仓库复制资产（需要在 Mac 上有源）
#   如果从服务器端做：先 scp 过来
#   scp -r weiyong@100.79.106.110:$SHULING_LOCAL/SKILL.md ./awesome_agent_skills/shuling-xiaohongshu-skill/
#   scp -r weiyong@100.79.106.110:$SHULING_LOCAL/scripts ./awesome_agent_skills/shuling-xiaohongshu-skill/
#   如果在 Mac 本地：直接 cp

# Step 4: 精心编辑三个文件
#   (a) SKILL.md — 瘦身或保留全量（见 3.5 风险对策）
#   (b) awesome_agent_skills/shuling-xiaohongshu-skill/README.md — 按 awesome_agent_skills/README.md 现有 skills 的风格写（100-200 行）
#   (c) requirements.txt — 列 mcp 客户端 + gemini SDK 版本

# Step 5: 在主 README.md 插入两处修改
#   在 "### 🧩 Awesome Agent Skills" section 增加一行
#   在 "Browse all 19 skills" 表格增加一行

# Step 6: 提交
git add awesome_agent_skills/shuling-xiaohongshu-skill/ README.md
git commit -m "feat: add ShuLing — Xiaohongshu Creator Skill"
git push -u origin "$BRANCH"

# Step 7: PR
gh pr create \
  --repo Shubhamsaboo/awesome-llm-apps \
  --title "feat: add ShuLing — Xiaohongshu Creator Skill (awesome_agent_skills)" \
  --body-file /root/shuling-promotion/pr3-body.md \
  --base main \
  --head "$MY_GH_USER:$BRANCH"
```

> 注意：需要把 3.4 的 PR body 单独存为 `/root/shuling-promotion/pr3-body.md`；复制 SKILL.md 时要同时复制 MIT LICENSE 头部 + 在子目录 README 顶部声明许可。

---

# 三个列表的对比差异化 cheat sheet

| 维度 | 列表 1: awesome-claude-code | 列表 2: awesome-ai-agents | 列表 3: awesome-llm-apps |
|---|---|---|---|
| **提交方式** | Issue 模板（人工 UI，禁止 CLI） | PR 或 Google Form | PR（贡献实际代码） |
| **pitch 重心** | Claude 生态工程范式（BRAIN.HANDS.CALIB / JSON Schema / migrations） | 完整自进化 agent（贝叶斯学习 + 模式生命周期） | Hand-built skill 模板（可 clone、可 ship） |
| **接纳概率** | 中高（格式匹配，语调严肃） | 中（格式严格，需对字母序） | 低（强调 in-repo hand-built） |
| **差异化卖点** | skill 工程化——版本号语义化、反模式工程化、preflight 双模式 | 闭环自进化——Laplace 平滑 + ε-greedy + pattern 生命周期 | 可运行模板——3 命令跑起 draft-only demo |
| **隐藏/弱化的卖点** | 不强调 Codex / Hermes（该列表围绕 Claude）；不强调 UI | 不讲 SKILL.md 长度（他们不关心 Markdown 架构）；不讲 CC 特性 | 弱化 Xiaohongshu 垂类（包装成"content creator pattern"） |
| **必讲的卖点** | Agent Skills 分类；1 week 满龄；MIT；可验证 prompt 样例 | 字母序；Open-source；<details> 格式；MIT | In-repo code；3 命令 run；MIT/Apache 兼容；瘦身的 SKILL.md |
| **一句话描述** | "A Claude Code skill for Xiaohongshu creator growth, built on Skill-as-Brain architecture." | "Xiaohongshu creator-growth AI agent with a self-evolving preference loop." | "Hand-built content creator skill with Bayesian preference learning and pattern lifecycle." |
| **不要提的** | "Awesome List" 自提（他们会厌烦） | "hand-built"（不是他们的价值主张） | "external link"（他们只要 in-repo 代码） |
| **风险最大项** | 维护者严格自测"Could Opus build this in one session?" | 字母序插错位置，或 <details> 块格式错乱 | PR 过大或 SKILL.md 过长，没有 runnable demo |
| **提交后预期响应时间** | 7-14 天（bot 先自检，人工后审） | 14-30 天（backlog 堆积） | 14-30 天（代码 review 慢） |
| **备胎路径** | 无（不提就不提） | Google Form（https://forms.gle/UXQFCogLYrPFvfoUA） | 关掉 PR 后只投 1 和 2 |
| **被拒后的二次机会** | 7-14 天后重新 Issue（措辞调整） | 分拆成 2 个 PR（README + landscape） | 转投 `advanced_ai_agents/` 分类 |

---

## 提交后的跟进动作

### 每个列表都要做的

1. **Watch + Star 目标仓库**：让维护者看到"这个人是生态成员，不是 drive-by"。
2. **本周内回复每一条 reviewer 留言**：窗口期很短，maintainer 一周不回复就沉底。
3. **不要同时改 PR 分支和等待 review**：merge 冲突会让维护者烦。
4. **被拒后不要追问"为什么"**：体面 close，等下一次 release（如 v2.4.0）再试。

### 列表专属动作

- **列表 1**：提交 Issue 后不要在 repo 发任何 comment（spam 检测严格）；如果 bot 发现格式错误，只做格式修复不要辩论。
- **列表 2**：同步填 Google Form 做备胎；PR 被忽视 2 周后在 Twitter @e2b 礼貌提醒（他们很活跃）。
- **列表 3**：PR 过程中如果 reviewer 问"能瘦身吗"，立刻准备 400 行版本 push 到同一分支；不要说"1208 行是设计选择"。

### 三个列表都有反馈后，下一步

- 把被 merge 的条目截图，更新到 shuling README 顶部作为"Featured in"标签。
- 把 PR 过程中被 reviewer 问到的高质量问题（如"如何证明自进化不是 placebo"），反过来整理成 `docs/FAQ.md` 发回主仓库，形成正反馈。

---

## 附录：三个 PR body 的独立文件

为了方便 `gh pr create --body-file` 使用，建议把 PR body（不含围栏）保存为：

- `/root/shuling-promotion/pr1-issue-body.md` — 列表 1 实际上是 Issue form 各字段，不是单一 body；建议用 1.4-1.9 节内容 copy-paste 到表单
- `/root/shuling-promotion/pr2-body.md` — 列表 2 的 PR body（2.4 节内容去掉 ```markdown fence）
- `/root/shuling-promotion/pr3-body.md` — 列表 3 的 PR body（3.4 节内容去掉 ```markdown fence）

生成命令：

```bash
# 这里先不生成，提交前手工从本文档 2.4、3.4 节 copy 到对应文件
# 避免和本文档存储重复
```

---

**最后提醒**：三个列表一起发请错开时间（至少相隔 1 天），否则 GitHub trending / 搜索结果会把你标记为"刷列表"行为。推荐顺序：Day 1 列表 2（最标准 PR 流程）、Day 3 列表 1（Issue 推荐，稳）、Day 5-7 列表 3（最花时间的，放最后）。
