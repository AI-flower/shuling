# 薯灵推广执行 Runbook · 第三方源采纳版

> **推广策略**：只做"让其他 skill 集合源 / awesome 列表 / 官方 marketplace **采纳** 薯灵"——不发内容、不运营社交账号。
> **时间表**：2 周内完成 3-5 个集合源的提交 + 至少 1-2 个被 merge。

---

## 📋 总览：4 个目标源 · 4 种不同通道

| 源 | 通道 | 预期效果 | 优先级 |
|---|---|---|---|
| **anthropics/skills**（Claude 官方 skill marketplace） | PR | 最强背书，long-term 流量 | P0（最终目标） |
| **e2b-dev/awesome-ai-agents** | PR | 通用 AI agent 合集，标准列表 | P0（先投，热身） |
| **hesreallyhim/awesome-claude-code** | **Issue 表单**（禁止 PR） | Claude Code 生态精准流量 | P1 |
| **Shubhamsaboo/awesome-llm-apps** | PR（需贡献代码副本） | 接纳概率低，不强求 | P2 |

---

## ✅ Step 0 · 投稿前硬阻断（必须全部满足才能投）

| 检查项 | 状态确认命令 | 当前 |
|---|---|---|
| ☐ 线上 LICENSE 存在 | `curl -s -o /dev/null -w "%{http_code}" https://raw.githubusercontent.com/AI-flower/shuling/main/LICENSE` | ✅ 200（v2.3 Day 0 已修） |
| ☐ 线上 SECURITY.md 存在 | 同上，路径换 SECURITY.md | ✅ 200 |
| ☐ README badge 是当前版本 | `curl -s https://raw.githubusercontent.com/AI-flower/shuling/main/README.md \| grep version-` | **需更新到 v2.4.0**（见 `DAY-0-v2.4.0-PATCH.md`） |
| ☐ 最新 Release 已发 | 浏览器看 `/releases/latest` | **v2.4.0 需发**（用 `github-release-v2.4.0.md`） |
| ☐ 仓库 ≥ 7 天 | git log 第一个 commit | ✅ 2026-04-16 创建，已 ≥ 7 天 |
| ☐ stars ≥ 10（awesome-claude-code 无明文门槛但实际会看） | 浏览器看 stars | **需补** |

> ⚠️ **不满足这 6 条就提 PR/Issue** → reviewer 第一眼就会关闭。

### 补 stars 的受限方式
用户说"不发内容"——那么 stars 不能靠社群推广拉。可接受的做法：
- 自己在同事/朋友群组里私信（非发帖）——不算"发内容推广"
- 你自己的几个 GitHub 账号 star（如果有）
- **或者**：承认 stars 低是事实，在 PR 描述里坦诚 "early-stage, seeking reviewers"——部分 awesome 维护者接受

---

## 🎯 Step 1 · Day 1-2 · 补齐投稿前置

### 1.1 · 发 v2.4.0 GitHub Release

按 `DAY-0-v2.4.0-PATCH.md` Step A-D 跑完：
- ✅ commit & push 所有 docs/promotion/ 里未 commit 的物料
- ✅ sed 改 README + landing badge 到 v2.4.0
- ✅ 浏览器创建 Release v2.4.0（粘贴 `github-release-v2.4.0.md` 全文）

### 1.2 · 为 PR 准备 demo GIF

```bash
brew install vhs
cd /path/to/shuling/docs/promotion
vhs demo.tape    # 产生 demo.gif
cp demo.gif ../../docs/images/demo.gif   # 放到项目里方便 PR 引用
git add docs/images/demo.gif
git commit -m "docs: add demo GIF for skill marketplace submissions"
git push
```

### 1.3 · 渲染 3 张架构图

- 打开 `architecture-diagram.md`，三块 mermaid 逐个到 https://mermaid.live
- 主题选 dark，导出 SVG
- 保存到 `docs/images/architecture-{overview,routing,evolution}.svg`
- README 顶部引用（如果还没）

### 1.4 · README 顶部"为什么值得收录"区块

投 awesome 列表时 reviewer 要 30 秒内看出卖点。在 README 顶部（badge 下面）加一段：

```markdown
## 🧭 Why this repo

- **Skill-as-Brain architecture** — 1208-line SKILL.md drives business logic; `scripts/` are mechanical hands only
- **Versioning designed for skills** — BRAIN.HANDS.CALIB semver
- **JSON Schema contracts** — prevents AI drift on state writes
- **Agent-native upgrade infrastructure** (v2.4.0) — `install.sh upgrade-all` with JSON observability
- **Multi-platform** — Claude Code / Codex / Hermes
- **Fully local, MIT, no telemetry**
```

这一段等价于给 reviewer 递名片。

---

## 🎯 Step 2 · Day 3 · 先投 e2b-dev/awesome-ai-agents（最标准）

### 为什么先投这个
- 允许 PR 通道（vs awesome-claude-code 只能 Issue）
- 按字母序 + `<details>` 块，格式最标准
- 通用 AI agent 合集，受众广
- 成功后作为其他列表的社会证明（"已被 XX 收录"）

### 具体操作
打开 `awesome-prs-ready-to-submit.md` 的 **列表 2** 章节，按里面的步骤：

1. Fork e2b-dev/awesome-ai-agents → 你的账号
2. clone → 新 branch → 在 README 正确位置插入 shuling 条目
3. commit → push → 用 `gh pr create` 或浏览器创建 PR
4. PR body 使用 awesome-prs-ready-to-submit.md 里 列表 2.4 节提供的完整 body

**不要**：在 PR 描述里贴你的博客链接或社群贴子——reviewer 会视为 content spam。

### 等待期
PR 提交后 3-7 天内可能被 review。期间：
- ⏸ 不要做任何"社交炒作"动作
- ✅ 每天 check PR comments，有 reviewer 评论就**当天**回
- ✅ 如果 reviewer 说"改下 description"之类，立刻改，不要争辩

### 通过后
- 立刻到 PR 里评论一句 "Thank you for the review, happy to help maintain" —— 为以后 awesome 扩展铺关系
- 在你的 `docs/adr/` 里加一份 "2026-04-XX-awesome-ai-agents-accepted.md" 记录——为下次投其他源提供社会证明

---

## 🎯 Step 3 · Day 5-6 · 投 hesreallyhim/awesome-claude-code（Issue 通道）

### 关键警告
⚠️ **不能用 PR**。README 明文："the only person who is allowed to submit PRs is Claude"。违规提 PR 会被反垃圾系统自动关闭。**必须走 Issue 表单**。

### 具体操作

1. 打开 https://github.com/hesreallyhim/awesome-claude-code/issues/new/choose
2. 选 "Recommend Resource" 模板
3. 按 `awesome-prs-ready-to-submit.md` **列表 1.3-1.11** 节，每个字段填进去
4. **不要**用 gh CLI 提交 Issue——用浏览器
5. 提交后 watch 这个 Issue，reviewer 可能几天内回复

### 等待期
同 Step 2，不要做任何社交动作，只盯 Issue 回复。

---

## 🎯 Step 4 · Day 7+ · Shubhamsaboo/awesome-llm-apps（低期望）

### 为什么低期望
该仓库明文："Hand-built, not curated — every template here is self-contained with full source code."
要接纳必须**贡献 SKILL.md + scripts 的代码副本**到 `awesome_agent_skills/shuling-xiaohongshu-skill/` 子目录。

### 如果你愿意做
按 `awesome-prs-ready-to-submit.md` **列表 3** 章节：
1. Fork → 创建 `awesome_agent_skills/shuling-xiaohongshu-skill/`
2. 精简版 SKILL.md（只留核心 §0a/§2/§4）
3. 简化版 scripts（只留 xhs.sh + db.sh + image.py 的最小可运行版）
4. 独立 README 讲 3 命令可跑
5. PR

### 如果不愿意
**跳过就跳过**。不强求。单纯 awesome-claude-code + awesome-ai-agents + Anthropic 官方 已经是很强的组合。

---

## 🎯 Step 5 · Day 10+ · 冲 anthropics/skills 官方

### 前置条件（比普通 awesome 严格）
- [ ] 至少 1 个 awesome 列表已 merge（社会证明）
- [ ] GitHub Release v2.4.0 已发
- [ ] stars ≥ 20（官方 skill marketplace 通常看活跃度）
- [ ] LICENSE / SECURITY / README 完整且专业
- [ ] demo GIF 或架构图放在 README 顶部
- [ ] CHANGELOG / UPGRADE / RELEASING 三件套齐全（薯灵已有）

### 具体操作
使用 `anthropics-skills-pr.md` 的完整 PR body。
提交到 https://github.com/anthropics/skills（注意：最新接纳流程看仓库 README，可能是 contributor process 而非直接 PR）。

### Review 周期
Anthropic 官方仓库 review 可能需要 2-4 周。期间：
- 准备好回应 reviewer 的问题（用 awesome-prs 里的"风险与对策"预案）
- 不要催——官方 review 催了反而有负面印象

---

## 📊 指标跟踪（周复盘）

每周一记录：
- 提交的 PR/Issue 数（本周）
- Merged / Closed / Pending 数
- Stars 周增量
- Issues 收到数（其他人看到后来 report bug）
- 官方/非官方收录数

### 成功阈值（2 周时）
- 至少 1 个 awesome 列表 merge → ✅ 最低成功
- 2 个 awesome + 1 个 anthropics/skills PR submitted → ✅ 好
- 3+ awesome + anthropics/skills merged → 🏆 超预期

---

## 🚫 明确不做的事

按用户本次调整，**以下全部不做**：
- ❌ 不发博客（Medium / Dev.to / 少数派 / 掘金 / 知乎 / 个人博客）
- ❌ 不发社群贴（V2EX / 即刻 / Anthropic Discord / 微信群 / B 站 / LinkedIn）
- ❌ 不发推特/X thread
- ❌ 不发 Hacker News Show HN
- ❌ 不联系 KOL、influencer
- ❌ 不投 Product Hunt

完备的这些弹药在 `archived-content-campaign/` 里保底，未来策略变了随时取。

---

## 🔁 如果 2 周后 0 merge

可能原因 + 应对：
1. **stars 太低** → 前面说过的"受限拉 star"或接受现实
2. **README 不够有说服力** → 加 demo GIF、架构图、testimonials（如果有）
3. **投错通道**（比如在 awesome-claude-code 提了 PR 被关） → 重新按 Issue 表单来
4. **维护者没看到** → 在 PR 里 ping 一次（不要连续 ping）

实在全部 0 merge：考虑加**最轻量**的一条内容（比如在你个人 GitHub profile README 加一条 pinned repo 介绍），这不算"发内容推广"。
