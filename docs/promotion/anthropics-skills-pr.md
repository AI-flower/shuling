# anthropics/skills PR 描述草案

> T1 官方 skill 集合源。建议在 Day 10 左右冲刺，前面 T2 awesome + T4 社群已积累星数和口碑后提交，过审概率更高。

---

## PR 标题

```
feat: Add shuling — Xiaohongshu creator-growth skill with Skill-as-Brain architecture
```

---

## PR 描述（英文版）

```markdown
# shuling — Xiaohongshu Creator-Growth Skill

**Repository**: https://github.com/AI-flower/shuling
**Version**: v2.3.0 "Pure Image Pipeline" (released 2026-04-21)
**License**: MIT

## What it does

A production-grade Claude skill for Xiaohongshu (RED, 小红书) creator workflow:

- **Onboarding**: 3-question profile dialog for new creators, OR batch-import 200 historical posts + AI-reversed profile for existing creators
- **Daily loop**: topic research → dual-stage drafting (outline + copy, RedInk-style) → two-stage image gen (Gemini 3 Pro Image) → publish via `xiaohongshu-mcp` → retrospect with NoteRx 5-dim diagnosis
- **Self-evolution**: Laplace-smoothed Bayesian preference learning + ε-greedy exploration + pattern lifecycle (experimental → medium → high)

## Why this is a good reference skill

This is not just another content tool — it's a **reference implementation for production skill engineering**:

1. **Skill-as-Brain architecture** — 1208-line SKILL.md drives the entire business loop; `scripts/` are pure mechanical "hands" (DB I/O, MCP calls, image gen). No business logic in code.

2. **BRAIN.HANDS.CALIB semver** — Semantic versioning designed *for* AI skills:
   - BRAIN+1 = SKILL.md flow changes (breaking)
   - HANDS+1 = scripts/DB/MCP additions (minor)
   - CALIB+1 = threshold/prompt tweaks (patch)

3. **JSON Schema contracts** — `schemas/` enforces AI writes to `state.json` / `profile.json` / `preferences.json` / `audit-report.json` follow strict field conventions. Defensive against AI drift.

4. **Dual-mode preflight** — `preflight.py` outputs structured JSON for agents AND colorized human table for manual debugging (exit codes 0/1/2).

5. **Idempotent migrations** — `migrations/vX.Y.Z.sh` run in order, safe to retry.

6. **Multi-platform** — Works identically on Claude Code (`/loop` trigger), Codex, Hermes (cron jobs). Platform-specific notes in `platform/*.md`.

7. **Active + disciplined** — 71 commits, 8 releases in 2 months, with matching CHANGELOG / UPGRADE / RELEASING triad.

## What's *not* included (by design)

- ❌ No automation / farming / TOS-violating behavior (§5 compliance rules enforced)
- ❌ No telemetry / analytics / data upload
- ❌ No IM/notification channels (those belong to the host platform, e.g. Hermes-agent)
- ❌ No HTML template fallback for image gen (v2.3.0 intentionally removed — Gemini-only for quality)

## Dependencies

- `xiaohongshu-mcp` (third-party MCP) — for Xiaohongshu platform ops
- Gemini API Key — for image generation (required, no fallback)
- SQLite3 / Python 3 / jq — standard tooling

## Links

- 📦 GitHub: https://github.com/AI-flower/shuling
- 🌐 Website: https://shuling.pages.dev
- 📖 SKILL.md: https://github.com/AI-flower/shuling/blob/main/SKILL.md (the agent-facing brain)
- 📋 CHANGELOG: https://github.com/AI-flower/shuling/blob/main/CHANGELOG.md
- 🏗 Architecture deep-dive (blog post): <TBD link to blog when published>

## Checklist

- [x] MIT licensed (`LICENSE` in repo root)
- [x] SECURITY.md documents data handling and threat model
- [x] README has install/usage for both new creators (path A) and existing creators (path B, v2.2.0+)
- [x] Platform adapters for Claude Code / Codex / Hermes
- [x] No telemetry, no data upload, fully local
- [x] CHANGELOG follows keep-a-changelog format with dual-column (user-visible / how-to-upgrade)
- [x] Active maintenance (latest release < 7 days old)

## Category suggestion

If `anthropics/skills` has categories, suggest placing under:
- `content-creation/` or `social-media/` (primary)
- With a tag `reference-implementation` or `production-grade` given the architecture depth
```

---

## PR 描述（中文版，如果仓库允许中文）

```markdown
# shuling — 小红书博主成长 Skill

**仓库**：https://github.com/AI-flower/shuling
**版本**：v2.3.0 "Pure Image Pipeline"（2026-04-21 发布）
**许可证**：MIT

## 做什么

面向小红书博主的生产级 Claude skill：

- **新手引导**：三问建画像；**或** 老博主批量导入 200 条历史 → AI 反推画像（v2.2.0+）
- **日常闭环**：选题 → RedInk 双阶段起稿（大纲 + 正文）→ 两阶段图片生成（Gemini 3 Pro Image + 封面参考）→ xiaohongshu-mcp 发布 → NoteRx 五维诊断复盘
- **自进化**：Laplace 贝叶斯偏好学习 + ε-greedy 探索 + pattern 生命周期

## 为什么值得收录为参考 skill

不只是业务工具，更是 **生产级 skill 工程的参考实现**：

1. **Skill-as-Brain 架构** — 1208 行 SKILL.md 驱动完整业务，scripts/ 只做物理操作
2. **BRAIN.HANDS.CALIB 三段语义化版本号** — 为 AI skill 设计
3. **JSON Schema 契约** — AI 写入前自校验，防飘走
4. **preflight 双模式** — 给 AI 的 JSON + 给人的彩色表
5. **migrations 幂等** — 可重试、可回溯
6. **三平台通用** — Claude Code / Codex / Hermes 一致行为

## 清单

- [x] MIT 许可
- [x] SECURITY.md 说明数据处理
- [x] README 覆盖新老博主两条路径
- [x] 三平台适配文档齐全
- [x] 零遥测、零上传、纯本地
- [x] CHANGELOG 遵循 keep-a-changelog + 双栏
- [x] 活跃维护（最新版本 < 7 天）
```

---

## 提交前最后清单

1. [ ] README 顶部 badge 同步到 v2.3.0（见 `patches/01-version-sync.patch`）
2. [ ] `LICENSE` 文件已添加（见 `LICENSE`）
3. [ ] `SECURITY.md` 已添加（见 `SECURITY.md`）
4. [ ] 录制 60-90s demo GIF/视频，放 README 顶部
5. [ ] 架构图 SVG 从 `architecture-diagram.md` 导出，放 README 架构章节
6. [ ] GitHub Release v2.3.0 的 release notes 写完整（复用 CHANGELOG.md 的 [2.3.0] 段）
7. [ ] 至少一个 T2 awesome 列表已 merge（证明有社区认可）
8. [ ] Anthropic Discord #skills 频道已 post（暖场）

全部勾完再提官方 PR。
