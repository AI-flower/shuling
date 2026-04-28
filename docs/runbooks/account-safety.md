# 账号安全运行手册（Account Safety Runbook）

> 适用版本：v3.1.0+（v3.1 Account Safety Hardening 后）。
> v3.0 用户阅读本文是为 v3.1 升级做准备；脚本与命令在 v3.1 Stage 2-5 落地后才会生效。
>
> 相关：[ADR-0003 账号执行权与外部情报安全边界](../adr/0003-account-execution-boundary.md) ·
> [v3 Account Execution Safety Hardening Plan](../plans/v3-account-execution-safety-hardening.md) ·
> [外部情报运行手册](external-intelligence.md)

## 1. 模式说明

`agent/config/account-safety.json` 表达用户选择的运行边界。四种模式互斥：

| 模式 | 默认 | 允许动作 | 禁止动作 |
|---|---|---|---|
| `draft-only` | 是 | 选题 / 起稿 / 生图 / 复盘 / 评论洞察（只读）/ L0-L2 外部情报 | 发布、评论、cron 自动发布 |
| `supervised` | 推荐生产模式 | `draft-only` 全部 + 用户确认后的 publish | 评论（除非显式启用）、unsafe quota override |
| `read-only-research` | 老博主导入前 | 只 search / detail / 读评论 / 分析 | 任何写动作（含草稿落库） |
| `ops-maintenance` | 运维 | doctor / preflight / verify / migration | 任何业务流程 |

默认策略：

```json
{
  "mode": "draft-only",
  "publishing_enabled": false,
  "commenting_enabled": false,
  "cookie_import_enabled": true,
  "bulk_import_enabled": false,
  "cron_publish_enabled": false,
  "max_daily_publishes": 1,
  "max_daily_comments": 0,
  "require_approval_for_publish": true,
  "require_approval_for_comment": true,
  "cooldown_on_risk_signal": true
}
```

首次安装后**不允许**自动发布。用户必须显式切到 `supervised` 才能进入 approval 流程。

## 2. 开启 supervised 模式

```bash
# 方式 A：直接编辑配置
$EDITOR agent/config/account-safety.json
# 把 "mode": "draft-only" 改成 "mode": "supervised"
# 把 "publishing_enabled": false 改成 "publishing_enabled": true

# 方式 B：通过 CLI（v3.1 Stage 2 后落地）
bash agent/scripts/account-safety.sh set-mode supervised

# 方式 C：通过对话告诉 AI
# "我要切到 supervised 模式，允许我确认后发布"
# AI 会按 09-troubleshooting.md 引导你确认 mode 切换
```

切换后立即生效，不需要重启 AI 助手或宿主平台。可用 `bash ops/doctor.sh` 检查当前 mode 和 safety state。

## 3. 授权一次发布

发布动作分两步：草稿生成（agent 自动）+ 发布授权（用户显式）。

### 3.1 标准流程

```bash
# 1. AI 在 03-daily-flow 完成后输出 draft_ready 事件，把 meta.json 路径告诉你
#    例如：/tmp/xhs-post/2026-04-28-1230-收纳/meta.json
#    AI 会询问："草稿已就绪，回复'发'我会请求授权。"

# 2. 用户回复"发"。AI 内部调用：
bash agent/scripts/approval.sh request publish /tmp/xhs-post/2026-04-28-1230-收纳/meta.json
# 输出：
# {"id":"appr_20260428_153000_abcd1234","status":"pending","expires_at":"2026-04-28T16:00:00Z"}

# 3. AI 把 approval_id 展示给你，并请你确认：
#    "请回复 'grant appr_20260428_153000_abcd1234' 授权发布"

# 4. 用户授权：
bash agent/scripts/approval.sh grant appr_20260428_153000_abcd1234
# 输出：{"id":"appr_...","status":"granted","granted_at":"..."}

# 5. AI 调用 xhs.sh publish 时附带 approval_id：
bash agent/scripts/xhs.sh publish /tmp/xhs-post/.../meta.json --approval-id appr_20260428_153000_abcd1234

# 6. 发布成功后 AI 内部调用 consume：
bash agent/scripts/approval.sh consume appr_20260428_153000_abcd1234
```

### 3.2 校验规则

`xhs.sh publish` 在执行前会做 6 道 verify（任一失败拒绝）：

1. approval 文件存在且 `status == granted`
2. action 字段 == `publish`
3. resource hash 与当前 meta.json 的 sha256 一致（防止中途修改草稿）
4. 当前时间未超过 `expires_at`（默认 30 分钟）
5. `consumed_at` 为 null（未消费过）
6. account-safety-state 不在 `cooldown` / `locked` 状态

### 3.3 一次性原则

每个 approval 只能消费一次。重新发布同一草稿需要重新 request + grant。

### 3.4 列出与撤销 approval

```bash
bash agent/scripts/approval.sh list                        # 列出未消费 approval
bash agent/scripts/approval.sh revoke appr_...             # 撤销（用于授权后反悔）
```

## 4. 查看 cooldown 状态

```bash
# 方式 A：doctor（推荐）
bash ops/doctor.sh
# 输出会包含 account_safety 一行，例如：
# account_safety   warn   risk_level=cooldown reason='captcha required' until=2026-04-29T15:30:00Z

# 方式 B：直接读 state 文件
cat agent/config/account-safety-state.json | python3 -m json.tool

# 方式 C：通过 CLI（v3.1 Stage 5 后落地）
bash agent/scripts/account-safety.sh status
```

`risk_level` 取值：

- `normal`：按 policy + approval 正常执行
- `watch`：允许草稿，发布前强提醒
- `cooldown`：禁止 publish / comment / import-cookie，允许 search / detail / 草稿
- `locked`：只允许 doctor / preflight / 只读

进入 cooldown 的常见原因：

- 发布连续失败 2 次
- 评论失败 1 次
- MCP 返回风险关键词（`429` / `captcha` / `风控` / `频繁` 等）
- 登录态连续失败
- 当天发布数达到 `max_daily_publishes`
- 用户手动暂停（`account-safety.sh pause`）

## 5. 解除 cooldown

cooldown 默认在 `cooldown_until` 时间到达后自动解除，但用户可以手动操作：

```bash
# 方式 A：CLI 解除（v3.1 Stage 5 后落地）
bash agent/scripts/account-safety.sh resume
# 会清除 cooldown_until 和 cooldown_reason，把 risk_level 重置为 normal

# 方式 B：直接编辑 state（不推荐，仅在 CLI 不可用时）
$EDITOR agent/config/account-safety-state.json
# 把 "risk_level" 从 "cooldown" 改成 "normal"
# 把 "cooldown_until" 改成 null
```

**重要**：解除 cooldown 不会清掉触发原因。如果是平台风控信号触发（429 / captcha），建议先停手 24-48 小时再继续，否则下一次调用大概率仍命中风控。`account-safety.sh status --history` 可看最近的风险事件历史。

## 6. 安全导入 Cookie

### 6.1 推荐方式：`@file` 输入

```bash
# 1. 用任意编辑器创建 cookie 文件，写入完整 cookie 串
$EDITOR /tmp/xhs-cookie.txt
chmod 600 /tmp/xhs-cookie.txt

# 2. 通过 @file 引用
bash agent/scripts/xhs.sh import-cookie @/tmp/xhs-cookie.txt

# 3. 导入成功后立即删除临时文件
rm /tmp/xhs-cookie.txt
```

`@file` 模式的好处：

- cookie 不进入 shell history
- cookie 不进入 AI 对话历史
- cookie 不进入 ps / 进程参数列表

### 6.2 不推荐方式：直接传字符串

```bash
# 不推荐：完整 cookie 会进入 shell history、AI 对话上下文、ps
bash agent/scripts/xhs.sh import-cookie '<完整 cookie 串>'
```

如果你已经这样做过，建议：

```bash
history -d <编号>           # 清掉 shell history 那一条
unset HISTFILE              # 当前 shell 不再记录
```

并在 AI 助手对话里告诉它「忘记我刚才的 cookie」（虽然 LLM 不会真正忘记，但会停止主动复读）。

### 6.3 导入前置条件

`xhs.sh import-cookie` 在执行前会检查：

1. `cookie_import_enabled == true`（默认是 true）
2. `risk_level` 不在 `cooldown` / `locked`
3. 文件权限不超过 `600`（v3.1 Stage 7 起）

## 7. 安全批量导入历史

老博主接入时需要批量拉取历史笔记。即使是只读动作，高并发拉取也可能触发风控。

### 7.1 标准 plan / run 模式

```bash
# 1. 先 plan，估算总量与节流时长
bash agent/scripts/import-existing.sh plan --limit 200
# 输出（v3.1 Stage 5 后）：
# {"plan":{"total":187,"batches":4,"batch_size":50,"estimated_minutes":42}}

# 2. 用户确认后真跑（每批之间强制 cooldown）
bash agent/scripts/import-existing.sh run --batch 50
# 进度通过 stderr 输出，最终结果走 stdout JSON
```

### 7.2 批次间 cooldown

每批之间会自动 sleep（默认 5 分钟），避免连续高频访问。可通过 `--batch-cooldown` 调整，但**不能为 0**。

### 7.3 unsafe override（仅 dev mode）

如果你确定要绕过限额（例如本机测试 mock 数据）：

```bash
# 必须 dev mode + TTY
SHULING_DEV_MODE=1 bash agent/scripts/import-existing.sh run --unsafe-override-quota

# 非 TTY（cron / CI）下永远拒绝，即使 SHULING_DEV_MODE=1：
# {"ok":false,"error":"unsafe_override_requires_tty"}
```

`--override-quota`（v3.0 旧名）从 v3.1 起改名为 `--unsafe-override-quota`，使用旧名会输出 deprecation warning 并仍然生效一次，v3.2 移除。

## 8. 故障矩阵速查

| 状态 | 现象 | 处理 |
|---|---|---|
| approval missing | `xhs.sh publish` 返回 `error: approval_required` | 跑 `approval.sh request` + `grant` |
| approval expired | 返回 `error: approval_expired` | 重新 request（默认 30 分钟有效） |
| approval hash mismatch | 返回 `error: resource_changed` | meta.json 被改过，重新生成草稿 + 重新 request |
| approval consumed | 返回 `error: approval_consumed` | 一次性原则；重新 request |
| cooldown | 返回 `error: cooldown` | 等待自动解除或显式 `account-safety.sh resume`（前置确认风险） |
| locked | 任何 mutation 拒绝 | 只允许 doctor + preflight；查 `account-safety-state.last_risk_event` |
| comment disabled | `xhs.sh comment` 返回 `error: comment_disabled` | `SHULING_ENABLE_COMMENT=1` + approval（同时需要 supervised 模式 + commenting_enabled=true） |

更详细的诊断步骤见 `agent/playbook/09-troubleshooting.md`（v3.1 Stage 3 起包含 Account Safety 故障矩阵）。
