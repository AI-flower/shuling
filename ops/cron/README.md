# ops/cron/ — 定时触发模板（不参与运行时）

> v3.0+：本目录是**模板库**，不参与 skill 运行。安装时 install.sh 不会拷贝本目录到 target。
> 用户按平台选一份 .example 模板，自己 cp 改名后启用。

## 模板清单

| 平台 | 模板 | 适用 |
|---|---|---|
| Hermes（推荐） | `hermes.yaml.example` | 每日候选草稿 + 复盘；hermes-agent 配套 |
| Claude Code | `claude-code.md` | 会话级 `/loop`；开发期/本机测试 |
| macOS launchd | `launchd.plist.example` | OS 级 user agent；macOS 长跑 |
| Linux systemd | `systemd.timer.example` | OS 级 user timer；Linux 长跑 |

## 通用纪律

- **薯灵不会自动启用任何 cron**——用户必须显式选模板 + 自己装
- 所有定时任务最终都是"唤起 AI 助手 → 助手读 SKILL.md → 启动协议 4 步 → 路由到 playbook"
- 节流/限额由 `agent/scripts/xhs.sh` 自管，cron 触发频率不影响 MCP 限额（触顶时自动拒绝）
- 推荐节奏：午间 12:00 / 晚间 19:00 / 复盘 23:00 / 周日深度回顾 22:00

## v3.1 Account Safety: Cron 默认 draft-only

从 v3.1 起，本目录所有 cron 模板（hermes / claude-code / launchd / systemd）的 prompt 都是 **draft-only** 语义：

- 定时任务只会触发"生成候选草稿"和"复盘"两类工作
- 不会自动调用发布或评论
- AI 在 cron 唤起后只会跑到 `draft_ready` 事件，并在输出里附上 `等待用户回复『发』` 的提示
- 用户回复"发"后才进入 approval flow（见 `docs/runbooks/account-safety.md`），授权一次性发布

这是 v3.1 Account Safety 边界的一部分。`draft_ready` 永远不等于 `publish_allowed`，cron 触发的会话拿不到 approval，因此一定走不到 `04-publish-flow`。

### 输出预期

cron 触发后的助手输出格式大致是：

```text
午间候选草稿已生成（3 选 1）：
1. ...
2. ...
3. ...

回复"发"将进入发布授权流程；回复"换"重新生成。
等待用户回复『发』确认后再进入发布。
```

### 如果你想让 cron 直接发文（不推荐）

v3.1 不再提供"开箱即用"的免授权发文 cron。如果你确实需要让定时任务跨过 approval（**强烈不推荐**，等同于 AI 托管账号风险），请：

1. 阅读 `docs/runbooks/account-safety.md` 中的 supervised mode 与 approval flow
2. 按 runbook 步骤切到 `supervised` 模式
3. 自行编写"先 approval.sh request → 等用户授权 → 再 xhs.sh"的串联脚本
4. 务必理解：一旦绕过 approval，账号风险由你自行承担（封号、限流、风控均不在薯灵保障范围内）

> 如果 `docs/runbooks/account-safety.md` 尚未生成，说明本机的 v3.1 账号安全层还在 Stage 1-3 之间，请先升级到包含该 runbook 的版本再考虑此类场景。
