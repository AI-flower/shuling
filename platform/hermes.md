# Hermes 平台适配指南

将小红书博主成长助手部署到 [Hermes](https://github.com/anthropics/hermes) 平台，实现全自动每日发布与复盘。

---

## 安装

### 1. 复制 skill 文件

```bash
SKILL_SRC="/path/to/xiaohongshu-skill"
HERMES_SKILL_DIR="$HOME/.hermes/skills/social-media/xiaohongshu"

mkdir -p "$HERMES_SKILL_DIR"
cp "$SKILL_SRC/SKILL.md" "$HERMES_SKILL_DIR/"
cp -r "$SKILL_SRC/scripts" "$HERMES_SKILL_DIR/"
cp -r "$SKILL_SRC/data" "$HERMES_SKILL_DIR/"
cp -r "$SKILL_SRC/knowledge-base" "$HERMES_SKILL_DIR/"
cp -r "$SKILL_SRC/templates" "$HERMES_SKILL_DIR/"
```

需要复制的内容：
- `SKILL.md` — Agent 执行的主剧本
- `scripts/` — 数据库操作 (db.sh)、MCP 调用 (xhs.sh)、图片生成 (image.py)、截图 (screenshot.cjs)
- `data/` — SQLite 数据库与内容规则
- `knowledge-base/` — 博主画像与偏好数据（首次运行会自动生成）
- `templates/` — HTML 截图模板

### 2. 初始化数据库

```bash
bash "$HERMES_SKILL_DIR/scripts/db.sh" init
```

---

## Cron Job 配置

在 Hermes 中创建以下两个定时任务：

### Job 1: 每日发布（08:00）

```yaml
name: "小红书每日发布"
schedule: "0 8 * * *"
prompt: |
  使用 xiaohongshu skill 执行每日发布流程。
  1. 读取 knowledge-base/ 了解博主画像和偏好
  2. 如果 profile.json 不存在，先完成首次设置
  3. 执行选题研究，推送给用户等待选择
  4. 生成草稿和图片，推送确认后发布
  5. 午间档和晚间档各一条
deliver: "telegram:用户ID"
```

### Job 2: 每日复盘（22:00）

```yaml
name: "小红书每日复盘"
schedule: "0 22 * * *"
prompt: |
  使用 xiaohongshu skill 执行每日复盘。
  采集今日帖子互动数据，更新偏好模型，生成日报推送。
  如果是周日，额外执行周进化分析。
deliver: "telegram:用户ID"
```

> 将 `用户ID` 替换为你的 Telegram 用户 ID。

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

检查 Gemini API Key 是否已配置。如果未配置或额度耗尽，系统会自动降级为 HTML 截图模式（使用 `templates/post.html` 模板 + Playwright 截图）。

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
