# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 本项目是什么

薯灵 (ShuLing) 是一个部署在 AI 平台（Hermes / Claude Code / Codex / OpenClaw）里的 **Skill**，帮用户做小红书博主的选题、创作、发布、复盘闭环。

它不是一个独立运行的服务，而是一套由 AI 助手"读 SKILL.md 执行业务"的剧本 + 一组辅助脚本。**业务逻辑全部在 `SKILL.md` 里**，`scripts/` 只负责 AI 做不了的物理操作（SQLite 读写、MCP 调用、图片生成）。

对 Claude Code 本身而言重要的含义：

- SKILL.md 是业务"源代码"，不是参考文档。改 SKILL.md ≈ 改业务行为 → 需要 BRAIN +1。
- 本仓库里的 Python/Shell 脚本是"手脚层"，扩展能力就在这里改。
- 本仓库自身 ≠ 部署。用户真正用的是 `install.sh` 把本仓库 rsync 到 `~/.hermes/skills/` 或 `~/.claude/skills/` 等 **target** 目录后的拷贝。源 (`$SKILL_DIR`) vs target 路径分离极其重要（见下文 Gotchas）。

## 常用命令

```bash
# ─── 预检 / 自检 ───
python3 scripts/preflight.py              # AI 读的 JSON 格式（退出码 0/1/2 分级）
python3 scripts/preflight.py --human      # 人类彩色表格
bash install.sh --check                   # 依赖 + 平台 + 版本对比，不写文件
bash install.sh --dry-run                 # 预演所有 install 动作，不执行

# ─── 数据库 ───
bash scripts/db.sh init                   # 初始化/补建 11 张表（幂等）
bash scripts/db.sh query-posts --today
SHULING_DB=/path/to/other/xhs.db bash scripts/db.sh init   # 指定 DB 路径（v2.4.2+）

# ─── 小红书 MCP 统一入口 ───
bash scripts/xhs.sh status                # 登录态 + MCP 连通
bash scripts/xhs.sh search "关键词"
bash scripts/xhs.sh log --summary         # request_log 聚合（v2.1.1+）

# ─── JSON Schema drift 校验（v2.4.0+） ───
python3 scripts/validate.py               # 校验 schemas/ 与运行时 JSON 结构一致

# ─── 发版前强制回归（v2.4.2+，21 项） ───
bash scripts/pre-submit-verify.sh         # 必跑；模拟社区 verifier 行为
bash scripts/pre-submit-verify.sh --json  # 给 agent / CI

# ─── install / upgrade ───
bash install.sh                           # 装到默认 targets（Hermes / Claude / Codex 自动检测）
bash install.sh --mode=existing-creator   # 老博主模式（v2.2.0+，走 §0c 流程）
bash install.sh upgrade-all --json        # 批量升级所有 target，机器可读 JSON（v2.4.0+）
bash install.sh upgrade-all --dry-run --json  # 只出 plan 不执行

# ─── Shell/Python 语法体检 ───
bash -n scripts/*.sh                      # 发版前必过
```

单个 migration 通常不手动跑 —— `install.sh` 按 `$target/VERSION` 跟当前版本对比后自动调度。如需手动：

```bash
env SHULING_DB=/path/to/target/data/xhs.db SKILL_DIR=/path/to/target bash migrations/vX.Y.Z.sh
```

**单独跑某个 upgrade-hook**（契约：单参数入口，stdout 单行 JSON）：

```bash
bash upgrade-hooks/vX.Y.Z/<hook>.sh /path/to/target
# 成功: {"status":"ok",...}  跳过: {"status":"skipped",...}  失败: {"status":"failed",...}
```

## 架构

### 三层分离

```
AI 助手（大脑）  ─读→  SKILL.md §0a 业务路由  ─决定→  当前走哪条流程
                                                    ├─ §0/§1   新博主冷启动
                                                    ├─ §0c     老博主接入（v2.2.0+）
                                                    └─ §2/§3/§4 日常流程

业务流程调用 ─→ scripts/（手脚层）─→ data/xhs.db + knowledge-base/*
                                    ↑ AI 写入前按 schemas/*.schema.json 自校验
```

- **SKILL.md**（~1200 行）：核心业务剧本。`§0a` 业务路由、`§0b` 平台识别+schema 校验、`§0c` 老博主接入、`§2` 每日流程、`§3` 复盘、`§4` 自进化算法。
- **scripts/**：`preflight.py`（环境自检）、`db.sh`（11 表 CRUD）、`xhs.sh`（9 个 MCP 工具统一入口，含节流+限额+日志）、`image.py`（Gemini 生图，无 HTML 降级）、`validate.py`（schema drift）、`pre-submit-verify.sh`（21 项发版门）。
- **schemas/**：4 份 JSON Schema（`state` / `profile` / `preferences` / `audit-report`），AI 写入 `config/state.json` / `knowledge-base/*.json` 前必须自校验。
- **migrations/**：按 `vX.Y.Z.sh` 顺序幂等执行；`_guard.sh` 提供 `__migrations` 表台账防重跑（v2.4.0+）。
- **upgrade-hooks/**：声明式的"代码+DB 之外"升级副作用（如就地改写 runtime.env 新字段、改老 JSON 结构）。单参数入口 + 单行 JSON 输出 + 幂等 + 零交互，详见 `upgrade-hooks/README.md`。
- **knowledge-base/**（运行时生成，`.gitignore`）：`profile.json`、`preferences.json`、`patterns.md` / `anti-patterns.md`、`evolution-log.md`、`audit-<date>.md|json`。
- **data/xhs.db**（运行时生成，`.gitignore`）：11 张表 `posts / post_metrics / user_choices / topic_candidates / comment_insights / note_diagnosis / generated_images / request_log / historical_stats / __migrations` + `post_sources` enum。

### 版本号语义 —— BRAIN.HANDS.CALIB（本项目的核心纪律）

决策树（见 `RELEASING.md`）：

- **BRAIN +1** ⇒ SKILL.md 主流程/算法/业务能力变 → **breaking**，必须在 `UPGRADE.md` 写迁移。
- **HANDS +1** ⇒ `scripts/` 新增重写 / DB schema 改 / MCP 接口改 / `install.sh` 结构改 → 一般非 breaking，但可能需要跑 migration。
- **CALIB +1** ⇒ 阈值 / 文档 / bugfix / prompt 微调 → 无感升级。
- 多维同时命中取最高级（`HANDS + CALIB → HANDS+1`）。

发一个版本涉及的必改文件：`VERSION`、`CHANGELOG.md`、`SKILL.md` frontmatter (`version / codename / last_updated`)、如有 breaking 或新环境变量也改 `UPGRADE.md`、如有 DB schema 变化加 `migrations/vX.Y.Z.sh`。

### 数据流（一条主线）

```
AI → SKILL.md 业务路由 → scripts/ 物理操作 → DB + knowledge-base/ → 下次路由读 state.json
```

所有自动化（午/晚间发布 + 夜间复盘 + 周日回顾）走这一条：`hermes cron` 定时唤起助手 → 助手读 SKILL.md `§0a` → 按 `state.json` 决定下一步业务。

## 关键约束与陷阱（Gotchas）

### 源 vs Target 路径隔离（v2.4.2 修过的一类 bug）

本仓库 = **源** (`$SKILL_DIR`)。用户用的 = **target** (`~/.hermes/skills/...` 等)。

- `scripts/db.sh` 默认按脚本自身位置推导 DB 路径。当 `install.sh` 或 migration 从源仓库调 db.sh 去操作 target DB 时，**必须显式传 `SHULING_DB=$target/data/xhs.db`**，否则会误写源 DB。
- `migrations/_guard.sh` 的 `_GUARD_DB` 同样受 `SHULING_DB` 影响。
- `install.sh` 的 `_runtime_env_set` 是 **force override**（v2.4.2+）：被调用即视为用户显式意图，无条件覆盖 `config/runtime.env` 模板默认值（否则 `MCP_URL=http://localhost:...` 这种非空模板会顶掉用户传入值）。

改 `install.sh` 里涉及 target 路径的循环时，检查是否正确透传 `SHULING_DB` 与 `SKILL_DIR`，别让它们指向源。

### 私密数据坚决不进 git

`.gitignore` 已覆盖；但 commit 时**不要** `git add -A` 或 `git add .`：

- `.env` / `config/runtime.env`（API Key）
- `data/*.db`
- `knowledge-base/*.json`、`knowledge-base/audit-*.md`
- `scripts/*.bak.*`（脚本热改产生，发版前必删）

`RELEASING.md` 的命令序列显式列文件 (`git add VERSION CHANGELOG.md UPGRADE.md SKILL.md scripts/ migrations/ README.md`)，照抄即可。

### pre-submit-verify.sh 是强制门

发版前必须跑通 `bash scripts/pre-submit-verify.sh`（v2.4.2+，21 项）。它把社区 cookbook-dev verifier 行为内化成本地回归，覆盖干净 target 初装、runtime.env 覆写、target DB init + `__migrations`、preflight 全绿、upgrade-all migration 写 target 而非源、源 DB md5 未被污染。

### 异常处理纪律（SKILL.md §8）

- AI 模型 API 报错最多 1 次重试。
- `preflight.py` 退出码 0 = 全绿 / 1 = auto-fixable / 2 = need-user。upgrade-all 把 0/1/2 都视为升级本身成功（代码+DB 升级完成），runtime 配置未就绪不算 upgrade failed（v2.4.2+）。
- 已写进 state.json 标记过 OK 的项，即使本次 check 超时，按 OK 处理。不要重复打扰用户、不要重复问画像、不要绕回默认路径。

### Git commit 风格

Conventional commits + HEREDOC，带 `Brain: / Hands: / Calib:` 分条说明：

```
feat(v2.4.2): Source-Target Isolation Patch — <一句话描述>

<Why>

Brain: <如有变化>
Hands: <如有变化>
Calib: <如有变化>

```

Tag 用 annotated (`git tag -a`)，push 必须 `--follow-tags`，忘了补 `git push origin vX.Y.Z`。

### 目录路径一律相对 skill 根

SKILL.md 第一条纪律：所有脚本、配置、数据都在 SKILL.md 同级或子目录下，**不去任何"上级/兄弟"目录读写文件**。这也是 skill 在 Hermes / Claude Code / Codex 下跨平台跑通的前提。

## 可借鉴的设计（如你被要求在其他项目复刻）

- `SKILL.md §0a` 业务路由 + 反模式禁令工程化（"不重复问画像 / 不放空 / 不绕回默认路径"）
- `schemas/` JSON Schema + AI 写入前自校验协议
- BRAIN.HANDS.CALIB 版本号语义 + `RELEASING.md` 决策树
- `upgrade-hooks/` 单参数+单行 JSON 契约，agent 可批量 orchestrate
- CHANGELOG 📦/⬆️ 双栏 + UPGRADE 逐版本步骤 + RELEASING SOP 三件套
