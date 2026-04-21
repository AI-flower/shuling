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
