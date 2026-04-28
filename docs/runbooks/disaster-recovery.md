# 灾难恢复 SOP（v3.0+）

> 当 v3.0 升级或日常运行出严重问题时的恢复流程。

## 场景 1：v3.0 升级中断 / install.sh 报错

**症状**：升级跑到一半失败，target 处于半迁移状态。

**恢复步骤**：

1. 检查 `agent/config/.layout-v3.done` marker 是否存在
   - 存在 → layout migration 已完成，问题在 ensure-schema 或 preflight；继续步骤 3
   - 不存在 → layout migration 未完成；继续步骤 2

2. 重跑 layout migration：
   ```bash
   bash ops/layout-migrations/v2-to-v3.sh "$target"
   ```
   幂等：成功的部分会 skip，失败的部分会重试。

3. 跑 `bash ops/doctor.sh "$target" --table` 确认状态
4. 如果 ensure-schema 失败 → 跑 `bash agent/scripts/db.sh ensure-schema --dry-run` 看 pending migration 清单，手动逐个跑
5. 如果以上都失败 → 走"完整回滚到 v2"

## 场景 2：完整回滚到 v2.4.x

**适用**：v3.0 升级后业务流程异常，需要回到 v2 已知稳定状态。

**步骤**：

```bash
# 1. 切回 v2 tag
cd /path/to/shuling
git checkout v2.4.3

# 2. v2 旧路径仍在 target（copy-first 没删）
# - $target/data/xhs.db 仍是 v2 路径下的 DB
# - $target/config/runtime.env 仍是 v2 路径下的配置
# - $target/knowledge-base/* 仍是 v2 路径
# 这些都不需要恢复——copy-first 的设计就是"v3 失败可直接回滚"

# 3. 删除 v3 添加的 marker（让下次升级重新做）
rm -f $target/agent/config/.layout-v3.done

# 4. 重启宿主 agent
# Hermes: hermes-cli reload
# Claude Code: /compact + 新对话
# Codex: 重启 session

# 5. 验证 v2 行为
bash $target/scripts/db.sh query-posts --today  # v2 命令仍可用
```

## 场景 3：agent/data/xhs.db 损坏

**症状**：`bash agent/scripts/db.sh query-posts` 报 sqlite 错误。

**恢复步骤**：

1. 备份当前损坏文件 + 立即检查 v2 旧路径有无副本
   ```bash
   cp $target/agent/data/xhs.db $target/agent/data/xhs.db.broken-$(date +%s)
   ls -la $target/data/xhs.db   # 如果存在就是 copy-first 留的副本
   ```

2. 恢复路径 A — 从 v2 旧路径恢复：
   ```bash
   cp $target/data/xhs.db $target/agent/data/xhs.db
   bash agent/scripts/db.sh ensure-schema   # 重应用 migration
   ```

3. 恢复路径 B — 从 git 恢复（如果 v2 旧路径也损坏）：
   ```bash
   # xhs.db 在 .gitignore，不在 git 历史里
   # 只能从用户自己的备份恢复
   # 这就是为什么 UPGRADE.md 第一步要求备份
   ```

4. 恢复路径 C — 重建空 DB：
   ```bash
   rm $target/agent/data/xhs.db
   bash $target/agent/scripts/db.sh init  # 全新空 DB
   bash $target/agent/scripts/db.sh ensure-schema  # 应用所有 migration
   # 历史数据丢失；后续从小红书 MCP 重新拉数据填充
   ```

## 场景 4：runtime.env 丢失或 API Key 失效

```bash
# 重新写入
python3 $target/agent/scripts/image.py --set-key "<NEW_GEMINI_KEY>"

# 或手工编辑
cp $target/agent/config/runtime.env.example $target/agent/config/runtime.env
vim $target/agent/config/runtime.env  # 填入 IMAGE_GEN_API_KEY / MCP_URL 等
```

## 场景 5：knowledge-base/ 损坏

knowledge-base 是 markdown + JSON 文件，无 schema 强约束。

```bash
# 从备份恢复（用户自管）
# 或：让 AI 助手对话"重新做画像"，重建 profile.json
# 或：从 patterns.md / anti-patterns.md 复制粘贴回来
```

## 场景 6：schema-degraded mode 触发

**症状**：`bash agent/scripts/db.sh query-*` 工作正常但 `bash agent/scripts/db.sh log-*` 报 schema-degraded。

**恢复步骤**：
```bash
# 1. 看 lock 文件
cat $target/agent/data/.schema-degraded.lock

# 2. 看哪个 migration 失败
bash $target/agent/scripts/db.sh ensure-schema --json
# 输出会显示 failed=N 的具体 migration

# 3. 手动跑该 migration（带 verbose）
env SHULING_DB="$target/agent/data/xhs.db" \
    SKILL_DIR="$target/agent" \
    bash $target/agent/migrations/db/v2.X.Y.sh

# 4. 修复后删 lock
rm $target/agent/data/.schema-degraded.lock

# 5. 重新跑 ensure-schema
bash $target/agent/scripts/db.sh ensure-schema
```

## 场景 7：宿主 agent 平台异常（hermes/claude-code/codex）

不在本 SOP 范围。参考各平台自己的故障文档。

## 通用诊断命令

```bash
bash ops/doctor.sh "$target" --table       # 12 项体检
python3 agent/scripts/preflight.py --human # 彩色环境自检
bash agent/scripts/xhs.sh status            # MCP 登录态
bash agent/scripts/db.sh query-preferences  # DB 是否能读
ls -la $target/agent/config/.layout-v3.done # 升级 marker
```

## 联系作者

- GitHub Issues：https://github.com/AI-flower/shuling/issues
- Email：详见 SECURITY.md
