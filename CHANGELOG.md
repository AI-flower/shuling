# Changelog

本项目版本号遵循 **BRAIN.HANDS.CALIB** 三段语义（见 `VERSION`）。
变更按以下类别归档：

- **Brain**: SKILL.md 核心流程重构、自进化算法换代、业务能力跃迁
- **Hands**: scripts/ 新增或重写、DB schema 迁移、MCP 接口替换、平台适配器
- **Calib**: 阈值/关键词/节流参数调整、bugfix、prompt 微调

---

## [2.1.1] - 2026-04-21 "Request Log"

观测先行。为后续节奏模拟 + 话题冷却铺路，先把 MCP 调用完整落表以便量化效果。

### Hands
- `scripts/db.sh` 新增 `request_log` 表（called_at / tool / status / latency_ms / error_hint / session_tag / args_preview），附三个常用索引
- `scripts/db.sh` 新增 `add-request-log` / `query-request-log` 子命令（支持 `--summary` 聚合，按 tool × status × 平均/最大延迟）
- `scripts/xhs.sh` 注入请求日志：每次 MCP 调用异步写入一条记录，覆盖状态 `ok / error / quota_block / session_refresh / mcp_unavailable`；DB 故障时静默忽略，不影响主流程
- `scripts/xhs.sh` 新增 `log [--summary] [--days N] [--tool T] [--status S] [--limit N]` 子命令，一步查日志
- `check_quota` 改为 `return` 而非 `exit`，使 quota_block 事件可被日志捕获

### Calib
- 新增环境变量 `XHS_DISABLE_LOG=1` 提供临时关闭开关（默认开启）
- observability profile: `request-log-v1`

### 为什么先出这个
下个版本 v2.2.0 (Human Rhythm) 计划加行为节奏模拟 + 话题窗口冷却 + 冷启动重构。没有这张 `request_log` 表，这些优化的效果**不可量化**，相当于盲飞。此版本是 2.2.0 的必要前置。

---

## [2.1.0] - 2026-04-21 "Anti-Ban Shield"

风控加固版本，堵上 xhs.sh 零节流的最大血口。

### Hands
- `scripts/xhs.sh` 注入分级节流：每接口独立 MIN_GAP + ±30% 抖动
- `scripts/xhs.sh` 注入日限额保险丝：按接口设当日硬上限，触顶退出
- `scripts/xhs.sh` 新增 `quota` 子命令：查看当日调用计数
- `scripts/xhs.sh` Session 复用能力（opt-in，`XHS_REUSE_SESSION=1` 启用；现场实测 xiaohongshu-mcp 服务端 session 2-3 次后失效，默认关闭等上游修复）
- 新增 `scripts/fetch-post-data.sh`：合并 fetch-metrics + fetch-comments，单次 detail 调用同时提取 metrics 和 comments，HTTP 请求减半
- 保留 `fetch-metrics.sh` / `fetch-comments.sh` 向后兼容，自动继承节流+限额

### Calib
- 节流 profile `v1-conservative`:
  - search_feeds: 20s / get_feed_detail: 10s / list_feeds: 15s
  - publish_content: 300s / post_comment_to_feed: 180s / user_profile: 30s
  - check_login_status / get_login_qrcode / import_cookie: 0（本地态）
- 日限额 profile `v1-conservative`:
  - search_feeds: 15/日 / get_feed_detail: 50/日 / list_feeds: 20/日
  - publish_content: 2/日 / post_comment_to_feed: 5/日 / user_profile: 20/日
- 新增环境变量开关：`XHS_DISABLE_THROTTLE` / `XHS_DISABLE_QUOTA` / `XHS_REUSE_SESSION` / `XHS_SESSION_TTL` / `XHS_CACHE_DIR`

### Notes
- 状态文件存于 `$HOME/.cache/shuling/`（mcp-session、mcp-quota.json、last-<tool>）
- 预期收益：日均 HTTP 请求 -75%，选题窗口调用 -85%，冷启动 -70%
- 回滚：`cp scripts/xhs.sh.bak.20260421_023540 scripts/xhs.sh`

---

## [2.0.0] - 2026-04-17 "Skill-as-Brain"

架构级重构：从 OpenClaw + Python workflow 双线架构 → SKILL.md 单线架构。

### Brain
- 核心定位改写：SKILL.md 即大脑（1040 行），承载全部业务逻辑
- 选题/起稿/复盘/自进化全部由 LLM 推理，不再依赖 Python 脚本做决策
- 第 2.2 节升级到 RedInk 风格：先大纲（6-9 页，每页配图提示）后文案
- 第 2.3 节明确两阶段封面参考出图（先封面 → 内容页 --reference 封面）
- 第 4.1 节偏好学习公式升级：贝叶斯拉普拉斯平滑 + 集中度 × 样本系数 confidence + ε-greedy 7 天探索窗口
- 新增模式生命周期：experimental → medium → high / deprecated（与 anti-patterns.md 联动）
- 接入 NoteRx 第三方五维诊断 API

### Hands
- scripts/ 重写：db.sh 结构化 CLI、xhs.sh 统一 MCP 入口
- DB 扩展到 7 张表（posts / post_metrics / user_choices / topic_candidates / comment_insights / note_diagnosis / generated_images）
- 图像生成默认切到 gemini-3-pro-image-preview（Nano Banana Pro，中文渲染更稳）
- 平台适配器抽象：hermes（cron）/ claude-code（/loop）/ codex

### Calib
- 合规规则初版（`data/content-rules.md`）
- emoji 词典 v1
- 废弃 `docs/capability-overview.md`（单线架构下不再适用）

---

## 版本路线图（参考）

- **v2.2.0**（下一版，codename 候选 "Human Rhythm"）：行为节奏模拟（昼夜节律 + burst/break）、话题窗口批处理 + 冷却、冷启动路径重构；全部走 opt-in 开关，默认关闭
- **v2.3.x**（规划中）：异常信号监听 + 自动熔断；MCP session 持久化（等上游 xpzouying 修复）
- **v3.0.0**（远期）：接入视频笔记能力 / 多账号灰度架构
