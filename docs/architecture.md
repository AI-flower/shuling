# 薯灵 v3.0 架构详解

> 三层架构：协议适配层 → 业务内核 → 部署运维。
> 本文是技术叙事，对开发者 / AI 助手而非普通用户。普通用户视角见 [`README.md`](../README.md)。

## 三层心智模型

```
┌────────────────────────────────────────────────────────────────────┐
│            宿主平台 (Claude Code / Codex / Hermes / OpenClaw)        │
│            通过 SKILL.md 装载 skill                                  │
└──────────────────────────────┬─────────────────────────────────────┘
                               ↓
┌────────────────────────────────────────────────────────────────────┐
│  协议适配层  SKILL.md  (≤ 150 行)                                    │
│  ────────────────────────────────────────                            │
│  · 启动协议 4 步（ensure-runtime-layout / ensure-schema /             │
│                    preflight / 读 00-routing.md）                    │
│  · 路由速查表（按状态 + 用户意图选剧本）                              │
│  · 全局禁令（不绕 xhs.sh / 不覆盖用户态 / 不自动启 cron / ...）        │
│  · 异常总入口（→ 09-troubleshooting.md）                             │
└──────────────────────────────┬─────────────────────────────────────┘
                               ↓
┌────────────────────────────────────────────────────────────────────┐
│  业务内核  agent/                                                    │
│  ────────────────────────────────────────                            │
│  agent/playbook/   00-09 + _shared/   ← AI 真正"读"的剧本             │
│  agent/scripts/    手脚层 + _paths.sh                                │
│  agent/schemas/    JSON Schema 数据契约                              │
│  agent/prompts/    图像生成 prompt 模板                              │
│  agent/policies/   内容规则 / 节流 / 限额                            │
│  agent/migrations/ db / + state /                                    │
│  agent/config/     runtime.env / state.json   (用户态)               │
│  agent/data/       xhs.db                     (用户态)               │
│  agent/knowledge-base/ profile / preferences / patterns  (用户态)    │
└──────────────────────────────┬─────────────────────────────────────┘
                               ↓ 仅源仓库可见，不进 target 包
┌────────────────────────────────────────────────────────────────────┐
│  部署运维层  ops/                                                    │
│  ────────────────────────────────────────                            │
│  ops/install.sh           7 子命令 install / upgrade-all / ...       │
│  ops/doctor.sh            12 项 target 健康检查                      │
│  ops/layout-migrations/   v2-to-v3.sh                                │
│  ops/upgrade-hooks/       单参数 + 单行 JSON 契约                    │
│  ops/cron/                4 平台模板（不分发）                       │
│  ops/verify/              34 条门禁 + pre-submit-verify.sh           │
└────────────────────────────────────────────────────────────────────┘

工程支撑层（不进 target，不出现在主流程）:
build/ docs/ site/ marketing/ legacy/ dist/
```

## 协议适配层（SKILL.md）

### 职责

SKILL.md 只做 4 件事：

1. 识别 skill 被装载（无论来源是用户消息、cron、`/loop`、宿主调度）
2. 跑启动协议 4 步：`ensure-runtime-layout` → `ensure-schema` → `preflight` → 读 `00-routing.md`
3. 路由：按 state + 用户意图查表选具体剧本
4. 全局约束（6 条禁令 + 异常总入口）

### 行数限制

**≤ 150 行**（verify 第 3 条门禁）。当前 SKILL.md 是 77 行。

为什么硬上限：v2.4.x 的 SKILL.md 1208 行，AI 每次进项目都吞完整剧本，token 成本高、决策不准、修改时易踩跨章节耦合。v3.0 拆出 9 份 playbook 后，AI 按需加载，根 SKILL.md 收敛到入口职责。

### 关键约束（不允许出现在 SKILL.md 里）

- **业务流程细节**（在 playbook）
- **算法公式**（在 06-learning-loop.md）
- **JSON 范例**（在 schemas + scripts/README.md）
- **完整内容规则**（在 agent/policies/content-rules.md）
- **bash 之外的代码块**（verify 第 26 条只允许 ` ```bash `）

### 启动协议 4 步（每次装载必跑）

```bash
# 1. v2→v3 用户态自愈（copy-first，幂等 marker）
bash agent/scripts/db.sh ensure-runtime-layout

# 2. 自动应用 pending DB migration（up_to_date 短路）
bash agent/scripts/db.sh ensure-schema

# 3. 环境预检（退出码 0/1/2 分级）
python3 agent/scripts/preflight.py --json

# 4. 读路由表决定走哪条剧本
cat agent/playbook/00-routing.md
```

任何一步异常都不要自行恢复，直接跳 `09-troubleshooting.md`。

### 路由速查表

| 触发 / 状态 | 进入剧本 |
|---|---|
| 新博主首次使用 / `profile.json` 不存在 | `01-onboarding-new.md` |
| 老博主接入 / `creator_mode=existing` | `02-onboarding-existing.md` |
| "今天发什么" / 起稿 / cron 午晚间 | `03-daily-flow.md` |
| 草稿确认后 / `draft_ready` 事件 | `04-publish-flow.md` |
| 夜间复盘 / 周深度回顾 | `05-review.md` |
| 用户做出选择 / 偏好更新 | `06-learning-loop.md` |
| 复盘触发评论提炼 | `07-comment-insights.md` |
| 写 JSON / 草稿合规 / 发布 QA | `08-compliance.md` |
| 任何 playbook 报错 / preflight 失败 | `09-troubleshooting.md` |

完整决策表（含 state 字段判定）见 `agent/playbook/00-routing.md`。

---

## 业务内核（agent/）

### 目录结构

```
agent/
├── playbook/                      # 9 个剧本 + _shared/
│   ├── 00-routing.md              # 业务路由（≈100 行）
│   ├── 01-onboarding-new.md       # 新博主冷启动（≈240 行）
│   ├── 02-onboarding-existing.md  # 老博主接入（≈200 行）
│   ├── 03-daily-flow.md           # 选题/创作/起稿（≈350 行）
│   ├── 04-publish-flow.md         # 发布 + 图片（≈130 行）
│   ├── 05-review.md               # 复盘（≈275 行）
│   ├── 06-learning-loop.md        # 自进化算法（公式权威，≈190 行）
│   ├── 07-comment-insights.md     # 评论提炼（≈70 行）
│   ├── 08-compliance.md           # schema + 内容合规（≈140 行）
│   ├── 09-troubleshooting.md      # 异常总入口（≈150 行）
│   └── _shared/
│       ├── emoji-dictionary.md
│       ├── confidence-mapping.md
│       ├── outline-template.txt
│       └── post-meta-schema.json
├── scripts/                       # 手脚层（README.md 是脚本契约唯一权威）
│   ├── _paths.sh                  # 路径单一来源（必须 source）
│   ├── _common.sh
│   ├── db.sh / xhs.sh / image.py / preflight.py / validate.py
│   ├── fetch-metrics.sh / fetch-comments.sh / fetch-post-data.sh
│   ├── noterx-diagnose.sh
│   ├── import-existing.sh / audit-report.sh
│   └── pre-submit-verify.sh
├── schemas/                       # JSON Schema 数据契约
│   ├── state.schema.json          # agent/config/state.json
│   ├── profile.schema.json        # agent/knowledge-base/profile.json
│   ├── preferences.schema.json    # agent/knowledge-base/preferences.json
│   ├── audit-report.schema.json   # agent/knowledge-base/audit-*.json
│   └── _meta.md                   # 数据契约文档
├── prompts/                       # 图像生成 prompt 模板
│   ├── image_prompt.txt
│   └── image_prompt_short.txt
├── policies/                      # 业务策略
│   └── content-rules.md           # （v3.1+ 拆 throttle.yaml / quota.yaml）
├── migrations/
│   ├── db/                        # SQLite migration（v*.sh + _guard.sh + __migrations 表）
│   └── state/                     # JSON / knowledge-base 结构迁移
├── config/                        # 用户态：runtime.env / state.json / .layout-v3.done
├── data/                          # 用户态：xhs.db
└── knowledge-base/                # 用户态：profile / preferences / patterns / evolution-log
```

### Playbook frontmatter 规范

每份 playbook 顶部必须带 YAML frontmatter，可被 `build/check-playbook-frontmatter.py` + verify 第 4-6、28、32、34 条机器校验。

**必填**：

- `id`: 文件 stem（如 `00-routing`），全仓唯一
- `title`: 人类可读标题
- `when`: 数组，描述什么场景下读本文件（非空，verify 第 5 条）
- `version`: 与 `VERSION` 一致（verify 第 2 条）
- `last_updated`: ISO 日期

**选填**：

- `needs.required`: 必须存在的文件（schema / 配置）
- `needs.optional`: 可选输入；**必须配 fallback**（verify 第 34 条）
- `needs.db_tables`: 依赖的 SQLite 表
- `needs.env_vars`: 依赖的环境变量
- `calls.scripts`: 调用的脚本（verify 第 6 条校验真实存在）
- `calls.playbooks`: 调用的其它 playbook（verify 第 28 条校验调用图无环）
- `writes.files`: 写入的文件
- `writes.emits`: 触发的事件名
- `preconditions`: 必须满足才能执行的条件（写 profile.json 的 playbook 必须非空，verify 第 32 条）
- `on_failure`: 失败跳转目标（通常是 `09-troubleshooting.md`）
- `authority`: 标记本文件是某个概念的权威定义（如 06 标 `formulas`）

完整规范见 `agent/playbook/00-routing.md` 顶部 + ADR-0002。

### 算法权威唯一性

**`06-learning-loop.md` 是 weight / confidence_level / ε-greedy / consecutive_rejects 的唯一定义文件**。verify 第 31 条强制约束（来自 ADR-0002 D1）。

```
weight = (chosen + 1) / (chosen + skipped + 2)              # Bayesian-Laplace
concentration = (weight_top1 + weight_top2) / Σ weight_all
sample_factor = min(total_choices / 10, 1.0)
confidence_level = round(concentration × sample_factor, 2)
```

其他 playbook 引用必须 cross-ref：

```markdown
weight 公式权威定义 → 06-learning-loop.md#bayesian-laplace-weight-formula
```

不允许复述。这是 v3.0 重构时反复踩坑学到的 - v2.x 公式散落在多处，迭代时数值漂移、反向 PR 难审。

### 路径单一来源

**`agent/scripts/_paths.sh` 是仓库内所有运行时路径的唯一权威**。verify 第 29 条门禁。

所有 shell 脚本必须：

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_paths.sh"

echo "DB at $SHULING_DB_PATH"
echo "KB at $SHULING_KB_DIR"
```

env var override 优先级（详见 `_paths.sh` 注释）：

```
SHULING_DB         > SHULING_AGENT_ROOT 推导 > 自动从脚本位置反推
SHULING_AGENT_ROOT > 自动从脚本位置反推
```

`SHULING_DB` 是 v2.4.2 引入的兼容路径（修源/target 隔离 bug 时加的），新代码用 `SHULING_DB_PATH` 别名。

### Self-healing：ensure-runtime-layout / ensure-schema

v3.0 新增的 runtime 自愈机制，让"只 `git pull` 不跑 install"的用户也能升级。

**`db.sh ensure-runtime-layout`**：

- copy-first 把 v2 的 `data/xhs.db`、`config/runtime.env`、`knowledge-base/*` 迁到 `agent/data/`、`agent/config/`、`agent/knowledge-base/`
- 用户态文件**永不删除**（v2 路径保留至 v3.2 删除窗口）
- 幂等 marker：`agent/config/.layout-v3.done` 存在则短路返回 `{"status":"skipped"}`
- `--dry-run --json` 不写盘，给 verify 第 8 条用

**`db.sh ensure-schema`**：

- 读 `__migrations` 表台账，自动应用 pending DB migration
- 已 up_to_date 则短路 `{"status":"up_to_date"}`
- 失败进入 read-only 降级模式：写 `agent/data/.schema-degraded.lock`，db.sh 读取仍可用、写入拒绝（避免脏数据）
- 降级状态由 `09-troubleshooting.md` 检测并提示用户跑 `install.sh --check`

设计原则之一（ADR-0001 §第 12 条）：每个引入的新机制必须给出"如果该机制不可用怎么办"的降级路径。

---

## 部署运维层（ops/）

仅在源仓库可见，**不进 target 包**（verify 第 13 条门禁）。

### ops/install.sh（1683 行，7 个子命令）

```bash
bash ops/install.sh                            # install（默认）
bash ops/install.sh upgrade-all [--json]       # 批量升级所有 target
bash ops/install.sh --dry-run                  # 预演
bash ops/install.sh --check                    # 只自检
bash ops/install.sh doctor [TARGET] [--json]   # 12 项 target 健康检查（v3.0+）
bash ops/install.sh migrate-layout [TARGET]    # v2 → v3 布局迁移
bash ops/install.sh rollback-to-v2 <TARGET>    # 输出 v2 回滚指引（不动用户态）
```

**rsync 模式**：

- v3 target：用源端**白名单**（`SKILL.md` / `VERSION` / `agents/` / `agent/`）+ atomic swap
- v2 target（升级中间态）：用 `--exclude` 黑名单兼容老布局

**用户态保护**：所有 destructive 操作前先 staging（拷贝到 `.staging/<timestamp>/` 目录），确认成功后再原子替换。verify 第 24 条门禁强制 upgrade-all 不能触碰用户态路径。

### ops/layout-migrations/v2-to-v3.sh

把 target 内 v2 布局迁到 v3，符合 upgrade-hooks 通用契约：

- **单参数入口**：`bash v2-to-v3.sh <target_path>`
- **单行 JSON 输出**：`{"status":"ok","action":"migrated","moved":N,"copied":N,...}`
- **零交互**：不读 stdin
- **幂等**：marker `agent/config/.layout-v3.done` 存在则跳过

迁移规则（仅代码 / 模板，用户态文件由 `ensure-runtime-layout` 处理）：

```
$target/scripts/         → $target/agent/scripts/
$target/schemas/         → $target/agent/schemas/
$target/prompts/         → $target/agent/prompts/
$target/migrations/      → $target/agent/migrations/db/
$target/upgrade-hooks/v2.3.0/preferences-structure-migrate.sh
                         → $target/agent/migrations/state/v2.3.0/
$target/upgrade-hooks/v2.3.0/{runtime-env-sync,scheduler-prompt-update}.sh
                         → $target/ops-staged-upgrade-hooks/v2.3.0/
$target/data/content-rules.md   → cp 到 $target/agent/policies/content-rules.md
$target/config/runtime.env.example → cp 到 $target/agent/config/runtime.env.example
```

### ops/upgrade-hooks/

代码 + DB 之外的"第三类副作用"hook（新字段塞进已存在的 runtime.env、旧 JSON 结构改写、外部 cron prompt 过时字样）。

**通用契约**（`ops/upgrade-hooks/README.md`）：

1. 单参数入口：`bash <hook>.sh <target_path>`
2. 幂等：跑第 N 次安全；已处理过 → `{"status":"skipped","reason":"..."}`
3. 单行 JSON 输出（stdout 只有一行 JSON，进度条走 stderr）
4. 零交互：不得有 `read` / `select` / `confirm`
5. 零 agent 推理依赖：自己该决定的事自己决定
6. 改写前备份：`<原文件>.bak-vX.Y.Z-<timestamp>`

**三类 migration 决策树**（来自 ADR-0002）：

| 副作用类型 | 归属 | 文件位置 |
|---|---|---|
| DB schema 改动 | DB migration | `agent/migrations/db/v*.sh` |
| state.json / knowledge-base/*.json 结构改 | state migration | `agent/migrations/state/v*/` |
| 外部配置（runtime.env 加字段、cron prompt 改） | upgrade-hook | `ops/upgrade-hooks/vX.Y.Z/` |

### ops/cron/（4 平台模板）

```
ops/cron/
├── README.md
├── claude-code.md            # 会话级 /loop（开发期）
├── hermes.yaml.example       # 推荐：全自动每日发布 + 复盘
├── launchd.plist.example     # macOS OS 级 user agent
└── systemd.timer.example     # Linux OS 级 user timer
```

**模板库性质**——install.sh 不会拷贝本目录到 target，用户必须显式选模板 + 自己装。详见 `ops/cron/README.md`。

verify 第 19-21 条强制约束：launchd 通过 `plutil -lint`、systemd 通过 `systemd-analyze verify`、yaml 通过 yq 解析。

### ops/verify/（34 条门禁）

```bash
bash ops/verify/pre-submit-verify.sh         # 主调度，必跑
bash ops/verify/pre-submit-verify.sh --strict   # warn 也阻断
```

**checks/ 目录**：34 个独立脚本，单一职责，零依赖（除 bash + python3）。

```
01-skill-frontmatter.sh           02-skill-version-match.sh         03-skill-line-count.sh
04-playbook-frontmatter.sh        05-playbook-when-nonempty.sh      06-playbook-calls-exist.sh
07-xhs-sh-executable.sh           08-ensure-runtime-layout-dryrun.sh 09-ensure-schema-dryrun.sh
10-json-schemas-parse.sh          11-preflight-ok.sh                12-package-whitelist.sh
13-package-no-inactive-dirs.sh    14-package-no-user-state.sh       15-active-region-no-old-paths.sh
16-active-region-no-legacy-refs.sh 17-active-region-no-tech-bias.sh 18-legacy-readme-coverage.sh
19-cron-plist-lint.sh             20-cron-systemd-verify.sh         21-cron-yaml-parse.sh
22-install-stub-dryrun.sh         23-ops-install-dryrun.sh          24-upgrade-all-no-user-overwrite.sh
25-git-diff-check.sh              26-skill-md-no-codeblock.sh       27-migration-isolation.sh
28-playbook-graph-no-cycle.sh     29-paths-singleton.sh             30-policy-drift.sh
31-algorithm-uniqueness.sh        32-profile-write-precondition.sh  33-compliance-inline-limit.sh
34-optional-fallback.sh
```

**通用契约**（`ops/verify/checks/README.md`）：

- 退出码：`0 = pass / 1 = warn / 2 = fail`
- stdout 单行 JSON：`{"check":"...","status":"...","message":"...","severity":"..."}`
- 第一参数：仓库根（默认从脚本位置反推）
- 副作用：零（只读）

**v3.0 关键新增条款**：

- **31** 算法唯一性：weight / confidence 公式仅在 06-learning-loop.md 出现（ADR-0002 D1）
- **32** profile 写入 preconditions：写 profile.json 的 playbook 必须有非空 preconditions（ADR-0002 D3）
- **33** 合规内联行数：03/04 内联合规摘要 ≤25/20 行（ADR-0002 D4）
- **34** optional fallback：`needs.optional` 字段必须配 fallback（ADR-0002 D5）

severity 三档：

- **error**：必过；`--strict` 与默认模式都阻断
- **warn**：默认仅警告；`--strict` 阻断
- **info**：仅提示

### ops/doctor.sh（12 项 target 健康检查）

```bash
bash ops/doctor.sh [TARGET]            # 默认表格
bash ops/doctor.sh --json [TARGET]
```

12 项检查：`skill_md / agent_dir / user_db / runtime_env / runtime_env_example / db_sh / layout_marker / preflight / ensure_layout / ensure_schema / playbooks (≥9) / schemas (≥4)`。

退出码：`0 全部通过 / 1 至少 1 项 warn / 2 至少 1 项 fail`。

设计与 verify 不同——doctor 是**用户态视角**（target 安装目录的健康），verify 是**源仓库视角**（发版前回归）。

---

## 工程支撑层（不进 target）

| 目录 | 用途 |
|---|---|
| `build/` | package + 4 个 check 工具（`package-skill.sh` / `check-package.sh` / `check-version-sync.sh` / `check-playbook-frontmatter.py` / `check-active-region-refs.py`） |
| `docs/` | adr / plans / runbooks / reference（本文件 + ADR-0001/0002 + 升级手册 + 平台配置） |
| `site/` | landing page 源码（独立部署到 shuling.pages.dev） |
| `marketing/` | v2.x 推广物料（v3.0 仍 active 但不分发） |
| `legacy/` | 归档（`old-xhs-mcp-skill/` / `archive/` / `promotion-archive/` / `shuling-full-spec.md`） |
| `dist/` | `build/package-skill.sh` 输出（gitignored） |

verify 第 13 条强制约束 `dist/shuling-agent-skill/` 顶层只能含 4 个条目：`SKILL.md / VERSION / agents/ / agent/`。

---

## 数据流（一条主线）

```
                ┌─────────────────────────────────────┐
                │  AI 助手（宿主平台装载 SKILL.md）   │
                └──────────────┬──────────────────────┘
                               │ 启动协议 4 步
                               ↓
            ensure-runtime-layout → ensure-schema → preflight
                               ↓
                agent/playbook/00-routing.md
                               ↓ 按 state + 意图查表
       ┌─────────┬───────────┬─────┴─────┬───────────┬─────────┐
       ↓         ↓           ↓           ↓           ↓         ↓
   01-onboard 02-existing 03-daily   04-publish  05-review  09-trouble
   ing-new   onboarding  flow        flow                   shooting
       │         │           │           │           │         │
       │         │           │           │           │         │
       └─────┬───┴────┬──────┴────┬──────┘           │         │
             ↓        ↓           ↓                  │         │
        06-learning-loop （所有写偏好的 playbook）   │         │
             ↓                                       │         │
        08-compliance （所有写 JSON 的 playbook）─ ─ ┴ ─ ─ ─ ─ ┘
                               ↓ 调用
                  agent/scripts/{xhs,db,image,...}
                               ↓ 读写
            agent/data/xhs.db + agent/knowledge-base/*
                               ↓
            状态落 agent/config/state.json，下次路由读 state
```

所有自动化（午/晚间发布 + 夜间复盘 + 周日回顾）走同一条主线，由 cron 唤起助手 → 助手读 SKILL.md → 启动协议 → 路由到 playbook。

---

## 与 v2.x 的关系

### 升级路径

- **v2.x → v3.0 是 BRAIN +1 breaking 升级**
- target 布局做 major migration（`scripts/` → `agent/scripts/` 等），由 `ops/layout-migrations/v2-to-v3.sh` 自动完成
- **copy-first 用户数据迁移**：`agent/data/xhs.db` 与 v2 的 `data/xhs.db` md5 一致（verify 强制约束）
- v2 旧路径**保留至 v3.2 删除窗口**（不破坏回滚能力）
- 根 `install.sh` 是兼容 stub，原样转发到 `ops/install.sh`，**v3.2 移除**

### 演进而非革命（ADR-0001 §第 8 条原则）

所有 v2.x 已有基础设施必须在 v3.0 找到对应位置，不允许"重写为 v3 新机制"：

| v2.x 机制 | v3.0 位置 |
|---|---|
| `migrations/__migrations` 表 | `agent/migrations/db/` + `_guard.sh`（位置变，行为不变） |
| `upgrade-hooks/` 单参数 + JSON 契约 | 三向拆分：`agent/migrations/state/` + `agent/migrations/db/` + `ops/upgrade-hooks/` |
| `pre-submit-verify.sh` 21 项 | `ops/verify/pre-submit-verify.sh` 主调度 + 34 条独立 checks |
| 节流 / 限额参数 | `agent/policies/`（v3.1 拆 yaml） |
| `schemas/*.schema.json` | `agent/schemas/*.schema.json`（位置变，schema 内容不变） |
| BRAIN.HANDS.CALIB 版本纪律 | 延续，`VERSION` 文件结构不变 |

### 兼容 stub 窗口

| 文件 / 路径 | v3.0 行为 | v3.2 行为 |
|---|---|---|
| 根 `install.sh` | 转发到 `ops/install.sh` + DEPRECATED 提示 | 移除 |
| target 内 `data/xhs.db` | 保留（copy-first 已迁到 `agent/data/`） | 删除 |
| target 内 `scripts/` 等 v2 旧路径 | 保留（`v2-to-v3.sh` 已迁到 `agent/`） | 删除 |
| `legacy/` 归档 | 保留 | 视情况删除（最早 v3.2） |

---

## v4.0 退出条件

ADR-0001 末尾锁定的 4 条退出条件，**任一满足即触发 v4.0 议题**：

1. **playbook 数量 >20**，路由表无法在 SKILL.md 50-150 行内表达
2. **多平台元数据（`agents/`）超过 5 个**，需要平台抽象层
3. **数据规模超过 SQLite 单文件能力**（>100k posts / multi-account）
4. **需要把 agent 从"用户本机进程内 skill"升级为"远程服务"**

显式记录 v4.0 候选议题，避免 v3.x 中后期反复争论"要不要重构"。

---

## 相关文档

- [`README.md`](../README.md) — 用户视角的项目介绍
- [`SKILL.md`](../SKILL.md) — 协议适配层入口（≤150 行）
- [`agent/playbook/00-routing.md`](../agent/playbook/00-routing.md) — 业务路由速查
- [`agent/scripts/README.md`](../agent/scripts/README.md) — 脚本契约
- [`agent/schemas/_meta.md`](../agent/schemas/_meta.md) — 数据契约
- [`docs/adr/0001-stateful-creator-agent.md`](adr/0001-stateful-creator-agent.md) — v3.0 重构决策（12 条总原则）
- [`docs/adr/0002-playbook-split-decisions.md`](adr/0002-playbook-split-decisions.md) — playbook 拆分决议（D1-D5）
- [`docs/plans/v3-playbook-split-feasibility.md`](plans/v3-playbook-split-feasibility.md) — 可行性研究
- [`UPGRADE.md`](../UPGRADE.md) — v2.x → v3.0 升级步骤
- [`RELEASING.md`](../RELEASING.md) — 发版流程 + BRAIN.HANDS.CALIB 决策树
