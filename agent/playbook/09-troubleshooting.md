---
id: 09-troubleshooting
title: Troubleshooting and Failure Handling
when:
  - "任何 playbook 报错"
  - "preflight.py 退出码 1/2"
  - "MCP 不连通"
  - "Gemini Key 缺失"
  - "schema 校验失败"
needs:
  required: []
calls:
  scripts:
    - agent/scripts/preflight.py
    - agent/scripts/db.sh
writes:
  files: []
preconditions: []
on_failure: []
version: 3.0.0
last_updated: 2026-04-27
---

# 09 Troubleshooting and Failure Handling

## Trigger

- 任何 playbook 通过 `on_failure` 跳转到此
- `agent/scripts/preflight.py` 退出码 1（auto-fixable）或 2（need-user）
- `xhs.sh status` 报 MCP 不连通 / 登录过期
- `image.py --check` 返回 2（Gemini Key 缺失）
- `validate.py` 报 schema drift 或 schema 校验失败
- `db.sh` 报数据库不存在 / 表缺失

## Read This When

- 出现异常前不主动读；on_failure 跳转后必读
- 安装期 0 节出现任何 `auto_fix` / `ask_user` / `optional` 项时
- 日常流程中遇到 MCP / Gemini / 网络相关报错时

## Inputs

- 调用方报告的错误码（exit code / stderr / stdout JSON）
- 当前 `agent/config/state.json`
- `preflight.py` 的输出 JSON（含每个 check 的 status / action）

## Procedure

### Preflight Failure Diagnosis（按 preflight.py 退出码 0/1/2 分级处理）

```bash
python3 agent/scripts/preflight.py
```

读输出 JSON 中的 `setup_completed`、`state` 与 `checks`，按退出码分级：

- **退出码 0**：全绿，无需处理
- **退出码 1**（auto-fixable）：对所有 `auto_install` / `auto_fix` 项，直接执行修复命令，**不需要问用户**：
  - 数据库未初始化 → `bash agent/scripts/db.sh init`
  - Playwright 未安装 → `npx playwright install chromium`
  - Node 模块缺失 → `npm install`
- **退出码 2**（need-user）：按 `ask` 字段中的话术引导用户提供信息（cookie / Gemini Key 等）

**关键纪律**：

- `state.json` 标记过 `ok` 的项，即使本次 check 超时/不确定，也按 ok 处理
- `setup_completed: true` 但某 check 当前报 `error` → **仅修复该项**，不要重新走整个安装流程
- upgrade-all 把 0/1/2 都视为升级本身成功（runtime 配置未就绪不算 upgrade failed）

### MCP / Login Failures

**xiaohongshu-mcp 不连通**：

- `xhs.sh` 自动尝试启动；失败则告知用户需要安装 / 启动 xiaohongshu-mcp（参考 `docs/runbooks/mcp-setup.md`）
- 启动后 `bash agent/scripts/xhs.sh status` 验证

**登录过期 / 未登录**：

- **用户主动提议方案优先**：用户说"我给你 cookie"/"我直接粘贴"/"帮我用 cookie 登录"等任何变体 → **立即接受**，让用户从浏览器复制完整 `Cookie` 头字符串，调用 `bash agent/scripts/xhs.sh import-cookie '<cookie字符串>'`。**不要绕回扫码、不要继续解释扫码流程**
- 默认扫码：`bash agent/scripts/xhs.sh login` 获取二维码链接，返回给上层让用户扫码
- `xhs.sh login` 返回"已登录"或"已进入注销流程" → 先视为已登录，调一次 `xhs.sh status` 确认；不要重复发起登录

### Image API Failures (Gemini / OpenAI)

**API Key 缺失或不可用**（`image.py --check` 返回 2）：

- **硬停**。薯灵已移除 HTML 截图降级，没有图像生成 API Key 就无法生图，也就无法发帖
- 询问用户走哪条路径：
  - **Gemini 3 Pro**（默认，免费额度 + 中文渲染稳）：获取 https://aistudio.google.com/app/apikey
  - **OpenAI gpt-image-2**（全球可达，需付费）：获取 https://platform.openai.com/api-keys
- 写入 Key 时同时指定 provider：
  - `python3 agent/scripts/image.py --set-key '<KEY>' --provider gemini`
  - `python3 agent/scripts/image.py --set-key '<KEY>' --provider openai`
- **用户拒绝提供 Key 时**：明确告知这是强依赖，安装流程停在这一步

**模型 API 报错**（404/401/503/空响应）：

- 告知用户切换模型或稍后重试，**最多 1 次重试，失败即停**
- 不要在同一会话反复重试同一失败调用
- 如果一个 provider 持续失败，建议用户换另一个（改 IMAGE_GEN_PROTOCOL）

### Schema / Migration Failures（schema-degraded mode 检测）

**Schema 校验失败**：

- 由 08-compliance.md Schema Validation 段返回的字段错误清单 → 修正字段名 / 类型 / 枚举值后重写
- 字段名漂移（如 `createdAt` 应为 `created_at`）→ 立即按 schema 文档纠正，不要保留旧字段名
- `dimension` 写入了 `topic/style/title_pattern` 之外的值 → 拒写，回报"未授权维度"

**Migration / DB schema drift**：

- `agent/data/xhs.db` 不存在 → 自动 `bash agent/scripts/db.sh init` 初始化
- `__migrations` 表里某 migration 标 `failed` → 不重跑；告知用户并建议跑 `install.sh --check`
- 知识库文件损坏/不存在 → 用默认值继续，不阻塞创作

### Account Safety Failure Matrix（v3.1+，对应 docs/adr/0003-account-execution-boundary.md）

publish / comment / import-cookie 是 privileged mutation，失败时按下表处理：

| 状态 / 错误码 | 现象 | 处理 |
|---|---|---|
| `approval_required` | `xhs.sh publish` 没传 `--approval-id` | 引导用户：`bash agent/scripts/approval.sh request publish <meta.json>` → grant |
| `approval_missing` | `--approval-id` 指向的文件不存在 | approval 文件被删/路径写错；重新 request |
| `approval_expired` | 当前时间 > expires_at（默认 30 分钟） | 重新 request 一份新 approval |
| `resource_changed` | meta.json sha256 与 approval 记录的不一致 | 草稿在 grant 后被改过，必须重新生成草稿 + 重新 request |
| `approval_consumed` | 该 approval 已使用过一次 | 一次性原则；重新 request |
| `approval_revoked` | 用户已 `approval.sh revoke` | 重新 request |
| `action_mismatch` | approval action ≠ 当前调用 | 检查是否把 publish approval 用到了 comment（或反之） |
| `safety_cooldown` | risk_level=cooldown | 展示 cooldown_reason + cooldown_until 给用户；自动到期解除，或显式 `account-safety.sh exit-cooldown`（前置确认风险） |
| `safety_locked` | risk_level=locked | 只允许 doctor / preflight / 只读；查 `account-safety.sh status` 的 last_risk_event |
| `comment_disabled` | `SHULING_ENABLE_COMMENT=0`（默认） | 默认提供回复建议、不发出；用户坚持需评论 → 切 supervised + 设 SHULING_ENABLE_COMMENT=1 + approval |
| `policy_disabled` | account-safety.json 关了对应 *_enabled | 用户改 `agent/config/account-safety.json` 或 `account-safety.sh set-mode supervised` |
| `daily_cap_reached` | 当日发布/评论已达 max_daily_* | 等待跨日重置（UTC 0 点）或调高 max_daily_publishes（不推荐） |
| `dev_mode_required` | 非 dev mode 设了 XHS_DISABLE_THROTTLE/QUOTA=1 | 拒绝；告诉用户这是生产保护，必须 `SHULING_DEV_MODE=1` 才允许 |

诊断步骤：

```bash
# 看当前 safety 状态
bash agent/scripts/account-safety.sh status

# 看 approval 列表（含状态）
bash agent/scripts/approval.sh list

# 重新 request 一份
bash agent/scripts/approval.sh request publish /tmp/xhs-post/meta.json
```

### General Exception Matrix（迁入 §8 完整异常场景）

| 场景 | 处理方式 |
|------|---------|
| MCP 未运行 | `xhs.sh` 自动尝试启动，失败则提示用户 |
| 登录过期 | `xhs.sh login` 获取二维码 → 返回给上层让用户扫码；若用户主动给 cookie，用 `xhs.sh import-cookie` |
| 图像 API 不可用（Gemini / OpenAI） | 硬停并提示用户配置 Key（已不再提供 HTML 截图降级） |
| 用户长时间不回复 | 超时后自动选择评分最高的（超时时间由平台层配置） |
| 知识库文件损坏/不存在 | 用默认值继续，不阻塞创作 |
| 发布失败 | 返回失败原因，保留 meta.json 供重试 |
| 数据库不存在 | 自动 `bash agent/scripts/db.sh init` 初始化 |
| 模型 API 报错（404/401/503/空响应） | 告知用户切换模型或稍后重试，**最多 1 次重试，失败即停**；不要在同一会话反复重试同一失败调用 |
| 配置已存在但 preflight 检查超时 | 视为已配置（preflight 会基于 `state.json` 自动放宽），继续后续流程 |
| `setup_completed: true` 但某 check 当前报 `error` | 仅修复该项，**不要重新走整个安装流程** |
| `xhs.sh login` 返回"已登录"或"已进入注销流程" | 先视为已登录，调一次 `xhs.sh status` 确认；不要重复发起登录 |
| 用户重复输入相同句子（≥2 次） | 上次明显没成。**换思路**：检查上一次失败原因，向用户说明，询问要换路径还是给更多信息 |
| 用户主动提议替代方案 | **优先采纳**用户方案；除非有强证据该方案不可行，否则不要绕回默认路径 |
| Schema 校验失败 | 见上面 Schema / Migration Failures 段 |
| Migration `__migrations` 标 failed | 不重跑；告知用户跑 `install.sh --check` |
| Import 中断（v0c 老博主） | `bash agent/scripts/import-existing.sh --resume` 续跑 |
| Gemini 配额耗尽 | 视为 Gemini 不可用，提示用户更换 Key 或等待配额重置 |

## Writes

- 修复成功 → 更新 `agent/config/state.json` 对应 check 字段为 `ok`
- 修复失败且为本剧本可记录的失败类型 → 写日志到 `agent/data/.shuling-troubleshoot.log`（可选）

## Failure Handling

- 本剧本本身的兜底：若无法识别异常类型，报告给用户原始 stderr + 提示运行 `bash install.sh --check` 或 `bash install.sh doctor`，并把状态原样保留，不擅自改 state.json

## Anti-Patterns

- 模型 API 报错最多 1 次重试
- preflight 标记过 ok 的不重复检查
- upgrade-all 把 0/1/2 都视为升级本身成功（runtime 配置未就绪不算 upgrade failed）

## Cross-Refs

被所有 playbook 通过 on_failure 引用。
