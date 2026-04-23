# v2.3.0 升级 hook

> 上级：[../README.md](../README.md)
> 设计文档：[docs/agent-upgrade-design.md](../../docs/agent-upgrade-design.md)

## 为什么需要这三个 hook

2026-04-21 把某台 Hermes target 从 v2.2.1 升到 v2.3.0 时，代码 rsync + DB migration 跑完后，agent 仍手动跑了 3 个额外动作才算升级完成。这 3 个动作无法靠 `git pull` 或 `migrations/*.sh` 自动完成，是 v2.3.0 的 **真实副作用**：

1. `config/runtime.env` 缺 `IMAGE_GEN_*` 五个字段（v2.3.0 删了 HTML 截图降级路径，Gemini 成必需），agent 得从 codex target 借 API_KEY 过去
2. `knowledge-base/preferences.json` 旧扁平结构（`topic_preferences / style_preferences / title_pattern_preferences`）与 v2.3.0 新 schema（`dimensions.topic / dimensions.style / dimensions.title_pattern`）不兼容，依赖 "AI 下次写入自愈" 的惰性迁移从来没触发，需要主动改写
3. `~/.hermes/cron/jobs.json` 里的 prompt 文案仍提 "HTML 截图"，v2.3.0 已删该路径，需替换成 "Gemini 生图"

本目录把这 3 件事固化成可重复、可审计、可批量调用的声明式脚本。

## 建议执行顺序

```bash
# 顺序不可交换：后两步依赖前面的 target 环境完整
bash upgrade-hooks/v2.3.0/runtime-env-sync.sh           <target_path>
bash upgrade-hooks/v2.3.0/preferences-structure-migrate.sh  <target_path>
bash upgrade-hooks/v2.3.0/scheduler-prompt-update.sh    <target_path>
```

- **runtime-env-sync 必须先跑**：preferences 迁移不依赖它，但按 "配置先稳 → 数据再迁 → 调度最后" 的习惯顺序最安全
- **scheduler-prompt-update 最后跑**：它只影响 hermes target，非 hermes target 会直接 skip，对 codex 等不用管

每个脚本独立幂等，允许重复跑；第二次跑全部应返回 `status: skipped`。

## hook 清单

### 1. runtime-env-sync.sh

补齐 v2.3.0 新增的 `IMAGE_GEN_*` 五项配置：

| 字段 | 默认值 | 含义 |
|------|--------|------|
| `IMAGE_GEN_PROVIDER` | `gemini` | 图片生成 provider |
| `IMAGE_GEN_API_KEY` | （空，必填）| API Key，优先从其他 target 借 |
| `IMAGE_GEN_MODEL` | `gemini-3-pro-image-preview` | 模型名 |
| `IMAGE_GEN_PROTOCOL` | `gemini-native` | 协议 |
| `IMAGE_GEN_BASE_URL` | （空，可选）| 代理 URL |

幂等策略：
- 字段已有且非空 → 不动（保护用户值）
- 字段存在但空值，且该字段是 API_KEY → 扫 `~/.codex/skills/*/config/runtime.env`、`~/.hermes/skills/**/config/runtime.env`、`~/.claude/skills/*/config/runtime.env`，取第一个非空值
- 字段存在但空值，且该字段不是 API_KEY → 写默认值（如果默认值非空）
- 字段完全缺失 → 追加字段，值按上述规则决定

### 2. preferences-structure-migrate.sh

`knowledge-base/preferences.json` 从旧扁平结构迁到 v2.3.0 嵌套结构：

```jsonc
// 旧：
{ "topic_preferences": {...}, "style_preferences": {...}, "title_pattern_preferences": {...} }

// 新（per schemas/preferences.schema.json）：
{ "dimensions": { "topic": {...}, "style": {...}, "title_pattern": {...} }, ... }
```

幂等策略：
- 文件不存在 → skip
- 已是 `dimensions` 结构 → skip
- 旧结构 → 备份到 `preferences.json.bak-v2.3.0-<timestamp>`，重写为新结构，保留所有 chosen/skipped 计数，`updated_at` 填今天

### 3. scheduler-prompt-update.sh

把 hermes 调度器配置里过时的 "HTML 截图" 字样替换为 "Gemini 生图"。

幂等策略：
- `~/.hermes/cron/jobs.json` 不存在（非 hermes target）→ skip
- 文件中无 "HTML 截图" → skip
- 有 → 备份 + 替换 + 用 `jq empty` 验证 JSON 仍有效

注意：此 hook 的 `<target_path>` 参数仅用于记录和日志，实际操作的是 `~/.hermes/cron/jobs.json`（全局 hermes 调度器配置，跨 target 共享）。
