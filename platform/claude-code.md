# Claude Code 适配指南

将小红书博主成长助手作为 Claude Code skill 使用。

---

## 安装

### 方式一：复制

```bash
cp -r /path/to/xiaohongshu-skill ~/.claude/skills/xiaohongshu
```

### 方式二：符号链接（推荐，便于更新）

```bash
ln -sfn /path/to/xiaohongshu-skill ~/.claude/skills/xiaohongshu
```

安装后初始化数据库：

```bash
bash ~/.claude/skills/xiaohongshu/scripts/db.sh init
```

---

## 使用方式

在 Claude Code 对话中直接说：

- **"帮我发小红书"** — 触发完整发布流程
- **"今天发什么"** — 选题研究
- **"小红书选题"** — 进入选题模式
- **"看看昨天的数据"** — 数据复盘
- **"复盘一下最近的帖子"** — 周期复盘
- **"我想做XX方向的博主"** — 首次画像设置 / 方向调整

Claude Code 会自动识别 skill 并按 SKILL.md 中的流程执行。

---

## 自动化

可以使用 `/loop` 命令配置定时触发每日流程：

```
/loop 8h 帮我执行小红书每日发布流程
```

或者更精细地拆分：

```
/loop 12h 检查小红书数据，如果有新帖子需要复盘就执行复盘流程
```

---

## MCP 配置

`xiaohongshu-mcp` 需要在本机运行。Claude Code 通过 skill 中的 `scripts/xhs.sh` 脚本与 MCP 交互。

启动 MCP：

```bash
# 确保 xiaohongshu-mcp 已安装
bash ~/.claude/skills/xiaohongshu/scripts/xhs.sh status
```

如果 MCP 在远程机器上，设置环境变量后再启动 Claude Code：

```bash
export XHS_MCP_URL="http://远程地址:端口"
claude
```
