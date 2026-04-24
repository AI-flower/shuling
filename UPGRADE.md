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
**Breaking**：**有** —— 之前靠 HTML 截图兜底的部署必须配置图片 API Key

**变化**：
- HTML 截图降级路径完全删除（`scripts/screenshot.cjs` / `templates/post.html` 移除）
- 图片 API Key 从可选变必需，且必须先固定选择 Gemini 原生或 OpenAI 兼容其中一种
- `scripts/image.py` 重写：`render_prompt()` 模板系统 + `--reference` 封面回流 + `--short` 极简 fallback
- 新增 `prompts/image_prompt.txt` / `prompts/image_prompt_short.txt` 中文模板
- `generated_images.prompt` 字段改为存 `page_content` 短语义（节省空间 + 便于 pattern 学习）

**升级动作**：

```bash
cd /path/to/shuling && git pull
bash install.sh     # 会强制问图片 API Key（老安装已配则不问）

# 预检
python3 scripts/image.py --check    # 返回 0 才能继续
```

**兼容性说明**：
- 老部署若未配图片 API Key：发帖流程 §2.3 会硬停，按提示补配
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
| `IMAGE_GEN_PROTOCOL` | 空 | 非交互模式下固定图片 API 类型：`gemini-native` 或 `openai-images` |
| `GEMINI_API_KEY` | 空 | 非交互模式下预填 Gemini 原生图片 Key，避免被 prompt 卡住 |
| `IMAGE_GEN_API_KEY` / `OPENAI_API_KEY` | 空 | 非交互模式下预填 OpenAI 兼容图片 Key |
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
