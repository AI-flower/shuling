---
title: knowledge-base 自进化闭环真实性诊断
date: 2026-04-23
trigger: roadmap A3 P0 任务
status: completed
---

# A3 诊断报告 — 自进化闭环真实性

**结论**：不是 dead code，但**每日复盘 → patterns 进化** 后半段在所有 target 上未观测到数据。

## 三 target 扫描结果（2026-04-23）

### codex (`~/.codex/skills/shuling/`)
- knowledge-base/: `audit-2026-04-21.{json,md}` / `evolution-log.md` / `patterns.md` / `preferences.json` **全在**
- state.json: **异常** — 只有 `{"mcp_configured":true}`，缺 `setup_completed`、`profile_created`、`setup_date`
- VERSION: 2.3.0
- 判定：v2.2.0 老博主接入流程走通过（有 audit report），但基础 state 字段丢失，下次 §0a 业务路由会误判为未完成安装

### hermes (`~/.hermes/skills/social-media/shuling/`)
- knowledge-base/: 仅 `preferences.json` + `profile.json` + `preferences.json.bak-v2.3.0`（升级备份）
- state.json: ✅ 完整（mcp + profile_created + setup_completed + setup_date）
- VERSION: 2.3.0
- 判定：profile 已建立，但**patterns.md / evolution-log.md / reviews/ 完全缺失** → 每日复盘未执行过（或执行了但未落盘）

### claude (`~/.claude/skills/shuling/`)
- knowledge-base/: 完全空（只有 `.gitkeep`）
- state.json: 只有 `mcp_configured`
- VERSION: 文件不存在
- 判定：仅初始化壳子，从未真正使用过

## 整体判定

| 阶段 | 是否在跑？ | 证据 |
|---|---|---|
| §0/§1 安装与画像 | ✅ 在跑 | hermes profile.json + setup_completed |
| §0c 老博主接入 | ✅ 在跑 | codex audit-*.{json,md} 产出 |
| §4.1 偏好学习 | ✅ 在跑 | 两 target preferences.json 有值 |
| **§3 每日复盘** | ❌ **零证据** | 无 target 有 evolution-log 增长 / reviews/ 周快照 / 最新 audit 之外的 patterns.md 变更 |
| §4.2 pattern 进化 | ❌ **零证据** | 同上 |

## 根因（待 v2.4.1 C1 JSON 日志落地后确认）

三种可能：
1. hermes cron 未实际配置（每日 11:30/20:30/22:00 三个 job）
2. cron 配了但触发时 skill 报错，静默失败，无日志可查
3. cron 触发了但没有真实发帖 → 复盘对象为空，patterns 自然无更新

## 影响范围

- **不阻塞 v2.4.0 发版**（v2.4.0 是基础设施，不改自进化逻辑本身）
- **v2.4.1 Observability 的首要验证项**：JSON 日志接入后第一周观察 cron × stage 的触发记录
- **需修复的 state drift**：codex 的 state.json 缺 setup_completed 应由 v2.4.0 的 schema validate (C3) 扫出

## 行动项（已分配）

- [ ] v2.4.0 C3 schema validation 会暴露 codex state.json drift
- [ ] v2.4.1 C1 JSON 日志落地后，专门跑一轮 kb-health.sh 验证 cron 触发真实性
- [ ] 若 v2.4.1 确认 cron 从未触发，需走 hermes 平台适配重配路径（platform/hermes.md 的 cron job 配置）
