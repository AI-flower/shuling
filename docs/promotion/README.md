# 薯灵推广物料包 · 第三方源采纳版

> 2026-04-23 调整：**只做"被第三方源平台采纳"**（awesome 列表 / anthropics/skills / skill marketplace）。
> **去掉**所有"自己在第三方平台发布内容"的推广（博客 / 社群贴 / Twitter / HN 等）。
>
> 内容类弹药完备归档在 `archived-content-campaign/`，未来策略变化可取用。

---

## 🗓️ 从这里开始

| 文件 | 做什么 |
|---|---|
| **`RUNBOOK.md`** | **主文件**：4 个源 × 不同通道 × 2 周时间表 |
| `DAY-0-QUICKSTART.md` | Day 0 准备工作（v2.3 版初始设置，已完成参考） |
| `DAY-0-v2.4.0-PATCH.md` | v2.4 上线追加动作（commit 未提交物料 + badge 同步 + 发 Release） |

---

## 📦 核心采纳物料（投稿时用）

| 文件 | 目标源 | 通道 |
|---|---|---|
| **`awesome-prs-ready-to-submit.md`** | 3 个 awesome 列表（含实地调研与正确通道） | PR / Issue |
| **`anthropics-skills-pr.md`** | anthropics/skills 官方 marketplace | PR |
| `awesome-listings.md` | 10 变体一行介绍（CN/EN） | 备选文案 |

---

## 🛡️ 投稿前置硬阻断（必须先齐）

| 文件 | 用途 | 状态 |
|---|---|---|
| `LICENSE` | MIT，被投稿必要条件 | ✅ 已上线 |
| `SECURITY.md` | 数据/凭据/威胁模型 | ✅ 已上线 |
| `github-release-v2.3.0.md` | v2.3 Release body | ✅ 已发 |
| **`github-release-v2.4.0.md`** | **v2.4 Release body（1148 词，待发）** | 🔴 需发 |
| `patches/01-version-sync.patch` | v2.2 → v2.3 badge 同步说明（已过） | （参考） |

---

## 🎨 PR 附件（README 会展示）

| 文件 | 用途 |
|---|---|
| `architecture-diagram.md` | 3 张 mermaid 源码（全景 / 业务路由 / 自进化），PR 里 README 配图 |
| `demo.tape` + `demo-README.md` | vhs 脚本自动录制 demo GIF（75 秒，无需真 Claude） |

---

## 📁 archived-content-campaign/ · 内容类弹药（当前不启用）

| 文件 | 类型 |
|---|---|
| `blog-1-skill-as-brain.md` + `.en.md` | 博客 3800 字中 / 2730 词英 |
| `blog-2-semver.md` + `.en.md` | 博客 2800 字中 / 2719 词英 |
| `blog-3-preference-learning.md` + `.en.md` | 博客 4800 字中 / 4300 词英 |
| `blog-drafts.md` | 原始博客大纲 |
| `social-posts.md` | V2EX / 即刻 / Twitter / HN / Discord / 微信群 / B 站 7 平台 |
| `hn-show-hn-post.md` | HN Show HN 优化稿 + 提交策略 |
| `v2.4.0-pitch.md` | v2.4 专属独立推广素材 |
| `anti-faq.md` | 13 条社群质疑回复模板 |

归档理由见 `archived-content-campaign/_WHY-ARCHIVED.md`。

未来要激活：删除一个 README 里的说明行，从 archive 把文件 mv 回父目录。

---

## 🎯 2 周目标

| 周 | 动作 |
|---|---|
| Week 1 | 投 1-2 个 awesome 列表（e2b-dev + hesreallyhim），发 v2.4 Release |
| Week 2 | 跟进 review，投第 3 个，冲 anthropics/skills 官方 |

**最低成功线**：Week 2 结束前至少 1 个 awesome 列表 merge。

---

## ✅ 当前状态速查

```bash
# 验证线上就绪
curl -s -o /dev/null -w "LICENSE:  %{http_code}\n"   https://raw.githubusercontent.com/AI-flower/shuling/main/LICENSE
curl -s -o /dev/null -w "SECURITY: %{http_code}\n"   https://raw.githubusercontent.com/AI-flower/shuling/main/SECURITY.md
curl -s https://raw.githubusercontent.com/AI-flower/shuling/main/README.md | grep -E 'version-|codename-' | head -2
curl -s -o /dev/null -w "Release v2.4.0: %{http_code}\n" https://api.github.com/repos/AI-flower/shuling/releases/tags/v2.4.0
```

通过 4 项（200/200/v2.4.0 badge/200），立刻开始投 Step 2。
