# ops/verify/checks/

每个脚本一个 check，单一职责，零依赖（除 bash + python3）。

## 通用契约

- 退出码：`0` = pass / `1` = warn / `2` = fail
- stdout：单行 JSON `{"check":"...","status":"...","message":"...","severity":"..."}`
- 第一参数：仓库根（默认从脚本位置反推）
- 副作用：零（只读）

## 清单

| # | 脚本 | severity | 职责 |
|---|---|---|---|
| 01 | `01-skill-frontmatter.sh` | error | 根 SKILL.md 含 frontmatter + name/description/version |
| 02 | `02-skill-version-match.sh` | error | SKILL.md frontmatter version 与 VERSION 文件一致 |
| 03 | `03-skill-line-count.sh` | error | 根 SKILL.md ≤ 150 行 |
| 04 | `04-playbook-frontmatter.sh` | error | 每个 0X playbook 有 frontmatter（id/title/when/version） |
| 05 | `05-playbook-when-nonempty.sh` | error | playbook frontmatter 的 when 数组非空 |
| 06 | `06-playbook-calls-exist.sh` | error | calls.scripts / calls.playbooks 引用都真实存在 |
| 07 | `07-xhs-sh-executable.sh` | error | agent/scripts/xhs.sh 存在且可执行 |
| 08 | `08-ensure-runtime-layout-dryrun.sh` | error | db.sh ensure-runtime-layout --dry-run --json OK |
| 09 | `09-ensure-schema-dryrun.sh` | error | db.sh ensure-schema --dry-run --json OK |
| 10 | `10-json-schemas-parse.sh` | error | agent/schemas/*.json 可被 python -m json.tool 解析 |
| 11 | `11-preflight-ok.sh` | warn | preflight.py --json 退出码 ≤ 2（≥3 fail） |
| 12 | `12-package-whitelist.sh` | error | dist/ v3 包顶层只含 SKILL.md/VERSION/agents/agent |
| 13 | `13-package-no-inactive-dirs.sh` | error | dist/ 包内不含 docs/site/marketing/legacy/ops/build |
| 14 | `14-package-no-user-state.sh` | error | dist/ 包内不含用户态（DB / runtime.env / kb 实文件） |
| 15 | `15-active-region-no-old-paths.sh` | error | active 区无 v2 旧根路径硬编码 |
| 16 | `16-active-region-no-legacy-refs.sh` | error | active 区文件不引用 legacy/ 或 docs/archive/ |
| 17 | `17-active-region-no-tech-bias.sh` | warn | active .md 不含 v2 技术偏向词 |
| 18 | `18-legacy-readme-coverage.sh` | error | legacy/README.md 覆盖所有归档子目录 |
| 19 | `19-cron-plist-lint.sh` | error | launchd plist 文件 lint 通过 |
| 20 | `20-cron-systemd-verify.sh` | error | systemd unit 文件可被解析（仅 linux） |
| 21 | `21-cron-yaml-parse.sh` | warn | cron 相关 yaml 可解析（无 yq 则 skip） |
| 22 | `22-install-stub-dryrun.sh` | error | 根 install.sh stub 输出 DEPRECATED 提示 |
| 23 | `23-ops-install-dryrun.sh` | error | ops/install.sh --dry-run 退出 0 |
| 24 | `24-upgrade-all-no-user-overwrite.sh` | error | upgrade-all 计划不触碰用户态路径 |
| 25 | `25-git-diff-check.sh` | error | git diff --check 干净（含 cached） |
| 26 | `26-skill-md-no-codeblock.sh` | error | 根 SKILL.md 仅允许 ```bash 代码块 |
| 27 | `27-migration-isolation.sh` | error | migrations/db / state / upgrade-hooks 文件类型隔离且 hook 名不重叠 |
| 28 | `28-playbook-graph-no-cycle.sh` | error | playbook calls.playbooks 调用图无环 |
| 29 | `29-paths-singleton.sh` | error | agent/scripts/*.sh 不 hardcode 路径常量（_paths.sh 单一来源） |
| 30 | `30-policy-drift.sh` | warn | policies/throttle.yaml + quota.yaml 与 xhs.sh 硬编码值一致（未拆分则 skip） |
| 31 | `31-algorithm-uniqueness.sh` | error | weight / confidence 公式仅在 06-learning-loop.md 出现（ADR-0002 D1） |
| 32 | `32-profile-write-precondition.sh` | error | 写 profile.json 的 playbook 必须有非空 preconditions（ADR-0002 D3） |
| 33 | `33-compliance-inline-limit.sh` | warn | 03/04 内联合规摘要 ≤25/20 行（ADR-0002 D4） |
| 34 | `34-optional-fallback.sh` | error | needs.optional 字段必须配 fallback（ADR-0002 D5） |
| 35 | `35-publish-requires-approval.sh` | error | xhs.sh publish 无 --approval-id 必须返回 approval_required |
| 36 | `36-comment-disabled-by-default.sh` | error | xhs.sh comment 未设 SHULING_ENABLE_COMMENT 时必须返回 comment_disabled |
| 37 | `37-cron-no-auto-publish.sh` | error | ops/cron/*.example 不含自动发布禁用词（draft-only 纪律） |
| 38 | `38-disable-throttle-dev-only.sh` | error | XHS_DISABLE_THROTTLE/QUOTA 在非 SHULING_DEV_MODE=1 下必须被拒 |
| 39 | `39-account-safety-schema.sh` | error | 6 个 account-safety/approval/external-signal schema 可解析 + default policy 自校验 |
| 40 | `40-no-cookie-in-docs-or-logs.sh` | error | docs/playbook/README 不含真实 cookie 字段或 API key 长串 |
| 41 | `41-external-intel-budget.sh` | error | external-intelligence policy 预算不超 conservative 上限；playbook 不直散调 xhs.sh（Stage 6 未运行时降为 warn） |
| 42 | `42-external-signals-no-raw-dumps.sh` | error | external-signals/*.json 不含原始转储字段且单文件 ≤50KB |

## 调用方式

```bash
bash ops/verify/checks/01-skill-frontmatter.sh
# 或显式传根
bash ops/verify/checks/01-skill-frontmatter.sh /path/to/shuling
```

## 与上层关系

`ops/verify/run.sh`（如有）按编号顺序串跑，聚合 JSON。本目录脚本之间无依赖，可独立调用。
