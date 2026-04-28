# 升级指南（UPGRADE）

本项目遵循 **BRAIN.HANDS.CALIB** 三段版本号（详见 `VERSION` 与 `RELEASING.md`）。

- **BRAIN** 升级：SKILL.md 核心流程变化，可能改变 AI 的行为方式
- **HANDS** 升级：脚本 / DB schema 变化，可能需要跑 migration
- **CALIB** 升级：阈值/文档/bugfix，一般无需额外动作

---

## 我现在在哪一版？

```bash
# 已部署版本
cat ~/.hermes/skills/social-media/shuling/VERSION | head -3
# 或 ~/.claude/skills/shuling/VERSION，按你的平台

# 源目录最新版本
cd /path/to/shuling && cat VERSION | head -3
```

---

## 通用升级流程（任意版本 → 最新）

```bash
cd /path/to/shuling
git fetch --tags origin
git checkout main && git pull

# v2.1.2 起 install.sh 自动识别已部署版本并运行所需 migration
bash install.sh
```

安装脚本会：
1. 读取当前源目录 `VERSION` 与每个已部署目录 `VERSION`
2. 列出版本差距，按顺序执行 `migrations/vX.Y.Z.sh`
3. 同步最新 skill 文件到各平台目录
4. 保留你的私人数据（`.env` / `config/runtime.env` / `data/xhs.db` / `knowledge-base/*`）

> **幂等设计**：重复跑 `install.sh` 不会破坏已有数据。

---

## 逐版本迁移步骤

## v3.0.0 → v3.1.0（Account Safety Hardening）准备

> ⏳ **状态**：v3.1.0 尚未发版。本节是过渡期文档铺垫——v3.1 落地前可以提前了解将要发生什么变化、准备好迁移路径。
>
> 决策依据：[`docs/adr/0003-account-execution-boundary.md`](docs/adr/0003-account-execution-boundary.md)
> 实施细则：[`docs/plans/v3.1-account-safety-implementation-plan.md`](docs/plans/v3.1-account-safety-implementation-plan.md)
> 运行手册：[`docs/runbooks/account-safety.md`](docs/runbooks/account-safety.md) · [`docs/runbooks/external-intelligence.md`](docs/runbooks/external-intelligence.md)

### v3.1 的关键行为变更（提前周知）

1. **`agent/scripts/xhs.sh publish` 将需要 approval**。从 v3.1 起，无 approval-id 调用直接返回 `error: approval_required`。AI 助手会自动在 `draft_ready` 之后请求 approval，用户回复「发」即触发 grant；自定义脚本必须显式调 `approval.sh request` + `grant`。
2. **评论默认禁用**。`xhs.sh comment` 即使在 supervised 模式下也需要 `SHULING_ENABLE_COMMENT=1` 环境变量 + approval。07-comment-insights 默认只输出回复建议。
3. **cron 改 draft-only**。`ops/cron/*` 模板的 prompt 移除「执行午间发布流程」「执行晚间发布流程」等字样，统一改为「生成草稿 + 等待用户确认 + 不要发布」。
4. **外部情报采样新增预算 / 缓存层**。所有对小红书 search / detail / comment 的访问必须通过 `agent/scripts/external-intel.sh` 入口，受 `agent/policies/external-intelligence.default.json` 预算约束。
5. **`draft_ready` 与 publish 解耦**。`draft_ready` 是 non-mutating 事件，仅用于通知用户；不再是 04-publish-flow 的触发条件。

### 旧自动化脚本迁移示例

如果你的 cron job、CI 任务或第三方集成里有这样的代码（v3.0 行为）：

```bash
# v3.0 自动化（v3.1 起失败）
bash agent/scripts/xhs.sh publish /tmp/xhs-post/meta.json
```

v3.1 起需要改为：

```bash
# v3.1 标准发布流程
APPROVAL=$(bash agent/scripts/approval.sh request publish /tmp/xhs-post/meta.json | jq -r '.id')

# 由用户在 TTY 或对话里 grant；非交互场景必须先获得用户确认
bash agent/scripts/approval.sh grant "$APPROVAL"

# 然后 publish 才能成功
bash agent/scripts/xhs.sh publish /tmp/xhs-post/meta.json --approval-id "$APPROVAL"

# 成功后 consume，防止误用
bash agent/scripts/approval.sh consume "$APPROVAL"
```

### 旧外部数据采样脚本迁移示例

如果你的 playbook / 脚本里有这样的散落调用（v3.0 行为）：

```bash
# v3.0 散落调用
bash agent/scripts/xhs.sh search "租房收纳"
bash agent/scripts/xhs.sh detail "$note_id"
bash agent/scripts/xhs.sh fetch-comments "$note_id"
```

v3.1 起统一走 external-intel.sh：

```bash
# v3.1 预算化外部情报
bash agent/scripts/external-intel.sh research-topic "租房收纳" --budget conservative
bash agent/scripts/external-intel.sh competition-gap "租房收纳"
bash agent/scripts/external-intel.sh comment-demand "$note_id" --limit 30
```

`xhs.sh search/detail/fetch-comments` 仍然存在并可被直接调用（用于一次性手工查询），但 v3.1 verify 第 41 条会扫描 playbook 文件，禁止 03/05/07 散落调用。

### 升级前可以做什么

v3.1 还未发版，但你现在就可以：

- 阅读 [`docs/adr/0003-account-execution-boundary.md`](docs/adr/0003-account-execution-boundary.md) 理解新边界
- 检查你的自动化脚本是否直接调用 `xhs.sh publish/comment/import-cookie`，规划迁移
- 备份 `agent/data/xhs.db` + `agent/config/runtime.env` + `agent/knowledge-base/*`（与 v2 → v3 升级前置 checklist 一致）

升级实际步骤将在 v3.1.0 发版时补全。

---

## v2.x → v3.0.0 "Stateful Creator Agent"（2026-04-27）

> ⚠ **v3.0 是 BRAIN +1 breaking 升级**——target 布局重组、SKILL.md 完全瘦身、scripts/ 路径变化。
> 用户数据自动 copy-first 迁移到 agent/，v2 旧路径保留至 v3.2。
> 详见 [`docs/adr/0001-stateful-creator-agent.md`](docs/adr/0001-stateful-creator-agent.md)。

### 升级前置 checklist

- [ ] 备份 `data/xhs.db`（一份独立副本）
- [ ] 备份 `config/runtime.env`（API Key 仍然有效）
- [ ] 记录当前 VERSION（应为 v2.4.x）
- [ ] git 工作树 clean（`git status` 应该没有未 commit 的 in-flight 改动）
- [ ] 确认有可用的回滚路径（`git tag v2.4.3 -- 还在`）

### 自动迁移路径（推荐）

```bash
git fetch --tags origin && git checkout main && git pull
bash ops/install.sh upgrade-all
```

`upgrade-all` 会：
1. 探测每个 target（`~/.hermes/skills/shuling`、`~/.claude/skills/shuling`、`~/.codex/skills/shuling` 等）
2. 跑 `ops/layout-migrations/v2-to-v3.sh`：把 target 的根级 `scripts/` `schemas/` `migrations/` `prompts/` `data/content-rules.md` `config/runtime.env.example` 迁到 `agent/`
3. 跑 `ensure-runtime-layout`：把 `data/xhs.db` `config/runtime.env` `knowledge-base/*` copy-first 到 `agent/data/` `agent/config/` `agent/knowledge-base/`（**v2 旧路径不删，作为兼容**）
4. 跑 `ensure-schema`：检测 `__migrations` 表，应用任何 pending migration（v3.0 不引入新 DB schema 变化，已应用 v2.x 6 条 migration 的 target 这步会 status=up_to_date）
5. 跑 `ops/install.sh doctor`：12 项体检

### 手动迁移路径（高级用户）

如果你不想跑 install.sh upgrade-all：

```bash
cd ~/.hermes/skills/shuling   # 或你的 target
bash ops/layout-migrations/v2-to-v3.sh "$PWD"        # 仅迁代码文件
bash agent/scripts/db.sh ensure-runtime-layout       # 迁用户态
bash agent/scripts/db.sh ensure-schema               # 应用 migration
bash ops/doctor.sh                                    # 12 项体检
```

### 验证步骤

- [ ] `bash ops/doctor.sh` 输出 fail=0
- [ ] `agent/config/.layout-v3.done` marker 存在且 schema_version=3.0.0
- [ ] `agent/data/xhs.db` 与原 `data/xhs.db` md5 一致
- [ ] `python3 agent/scripts/preflight.py --json` 退出码 ≤ 1（auto-fixable）
- [ ] `bash agent/scripts/xhs.sh status` 报告登录态（如果之前已登录）
- [ ] AI 助手对话"看看昨天的数据"能正常返回历史

### 自定义脚本路径迁移

如果你的工作流脚本（cron job 配置 / 自动化脚本）调用了：
- `bash scripts/xhs.sh ...` → 改为 `bash agent/scripts/xhs.sh ...`
- `bash scripts/db.sh ...` → 改为 `bash agent/scripts/db.sh ...`
- `python3 scripts/preflight.py` → 改为 `python3 agent/scripts/preflight.py`
- `cat data/content-rules.md` → 改为 `cat agent/policies/content-rules.md`
- `bash install.sh` → 仍然有效（v3.0 是 stub，转发到 `ops/install.sh`，v3.2 删除）

### 回滚步骤

如果 v3.0 升级出问题：

```bash
# 1. 切回 v2.4.3 标签
git checkout v2.4.3

# 2. v2 旧路径仍在 target，无需恢复（copy-first 没删）
# - $target/data/xhs.db 仍是 v2 路径下的 DB
# - $target/config/runtime.env 仍是 v2 路径下的配置

# 3. 提示宿主 agent 重启
# Hermes: hermes-cli reload
# Claude Code: 重新 /compact + 重新对话
# Codex: 重启 Codex session
```

详见 [`docs/runbooks/disaster-recovery.md`](docs/runbooks/disaster-recovery.md)。

### 已知问题（v3.0 GA 后第一周持续更新）

- 暂无报告

### v3.0 重构带来的变化

- **breaking**：target 布局变（`scripts/` → `agent/scripts/` 等）；自定义脚本必须改路径
- **breaking**：SKILL.md 从 1204 行业务剧本变成 ≤150 行协议适配层；如果你 fork 改了 SKILL.md 内容，需重做到 `agent/playbook/` 下
- **non-breaking**：用户数据 copy-first 自动迁移，v2 旧路径保留
- **non-breaking**：所有 v2.x 子命令仍工作（install / upgrade-all / --check / --dry-run / --mode 等）
- **新增**：ops/install.sh doctor / migrate-layout / rollback-to-v2 子命令
- **新增**：agent/scripts/db.sh ensure-runtime-layout / ensure-schema 自愈命令
- **新增**：34 项 verify 门禁（vs v2.x 21 项）

---

### → v2.4.0 "Agent-Friendly Upgrade Infrastructure"（2026-04-23）

**类型**：HANDS（纯工程基础设施，SKILL.md 完全不动）
**Breaking**：无

**新增内容**：
- `install.sh upgrade-all` 一键升级所有已装 target（agent-first，JSON 输出）
- `migrations/__migrations` 表 + `_guard.sh`：migration 全部幂等化可安全重跑
- `upgrade-hooks/v2.3.0/` 三个 hook 固化本次升级手工踩过的坑（runtime-env 同步 / preferences schema 迁移 / hermes cron prompt 更新）
- `scripts/validate.py`：schemas JSON schema drift 校验
- `requirements.txt`：Python 依赖锁定
- `docs/{adr,plans,runbooks,reference,archive}/` 五子目录结构

**升级动作（推荐新路径）**：

```bash
cd /path/to/shuling
git pull

# 先看计划不执行
bash install.sh upgrade-all --dry-run --json | python3 -m json.tool

# 实际升级（所有 target 一起）
bash install.sh upgrade-all

# 或只升某个 target
bash install.sh upgrade-all --target=hermes
```

**升级后验证**：

```bash
# 1. __migrations 表应列出 2.1.1 ~ 2.3.0
sqlite3 <target>/data/xhs.db "SELECT * FROM __migrations"

# 2. schema drift 检查
python3 scripts/validate.py --target <target-path> --json

# 3. preflight 过（含新增 schemas check）
cd <target> && python3 scripts/preflight.py --json
```

**兼容性说明**：
- 老的 `bash install.sh` 六模式完全保留，不强制改路径
- `upgrade-all` 与 `--target=<name>` 组合过滤，未匹配返回 exit 3
- 所有 migration / hook 都幂等，重跑安全；失败不阻塞其他 target
- 原有 `knowledge-base/` / `config/runtime.env` / `data/xhs.db` 完全保留，不动用户私人数据

**升级出错时**：
- 回滚：`mv <target>.bak-v2.4.0-<timestamp> <target>`（备份在每个 target 同级目录）
- 查错：`bash install.sh upgrade-all --json 2>&1 | tee upgrade.log` 的 JSON 每步有 status/reason
- schema drift：`python3 scripts/validate.py --target <path>` 指出具体字段

**本版扫出的历史 drift**（已知但不自动修）：
- `~/.codex/skills/shuling/config/state.json` 缺 `setup_completed` / `profile_created` / `setup_date`
- validate.py 会报，但升级 hook 暂不自动修复 —— 需 agent 下次按 §0a 业务路由触发状态重建

---

### → v2.3.0 "Pure Image Pipeline"（2026-04-21）

> ⚠️ 本条目为 v2.4.0 发版时**补录**（v2.3.0 发版时 UPGRADE.md 漏更新）。

**类型**：HANDS + CALIB
**Breaking**：**有** —— 之前靠 HTML 截图兜底的部署必须配 Gemini API Key

**变化**：
- HTML 截图降级路径完全删除（`scripts/screenshot.cjs` / `templates/post.html` 移除）
- Gemini API Key 从可选变必需
- `scripts/image.py` 重写：`render_prompt()` 模板系统 + `--reference` 封面回流 + `--short` 极简 fallback
- 新增 `prompts/image_prompt.txt` / `prompts/image_prompt_short.txt` 中文模板
- `generated_images.prompt` 字段改为存 `page_content` 短语义（节省空间 + 便于 pattern 学习）

**升级动作**：

```bash
cd /path/to/shuling && git pull
bash install.sh     # 会强制问 Gemini API Key（老安装已配则不问）

# 预检
python3 scripts/image.py --check    # 返回 0 才能继续
```

**兼容性说明**：
- 老部署若未配 Gemini Key：发帖流程 §2.3 会硬停，按提示补配
- 老数据（posts / generated_images）完全保留
- v2.4.0 起 upgrade-hooks/v2.3.0/ 提供自动化路径（`runtime-env-sync.sh` 跨 target 借用 Key）

---

### → v2.2.1 "Migration Safety Fix"（2026-04-21）

> ⚠️ 本条目为 v2.4.0 发版时**补录**（v2.2.1 发版时 UPGRADE.md 漏更新）。

**类型**：HANDS（bugfix）
**Breaking**：无

**变化**：
- `migrations/v2.1.1.sh` 重写：只建 `request_log` 表，不再连调 `db.sh init`（避免存量 v2.0 → v2.2.x 跨版升级时 `no such column: source` 阻断）

**升级动作**：

```bash
cd /path/to/shuling && git pull
bash install.sh     # 幂等，无新 schema 变化
```

无特殊兼容性问题。v2.4.0 起此 migration 也受 `__migrations` 表保护，不会重复跑。

---

### → v2.2.0 "Existing Creator Support"（2026-04-21）

**类型**：HANDS + CALIB（新脚本 + DB schema 扩展 + §0c 新分支）
**Breaking**：无

**新增内容**：
- `SKILL.md §0c` 已有账号接入模式（AI 5 步流程）
- `scripts/import-existing.sh` 批量导入历史帖
- `scripts/audit-report.sh` 账号体检报告
- `posts.source` 字段 + `historical_stats` 新表
- `schemas/audit-report.schema.json`
- `install.sh --mode=existing-creator`
- `docs/plans/existing-creator-onboarding.md` 完整设计文档

**升级动作**：

```bash
cd /path/to/shuling && git pull
bash install.sh     # 自动跑 v2.2.0.sh migration（ALTER posts + CREATE historical_stats）
```

**新能力使用**：

```bash
# 老博主接入流程（推荐用 install.sh 一次配置）:
bash install.sh --mode=existing-creator

# 或在 AI 对话里说:
# "我已经在运营小红书，帮我接入"

# 手动流程:
bash scripts/import-existing.sh --limit 200            # 批量导入（~30 分钟）
bash scripts/audit-report.sh --extract-patterns        # 出体检 + patterns 候选
```

**新增环境变量**：
| 变量 | 默认 | 作用 |
|---|---|---|
| `SHULING_CREATOR_MODE` | 空 | 设 `existing` 等同 `--mode=existing`，用于 install.sh 预填 |
| `SHULING_IMPORT_USER_ID` | 空 | 老博主接入时可显式指定要导入的账号 ID |

**DB schema 变化**（幂等 migration 自动处理）：
- `posts` 表加 `source TEXT DEFAULT 'shuling'` 列（不影响已有行）
- 新增 `historical_stats` 表（账号快照纵向趋势）
- 新增 `idx_posts_source` / `idx_posts_note_id` / `idx_hstats_snapshotted_at` 索引

**兼容性说明**：
- 老用户（新博主，`creator_mode != 'existing'`）行为**完全不变**
- §0c 是 additive 扩展，不触发任何老流程的重构
- `posts.source` 默认 `shuling`，不需要回填老数据
- 每日复盘默认只看 `source='shuling'`，老博主导入的帖子不会被误判为"今日新发"

**MVP 阶段已知限制**（不影响升级）：
- `xhs.sh` 尚未暴露 `list-user-feeds` 子命令 → import-existing.sh 真实路径需等小版本补齐；当前可用 `--mock <json>` 完整测试
- AI 自动分类 imported 帖子靠 SKILL.md 描述驱动，未来版本会加 prompt 模板

### → v2.1.3 "Friendly Onboarding"（2026-04-21）

**类型**：HANDS + CALIB（install.sh 重构 + schema 新增 + 文档打磨）
**Breaking**：无

**新增内容**：
- `install.sh` 四个新模式：`--check` / `--dry-run` / `--yes` / `--target`
- `scripts/preflight.py --human`：彩色健康检查
- `schemas/` 目录：JSON Schema 约束 AI 写入 state/profile/preferences
- `SKILL.md §0b`：识别平台 + 写入前校验
- `docs/runbooks/mcp-setup.md` 重写（一键安装 + cookie 图文 + systemd/launchd）
- `RELEASING.md` 新增 .bak 清理检查 + `--check`/`--dry-run` 验证步

**升级动作**：
```bash
# 从任意 2.x 版本升级（推荐）
bash install.sh
# install.sh 会自动识别 v2.1.2 → v2.1.3 并跑 v2.1.3.sh（无实际 DB 操作）

# 或者先预演再执行
bash install.sh --dry-run           # 列出要做什么
bash install.sh                     # 确认后真跑

# CI/远程/cron 场景
SHULING_ASSUME_YES=1 bash install.sh
```

**如何验证**：
```bash
bash install.sh --check                  # 只自检，不改文件
python3 scripts/preflight.py --human     # 彩色健康检查
ls schemas/                              # 应看到 3 个 .schema.json
```

**新增/变化环境变量**：
| 变量 | 默认 | 作用 |
|---|---|---|
| `SHULING_ASSUME_YES` | `0` | 设 `1` 等同 `--yes`，所有交互用默认值 |
| `GEMINI_API_KEY` | 空 | 非交互模式下预填 Gemini Key，避免被 prompt 卡住 |
| `XHS_MCP_URL` | 空 | 非交互模式下预填 MCP URL |

> `preflight.py` 退出码从 v2.1.3 起分级：`0` 就绪 / `1` 可自动修复 / `2` 需用户配合。如果你的 CI 脚本之前假设 exit=0 就是"没问题"，请复核——以前总是返回 0。

### → v2.1.2 "Release Polish"（2026-04-21）

**类型**：CALIB + HANDS（install.sh 增强）
**Breaking**：无

**新增内容**：
- `UPGRADE.md`（你正在看的文件）
- `RELEASING.md` 发版 SOP
- `migrations/` 目录及 migration 脚本框架
- `install.sh` 升级模式
- README 版本徽章 + 环境变量参考表 + 升级指南节

**升级动作**：
```bash
# 从任意 2.x 版本升级，install.sh 会自动处理
bash install.sh
```

---

### → v2.1.1 "Request Log"（2026-04-21）

**类型**：HANDS
**Breaking**：无
**默认行为变化**：每次 MCP 调用会异步写一条 `request_log` 记录

**新增内容**：
- `request_log` 表（需建表）
- `xhs.sh log` 子命令
- `db.sh add-request-log` / `query-request-log` 子命令

**升级动作**：
```bash
# 自动（v2.1.2+ 的 install.sh）
bash install.sh

# 手动（v2.1.1 时代直接跑）
bash scripts/db.sh init   # 幂等，只会补建缺失的表
```

**新增环境变量**：
| 变量 | 默认 | 作用 |
|---|---|---|
| `XHS_DISABLE_LOG` | `0`（开启日志）| 设 `1` 跳过写 request_log |

**如何验证**：
```bash
bash scripts/xhs.sh status         # 触发一次调用
bash scripts/xhs.sh log --limit 3  # 应看到刚才那条
```

---

### → v2.1.0 "Anti-Ban Shield"（2026-04-21）

**类型**：HANDS + CALIB（重大：引入节流和限额）
**Breaking**：无，但**首次接入即生效**（之前零节流）

**新增内容**：
- 分级节流（每个 MCP 接口独立 `MIN_GAP` + ±30% 抖动）
- 日调用限额（超限保护性拒绝）
- Session 复用（opt-in，默认关）
- `scripts/fetch-post-data.sh`（合并 metrics + comments 脚本，HTTP 请求减半）
- `VERSION` 文件、`CHANGELOG.md`

**升级动作**：
```bash
bash install.sh
# 无 DB 迁移，无需手动动作
```

**新增环境变量**：
| 变量 | 默认 | 作用 |
|---|---|---|
| `XHS_CACHE_DIR` | `~/.cache/shuling` | 节流戳文件 + quota 状态目录 |
| `XHS_DISABLE_THROTTLE` | `0` | 设 `1` 跳过节流（仅调试） |
| `XHS_DISABLE_QUOTA` | `0` | 设 `1` 跳过日限额（仅调试） |
| `XHS_REUSE_SESSION` | `0` | 设 `1` 启用 session 复用（上游服务端 2-3 次后会失效，谨慎） |
| `XHS_SESSION_TTL` | `120` | session 复用 TTL 秒数 |

**默认节流 profile（保守版）**：
| 接口 | MIN_GAP 秒 | 日上限 |
|---|---|---|
| `search_feeds` | 20 | 15 |
| `get_feed_detail` | 10 | 50 |
| `list_feeds` | 15 | 20 |
| `publish_content` | 300 | 2 |
| `post_comment_to_feed` | 180 | 5 |
| `user_profile` | 30 | 20 |

- 嫌慢可以 `XHS_DISABLE_THROTTLE=1`，**但账号安全自理**
- 嫌保守可以直接改 `scripts/xhs.sh` 内的 `min_gap_for()` / `daily_cap_for()`

---

### → v2.0.0 "Skill-as-Brain"（2026-04-20）

**类型**：BRAIN（核心架构重写）
**Breaking**：**是**。与 1.x 不兼容。

**变化**：
- 业务逻辑从 Python 脚本迁入 SKILL.md，AI 直接当大脑
- 所有决策（选题打分/文案生成/质量评估）不再调 Python "思考"
- 脚本降级为物理操作层（API 调用/DB 读写/图片生成）

**升级动作**：**重新安装**
```bash
# 备份你的数据
cp -r data/xhs.db data/xhs.db.bak.$(date +%Y%m%d)
cp -r knowledge-base knowledge-base.bak.$(date +%Y%m%d)

# 清空旧 skill 目录（注意留好数据）
# 然后 git pull + bash install.sh
```

> v1.x → v2.0.0 是**一次性硬切**。后续 v2.x 保持兼容。

---

## 降级

**不建议**。但如确有需要：

```bash
git checkout v2.1.1    # 换到目标 tag
bash install.sh         # 重新部署该版本
```

注意：
- 新版本写入的 DB 表（如 `request_log`）在老版本仍保留，不影响
- 新版本引入的环境变量在老版本会被忽略
- 数据兼容性：**向后兼容**（老版本读新 schema 不报错）
