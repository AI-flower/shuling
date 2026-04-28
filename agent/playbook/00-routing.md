---
id: 00-routing
title: Business Routing
when:
  - "skill 被任何宿主 agent 装载"
  - "cron 自动触发但无具体业务指令"
needs:
  files:
    - agent/config/state.json
  scripts:
    - agent/scripts/preflight.py
calls:
  scripts:
    - agent/scripts/preflight.py
    - agent/scripts/db.sh
  playbooks:
    - 01-onboarding-new.md
    - 02-onboarding-existing.md
    - 03-daily-flow.md
    - 05-review.md
    - 09-troubleshooting.md
writes:
  files:
    - agent/config/state.json
preconditions: []
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
---

# 00 Business Routing

## Trigger

无论是用户主动对话调起，还是 hermes 通过 cron 等机制自动触发，**第一件事都是跑预检并按 state 决定下一步业务，不要默认从头开始**。

## Read This When

每次 skill 被装载——无论触发源是用户消息、`hermes cron`、`/loop`、还是宿主 agent 在多技能场景下挑了本 skill。本节是所有其他剧本的入口。

## Inputs

- `agent/config/state.json` —— 业务里程碑（`setup_completed` / `creator_mode` / `existing_import_done` / `cold_start_done` / `profile_created`）
- `agent/scripts/preflight.py` 输出 JSON —— `setup_completed` / `state` / `checks[]`
- 用户当前消息（如有）—— 用来覆盖默认路径（"我给你 cookie"、"已经在运营了"）
- 触发上下文 —— cron / 用户对话 / 宿主 agent 调度

## Procedure

**第 1 步：跑预检**

```bash
python3 agent/scripts/preflight.py
```

读输出 JSON 中的 `setup_completed`、`state` 与 `checks`。

**第 2 步：按下表行动**

| 当前状态 | 下一步 |
|---------|------|
| `setup_completed: true` 且 `state.cold_start_done: true` | 直接进入 `03-daily-flow.md`：根据当前时间（午间/晚间）走选题→创作→发布；夜间走 `05-review.md` |
| `state.creator_mode == 'existing'` 且 `existing_import_done == false` | 走 `02-onboarding-existing.md`（不要跳回 01） |
| `setup_completed: true` 但 cold_start 未做 | 跳过环境安装与建画像，直接执行 `01-onboarding-new.md` 的"冷启动播种"段（竞品分析 + 写 patterns.md），完成后写 `state.cold_start_done = true` |
| `state.profile_created: true` 但某 check 报 `error`/`missing` | **仅修复缺失项**，不要重新走 01/02 流程，不要重新问画像 |
| `state.profile_created` 缺失/false，且用户自述"已在运营小红书" | 走 `02-onboarding-existing.md` |
| `state.profile_created` 缺失/false，且用户为新博主 | 走 `01-onboarding-new.md`（仅缺失项 → 建画像） |

**第 3 步：识别运行平台**

按优先级：
1. **检查 skill 所在路径**：`~/.hermes/skills/`（Hermes，支持 cron） / `~/.claude/skills/`（Claude Code，支持 `/loop`） / `~/.codex/skills/`（Codex） / `~/.agents/skills/`（OpenClaw / 通用）
2. **检查触发方式**：无用户具体指令（cron 自动触发）→ 必定是 Hermes cron，按上表自行选业务；有 `/loop` 上下文 → Claude Code
3. **兜底**：不确定时按"通用对话"处理，所有命令走 skill 根目录相对路径

平台特有能力（cron 配置、`/loop` 建议）才参考 `agent/platform/{hermes,claude-code,codex}.md`，业务流程本身在所有平台一致。

## Writes

- `agent/config/state.json` —— 仅在路由检测到 milestone 完成时（如冷启动种子已落 patterns.md 后）才更新对应字段；常规路由命中只读不写
- 平台识别结果 **不写盘**，按当次触发上下文判定

## Failure Handling

- `preflight.py` 退出码 `1` (auto-fixable) → 当场跑 `auto_fix` 命令；仍不通过则降级到 `09-troubleshooting.md`
- `preflight.py` 退出码 `2` (need-user) → 路由 `01-onboarding-new.md` 的"环境准备"子段，仅修缺失项
- 已写进 `state.json` 标记过 OK 的项，本次 check 即使超时也按 OK 处理（详见 `08-compliance.md` 异常纪律）

## Anti-Patterns
- 不重复打扰用户（state 标记过 ok 的不复查）
- 不重复问画像（profile.json 存在则直读）
- 不放空（cron 触发也要按表选业务）
- 不绕回默认路径（用户主动方案优先）

## Cross-Refs
- → 01-onboarding-new.md（新博主入口）
- → 02-onboarding-existing.md（老博主入口）
- → 03-daily-flow.md（日常选题/创作/发布）
- → 05-review.md（夜间复盘 / 周日回顾）
- → 08-compliance.md（schema 校验 + 异常处理纪律）
- → 09-troubleshooting.md（任何步骤失败）
