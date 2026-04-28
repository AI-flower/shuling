# Hermes 平台适配指南

将薯灵 (ShuLing) 部署到 [Hermes](https://github.com/anthropics/hermes) 平台，实现全自动每日发布与复盘。

---

## 安装

### 1. 复制 skill 文件

```bash
SKILL_SRC="/path/to/shuling"
HERMES_SKILL_DIR="$HOME/.hermes/skills/social-media/shuling"

mkdir -p "$HERMES_SKILL_DIR"
cp "$SKILL_SRC/SKILL.md" "$HERMES_SKILL_DIR/"
cp -r "$SKILL_SRC/scripts" "$HERMES_SKILL_DIR/"
cp -r "$SKILL_SRC/data" "$HERMES_SKILL_DIR/"
cp -r "$SKILL_SRC/knowledge-base" "$HERMES_SKILL_DIR/"
cp -r "$SKILL_SRC/templates" "$HERMES_SKILL_DIR/"
```

需要复制的内容：
- `SKILL.md` — Agent 执行的主剧本
- `scripts/` — 数据库操作 (db.sh)、MCP 调用 (xhs.sh)、图片生成 (image.py)
- `data/` — SQLite 数据库与内容规则
- `knowledge-base/` — 博主画像与偏好数据（首次运行会自动生成）

### 2. 初始化数据库

```bash
bash "$HERMES_SKILL_DIR/scripts/db.sh" init
```

---

## Cron Job 配置

> **重要原则**：hermes cron 不是"跑 Python 脚本"，而是"定时唤起 AI 助手让它读 SKILL.md 自己决定该做什么"。所有业务逻辑由 SKILL.md 0a 节的"业务路由"决定。

在 Hermes 中创建以下三个定时任务（都通过 `prompt` 唤起助手）：

### Job 1: 每日午间档发布（11:30）

```yaml
name: "薯灵-午间发布"
schedule: "30 11 * * *"
prompt: |
  使用 shuling skill。先跑 scripts/preflight.py 看 setup_completed
  是否为 true；为 true 直接进入今日午间档创作发布流程
  （选题 → 草稿 → 图片 → 发布），完成后输出业务结果。
deliver: "telegram:用户ID"
```

### Job 2: 每日晚间档发布（20:30）

```yaml
name: "薯灵-晚间发布"
schedule: "30 20 * * *"
prompt: |
  使用 shuling skill。先跑预检，进入今日晚间档创作发布流程。
deliver: "telegram:用户ID"
```

### Job 3: 每日复盘（22:00）

```yaml
name: "薯灵-每日复盘"
schedule: "0 22 * * *"
prompt: |
  使用 shuling skill 执行 SKILL.md 第 3 节"每日复盘"流程：
  拉今日所有已发帖子的互动数据 + 评论 + NoteRx 诊断，
  做综合分析，当晚立即更新 patterns.md / preferences.json /
  evolution-log.md，最后输出日报。
  如果今天是周日，按 SKILL.md 4.3 节再做一次"周深度回顾"
  并输出周报。
deliver: "telegram:用户ID"
```

> **注意**：cron 任务的 `prompt` 是给助手看的"任务说明"，不是给脚本的命令。助手会自己决定调哪些工具。如果某次 cron 触发后助手返回"setup_completed=false"，说明用户还没完成首次设置，跳过本次即可，不报警。
---

## MCP 配置

小红书 skill 依赖 `xiaohongshu-mcp` 服务来与小红书平台交互（发布、采集数据等）。

### 方式一：本机运行

确保 `xiaohongshu-mcp` 已安装并在本机运行，skill 中的 `xhs.sh` 会自动连接默认端口。

### 方式二：远程 MCP

如果 MCP 运行在其他机器上，设置环境变量：

```bash
export XHS_MCP_URL="http://远程地址:端口"
```

或在 Hermes 的 cron job 配置中添加 `env` 字段：

```yaml
env:
  XHS_MCP_URL: "http://远程地址:端口"
```

---

## 常见问题

### Q: 首次运行报 profile.json 不存在？

正常现象。首次运行时 skill 会进入「建立博主画像」流程，通过对话收集你的方向、受众和风格偏好。完成后会自动生成 `knowledge-base/profile.json`。

### Q: 图片生成失败？

检查 Gemini API Key 是否已配置。未配置时硬停并提示用户补配（薯灵已移除 HTML 截图降级路径）。

### Q: MCP 连接超时？

1. 确认 `xiaohongshu-mcp` 进程正在运行
2. 运行 `bash scripts/xhs.sh status` 检查连接状态
3. 如果用远程 MCP，检查网络连通性和 `XHS_MCP_URL` 配置

### Q: 数据库损坏？

```bash
bash scripts/db.sh check    # 检查数据库完整性
bash scripts/db.sh backup   # 备份当前数据库
bash scripts/db.sh init     # 重新初始化（会保留备份）
```
