# 小红书自动发布分享包

这份包是从当前正在使用的小红书自动发布系统整理出来的“交接版”。

它包含：

- 当前在用的 `xiaohongshu` skill
- 当前截图用的 `xhs-content-generator` skill
- 当前自动发布流程脚本副本
- 安装脚本
- launchd 模板
- 示例候选和示例帖子

它没有包含：

- 你的真实 cookies
- 你的真实 Telegram 机器人配置
- 你的真实 Anthropic token
- 你的实时数据库和日志

## 目录结构

```text
skills/
  xiaohongshu/
  xhs-content-generator/
workflow/
  xhs-automation/
install.sh
README.md
```

## 给接手人的最短路径

```bash
cd /path/to/xhs-autopublish-share-2026-04-14
bash install.sh
```

然后按提示：

1. 编辑 `~/xhs-automation/config/runtime.env`
2. 安装 `xiaohongshu-mcp` / `xiaohongshu-login`
3. 跑一次 `~/.agents/skills/xiaohongshu/scripts/start-mcp.sh`
4. 登录小红书
5. 手动测试 `research -> create -> publish -> review`
6. 最后再决定是否 `launchctl load`

更细的流程见 `workflow/xhs-automation/README.md`。
