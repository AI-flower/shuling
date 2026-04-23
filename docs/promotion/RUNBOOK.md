# 薯灵推广执行 Runbook（14 天完整时间表）

> 每天照着打勾执行。所有动作都有对应物料文件，不用现写。

---

## Day 0 · 今日必做（准备工作，2-3 小时）

### ☐ 1. 同步版本 badge
```bash
# 按 patches/01-version-sync.patch 手工改 README.md + landing/index.html
# 或一键 sed（小心当前工作区已脏，冲突时手工）
cd /Users/weiyong/Documents/10/shuling

# 先 commit 当前脏工作区（如果改动是 OK 的）
git diff README.md landing/index.html > /tmp/shuling-dirty-backup.patch

# 再 apply badge 同步
# 详细替换命令见 patches/01-version-sync.patch
```

### ☐ 2. 添加 LICENSE 和 SECURITY.md
```bash
scp /root/shuling-promotion/LICENSE weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/LICENSE
scp /root/shuling-promotion/SECURITY.md weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/SECURITY.md
```

### ☐ 3. 导出 mermaid 架构图 → SVG/PNG
- 打开 `architecture-diagram.md`
- 逐个复制 mermaid 代码块到 https://mermaid.live
- 选 `dark` 主题，Export SVG
- 保存到 Mac 的 `shuling/docs/images/`（新建目录）：
  - `architecture-overview.svg`（全景）
  - `routing-flow.svg`（业务路由）
  - `self-evolution.svg`（自进化引擎）

### ☐ 4. 录 demo GIF（可选但强推）
- 工具：`vhs` 或 `asciinema` 或手机录屏转 GIF
- 内容：60-90 秒
- 脚本：
  1. 终端输入 `bash install.sh --check`（3s）
  2. 切到 Claude Code，输入"帮我发小红书"（3s）
  3. 展示选题三选一（8s）
  4. 用户回"1"（1s）
  5. 展示大纲 6 页（10s 滚动）
  6. 展示图片生成过程（15s）
  7. 展示发布成功（3s）
  8. 数据进化日志（5s）
- 保存 `shuling/docs/images/demo.gif`（≤5MB，推特/GitHub 友好）

### ☐ 5. commit + tag + push
```bash
cd /Users/weiyong/Documents/10/shuling
git add LICENSE SECURITY.md README.md landing/index.html docs/images/
git commit -m "docs(v2.3.0): sync badges + add LICENSE/SECURITY.md + demo assets"
git tag -a v2.3.0 -m "Pure Image Pipeline"
git push origin main --tags
```

### ☐ 6. 在 GitHub 创建 Release v2.3.0
- 访问 https://github.com/AI-flower/shuling/releases/new
- Tag: `v2.3.0`
- Title: `v2.3.0 — Pure Image Pipeline`
- Body: 复制 `github-release-v2.3.0.md` 内容
- Publish

---

## Day 1-2 · 内容储备

### ☐ 7. 补充项目根目录的 `docs/promotion/` 目录
```bash
scp -r /root/shuling-promotion weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/docs/promotion/
# 注意：这个目录会进 git，体现你把推广当作正规工程
```

### ☐ 8. 发三篇博客中的至少一篇到你的平台
- 首选：文章 1（Skill-as-Brain） → `blog-1-skill-as-brain.md`
- 平台：少数派 / 掘金 / Medium（英文） / 个人博客
- 发布后把链接更新到 `anthropics-skills-pr.md` 的 "Architecture deep-dive" 占位

---

## Day 3 · 中文社群首轮（先拉 stars，不投 awesome）

### ☐ 9. V2EX 分享创造节点发长贴（早 10 点）
- 使用 `social-posts.md` 第 1 条完整版
- 重点突出 "Skill-as-Brain 架构" 的叙事
- 目标：产出 1 个 V2EX 贴子 → 200+ 浏览 → 10-20 GitHub stars

### ☐ 10. 即刻 AI 探索者圈子短贴（午 12:30）
- 使用 `social-posts.md` 第 2 条
- 配图：博客 1 里的架构 mermaid 截图

### ☐ 11. Claude Code 中文社区微信/飞书群（晚 8 点）
- 使用 `social-posts.md` 第 6 条（200 字版）
- 强调"参考架构"，不要推销"小红书工具"

**目标**：Day 4 早上 GitHub stars ≥ 15-20，才具备冲 awesome 的资格。

---

## Day 4-7 · T2 Awesome 列表投递（❗ 顺序和通道都有讲究）

> ⚠️ **实地调研发现**（见 `awesome-prs-ready-to-submit.md`）：三个列表规则差异很大，**不要一起 PR**。

### ☐ 12a. Day 4 · 先投 `e2b-dev/awesome-ai-agents`（最标准，PR 通道）
- 按字母序插入 `## [shuling](url)` + `<details>` 块
- 允许 PR 或 Google Form 双通道
- **pitch 重心**：贝叶斯偏好学习 + ε-greedy + pattern 生命周期（自进化闭环）
- 完整 diff + 提交命令见 `awesome-prs-ready-to-submit.md` 列表 2 章节

### ☐ 12b. Day 6 · 再投 `hesreallyhim/awesome-claude-code`（Issue 通道）
> ⚠️ **不要用 `gh` CLI 提 PR**——维护者在 README 明文禁止："the only person who is allowed to submit PRs is Claude"；`gh` CLI 提交会被反垃圾系统自动关闭
- **正确通道**：在浏览器打开 Issues → New Issue → 选 "Recommend Resource" 模板
- 按 `.github/ISSUE_TEMPLATE/recommend-resource.yml` 逐字段填
- **pitch 重心**：BRAIN.HANDS.CALIB / JSON Schema / migrations（工程范式）
- Issue body 和逐字段填值见 `awesome-prs-ready-to-submit.md` 列表 1 章节

### ☐ 12c. Day 7 · 最后冲 `Shubhamsaboo/awesome-llm-apps`（接纳概率低，期望降低）
> ⚠️ 该仓库**明文不收外链**："Hand-built, not curated — every template here is self-contained with full source code"
- 要接纳必须贡献 **SKILL.md + scripts 的代码副本** 到 `awesome_agent_skills/shuling-xiaohongshu-skill/` 子目录
- **pitch 重心**：3 命令可跑的 skill 模板（降垂类，升通用 pattern）
- 投递不成功不必纠结——这是 nice-to-have，不是必拿

### 🚨 投递前硬阻断（先完成 Day 0-2 才能投）
- [ ] 线上 repo 有 `LICENSE` 文件（`raw.githubusercontent.com/.../LICENSE` 不能 404）
- [ ] 线上 README badge 已同步 v2.3.0（当前仍是 v2.2.0）
- [ ] GitHub Release v2.3.0 已发布
- [ ] stars ≥ 20（建议先 Day 4-5 在中文社群拉一波）
- [ ] 仓库龄 ≥ 7 天（awesome-claude-code 最低龄要求，2026-04-23 正好第 8 天，刚过）

---

## Day 8 · B 站视频（可选，看精力）

### ☐ 13. 录 6 分钟技术 vlog（如有精力）
- 脚本见 `social-posts.md` 第 7 条
- 硬件：OBS 屏幕录制 + 普通麦克风
- 后期：剪映简剪，加字幕
- 上传：标签 `编程 AI 开源 Claude MCP 小红书`

---

## Day 10 · Anthropic Discord #skills

### ☐ 14. Discord 发完整介绍贴
- 使用 `social-posts.md` 第 5 条
- 频道：Anthropic official server / Claude Code channel
- 时间：周日午（欧美活跃时间，中国夜晚）

---

## Day 11 · Twitter/X 英文 Thread

### ☐ 15. 3-tweet thread
- 使用 `social-posts.md` 第 3 条
- 时间：周一上午（美东时间）
- 转发：自己其他账号 + @ 几个相关 KOL（如 @simonw @karpathy 不强求 interaction）

---

## Day 14 · Hacker News Show HN（最后冲刺）

### ☐ 16. Show HN
- 使用 `social-posts.md` 第 4 条
- 时间：周二或周三美东早上 9 点（HN 流量峰值）
- 注意：不要刷票、不要点赞党、不要评论区自我吹嘘
- 准备：手机开通知，头 2 小时内要快速回所有评论

---

## Day 14+ · T1 anthropics/skills 官方 PR

### ☐ 17. 冲官方 skill 集合源
前置条件（必须全勾才提交）：
- [ ] 至少 1 个 T2 awesome 列表已 merge
- [ ] Anthropic Discord 有反馈
- [ ] Twitter thread 有 ≥ 50 like
- [ ] GitHub stars ≥ 30
- [ ] 至少 1 篇博客发了

满足后：
- 使用 `anthropics-skills-pr.md` 的完整 PR 描述
- 提交到 https://github.com/anthropics/skills
- 准备 review iteration（可能要改几轮）

---

## 持续跟踪（每周一复盘）

### 指标
- GitHub stars 增长曲线
- 官网 `shuling.pages.dev` 访问量
- 各社群贴子的浏览/回复/转发
- issue 和 PR 数（有人在看真实代码的信号）

### 如果某些渠道没反应
- V2EX 24 小时没 up 主动→ 换节点再发一次
- 即刻没人点→ 配更好的封面图再发
- awesome PR 被拒 → 看评论调整策略，2 周后再试
- Discord 没回复 → 换个子频道 repost 一次（不要刷）

### 如果火了
- 把评论区最好的 5 个反馈写进 `docs/testimonials.md`
- 准备好回答"你们会做 SaaS 吗？"—— 答：不会（要捍卫 Skill-as-Brain 叙事）
- 所有媒体询问都回导向 GitHub，不接私下定制

---

## 附录 A · 物料速查

| 你要的东西 | 在哪 |
|---|---|
| 一行介绍（多语言多变体） | `awesome-listings.md` |
| 官方 PR 描述 | `anthropics-skills-pr.md` |
| 社群贴子（中英 7 平台） | `social-posts.md` |
| 3 个 awesome PR 完整指令 | `awesome-prs-ready-to-submit.md` |
| GitHub Release body | `github-release-v2.3.0.md` |
| 核心博客 1 完整稿 | `blog-1-skill-as-brain.md` |
| 博客 2 完整稿 | `blog-2-semver.md` |
| 博客 3 大纲 | `blog-drafts.md` 第 3 段 |
| 架构图源码（mermaid） | `architecture-diagram.md` |
| LICENSE 全文 | `LICENSE` |
| SECURITY.md | `SECURITY.md` |
| 版本同步 patch | `patches/01-version-sync.patch` |

## 附录 B · 一键全部 scp 到 Mac

```bash
scp -r /root/shuling-promotion weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/docs/promotion/
```

然后 Mac 上 commit 这个目录：
```bash
cd /Users/weiyong/Documents/10/shuling
git add docs/promotion/
git commit -m "docs: add promotion materials package"
```
