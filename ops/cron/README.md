# ops/cron/ — 定时触发模板（不参与运行时）

> v3.0+：本目录是**模板库**，不参与 skill 运行。安装时 install.sh 不会拷贝本目录到 target。
> 用户按平台选一份 .example 模板，自己 cp 改名后启用。

## 模板清单

| 平台 | 模板 | 适用 |
|---|---|---|
| Hermes（推荐） | `hermes.yaml.example` | 全自动每日发布 + 复盘；hermes-agent 配套 |
| Claude Code | `claude-code.md` | 会话级 `/loop`；开发期/本机测试 |
| macOS launchd | `launchd.plist.example` | OS 级 user agent；macOS 长跑 |
| Linux systemd | `systemd.timer.example` | OS 级 user timer；Linux 长跑 |

## 通用纪律

- **薯灵不会自动启用任何 cron**——用户必须显式选模板 + 自己装
- 所有定时任务最终都是"唤起 AI 助手 → 助手读 SKILL.md → 启动协议 4 步 → 路由到 playbook"
- 节流/限额由 `agent/scripts/xhs.sh` 自管，cron 触发频率不影响 MCP 限额（触顶时自动拒绝）
- 推荐节奏：午间 12:00 / 晚间 19:00 / 复盘 23:00 / 周日深度回顾 22:00
