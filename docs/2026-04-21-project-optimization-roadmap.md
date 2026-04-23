---
title: 薯灵项目侧优化路线图
status: draft
created: 2026-04-21
audience: agent  # 使用方与执行方均为 AI agent
scope: project-infrastructure  # 仅工程/架构侧，不含业务规划
current_version: v2.3.0
---

# 薯灵项目侧优化路线图

> 本文档基于 2026-04-21 实际代码扫描、git log、目录实察产出。
> **只讲项目工程与架构**，不含业务能力（内容创意 / 流量 / 归因 / 变现）规划。
> 业务侧路线图需另起文档。

---

## 零、扫描基线（2026-04-21）

以下是得出本路线图的事实依据：

| 事实 | 值 |
|---|---|
| VERSION | v2.3.0（Pure Image Pipeline） |
| Git tags | v2.0.0 → v2.3.0 共 8 个 |
| Git 工作区 | **脏**：`README.md` / `landing/index.html` modified；`docs/agent-upgrade-design.md` untracked |
| SKILL.md 行数 | **1208** 行 / 54KB |
| scripts/db.sh | **650** 行 Bash |
| scripts/xhs.sh | 502 行 Bash |
| scripts/image.py | 526 行 Python |
| scripts/preflight.py | 391 行 Python |
| install.sh | 487 行 Bash |
| migrations/ 文件 | v2.1.1 / v2.1.2 / v2.1.3 / v2.2.0 —— **v2.2.1、v2.3.0 完全缺失** |
| schemas/ 文件 | state / profile / preferences / audit-report 四个 |
| knowledge-base/ 目录 | **源码仓库是空的**（可能是 .gitignore，但运行时状态未验证） |
| 遗留杂物 | `scripts/image.py.bak`、`SKILL.md.bak`、根目录 `.session-recorder/`、`landing/` |
| 依赖锁定 | 无 `requirements.txt` / `pyproject.toml` / `package.json` / `go.mod` |
| 测试 | 无 `tests/` 目录，650 行 Bash 零测试 |
| 悬挂 checkbox | superpowers/plans/ 3 份合计 150 个 + self-evolution-plan 45 个 = **195 个未回勾** |

---

## 一、顶层原则

1. **业务已稳，瓶颈在工程**：v2.0-v2.3 把核心能力搭完，当前每次发版的真实成本在基础设施（本次升级 agent 手推 9 步是直接证据）
2. **项目形态特殊**：使用方 + 升级执行方都是 AI agent，优化原则是 **agent-friendly**（JSON / 幂等 / 零对话依赖），而非 human-friendly
3. **先修已坏，再建未来**：本文档 P0 项**全部是在修已存在但没被发现的问题**，不是加新能力
4. **红线**（三条强约束）：
   - A3（自进化闭环健康度）**必须先于**任何新基础设施——否则是装修没人住的房子
   - B1/B2/B3 **必须捆绑做**——拆分成三次发版会制造更多 drift
   - A1（SKILL.md 瘦身）**必须先于**向 SKILL.md 加新内容——否则 token 成本线性恶化

---

## 二、诊断分类总览

优化项按主题分 5 组，共 16 项：

| 组 | 主题 | 项数 | 核心问题 |
|---|---|---|---|
| A | 架构重量级 | 3 | SKILL 膨胀 / db.sh 臃肿 / 自进化闭环真实性 |
| B | 升级与发版基础设施 | 4 | migrations 缺口 / 幂等性 / upgrade-hooks / install.sh 边界 |
| C | 可观测性 / 测试 / 诊断 | 4 | 日志 / smoke / schema drift / 三平台回归 |
| D | 工程卫生 | 5 | 文档组织 / 杂物 / git 清洁 / 依赖锁定 / 备份 |
| E | 代码质量 | 2 | ShellCheck / 命名（其中一项判定"不做"） |

每项均按 **说明 → 要不要做 → 怎么做 → 提升** 展开。

---

## 三、A 组 · 架构重量级问题

### A1. SKILL.md 瘦身（1208 行 → 拆分）

**说明**
SKILL.md 是 AI 每次启动都要完整读取的唯一 source of truth。54KB 单文件里混着：
业务路由 §0a / 冷启动 §0b / 老博主接入 §0c / 核心流程 §1-§8 / 状态表 / 错误码 / 平台差异分支 / 升级指引。

**要不要做 — 要，P1**
不是洁癖，是 **token 成本**：
- 三平台每次 skill load 都读全文
- 1208 行 × 4 token/行 ≈ 5000 token/次 load
- hermes cron 每天 5 次 + 对话启动 3 次 ≈ 8 × 5000 = 4 万 token / 日 / target × 2 target = **8 万 token / 日纯 overhead**
- 月 overhead ≈ 240 万 token，折算成 API 成本是**每月数美元起的白烧**

**怎么做**
1. 拆成两层：
   - 主干 `SKILL.md` ≤ 300 行：只留业务路由 §0a + 关键状态机 + 章节索引 + **唯一路由表**
   - 章节外置到 `skill-chapters/`（例：`§2-creation.md` / `§4-preferences.md` / `§0c-existing-creator.md`）
2. 主干用相对链接指向章节，显式声明"只有执行到这一步才读对应章节"
3. 错误码表、emoji 词典等**数据**移到 `data/` 或 `schemas/`
4. 验证方式：
   - 观察 token 账单变化
   - 验 AI 仍能正确路由（路由逻辑留主干）
   - smoke test 跑一遍 §0a/b/c 所有入口

**提升**
- 每次 skill load token 成本 **降 60-70%**
- SKILL.md review 成本骤降（review 200 行 vs 1200 行）
- 未来多平台差异化有地方放（`§0a-hermes.md` / `§0a-codex.md`）

**风险与对策**
- 破坏 "single source of truth" → 主干保持**唯一路由表**，章节不允许独立做路由决策
- AI 读章节顺序错误 → 路由表里每步显式给出"下一步该读哪个章节"

---

### A2. `scripts/db.sh` 650 行 Bash → Python 重写

**说明**
650 行 Bash 做 SQLite 封装，涵盖表初始化、多表 CRUD、报表查询、备份/恢复。Bash 在这个规模已明显超出表达力，git log `dfdd1b2` 出现过 awk 引号问题即是信号。

**要不要做 — 要，P3（按需）**
当前不是立刻痛点，但**长期地雷**：每次加字段都可能踩引号转义。等下一次需要大改 db（比如 v2.4.x 新表）时顺手迁移，不为迁移而迁移。

**怎么做**
1. 新写 `scripts/db.py`（用 Python 3 标准库 sqlite3 + argparse）
2. 保留 `scripts/db.sh` 作为 shim 调用 `db.py`，零破坏切换
3. 所有调用方逐步改直调 `db.py`，最终删除 shim
4. SQL 拼接全部参数化（顺便**修潜在 SQL 注入**）

**提升**
- 650 行 Bash → ~350 行 Python，可读性质变
- 给 db 加单测成为可能（见 C2）
- SQL 注入风险从"存在" → "不存在"

**风险**
- 调用方较多（xhs.sh / 各 fetch-*.sh / audit-report.sh / import-existing.sh / review 相关），需要一次性批量改

---

### A3. knowledge-base/ 空 → 自进化闭环真实性验证 🚨

**说明**
刚才 `ls knowledge-base/` 发现目录**是空的**。这意味着可能的三种情况：
1. 源码仓库空是 .gitignore 所致，target 上有运行时产物（正常）
2. target 上也是空，冷启动播种**从未触发**（严重）
3. 冷启动触发过但失败，静默吞错（中等）

无论哪种，`research.py` / `create_content.py` 的"读知识库注入 prompt"若拿不到数据会走 fallback，**整个 v2.3.0 自进化系统在生产中可能是 dead code**。

**要不要做 — 必做，P0，最高优先级**
这不是"优化"，是**诊断可能的 bug**。所有其他 infra 都建立在"自进化在跑"这个假设上。

**怎么做（诊断顺序）**
1. **第一步 SSH 验证**：
   ```bash
   for t in ~/.codex/skills/shuling ~/.hermes/skills/social-media/shuling ~/.claude/skills/shuling; do
     echo "=== $t ==="
     [ -d "$t/knowledge-base" ] && ls -la "$t/knowledge-base/" || echo "NOT EXIST"
   done
   ```
2. **根据结果分支**：
   - 情况 1（正常）：只需补 `scripts/kb-health.sh` 监控 patterns 数量、最近 review 日期、规则版本
   - 情况 2（从未触发）：查 SKILL.md 冷启动触发条件为什么没满足；**人工触发一次**冷启动播种
   - 情况 3（触发失败）：查 LLM 调用失败日志（如果存在——结合 C1 日志改造项）
3. 补一个 `install.sh doctor` 的前身：`kb-health.sh` 独立跑，吐 JSON 状态报告

**提升**
- 把文档自称的能力变成**真在运行**的能力
- 发现是"没触发"还是"触发了失败"，修法完全不同
- **这一项做完之前，任何后续 infra 投入都是在装饰不工作的系统**

---

## 四、B 组 · 升级与发版基础设施

### B1. migrations/ 补齐 v2.2.1 / v2.3.0 空壳

**说明**
刚才 `ls migrations/` 只有 v2.1.1 / v2.1.2 / v2.1.3 / v2.2.0——**v2.2.1 和 v2.3.0 的 migration 文件根本不存在**。
按 `docs/agent-upgrade-design.md` 原则"哪怕本版无 DB 变化也放空壳脚本占位"，必须补。

**要不要做 — 立刻做，P0，10 分钟成本**
这是一个**此刻就能修**的具体问题，不是规划。

**怎么做**
```bash
cd /Users/weiyong/Documents/10/shuling

for v in 2.2.1 2.3.0; do
  cat > migrations/v${v}.sh <<EOF
#!/usr/bin/env bash
# v${v}: 无 DB 变更占位（保持版本线连续）
echo '{"status":"skipped","reason":"no_schema_change","version":"${v}"}'
exit 0
EOF
  chmod +x migrations/v${v}.sh
done

# RELEASING.md 新增一条规则：每个 tag 必须有对应 migration 文件，即使是空壳
```

**提升**
- `migrations/` 目录变成**版本真相表**：看目录就知道发过哪些版本
- 未来 `install.sh upgrade-all` 可以纯按目录遍历跑 migration，不需另维护 version 列表

---

### B2. `__migrations` 表 + 存量脚本幂等化

**说明**
刚才实察四个 migration 脚本（v2.1.1:40 行、v2.1.2:5 行、v2.1.3:10 行、v2.2.0:44 行），**全部直接跑 sqlite3，无任何"已 applied 判断"**。重跑会对非幂等的 DDL 报错。

**要不要做 — 必做，P0**
所有后续 upgrade infra 的基础。没有这个，`upgrade-all` 没法安全重试。

**怎么做**
1. 建 `migrations/_applied_table.sql`：
   ```sql
   CREATE TABLE IF NOT EXISTS __migrations (
     version TEXT PRIMARY KEY,
     applied_at TEXT NOT NULL DEFAULT (datetime('now'))
   );
   ```
2. 写 `migrations/_guard.sh` 公共库：
   ```bash
   already_applied() {
     local v="$1"
     [ "$(sqlite3 "$DB" "SELECT 1 FROM __migrations WHERE version='$v'")" = "1" ]
   }
   mark_applied() {
     sqlite3 "$DB" "INSERT OR IGNORE INTO __migrations(version) VALUES('$1')"
   }
   ```
3. 四个存量脚本顶部 source guard，首次 applied 后写入 `__migrations`
4. 新写的 v2.2.1 / v2.3.0 空壳也 source 同一 guard
5. 给 v2.4.0 新 migration 做模板：`source _guard.sh → already_applied && exit 0 → ... → mark_applied`

**提升**
- 重跑 migration 安全 → agent 可无脑重试
- 升级失败恢复清晰 → 看 `__migrations` 表差集即知道卡在哪

---

### B3. `upgrade-hooks/v2.3.0/` 三 hook 固化本次踩的坑

**说明**
2026-04-21 本次 v2.2.1→v2.3.0 升级，agent 手工做了三件事（见 `agent-upgrade-design.md`）：
1. `runtime-env-sync.sh`：新增 `IMAGE_GEN_*` 四字段跨 target 借用
2. `preferences-structure-migrate.sh`：topic_preferences → dimensions.topic schema 迁移
3. `scheduler-prompt-update.sh`：`jobs.json` 里过时的"HTML 截图"描述替换成"Gemini 生图"

这些都是 DB 和代码之外的副作用，不固化下次还会踩。

**要不要做 — 必做，P0，捆绑 B2 一起上**
这次踩过的坑不固化，下次升级还要 agent 手工推理。

**怎么做**
1. 建目录 `upgrade-hooks/v2.3.0/`，放上述三个 hook 脚本
2. 每个 hook 契约：
   - 幂等（先探测状态，已处理则 skip）
   - 输入/输出均 JSON：`{"status":"ok|skipped|failed","detail":"..."}`
   - 不做任何"让 agent 推理"的事
3. `upgrade-hooks/v2.3.0/README.md` 写清"为什么 v2.3.0 需要这三个 hook"——给未来 agent 看
4. 为 v2.4.0 发版定规矩：新 breaking/新副作用 → 对应 hook 必须同 PR 提交

**提升**
- 升级副作用从 agent 脑袋里搬进仓库 → **可审计**
- 跨多版本升级（v2.1 → v2.5）可按版本线性跑完所有 hook，不会漏

---

### B4. `install.sh upgrade-all --json` + 自动扫描 targets

**说明**
当前 `install.sh` 487 行已含 install/upgrade/check/dry-run/creator-mode 五子命令。
本次升级 agent 手推 9 步，其中第 2 步 rsync、第 3-4 步 migration、第 5-6 步 runtime.env、第 7 步 preferences、第 8 步 scheduler prompt、第 9 步 preflight，都该一条命令搞定。

**要不要做 — 要，P0-**，紧随 B2/B3
是 B1+B2+B3 的**聚合器**。没有它，agent 还是要手串三套命令。

**怎么做**
1. 先做 `--dry-run`（吐计划不执行），低风险验证设计
2. 自动扫描 targets：`discover_targets()` glob 扫
   - `~/.codex/skills/*`
   - `~/.hermes/skills/**`
   - `~/.claude/skills/*`
   - 识别条件：目录内有 `VERSION` + 顶层有 `SKILL.md`
3. 输出契约按 agent-upgrade-design.md 已定的 JSON schema：
   ```json
   {
     "overall": "success",
     "targets": [
       {
         "name": "...",
         "path": "...",
         "from_version": "...",
         "to_version": "...",
         "steps": [{"id": "...", "status": "ok|skipped|failed", ...}]
       }
     ]
   }
   ```
4. 兜底：扫描结果可写入 `~/.shuling/targets.yaml`，下次不扫；用户可手动编辑
5. `install.sh 487 行 → 会到 ~700 行`：同时做 B5 的拆分门槛

**提升**
- 升级入口 N 条命令 → 1 条
- Agent 的 preflight / migrate / hook 三阶段统一模型
- 多 target 从"串行 18 步" → "并行 2 条命令"

**不做的子项**
- **TARGETS.yaml 显式登记**：自动扫描已够，YAML 作为兜底不作主要入口
- **install.sh doctor 独立命令**：先给 preflight 加 `--json`，观察 3 个月再决定要不要独立 doctor

---

## 五、C 组 · 可观测性 / 测试 / 诊断

### C1. 脚本级结构化 JSON 日志

**说明**
当前 11 个脚本各自 echo/print 到 stdout+stderr，无统一格式。cron 失败时 debug 要翻 hermes 日志、cron log、脚本输出——**无中心化视角**。

**要不要做 — 要，P2**
upgrade infra 做完后，下一瓶颈就是"发生问题时如何快速定位"。没有统一日志 = 每次 debug 从零。

**怎么做**
1. 建 `scripts/lib/log.sh` 和 `scripts/lib/log.py`：
   ```bash
   log_json() {
     local level="$1" stage="$2" event="$3" ctx="${4:-{}}"
     echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"target\":\"${TARGET:-unknown}\",\"level\":\"$level\",\"stage\":\"$stage\",\"event\":\"$event\",\"ctx\":$ctx}" >> "$LOG_FILE"
   }
   ```
2. 所有脚本 source 该库，输出到 `data/logs/YYYY-MM-DD.jsonl`
3. 日志字段标准化：`{ts, target, stage, level, event, context}`
4. `scripts/logs.sh tail | grep | since` 本地查询

**提升**
- Debug 从"翻三处" → "jq 一文件"
- 可统计：脚本失败率 / 平均耗时 / cron 触发 vs 实际执行差集
- JSONL → 任何监控系统都能吃，为未来 CI/监控铺路

**成本**：约 1 天，但所有脚本都要过一遍

---

### C2. Smoke test / 回归测试

**说明**
无 `tests/` 目录。11 个脚本零测试，每次发版靠 preflight + 手工验证。

**要不要做 — 要，P2，分步**
从零到单测太重。**先做 smoke**（能跑/参数错误报错/输出可解析），成本低覆盖 60%。

**怎么做（三步走）**
1. **第一步（1 天）**：`tests/smoke/` 每脚本一个 `test_xhs.sh` / `test_db.sh`，只测"能跑起来 / 参数错误会报错 / 输出 JSON 可解析"
2. **第二步（2-3 天）**：关键路径加 fixture 测试
   - `import-existing.sh --dry-run`
   - `db.sh add-post` + verify
   - `image.py --check`
   - `preflight.py --human/--json`
3. **第三步（按需）**：配合 C1 日志，测试失败直接看 JSONL
4. **不追求覆盖率**：等 upgrade-all 有稳定接口再上更严格测试

**提升**
- 发版前 `bash tests/smoke/all.sh` 替代部分手工
- 重构 db.sh 或拆 SKILL.md 有 safety net
- 降低"小改 cause 大崩"事故率

---

### C3. Schema ↔ DB ↔ state.json drift 校验（激活已有资产）

**说明**
刚才实察 `schemas/` 下已有 5 个 JSON schema 文件：
state / profile / preferences / audit-report。
本次 v2.3.0 升级正是因为 preferences.json 不符合 schema 手动重置的。
**当前没有任何机制在使用这些 schema 校验**。

**要不要做 — 要，P1，零成本激活**
典型的"有基础设施没利用"，最低垂果实。

**怎么做**
1. 建 `scripts/validate.py`（或 `validate.sh` 调 `ajv-cli`），读 `schemas/*.json` 校验对应 runtime 产物
2. `preflight.py` 新增 `check_schemas()`
3. 未来 `install.sh doctor --json` 直接吐 drift 列表
4. **关键**：upgrade-hooks 做 preferences migration 后，必须跑 schema 校验作为 post-condition

**提升**
- 本次 v2.3.0 那种 drift 会**当场被抓**
- schema 变更时自动发现历史 runtime 产物是否需要迁移
- 为多 target 差异化埋桩

---

### C4. 三平台独立 smoke

**说明**
hermes / claude-code / codex 三 target 部署链路不同（skill 加载机制、cron 形态、IM 通道）。升级时手工一个个验。

**要不要做 — 暂不做，P3**
当前 target 少、问题还没真发生。先做 C1-C3 通用层，等 upgrade-all 到位再考虑。

**怎么做（将来）**
每个 target 一个 `targets/{hermes,codex,claude-code}/smoke.sh`，用对应平台能力（cron mock / IM mock / skill-load 模拟）做 E2E。

---

## 六、D 组 · 工程卫生

### D1. docs/ 目录重组 + 195 个悬挂 checkbox reconcile

**说明**
`docs/` 扁平混杂：
- 日期前缀：`2026-04-15-self-evolution-design.md` / `2026-04-15-self-evolution-plan.md`
- 主题平铺：`agent-upgrade-design.md` / `capability-overview.md` / `mcp-setup.md`
- 子目录：`features/` / `superpowers/plans/` / `superpowers/specs/`

**没有一致约定**。`superpowers/plans/` 3 份文件共 150 个未勾 checkbox，`self-evolution-plan.md` 45 个。这些计划日期 04-15/04-17，而项目已到 v2.3.0（04-21）——**195 个 checkbox 状态不明，未来 AI 读到会被误导**。

**要不要做 — 要，P1，0.5-1 天**
低成本高收益，不做的话 AI 每次读文档都被误导。

**怎么做**
1. **约定目录结构**：
   ```
   docs/
     adr/              # 决策记录（替代原 specs/）
     plans/            # 实施计划（带 status frontmatter）
     runbooks/         # 运维手册（mcp-setup 这类）
     reference/        # 长青文档（capability-overview）
     archive/          # 已完成 / 已废弃
   ```
2. **reconcile sprint（半天）**：
   - 四份 plan（3 份 superpowers + self-evolution）逐 task 判定：done / dropped / still-open
   - done / dropped 的整文件移 `archive/`，加 frontmatter `status: archived + superseded-by: ...`
   - 仍 open 的重写为一份干净的 v2.4.0 plan
3. frontmatter 加 `status: active | archived | superseded-by`
4. 项目根加 `docs/README.md` 做 index

**提升**
- AI 读文档"误导率"清零
- 新 plan 有固定位置
- `git blame` 查决策历史更直接

---

### D2. 清理杂物 + .gitignore 更新

**说明**
- `scripts/image.py.bak` 遗留
- `SKILL.md.bak` 根目录遗留
- `.session-recorder/` 在根目录（工具副产物不该在这里）
- `landing/` 产品官网和代码耦合

**要不要做 — 要，P1，10 分钟**
纯卫生问题。

**怎么做**
1. **`.bak` 文件**：删掉（备份应该 git 或 external backup，不是 `.bak`）
2. **`.session-recorder/`**：如果是工具副产物 → 加 `.gitignore`；如果是项目依赖 → 移 `tools/` 下
3. **`landing/`**：产品官网应该独立仓库。暂不拆也要**在 install.sh rsync 明确 `--exclude landing`**，避免被 rsync 到 target
4. `.gitignore` 加规则：`*.bak` `*.old` `*-backup-*`
5. 验证：`git status` 清洁 + install.sh dry-run 不提到 landing

**提升**
- 新 AI 读项目不被 `.bak` 误导
- 部署 rsync 不误传 landing（省带宽，隔离边界）

---

### D3. git 工作区清洁（此刻动作）

**说明**
刚才 `git status` 显示：
```
 M README.md
 M landing/index.html
?? docs/agent-upgrade-design.md
```
v2.3.0 刚发完，工作区不应该还有未提交改动。

**要不要做 — 立刻做，P0**
此刻任务，不是规划。

**怎么做**
1. `docs/agent-upgrade-design.md` 有设计价值 → commit 到 main
2. `README.md` / `landing/index.html` 看 diff 决定：有意义就 commit，无意义就 revert
3. `RELEASING.md` 加一条规则：**发版 SOP 最后一步 `git status` 必须为空**

**提升**
- 发版后仓库清洁 = 下次 agent 接手时起点明确
- 避免"某次升级后留改动，两周后没人知道属于哪版本"

---

### D4. 依赖锁定（拆时间炸弹）

**说明**
无 `requirements.txt` / `pyproject.toml` / `package.json` / `go.mod`。
image.py / preflight.py / fetch-*.sh 用了什么 Python 包 / 哪个版本，全靠系统 Python 猜。

**要不要做 — 要，P1**
**时间炸弹**。今天 `pip install openai` 默认装最新版，三个月后 API 变了脚本就挂。

**怎么做**
1. `requirements.txt`（最小粒度）：
   - 扫 `image.py` / `preflight.py` / `import-existing.sh` 的 `import` 语句
   - 列出非标准库：`openai` / `anthropic` / `requests` / `jsonschema` 等
   - 加版本范围：`>=X.Y,<X+1.0`（允许 patch 但禁止 major）
2. `install.sh` 安装阶段强制 `pip install -r requirements.txt`
3. **不做 venv**（skill 不是独立 service，系统级 pip 够用）
4. `tools/xhs-downloader/` 若有单独依赖则单独 requirements

**提升**
- 升级依赖地狱从"手工排查" → "pip freeze 自动捕获"
- 多 target 环境一致
- `requirements.txt` 进 git → 依赖变更有 diff 可追溯

---

### D5. 备份清理策略

**说明**
升级留档提到 `.bak-v2.3.0-20260421-190540` 这种备份。多 target × 多次升级会累积。

**要不要做 — 暂不做，P3**
当前 target 机器磁盘充裕（Mac 100.79.106.110），等第一次磁盘告警再做。

**怎么做（将来）**
`install.sh cleanup --keep=3` 只保留最近 3 个备份。加到 cron 每周跑一次。

---

## 七、E 组 · 代码质量

### E1. ShellCheck lint

**说明**
项目里 3 个 500+ 行 Bash（install.sh 487 / db.sh 650 / xhs.sh 502）零 lint。git log `dfdd1b2` 的"修 awk 引号问题"是典型信号。

**要不要做 — 要，P2，0.5 天**
Bash 坑多（未引号变量 / `set -e` 失效场景 / pipe 退出码），不做 lint 就是等 bug。

**怎么做**
1. 加 `scripts/lint.sh`：`shellcheck scripts/*.sh install.sh migrations/*.sh`
2. 修现有 warnings（650 行 db.sh 估计有一堆引号 + SC2086 未引号变量）
3. 加到 smoke test
4. （可选）加 `.shellcheckrc` 配置严格度

**Python lint 可暂缓**（Python 代码量小，且 image.py / preflight.py 明显写得还算规整）。

**提升**
- Bash 常见坑提前暴露
- 本次发版前那种引号问题会被 ShellCheck 抓住

---

### E2. 命名一致性

**说明**
部分统一（`fetch-metrics.sh` / `fetch-comments.sh` / `fetch-post-data.sh`）；
部分不统一（`xhs.sh` / `db.sh` / `image.py` / `noterx-diagnose.sh`）。

**要不要做 — 不做**
改名成本（改所有调用方 + 文档 + install.sh）远大于收益。**接受现状**。

---

## 八、优先级与执行路线图

### 8.1 优先级一览表

| 级别 | 编号 | 项目 | 成本 | 依赖 |
|---|---|---|---|---|
| **P0 立即** | **A3** | knowledge-base 空 → 自进化闭环真实性诊断 | 0.5 天 | 无 |
| **P0 立即** | **B1** | 补 v2.2.1/v2.3.0 migration 空壳 | 10 分钟 | 无 |
| **P0 立即** | **D3** | git 工作区 clean | 10 分钟 | 无 |
| **P0 本周** | **B2** | `__migrations` 表 + 存量脚本幂等化 | 1 天 | B1 先 |
| **P0 本周** | **B3** | upgrade-hooks/v2.3.0/ 三 hook 固化 | 1 天 | B2 先 |
| **P0- 本周** | **B4** | install.sh upgrade-all --json + 自动扫描 | 2 天 | B2/B3 先 |
| **P1 两周** | **A1** | SKILL.md 瘦身拆分 | 2 天 | 无 |
| **P1 两周** | **C3** | Schema drift 校验激活 | 0.5 天 | 无 |
| **P1 两周** | **D1** | docs 重组 + 195 checkbox reconcile | 0.5-1 天 | 无 |
| **P1 两周** | **D2** | 清杂物 + .gitignore | 10 分钟 | 无 |
| **P1 两周** | **D4** | requirements.txt | 0.5 天 | 无 |
| **P2 一月** | **C1** | 脚本级结构化日志 | 1 天 | 无 |
| **P2 一月** | **C2** | Smoke test 骨架 | 1-2 天 | C1 先 |
| **P2 一月** | **E1** | ShellCheck | 0.5 天 | 无 |
| **P3 按需** | **A2** | db.sh → db.py | 3 天 | 下次大改 db 时顺手做 |
| **P3 按需** | **C4** | 三平台独立 smoke | — | target 数量到 5+ 再做 |
| **P3 按需** | **D5** | 备份清理策略 | — | 首次磁盘告警触发 |
| **不做** | **E2** | 命名一致性 | — | 收益 < 改动成本 |

### 8.2 执行路线图（按周）

**第 1 周（本周）—— P0 清零**
- Day 1 上半：A3 诊断 + B1 补空壳 + D3 git clean（都是分钟级）
- Day 1 下半 - Day 3：B2 `__migrations` 表 + 存量幂等化
- Day 4-5：B3 upgrade-hooks/v2.3.0/ 三 hook

**第 2 周 —— 聚合 + 清库**
- Day 6-7：B4 `install.sh upgrade-all --json`（含自动扫描）
- Day 8：D1 docs reconcile + 清 195 checkbox
- Day 9：D2 清杂物 + D4 requirements.txt + C3 schema 校验激活
- Day 10：**v2.4.0 发版**（主题：Agent-Friendly Upgrade Infrastructure）

**第 3-4 周 —— P1 架构 + P2 可观测**
- Week 3：A1 SKILL.md 瘦身拆分
- Week 4：C1 结构化日志 + C2 smoke test 骨架 + E1 ShellCheck

**第 5 周及以后 —— 按需**
- A2 db.py 等待下次大改 db
- C4 等 target 数量扩张
- D5 等磁盘告警

### 8.3 三条红线（重申）

1. **A3 必须先于任何 infra 投入**：自进化真实性未验证前，一切 upgrade infra 都是在装修没人住的房子
2. **B1+B2+B3 必须捆绑做**：拆成三次发版会制造更多 drift
3. **A1 必须先于再给 SKILL.md 加新内容**：SKILL.md 已 1208 行，每加一节 token 成本线性恶化

---

## 九、v2.4.0 发版内容锁定

基于本路线图，**v2.4.0 主题：Agent-Friendly Upgrade Infrastructure**，包含：

- B1 补全 migrations 版本线
- B2 `__migrations` 表
- B3 upgrade-hooks/v2.3.0/ 三 hook
- B4 `install.sh upgrade-all --json` + 自动扫描
- D1 docs 重组 + reconcile
- D2 清杂物
- D4 requirements.txt
- C3 schema 校验激活（附赠）

发版后 SKILL.md 无变更（A1 留 v2.4.1 或 v2.5.0），算法无变更，纯 HANDS+1。

**v2.4.1 候选主题：Observability + Test**（C1 + C2 + E1）。
**v2.5.0 候选主题：SKILL.md Modular**（A1，BRAIN+1，需 UPGRADE.md 迁移指引）。

---

## 十、与其他规划的关系

- `docs/agent-upgrade-design.md`：本文档是该设计的**完整路线图**，扩展了 B 组外的 13 项
- `docs/2026-04-15-self-evolution-plan.md`：由 D1 reconcile 决定归档 or 继续
- `docs/superpowers/plans/` 3 份：由 D1 reconcile 决定归档 or 继续
- `README.md` 版本矩阵：v2.4.0 条目应指向本文档 §9
- `RELEASING.md`：B1 和 D3 带来新 SOP 条款

---

**附录 A · 本次扫描命令**（供复现）

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  ls scripts/ schemas/ migrations/ knowledge-base/ && \
  cat VERSION && git status --short && git log --oneline -10 && \
  wc -l SKILL.md scripts/*.sh scripts/*.py install.sh"
```
