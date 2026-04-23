# upgrade-hooks/ — 升级副作用声明

> 相关设计：[docs/agent-upgrade-design.md](../docs/agent-upgrade-design.md)（Team-4 会移到 [docs/adr/agent-upgrade-design.md](../docs/adr/agent-upgrade-design.md)，两处链接至少一个有效）

## 目录作用

每次版本升级除了 "代码 rsync + DB migration" 之外，经常还会引入 **第三类副作用**：

- 新字段要塞进已存在的 `runtime.env`
- 旧的 JSON 数据结构要就地改写
- 外部调度器（hermes-cron 等）的 prompt 里有过时字样

这些改动既不属于 git 管理的源码、也不属于 `migrations/*.sh` 管的 DB schema。
过去它们散落在人类或 agent 的脑子里，每次升级靠 **现场推理** 完成，不可审计也不幂等。

`upgrade-hooks/` 就是把这类副作用 **声明式**、**代码化** 存起来的地方。

## 目录约定

每个引入副作用的版本有一个子目录：

```
upgrade-hooks/
  v2.3.0/
    README.md                              # 本版为何需要这些 hook
    runtime-env-sync.sh                    # 副作用脚本 1
    preferences-structure-migrate.sh       # 副作用脚本 2
    scheduler-prompt-update.sh             # 副作用脚本 3
  v2.4.0/
    README.md
    ...
```

未引入副作用的版本可以没有目录。目录名即版本号（带 `v` 前缀）。

## 每个 hook 的契约

所有 hook 必须满足以下规则。这些是 `install.sh upgrade-all` 能安全批量调用的前提。

### 1. 单参数入口

```bash
bash upgrade-hooks/vX.Y.Z/<hook>.sh <target_path>
```

第一个位置参数 = target 安装目录（如 `~/.codex/skills/shuling` 或 `~/.hermes/skills/social-media/shuling`）。
缺参数或目录不存在 → exit 1 + `{"status":"failed","detail":"target_path required"}`。

### 2. 幂等

同一条命令跑第 N 次必须安全。已处理过的 target 直接 `{"status":"skipped","reason":"..."}` 退出 0。
不允许出现 "跑第二次产生重复数据 / 覆盖已正确的用户值" 的情况。

### 3. 单行 JSON 输出

**stdout 只能有一行 JSON**，不允许进度条、彩色文字、人类友好提示。

成功：
```json
{"status":"ok","detail":"<what changed>","target":"<target_path>"}
```

跳过：
```json
{"status":"skipped","reason":"<why>","target":"<target_path>"}
```

失败：
```json
{"status":"failed","detail":"<err>","target":"<target_path>"}
```

stderr 可留给 `set -e` 捕获的异常 trace（agent 不解析 stderr，但保留便于人类 debug）。

### 4. 零交互

**不得** 有任何 `read`、`select`、`confirm` 之类的交互式 prompt。agent 处理不了。

### 5. 零 agent 推理依赖

hook 不应当输出 "请 agent 下一步去做 X" 式的人话，自己该决定的事自己决定。

### 6. 改写前备份

凡涉及就地改写已有文件的 hook，**必须** 先备份到 `<原文件>.bak-vX.Y.Z-<timestamp>` 再改写。
备份文件命名规则：版本号 + 时间戳，便于 agent 或人类直接识别来源。

## 如何被调用

短期：agent 在执行升级时显式 `bash upgrade-hooks/v2.3.0/*.sh <target>`，逐个 hook 调用。
中期：`install.sh upgrade-all` 扫 `upgrade-hooks/` 下高于当前安装版本的目录，按目录内顺序或脚本字典序调用，汇总 JSON 输出到上层 plan。

## 命名建议

- 用动词短语开头（`runtime-env-sync`、`preferences-structure-migrate`、`scheduler-prompt-update`）
- 不要带版本号（版本号在目录名上）
- 不要带 "fix"、"hotfix" 等情绪词
