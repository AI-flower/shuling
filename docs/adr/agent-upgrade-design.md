---
title: 面向智能体的升级基础设施设计
status: active
created: 2026-04-21
moved_from: docs/agent-upgrade-design.md
moved_at: 2026-04-23
audience: agent  # 使用方 + 升级执行方都是 AI agent，人类只做指挥
category: adr
---

# 面向智能体的升级基础设施设计

## 背景与约束

**薯灵这个项目的运行特点**：
- 使用方是 AI agent（Claude / Codex / Hermes 调度的其他 LLM）
- 升级执行方也是 AI agent（人类用自然语言指挥，agent 实际跑命令）
- 人类不会手工读 CLI 输出、不会手工编辑配置文件
- 人类只负责 **授权 / 决策 / 收结果**

这意味着升级工具的设计原则必须翻转：**不是让人类用得舒服，是让 agent 用得可靠**。

## 现状问题（以 2026-04-21 Hermes 升级 v2.2.1 → v2.3.0 为例）

本次一次 Hermes 端升级，AI agent 实际执行了 **9 步人工推理动作**：

| # | 动作 | 为什么是 agent 手动做？ |
|---|---|---|
| 1 | `cp -R` 备份 | install.sh 没内建 |
| 2 | `rsync -a --delete --exclude data/config/output/knowledge-base` | install.sh 没有"同步到已安装位置"入口 |
| 3 | `bash migrations/v2.1.1.sh` | install.sh 对跨 major 版本升级的 migration 链路不稳（有跳过 drift） |
| 4 | `bash migrations/v2.2.0.sh` | 同上 |
| 5 | 手查 `runtime.env` 字段完整性 | v2.3.0 新增 `IMAGE_GEN_*` 四项，没有声明谁负责补 |
| 6 | 从 codex runtime.env 复制 `IMAGE_GEN_*` 四项 | 跨 target 复用密钥的逻辑完全没有 |
| 7 | 重置 `preferences.json` 为 schema 合规空骨架 | 依赖"AI 下次写入自愈"的惰性迁移从未触发 |
| 8 | `python3` 脚本替换 `jobs.json` 里的 "HTML 截图" → "Gemini 生图" | 外部调度器配置里的过时 prompt，install.sh 碰不到 |
| 9 | 再跑 preflight 验证 | 这步是唯一自动化的 |

**9 步里 8 步需要 agent 自己推理"下一步该做什么"**——这是升级基础设施的失败。agent 每做一步都要消耗 token 去想、去判断、去读文档、去对比 target。

## 面向 agent 的升级基础设施应该长什么样

### 核心理念：声明式 + 幂等 + 结构化

- **声明式**：版本 A → B 要做的所有事都写在仓库里的某个声明文件，不是散落在 agent 脑子里
- **幂等**：同一条命令连跑 N 次结果一致，agent 重试安全
- **结构化**：一条命令吐 JSON，agent 不需要解析人类友好文案
- **可 dry-run**：能产出"如果执行会发生什么"的机器可读 plan

### 具体形态：`./install.sh upgrade-all`

```bash
./install.sh upgrade-all                 # 扫所有已安装 target，全部升到最新版
./install.sh upgrade-all --dry-run       # 只出 plan，不动手
./install.sh upgrade-all --target=hermes # 只升某一个 target
./install.sh upgrade-all --json          # 所有输出结构化
```

#### 输出契约（JSON）

```json
{
  "overall": "success",
  "targets": [
    {
      "name": "codex",
      "path": "/Users/weiyong/.codex/skills/shuling",
      "from_version": "2.2.1",
      "to_version": "2.3.0",
      "steps": [
        {"id": "backup",                "status": "ok", "artifact": "...bak-20260421-190540"},
        {"id": "rsync_code",            "status": "ok", "files_changed": 18},
        {"id": "migration_v2.1.1",     "status": "skipped", "reason": "already_applied"},
        {"id": "migration_v2.2.0",     "status": "skipped", "reason": "already_applied"},
        {"id": "upgrade_hook_v2.3.0",  "status": "ok", "hooks_ran": ["runtime-env-sync","preferences-migrate"]},
        {"id": "preflight",             "status": "ok"}
      ]
    },
    {
      "name": "hermes",
      "path": "/Users/weiyong/.hermes/skills/social-media/shuling",
      "from_version": "pre-v2.0",
      "to_version": "2.3.0",
      "steps": [...]
    }
  ]
}
```

Agent 只要看 `overall=="success"` 和 `targets[].steps[].status`，剩下不需要理解任何人类文案。

## 需要新增的四样东西

### 1. `TARGETS.yaml`（已装位置登记）

让 install.sh 不需要 agent 告诉它去哪升级，自己扫。

```yaml
# 放在项目根 TARGETS.yaml，或放在 ~/.shuling/targets.yaml（全局登记）
targets:
  - name: codex
    path: ~/.codex/skills/shuling
    scheduler: none
    runtime_env: ~/.codex/skills/shuling/config/runtime.env

  - name: hermes
    path: ~/.hermes/skills/social-media/shuling
    scheduler:
      kind: hermes-cron
      config: ~/.hermes/cron/jobs.json
    runtime_env: ~/.hermes/skills/social-media/shuling/config/runtime.env
```

Install.sh 自动发现兜底：扫常见位置 (`~/.codex/skills/*`, `~/.hermes/skills/**`, `~/.claude/skills/*`)，识别出 shuling 就登记。

### 2. `upgrade-hooks/` 目录（升级副作用声明）

每个引入"代码和 DB 以外副作用"的版本，在这里放一个可独立运行的脚本：

```
upgrade-hooks/
  v2.3.0/
    runtime-env-sync.sh           # 新增 IMAGE_GEN_* 字段，跨 target 借用
    preferences-structure-migrate.sh   # topic_preferences → dimensions.topic
    scheduler-prompt-update.sh    # jobs.json 里的过时描述
    README.md                     # 声明"为什么 v2.3.0 需要这些 hook"
```

**关键**：每个 hook 必须满足：
- 幂等（已处理过的 target 跳过，出 `status: skipped`）
- 输入/输出都是 JSON（agent 可判定）
- 不做任何"让 agent 推理"的事

### 3. `migrations/` 也改成 agent 友好

现在 migrations/v*.sh 是直接跑 sqlite3，没记谁跑过。应该：

```
migrations/
  _applied_table.sql               # 每个 target DB 里维护 __migrations 表
  v2.1.1.sh                        # 进去前先 SELECT 看是否已 applied，是就跳过
  v2.2.0.sh
  v2.3.0.sh                        # 哪怕本版无 DB 变化，也放空壳脚本占位，让版本线性清晰
```

`__migrations(version TEXT PRIMARY KEY, applied_at TEXT)` 是 schema 第一公民。Agent 跑升级时先查，能决定"从哪一步开始跑"。

### 4. `./install.sh doctor`（agent-first 诊断）

```bash
./install.sh doctor --target=hermes --json
```

输出：

```json
{
  "target": "hermes",
  "version_on_disk": "2.3.0",
  "version_db_migrated": "2.3.0",
  "runtime_env_complete": true,
  "preferences_schema_valid": true,
  "scheduler_prompt_fresh": true,
  "preflight": "ready",
  "drift": []
}
```

一条命令回答"这个 target 有没有漂移"。Agent 定期跑一次，有问题直接触发 upgrade-hook。

## 设计原则清单（agent friendly）

- [x] **零人类文案依赖**：所有决策输入都是 JSON/exit code，不靠解析中文/英文提示
- [x] **幂等**：同一个命令跑 N 次安全
- [x] **可 dry-run**：先看 plan 再执行是 agent 的默认工作方式
- [x] **声明式变更**：升级副作用写在 `upgrade-hooks/vX.Y.Z/`，不散落在 agent 脑里
- [x] **单一入口**：`install.sh upgrade-all` 能完成 95% 场景，不用 agent 串 9 步命令
- [x] **可被 agent 审计**：每一步都能回答"为什么跑 / 为什么跳 / 改了什么"
- [x] **回滚点明确**：每步 backup 位置固定，agent 可直接指回滚

## 非目标（不要做的事）

- ❌ **不要做好看的 TUI / 进度条 / 彩色输出**：对 agent 是噪音
- ❌ **不要"人类友好的向导"式交互**：agent 无法处理交互式 prompt
- ❌ **不要"check first, ask user" 的防守性设计**：应当自己决定是否安全，不能安全就直接 exit 非零 + JSON 说明
- ❌ **不要把升级逻辑藏在"agent 提示词里"**：那种"告诉 AI 升级时要注意..."全部应当形式化为 hook 脚本

## 实施优先级建议

不用一口气全做，按痛点排序：

1. **P0**：`__migrations` 表 + migrations/ 幂等化（本次升级 2 次因为这个出过 drift）
2. **P0**：`upgrade-hooks/` 目录 + v2.3.0 三个 hook（把这次手动做的 3 件事固化）
3. **P1**：`install.sh upgrade-all` + JSON 输出
4. **P1**：`TARGETS.yaml` 登记机制（或自动扫描）
5. **P2**：`install.sh doctor`（这个现在靠 preflight 勉强顶用）

## 本次升级留下的 TODO（写给下次 agent）

下次 agent 看到这份文档，应当能回答：

- 薯灵现在装在哪几个 target 上？→ 读 `TARGETS.yaml`（尚未创建）
- 某 target 目前是什么版本？→ 读 `VERSION` + 查 `__migrations` 表（表尚未创建）
- 下一次升级需要跑哪些 hook？→ 读 `upgrade-hooks/` 对比已跑 hook（机制尚未创建）
- 一行命令能不能升级？→ 不能，`install.sh upgrade-all` 尚未实现

上面四个"尚未"就是这份文档要解决的事。

---

**本次升级留档**：
- codex target：`~/.codex/skills/shuling`，升级成功（v2.2.1 → v2.3.0）
- hermes target：`~/.hermes/skills/social-media/shuling`，升级成功（pre-v2.0 → v2.3.0）
- 备份位置：
  - `~/.codex/skills/shuling.bak-v2.3.0-20260421-190540`
  - `~/.hermes/skills/social-media/shuling.bak-v2.3.0-20260421-193933`
- 下次 cron 触发：2026-04-21T20:00（小红书每日自动化）
