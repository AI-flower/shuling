# Changelog

本项目版本号遵循 **BRAIN.HANDS.CALIB** 三段语义（见 `VERSION`）。
升级步骤集中在 [`UPGRADE.md`](UPGRADE.md)；发版流程见 [`RELEASING.md`](RELEASING.md)。

变更按以下类别归档：

- 🧠 **Brain**: SKILL.md 核心流程重构、自进化算法换代、业务能力跃迁
- ✋ **Hands**: scripts/ 新增或重写、DB schema 迁移、MCP 接口替换、平台适配器
- 🎛 **Calib**: 阈值/关键词/节流参数调整、bugfix、prompt 微调

每个版本同时给出：
- 📦 **用户可见改动**：实际使用体验的变化
- ⬆️ **如何升级**：从上一版升到这一版需要做什么

---

## [2.4.0] - 2026-04-23 "Agent-Friendly Upgrade Infrastructure"

工程侧大修：把本次 v2.2.1→v2.3.0 升级 agent 手推 9 步的经验固化为可复用基础设施。**SKILL.md / 业务流程 / 自进化算法完全不变**，纯工程升级。

**版本位决策**：BRAIN +0 / HANDS +1 / CALIB +0 → HANDS +1 → v2.4.0

### 📦 用户可见改动

- **一键升级**：`bash install.sh upgrade-all [--dry-run] [--json] [--target=<name>]` 扫出所有已装 target 并统一升级，替代过去逐 target 手动 rsync + migrate + run hook 的 9 步
- **JSON 可观测**：每步（backup / rsync / migration / upgrade_hook / pip_install / preflight）输出机器可读 JSON，agent 可审计每步为什么跑/跳/改了什么
- **migrations 幂等化**：旧 4 份 migration 改造后安全重跑；新增 v2.2.1 / v2.3.0 空壳保持版本线连续；所有 migration 通过 `__migrations` 表记录 applied
- **升级副作用固化**：新增 `upgrade-hooks/v2.3.0/` 三个 hook（runtime-env 四字段同步 / preferences schema 迁移 / hermes jobs.json "HTML 截图" 词条替换），下次 agent 升级不用再手工推理
- **依赖锁定**：新增 `requirements.txt`（当前只锁 `jsonschema>=4.0,<5.0`，实际扫描后 image.py/preflight.py 纯 stdlib）
- **schema drift 可校验**：`python3 scripts/validate.py --target <path>` 一键查 state/profile/preferences/audit-report 是否符合 schema —— 本次扫出 codex target `state.json` 缺 `setup_completed` 等字段的历史 drift
- **docs/ 结构化**：五子目录 `adr/plans/runbooks/reference/archive`；195 个悬挂 checkbox 的旧 plan 统一归档；`docs/README.md` 目录索引

### 🧠 Brain

_无。本版 SKILL.md 完全不动。业务流程 / 自进化算法 / AI 行为方式零变化。_

### ✋ Hands

**migrations 幂等化（B1 + B2）**
- `migrations/_applied_table.sql`：单一真实 `__migrations(version, applied_at)` schema，供 guard 和 `db.sh init` 共用
- `migrations/_guard.sh`：公共库，提供 `already_applied` / `mark_applied`；source 时自动建表兜底；DB 路径从 `$SHULING_DB` 或 `$SKILL_DIR/data/xhs.db` 推导
- `migrations/v2.2.1.sh` / `v2.3.0.sh`：空壳占位，保持版本线连续（install.sh upgrade-all 按目录扫描）
- `migrations/v2.1.1.sh` / `v2.1.2.sh` / `v2.1.3.sh` / `v2.2.0.sh`：存量四份全部改造为 guard-wrapped，DDL 本体保留，重跑无害，输出统一单行 JSON
- `scripts/db.sh init`：同步补建 `__migrations` 表，`.tables` 输出从 10 张扩展到 11 张

**升级副作用固化（B3）**
- `upgrade-hooks/README.md` + `upgrade-hooks/v2.3.0/README.md`：目录约定文档
- `upgrade-hooks/v2.3.0/runtime-env-sync.sh`：检查 `config/runtime.env` 的 `IMAGE_GEN_*` 四字段；缺则从其他 target 借用 API_KEY，补默认值；**不覆盖用户已有值**
- `upgrade-hooks/v2.3.0/preferences-structure-migrate.sh`：旧扁平 `topic_preferences/style_preferences/title_pattern_preferences` → 新嵌套 `dimensions.topic/style/title_pattern`，自动备份到 `.bak-v2.3.0-<timestamp>`
- `upgrade-hooks/v2.3.0/scheduler-prompt-update.sh`：hermes `~/.hermes/cron/jobs.json` 里 "HTML 截图" 替换 "Gemini 生图"，自动备份
- 每 hook 幂等、JSON stdout（单行）、无交互

**install.sh 升级聚合器（B4）**
- 新增子命令 `upgrade-all`（install.sh 487 → 979 行）：
  - `discover_targets()` 扫 `~/.codex/skills/*` / `~/.hermes/skills/**` / `~/.claude/skills/*`，识别需同时有 VERSION + SKILL.md
  - 每 target 6 步：backup / rsync_code / migrations / upgrade_hooks / pip_install / preflight
  - 支持 `--dry-run`（纯 plan）/ `--json`（agent-first）/ `--target=<name>`（过滤）
  - 单 step 失败 → 本 target 后续自动 `skipped/prior_failed`，不阻塞其他 target
  - JSON 契约符合 `docs/adr/agent-upgrade-design.md`
- 原六模式（install / --check / --dry-run / --yes / --target / --mode=existing-creator）完全兼容

**依赖锁定（D4）**
- `requirements.txt`（新）：按 `scripts/*.py` 实际 import 扫描产出；image.py/preflight.py 只用 stdlib；唯一真依赖是 `jsonschema>=4.0,<5.0`（v2.4.0 新增的 validate.py 使用）；注释说明未来引入 SDK 的追加规则

**schema drift 校验（C3）**
- `scripts/validate.py`（新）：读 `schemas/*.json` 校验对应 runtime 产物（state/profile/preferences + glob audit-*.json）；`--target <path>` / `--file <path> --schema <name>` / `--json` / 退出码 0/1/2
- `scripts/preflight.py`：加 `check_schemas()` 项，drift 时 action="optional" 引导跑 validate.py

### 🎛 Calib

**docs 重组（D1）**
- 新建 `docs/{adr,plans,runbooks,reference,archive}/` 五子目录
- `git mv` 共 11 份历史文档归档（保留 history）：
  - `runbooks/`: mcp-setup.md
  - `reference/`: capability-overview.md
  - `plans/`: 2026-04-21-project-optimization-roadmap.md / existing-creator-onboarding.md（从 features/ 移出）
  - `adr/`: agent-upgrade-design.md / 2026-04-23-kb-health-diagnosis.md（Phase 0 新建）
  - `archive/`: 2026-04-15-self-evolution-{design,plan}.md + 4 份 superpowers-*.md 历史 plan
- 195 个悬挂 checkbox 头部加 reconcile 说明统一归档，不逐一勾选
- 新建 `docs/README.md` 目录索引（frontmatter + 用途表）

**清杂物（D2）**
- 删除 `SKILL.md.bak` / `scripts/image.py.bak`
- `.gitignore` 追加 `*.bak.*` / `.session-recorder/`

**引用修正**
- SKILL.md / README.md / UPGRADE.md 中指向旧 `docs/mcp-setup.md` 和 `docs/features/existing-creator-onboarding.md` 的链接全部更新到新路径

### ⬆️ 如何升级

**推荐（新路径，v2.4.0 起）**：

```bash
cd /path/to/shuling && git pull
bash install.sh upgrade-all --dry-run --json | python3 -m json.tool  # 先看 plan
bash install.sh upgrade-all                                           # 实际升级
```

`upgrade-all` 会对每个发现的 target：
1. backup 到 `<target>.bak-v2.4.0-<timestamp>`
2. rsync 源码（自动 exclude `data/ / config/runtime.env / knowledge-base/`）
3. 跑 migrations（已 applied 自动 skip）
4. 跑 upgrade-hooks（已处理自动 skip）
5. pip install -r requirements.txt
6. preflight 验证

**老路径依然可用**（向后兼容）：

```bash
bash install.sh         # 原六模式完全保留
```

**升级后验证**：

```bash
python3 scripts/validate.py --target <target-path>                       # schema drift
sqlite3 <target>/data/xhs.db "SELECT * FROM __migrations"                 # 应列出 2.1.1~2.3.0
```

**Breaking**：无。老部署一条命令平滑升级。

### 🧭 路线图预告

- **v2.4.1**（Observability + Test）：C1 脚本级 JSON 日志 + C2 smoke 测试 + E1 ShellCheck
- **v2.5.0**（SKILL.md Modular，BRAIN+1）：A1 1208 行 SKILL.md 拆分为主干 ≤300 行 + `skill-chapters/*`
- **历史债 backlog**（按需触发）：A2 db.sh → db.py、C4 三平台独立 smoke、D5 备份清理
- **永久不做**：E2 命名一致性改名（成本 > 收益）

详见 `docs/plans/2026-04-21-project-optimization-roadmap.md`

---

## [2.3.0] - 2026-04-21 "Pure Image Pipeline"

图像生成管线的一次收紧：去掉 HTML 截图降级路径，强制走 Gemini AI 生图；引入结构化 prompt 模板系统 + 封面回流参考图 + 极简 fallback。

### 📦 用户可见改动

- **Gemini API Key 现在是必需**，没有就无法生图，也就无法发帖（install.sh 会强制问）
- **HTML 截图降级路径完全移除**：不再有 'templates/post.html + Playwright screenshot' 的兜底，Gemini 出错就硬停、提示重试
- **新增 prompt 模板系统**：'prompts/image_prompt.txt'（完整版）+ 'prompts/image_prompt_short.txt'（API 上下文受限时的极简版），由 image.py 自动渲染
- **封面回流参考**：'image.py --reference <cover>' 把第一张封面作为参考图回注每一张内容页，大幅提升风格统一性（Nano Banana Pro multimodal 能力）
- **老的 xhs-content-generator 子 skill 撤销**（单独用 HTML 模板出图的能力已被主 skill 消化）

### 🧠 Brain

- 'SKILL.md §0' 第 2 步：图片生成 API 由 '可选' → '必需'，措辞替换为'硬停'语义
- 'SKILL.md §2.3' 图片生成流程重写：只保留 AI 生图一条路径，明确两阶段封面参考 + --short fallback
- 'SKILL.md §8' 异常处理矩阵：'Gemini 不可用 → HTML 截图降级' 改为 '硬停并提示用户配置 Key'
- 'generated_images' 表的 'prompt' 字段改为存 'page_content' 短语义，不存整段渲染后 prompt（节省空间 + 便于 pattern 学习）

### ✋ Hands

- 'scripts/image.py' 重写 (~240 行 diff):
  - 'render_prompt(page_type, page_content, full_outline, user_topic, short)' 模板渲染器
  - '_gen_gemini_native()' 独立 gemini-native protocol 分支
  - '_load_reference_image()' 支持 '--reference' 参考图回注
  - '--short' flag 切到极简 prompt 模板
  - CLI 新增 '--topic' / '--outline-file' / 多个 '--reference'
- **删除文件**:
  - 'scripts/screenshot.cjs' (HTML 截图降级脚本)
  - 'templates/post.html' (448 行 HTML 模板)
  - 'skills/xhs-content-generator/' 整个子 skill 目录
- 'scripts/preflight.py' 调整：图片 API 从 'optional' → 'required'
- 'install.sh' 调整：不配 Gemini Key 会报更强的警告
- 'config/runtime.env.example' 更新变量说明

### 🌐 Landing page

- 'landing/index.html' 版本号全部动态化（读 GitHub Releases API）：
  - 所有 'v2.X.Y'（当前版本）/ codename / 发布日期硬编码处加 'data-ver' 属性
  - 顶部加载一段 ~15 行 JS，fetch /releases/latest 后覆盖
  - 硬编码值作 fallback（API 失败不破坏页面）
  - 发版后 Landing page **自动同步**，不再需要手动改

### 🎛 Calib

- 'docs/capability-overview.md' / 'shuling-full-spec.md' / 'platform/hermes.md' 同步删除 HTML 截图相关段落

### ⬆️ 如何升级

```bash
cd /path/to/shuling && git pull
bash install.sh     # 会强制问你要 Gemini API Key（老安装如已有 Key 不会重问）
```

**有 breaking**：存量部署之前靠 HTML 截图兜底的，升级后必须配 Gemini Key 才能继续发帖。建议先：

```bash
python3 scripts/image.py --check
```

返回 0 才能跑 v2.3.0 日常流程。

### 🔀 路线图调整

原 v2.3.0 规划主题 'Human Rhythm（行为节奏模拟）' 顺延到 v2.4.0+。本版本主题改为图像管线收紧。

---

## [2.2.1] - 2026-04-21 "Migration Safety Fix"

修复 v2.1.1 migration 在存量 v2.0 升级到 v2.2.x 时阻断的问题。

### 📦 用户可见改动

- 存量 v2.0 部署跑 `bash install.sh` 升级不再被 `no such column: source` 错误挡下
- 各 migration 职责单一，互不拖累

### ✋ Hands

- `migrations/v2.1.1.sh` 重写：只建 `request_log` 表，**不再调用 `db.sh init`**（原实现会跑到 v2.2.0 的 `CREATE INDEX idx_posts_source`，在 posts 还没 source 字段时炸）
- 其他 migration 不变

### ⬆️ 如何升级

```bash
cd /path/to/shuling && git pull
bash install.sh     # v2.1.1.sh 现在幂等安全
```

无 breaking。已经成功跑过老版 v2.1.1.sh 的部署无影响（幂等再跑）。

---

## [2.2.0] - 2026-04-21 "Existing Creator Support"

让已经在运营小红书的老博主无缝接入，用他们自己的历史数据预填画像、挖掘 patterns、bootstrap 偏好——第一条薯灵发帖即达其历史 P50 水平。

### 📦 用户可见改动

- **新增"老博主接入模式"**：
  - `bash install.sh --mode=existing-creator` 一键进入；或对话里说"我已经在运营小红书"
  - 系统会拉你最近 200 条历史帖，自动分析出你的领域 / 受众 / 风格
  - 挖掘出你自己已经验证有效的标题模式与结构，写入 `patterns.md` (confidence=medium)
  - 产出**账号体检报告** `knowledge-base/audit-<YYYY-MM-DD>.md`：Top5/Bottom5 归因、主题分布、标题模式命中率、评论需求积压、风险信号
- **新增两条命令行工具**：
  - `bash scripts/import-existing.sh --limit 200` 批量导入历史（带节流 / 断点续跑 / dry-run / mock）
  - `bash scripts/audit-report.sh --extract-patterns` 出体检报告 + patterns 候选
- **install.sh 新增 `--mode <new|existing|ask>`**：装完后问一次是新号还是老号（非交互默认 new）

### 🧠 Brain

- **SKILL.md 新增 §0c "已有账号接入模式"**（additive，不改变原有 §1 新博主流程）
  - 5 步流程：确认登录 → 批量导入 → 自动分类 → 画像反推 → 出体检报告
  - 四条关键纪律（不走三问对话 / 不让用户凭空填 / 多方向不擅自合并 / 中断必可续）
- **§0a 业务路由扩展**：新增 `creator_mode == 'existing'` 分支，路由到 §0c
- **偏好 bootstrap 协议**：把历史已发视为"隐式选择"，封顶 `total_choices=50` 预留学习空间

### ✋ Hands

- **新增脚本**：
  - `scripts/import-existing.sh` — 批量导入历史帖，带 `--limit / --batch-size / --dry-run / --resume / --override-quota / --mock`，节流遵守 `v1-conservative` profile
  - `scripts/audit-report.sh` — 账号体检报告生成器，纯 SQL 统计 + jq 组装 JSON，8 维度
- **DB schema 扩展**：
  - `posts` 表新增 `source` 字段（`shuling` / `imported` / `manual`，默认 `shuling`）；新增 `idx_posts_source` 和 `idx_posts_note_id` 索引
  - 新增 `historical_stats` 表（账号快照纵向趋势）+ `idx_hstats_snapshotted_at` 索引
  - `posts` 的 `add-post` 现在支持 `source` + `published_at` 字段，对 `source=imported` + `note_id` 做幂等 upsert
- **db.sh 新增命令**：
  - `db.sh add-historical-stat '<json>'`
  - `db.sh query-historical-stats [--limit N]`
  - `db.sh update-post-meta '<json>'`（给 AI 分类 imported 帖子后回写三维分类）
  - `db.sh query-posts --source <shuling|imported|manual>` 按来源过滤
- **新增 schema**：`schemas/audit-report.schema.json`（约束 audit-report.sh 输出 + AI `ai_narrative` 写入契约）
- **state.schema.json 扩展**：新增 `creator_mode` (new/existing/unset) 和 `existing_import_done` 字段
- **install.sh 新增 `--mode`**：支持 `new / existing / existing-creator / ask`；通过 `SHULING_CREATOR_MODE` 环境变量预填；写入每个 target 的 `config/state.json`
- **新增 migration**：`migrations/v2.2.0.sh`（幂等：ALTER posts 加 source + CREATE historical_stats）
- **设计文档**：`docs/features/existing-creator-onboarding.md`（完整 spec，含用户故事 / 数据模型 / 风险矩阵 / 验收标准）

### 🎛 Calib

- `existing_creator_feature: v2.2.0-mvp` — MVP 阶段：MCP `list_feeds` 的用户 feed 拉取需等 xhs.sh 后续迭代暴露，当前可走 `--mock` 路径完整测试
- 老博主 imported posts **不纳入每日复盘**（`§3` 默认 `source='shuling'`），需要时 `audit-report.sh --include-organic`

### ⬆️ 如何升级

```bash
cd /path/to/shuling && git pull
bash install.sh     # v2.2.0.sh migration 自动跑：ALTER posts add source + CREATE historical_stats

# 老博主接入（全新能力）:
bash install.sh --mode=existing-creator
# 或对话里说: "我已经在运营小红书，帮我接入"

# 手动跑核心脚本:
bash scripts/import-existing.sh --limit 200           # 批量导入（~30 分钟）
bash scripts/audit-report.sh --extract-patterns      # 出体检 + patterns 候选
```

**无 breaking**。老用户（新博主）行为完全不变；§0c 是可选分支，仅在 `creator_mode=existing` 时触发。

### 🚧 v2.2.0 MVP 未覆盖（留给后续）

- MCP `list_feeds` 在 xhs.sh 的子命令包装（目前需走 `--mock` 或后续小版本补齐）
- AI 自动分类 imported 帖子的 prompt 模板（SKILL.md §0c 第 3 步，目前靠 AI 按 SKILL.md 描述自由发挥）
- audit-report 的 90 天趋势 PNG（目前只有 markdown 表 + JSON）
- 历史帖改写重发建议脚本 `rewrite-suggest.sh`（Layer 2）
- 竞品横向对标（Layer 3，规划中）

---

## [2.1.3] - 2026-04-21 "Friendly Onboarding"

降低新手门槛 + 拓宽非交互场景 + 给智能体写入协议。

### 📦 用户可见改动
- **`install.sh` 新增 4 个模式**：
  - `--check`：只跑依赖/平台/版本对比，不写任何文件（日常自检）
  - `--dry-run`：列出将要执行的全部动作，不真正执行（升级前预演）
  - `--yes` / `--non-interactive`：跳过所有 prompt，用默认值（CI/远程/cron 场景）
  - `--target <path>`：显式指定部署目标路径（可重复），覆盖默认自动检测
- **`preflight.py --human`**：人类可读的彩色自检输出（依赖状态 + 修复建议 + 下一步）；退出码按严重度分级（0=就绪 / 1=可自修 / 2=需人工）
- **`docs/mcp-setup.md` 重写**：
  - 补源码编译（Go）+ Release 二进制 + Docker 三种安装路径
  - 加 macOS launchd / Linux systemd 常驻服务配置
  - Cookie 提取图文指引（哪个面板、哪个请求、复制哪段）
  - 常见错误自检对照表
- **README 顶部版本徽章升级到 v2.1.3**

### 🧠 Brain
- **SKILL.md 新增 §0b**："识别运行平台 + 写入前校验 schema"——AI 进入项目后先识别平台来源（路径/触发方式），再在写入 state/profile/preferences 前按 schema 核对字段名与类型，杜绝 `created_at`/`createdAt` 漂移、`weight` 越界等退化

### ✋ Hands
- `install.sh` 全面重构：参数解析、run/prompt 包装器、非 TTY 自动 non-interactive、dry-run 全流程覆盖
- `scripts/preflight.py` 新增 `--human` / `--json` / `--no-color` 参数，带退出码
- 新增 `schemas/` 目录：`state.schema.json` / `profile.schema.json` / `preferences.schema.json`（JSON Schema 2020-12），供 AI 智能体写入前自校验
- 新增 `migrations/v2.1.3.sh`（空 migration，纯文档版本留痕）
- 修掉 `install.sh` 依赖检查里 Python 版本显示 bug（曾显示 `Python Python`）
- `RELEASING.md` 检查清单加三项：清理 `scripts/*.bak.*`、跑 `install.sh --check`、跑 `install.sh --dry-run`

### 🎛 Calib
- 非 TTY 环境（cron/ssh 管道/CI）自动进入 non-interactive，不再因 `read -r` 卡死
- install.sh 中 Python 版本显示修复（`awk '{print $2}'`）

### ⬆️ 如何升级
```bash
cd /path/to/shuling && git pull
bash install.sh           # 会识别出 v2.1.2 → v2.1.3 并跑 v2.1.3.sh（无实际 DB 操作）

# 新能力体验
bash install.sh --check                 # 纯自检
python3 scripts/preflight.py --human    # 彩色健康检查
```
无 breaking。**自动化/CI 用户现在可以安全地跑** `SHULING_ASSUME_YES=1 bash install.sh`。

---

## [2.1.2] - 2026-04-21 "Release Polish"

版本管理与用户文档专项，让升级/借鉴/贡献有据可依。

### 📦 用户可见改动
- 新增 `UPGRADE.md`：每版本升级步骤、新增环境变量、是否有 breaking
- 新增 `RELEASING.md`：未来发版 SOP（版本号决策树、commit/tag/release 模板）
- `README.md` 顶部露出当前版本、升级入口、环境变量参考表
- `install.sh` 升级模式：自动识别已部署版本，按需跑 `migrations/vX.Y.Z.sh`
- `VERSION` 新增 `breaking_change_policy` 字段，明文说明三段版本号的破坏性承诺

### ✋ Hands
- `install.sh` 新增版本对比 + migration 调度逻辑（幂等）
- 新增 `migrations/` 目录及 `v2.1.1.sh`（补建 `request_log` 表）

### 🎛 Calib
- 文档工程规范固化：所有未来发版必经 RELEASING.md SOP
- README 加版本徽章占位（从 VERSION 读取）

### ⬆️ 如何升级
```bash
cd /path/to/shuling && git pull
bash install.sh   # 自动检测并补齐 request_log 表（如还没建）
```
无 breaking。无需手动动作。

---

## [2.1.1] - 2026-04-21 "Request Log"

观测先行，为 v2.2.0 Human Rhythm 量化效果提供数据基础。

### 📦 用户可见改动
- 每次调用小红书（搜索/详情/发布等）会自动留下一条日志记录
- 新命令 `bash scripts/xhs.sh log` 随时查看最近调用（含耗时、状态、错误提示）
- 可以用 `bash scripts/xhs.sh log --summary` 看每个接口的成功率和平均延迟
- 默认开启，不想记录可设 `XHS_DISABLE_LOG=1`

### ✋ Hands
- `scripts/db.sh` 新增 `request_log` 表（called_at / tool / status / latency_ms / error_hint / session_tag / args_preview），附三个常用索引
- `scripts/db.sh` 新增 `add-request-log` / `query-request-log` 子命令（支持 `--summary` 聚合，按 tool × status × 平均/最大延迟）
- `scripts/xhs.sh` 注入请求日志：每次 MCP 调用异步写入一条记录，覆盖状态 `ok / error / quota_block / session_refresh / mcp_unavailable`；DB 故障时静默忽略，不影响主流程
- `scripts/xhs.sh` 新增 `log [--summary] [--days N] [--tool T] [--status S] [--limit N]` 子命令
- `check_quota` 改为 `return` 而非 `exit`，使 quota_block 事件可被日志捕获

### 🎛 Calib
- 新增环境变量 `XHS_DISABLE_LOG=1`（默认开启）
- observability profile: `request-log-v1`

### ⬆️ 如何升级
```bash
cd /path/to/shuling && git pull
bash scripts/db.sh init       # 补建 request_log 表（幂等）
```

### 💡 为什么先出这个
下个版本 v2.2.0 (Human Rhythm) 计划加行为节奏模拟 + 话题窗口冷却 + 冷启动重构。没有这张 `request_log` 表，这些优化的效果**不可量化**，相当于盲飞。此版本是 2.2.0 的必要前置。

---

## [2.1.0] - 2026-04-21 "Anti-Ban Shield"

风控加固版本，堵上 xhs.sh 零节流的最大血口。

### 📦 用户可见改动
- **每次调小红书接口不再瞬发**：接口之间自动拉开时间间隔（最短 10s，发布类 300s）
- **每天调用次数有上限**：搜索 15 次/日、详情 50 次/日、发布 2 次/日、评论 5 次/日（触顶自动拒绝）
- 新命令 `bash scripts/xhs.sh quota` 查看当日各接口调用计数
- 新脚本 `scripts/fetch-post-data.sh`：一次调用同时拿数据+评论，替代原来的两次调用
- 预期收益：日均 HTTP 请求 **-75%**，选题窗口调用 **-85%**

### ✋ Hands
- `scripts/xhs.sh` 注入分级节流：每接口独立 MIN_GAP + ±30% 抖动
- `scripts/xhs.sh` 注入日限额保险丝：按接口设当日硬上限，触顶退出
- `scripts/xhs.sh` 新增 `quota` 子命令：查看当日调用计数
- `scripts/xhs.sh` Session 复用能力（opt-in，`XHS_REUSE_SESSION=1` 启用；现场实测 xiaohongshu-mcp 服务端 session 2-3 次后失效，默认关闭等上游修复）
- 新增 `scripts/fetch-post-data.sh`：合并 fetch-metrics + fetch-comments，单次 detail 调用同时提取 metrics 和 comments，HTTP 请求减半
- 保留 `fetch-metrics.sh` / `fetch-comments.sh` 向后兼容，自动继承节流+限额

### 🎛 Calib
- 节流 profile `v1-conservative`:
  - search_feeds: 20s / get_feed_detail: 10s / list_feeds: 15s
  - publish_content: 300s / post_comment_to_feed: 180s / user_profile: 30s
  - check_login_status / get_login_qrcode / import_cookie: 0（本地态）
- 日限额 profile `v1-conservative`:
  - search_feeds: 15/日 / get_feed_detail: 50/日 / list_feeds: 20/日
  - publish_content: 2/日 / post_comment_to_feed: 5/日 / user_profile: 20/日
- 新增环境变量开关：`XHS_DISABLE_THROTTLE` / `XHS_DISABLE_QUOTA` / `XHS_REUSE_SESSION` / `XHS_SESSION_TTL` / `XHS_CACHE_DIR`

### ⬆️ 如何升级
```bash
cd /path/to/shuling && git pull
# 无 DB 迁移，无需手动动作；节流/限额立即生效
```

**提醒**：本版本**默认开启**节流和限额。嫌慢可设 `XHS_DISABLE_THROTTLE=1`，但**账号安全自理**。

### 📝 Notes
- 状态文件存于 `$HOME/.cache/shuling/`（mcp-session、mcp-quota.json、last-<tool>）
- 回滚：`cp scripts/xhs.sh.bak.<timestamp> scripts/xhs.sh`

---

## [2.0.0] - 2026-04-17 "Skill-as-Brain"

架构级重构：从 OpenClaw + Python workflow 双线架构 → SKILL.md 单线架构。

### 📦 用户可见改动
- **换 AI 平台无需改代码**：只要平台能读 SKILL.md，就能无缝迁移（Hermes / Claude Code / Codex）
- **流程修改门槛降至零**：改 SKILL.md 即可，不用碰 Python
- 选题、起稿、复盘、自进化全部由 AI 推理完成，不再依赖 Python "思考"
- 首次接入两阶段封面参考出图（先封面 → 内容页参考封面）
- 首次接入 RedInk 风格创作流程（先大纲 6-9 页 → 后文案）
- 首次接入贝叶斯 + ε-greedy 的偏好学习
- 首次接入 NoteRx 第三方五维诊断 API

### 🧠 Brain
- 核心定位改写：SKILL.md 即大脑（1040 行），承载全部业务逻辑
- 选题/起稿/复盘/自进化全部由 LLM 推理，不再依赖 Python 脚本做决策
- 第 2.2 节升级到 RedInk 风格：先大纲（6-9 页，每页配图提示）后文案
- 第 2.3 节明确两阶段封面参考出图（先封面 → 内容页 --reference 封面）
- 第 4.1 节偏好学习公式升级：贝叶斯拉普拉斯平滑 + 集中度 × 样本系数 confidence + ε-greedy 7 天探索窗口
- 新增模式生命周期：experimental → medium → high / deprecated（与 anti-patterns.md 联动）
- 接入 NoteRx 第三方五维诊断 API

### ✋ Hands
- scripts/ 重写：db.sh 结构化 CLI、xhs.sh 统一 MCP 入口
- DB 扩展到 7 张表（posts / post_metrics / user_choices / topic_candidates / comment_insights / note_diagnosis / generated_images）
- 图像生成默认切到 gemini-3-pro-image-preview（Nano Banana Pro，中文渲染更稳）
- 平台适配器抽象：hermes（cron）/ claude-code（/loop）/ codex

### 🎛 Calib
- 合规规则初版（`data/content-rules.md`）
- emoji 词典 v1
- 废弃 `docs/capability-overview.md`（单线架构下不再适用）

### ⬆️ 如何升级
**这是 breaking change**。v1.x → v2.0.0 是一次性硬切：

```bash
# 备份
cp -r data/xhs.db data/xhs.db.bak.$(date +%Y%m%d)
cp -r knowledge-base knowledge-base.bak.$(date +%Y%m%d)

# 切换
git checkout v2.0.0
bash install.sh
```

后续 v2.x 保持兼容。

---

## 版本路线图（参考）

- **v2.2.0**（下一版，codename 候选 "Human Rhythm"）：行为节奏模拟（昼夜节律 + burst/break）、话题窗口批处理 + 冷却、冷启动路径重构；全部走 opt-in 开关，默认关闭
- **v2.3.x**（规划中）：异常信号监听 + 自动熔断；MCP session 持久化（等上游 xpzouying 修复）
- **v3.0.0**（远期）：接入视频笔记能力 / 多账号灰度架构
