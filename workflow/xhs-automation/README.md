# XHS Automation Workflow

这份目录是当前小红书自动发布链路的“可分享版”副本，保留了正在使用的流程和脚本结构，但去掉了你的私密登录态和密钥。

## 当前流程

1. `scripts/research.py`
   - 早上抓 GitHub trending 和 GitHub API
   - 用小红书 MCP 搜索竞品
   - 产出当天候选题材

2. `scripts/create_content.py`
   - 读取候选
   - 用 Claude CLI 生成多页 HTML
   - 调截图脚本导出 `page-*.png`
   - 写入 `meta.json` 和 SQLite

3. `scripts/send_preview.py`
   - 晚上把次日草稿图文发到 Telegram 预览

4. `scripts/publish_post.py` + `publish.sh`
   - 调小红书 MCP 的 `publish_content`
   - 根据 `meta.json` 里的 `schedule_at` 提交定时发布

5. `scripts/review.py`
   - 拉取互动数据
   - 发 Telegram 日报

6. `scripts/keepalive.py`
   - 检查 MCP 进程和登录状态
   - 登录失效时发二维码提醒

## 默认调度时间

- `08:00` `research.py`
- `09:00` `create_content.py`
- `11:30` `publish_post.py <today> noon`
- `20:30` `publish_post.py <today> evening`
- `21:30` `send_preview.py`
- `22:00` `review.py`
- 每 `4` 小时 `keepalive.py`

## 必填配置

先把 `config/runtime.env.example` 复制为 `config/runtime.env`，至少补这几项：

- `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_BASE_URL`
- `XHS_TELEGRAM_BOT_TOKEN`
- `XHS_TELEGRAM_CHAT_ID`

如果 `node`、`claude` 或 `playwright` 不在默认位置，再补：

- `XHS_CLAUDE_BIN`
- `XHS_NODE_BIN`
- `XHS_NODE_PATH`

## 手动跑通命令

```bash
cd ~/xhs-automation

python3 scripts/research.py 2026-04-14
python3 scripts/create_content.py 2026-04-14
python3 scripts/send_preview.py 2026-04-15
python3 scripts/publish_post.py 2026-04-14 noon
python3 scripts/review.py 2026-04-14
python3 scripts/keepalive.py
```

## 示例内容

- `examples/candidates-2026-04-14.json`: 一份真实候选样本
- `examples/posts/2026-04-14-post1`
- `examples/posts/2026-04-14-post2`

## 有意移除的内容

- 小红书 cookies
- 真实 Telegram bot token / chat id
- 真实 Anthropic token
- 运行中的数据库、日志和你本机专属绝对路径
