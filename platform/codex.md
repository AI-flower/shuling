# Codex 适配指南

将小红书博主成长助手作为 Codex skill 使用。

---

## 安装

```bash
cp -r /path/to/xiaohongshu-skill ~/.codex/skills/xiaohongshu
```

或使用符号链接：

```bash
ln -sfn /path/to/xiaohongshu-skill ~/.codex/skills/xiaohongshu
```

初始化数据库：

```bash
bash ~/.codex/skills/xiaohongshu/scripts/db.sh init
```

---

## 使用

在 Codex 中直接说"帮我发小红书"或描述你想做的事情，Codex 会自动调用 skill 执行。

支持的指令与 Claude Code 相同，参考 [claude-code.md](claude-code.md)。

---

## MCP

确保 `xiaohongshu-mcp` 在本机运行，或设置 `XHS_MCP_URL` 环境变量指向远程 MCP 地址。
