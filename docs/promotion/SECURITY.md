# Security Policy

## 数据本地化（Nothing Leaves Your Machine）

薯灵是 **纯本地运行** 的 AI skill，所有状态都存在本机：

| 类型 | 存储位置 | 是否上传 |
|---|---|---|
| 博主画像 `profile.json` | `knowledge-base/` | ❌ 仅本地 |
| 偏好学习 `preferences.json` | `knowledge-base/` | ❌ 仅本地 |
| Pattern 库 `patterns.md` / `anti-patterns.md` | `knowledge-base/` | ❌ 仅本地 |
| 历史帖子 / 互动数据 | `data/xhs.db`（SQLite） | ❌ 仅本地 |
| 生成的图片 | `/tmp/xhs-post/` | ❌ 仅本地 |
| 小红书 Cookie | 由 `xiaohongshu-mcp` 管理 | ❌ 仅本地 |

**`.gitignore` 已屏蔽**：`config/runtime.env`、`config/state.json`、`knowledge-base/*.json`、`knowledge-base/*.md`（除模板）、`data/xhs.db`。

> ⚠️ **切勿** `git add -f` 这些文件——它们是你的私人数据。

---

## 凭据管理

### 小红书凭据
- **扫码登录**：`xiaohongshu-mcp` 维护 session，薯灵只通过 MCP 间接调用，不持有凭据
- **Cookie 导入**：用户主动粘贴，`scripts/xhs.sh import-cookie` 传给 MCP；薯灵本身不存储

### Gemini API Key
- 存储位置：`config/runtime.env`（已被 `.gitignore` 屏蔽）
- 使用范围：仅 `scripts/image.py` 调用 Google AI Studio API 生图
- 轮换建议：定期在 https://aistudio.google.com/app/apikey 轮换

### NoteRx API Key（可选）
- 存储位置：同上 `config/runtime.env`
- 使用范围：仅 `scripts/noterx-diagnose.sh` 调第三方诊断 API

---

## 威胁模型

### 薯灵**不做**的事
- ❌ 不自动刷量、不批量发布、不绕风控
- ❌ 不上传任何用户数据到第三方服务器（除了用户显式配置的 Gemini/NoteRx API）
- ❌ 不内嵌任何遥测（telemetry）或分析（analytics）
- ❌ 不修改 `xiaohongshu-mcp` 之外的系统设置

### 已知依赖的安全边界
- `xiaohongshu-mcp`（第三方 MCP 服务）：你信任它如何管理 Cookie
- `Gemini API`（Google）：发送的是图片生成 prompt（含你的内容大纲），不含账号凭据
- `NoteRx API`（第三方诊断服务，可选）：发送的是帖子标题/正文/标签

### AI agent 自律边界
- SKILL.md §0b 强制 AI 写入 `state.json` / `profile.json` / `preferences.json` 前按 JSON Schema 校验
- §0a 业务路由明确禁止 AI 跳过已完成步骤或重复询问画像
- §5 合规规则绝对禁止：平台名提及 / 费用信息 / AI 自述类内容

---

## 报告安全问题

发现 bug 或漏洞请提 Issue（已公开披露）或邮件私下报告（未公开的严重问题）：

- GitHub Issues: https://github.com/AI-flower/shuling/issues
- 私下披露: 见项目主页 contact

**请勿** 在 PR 或 public Issue 中粘贴你的 Cookie / API Key / `data/xhs.db` 内容——它们可能被公开索引。

---

## 合规声明

薯灵遵循小红书平台 TOS：
- 发布频率按账号风控分级节流（`config` 中 throttle_profile）
- 日限额 profile `v1-conservative`，触顶自动拒绝
- 内容合规规则 `data/content-rules.md` 禁止标题党、平台名提及、AI 自述

使用薯灵产生的小红书账号行为由用户本人负责。
