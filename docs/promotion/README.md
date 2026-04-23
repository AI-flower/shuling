# 薯灵推广物料包

> 生成于 2026-04-23
> 目标：把薯灵 v2.3.0 "Pure Image Pipeline" 推广到各 skill 集合源
> 策略：T2 Awesome 列表 → T3 第三方 skill 仓库 → T1 anthropics/skills 官方

---

## 物料清单

### 🗓️ 执行手册（先看这个）
| 文件 | 用途 |
|---|---|
| **`DAY-0-QUICKSTART.md`** | 🔥 **今天 1 小时搞定准备**（8 步可复制粘贴命令） |
| **`RUNBOOK.md`** | 14 天完整执行时间表，每天勾选即可 |

### 📦 直接可用的发布物料
| 文件 | 用途 | 投放目标 |
|---|---|---|
| `github-release-v2.3.0.md` | v2.3.0 Release notes（935 词，中英混排） | GitHub Releases 页面直接粘贴 |
| `blog-1-skill-as-brain.md` | **核心博客**：Skill-as-Brain 架构全解（3800 字中文） | 少数派/掘金/个人博客 |
| `blog-1-skill-as-brain.en.md` | 英文版（2730 词） | Dev.to/Medium/Hacker News |
| `blog-2-semver.md` | BRAIN.HANDS.CALIB 版本号文章（2700-2900 字） | 同上，第二篇 |
| `blog-3-preference-learning.md` | 算法深度稿 Laplace+Confidence（4500-5000 字） | 同上，第三篇（技术最硬） |
| `awesome-prs-ready-to-submit.md` | **3 个 Awesome 列表实地调研 + PR/Issue 完整草案**（含禁用 gh CLI 警告等关键信息） | 按列表不同通道提交 |
| `anthropics-skills-pr.md` | anthropics/skills 官方 PR 描述（T1 冲刺用） | PR body 粘贴 |
| `social-posts.md` | 7 个平台发布贴（V2EX/即刻/Twitter/HN/Discord/微信群/B 站） | 按日期分平台发 |
| `awesome-listings.md` | 各 Awesome 列表一行介绍（中英 10 变体） | 补充备选文案 |
| `anti-faq.md` | 13 个常见质疑的标准回复（推广时评论区用） | 遇到问题时查 |

### 🏗️ 项目补齐文件
| 文件 | 用途 |
|---|---|
| `LICENSE` | MIT LICENSE（项目根目录缺失） |
| `SECURITY.md` | 安全声明：数据本地化、凭据保护、威胁模型 |
| `patches/01-version-sync.patch` | README + landing badge v2.2.0 → v2.3.0 替换说明 |

### 🎨 配图与深度内容
| 文件 | 用途 |
|---|---|
| `architecture-diagram.md` | 3 份 mermaid 架构图源码（全景/业务路由/自进化） |
| `blog-drafts.md` | 原始三篇大纲（仅留作参考，blog-1/2/3 已完整稿） |

---

## 如何使用

### 第 1 步：apply patch（可选）

```bash
cd /Users/weiyong/Documents/10/shuling
git diff > /tmp/current-dirty.patch  # 先备份当前脏工作区
# 用编辑器把 patches/01-version-sync.patch 的替换逻辑对照到 README.md 和 landing/index.html
```

> ⚠️ 注意：你本地已有 README.md / landing/index.html 的未提交改动（tabel 已改成 v2.3.0，title 已改成新文案），patch 只需改 README 顶部 badge（3 处）+ landing 硬编码 v2.2.0（8 处）。不要盲目用 `git apply`，因为当前脏状态会冲突——手工改最稳。

### 第 2 步：复制 LICENSE 和 SECURITY.md

```bash
scp /root/shuling-promotion/LICENSE weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/LICENSE
scp /root/shuling-promotion/SECURITY.md weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling/SECURITY.md
```

### 第 3 步：按时间表投稿

参考主回答里的两周时间表，从 Day 3 开始 T2 Awesome 列表批量 PR，到 Day 10 冲 anthropics/skills 官方。

---

## 关于 demo GIF 和架构图

- **demo GIF**：我无法代录，建议你用 `asciinema rec` 或 `vhs` 录 90 秒。脚本：`install.sh --check` → "帮我发小红书" → 选题三选一 → 大纲 → 图（配图建议展示）→ 发布成功。
- **架构图**：我生成了 mermaid 源码，`architecture-diagram.md` 里 3 张。用 `mermaid.live` 或本地 `mmdc` 导出 SVG/PNG 后放 README。
