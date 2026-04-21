# Migrations

每个 migration 脚本对应一个版本号，命名 `vX.Y.Z.sh`，由 `install.sh` 自动调度。

## 规则

1. **幂等**：重复执行必须无害
2. **顺序敏感**：按版本号从低到高执行
3. **零交互**：不读 stdin，不依赖用户输入
4. **失败可重试**：脚本中间失败后重跑必须能恢复到目标状态

## 写一个 migration

```bash
#!/usr/bin/env bash
# Migration for vX.Y.Z — 一句话说明改了什么
set -e
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 例：加一张新表
bash "$SKILL_DIR/scripts/db.sh" init >/dev/null

# 例：迁移环境变量
# if grep -q 'OLD_VAR' "$SKILL_DIR/.env"; then
#     sed -i.bak 's/OLD_VAR/NEW_VAR/' "$SKILL_DIR/.env"
# fi

echo "  [vX.Y.Z] OK"
```

## install.sh 如何调度

`install.sh` 读 `$DEPLOY_DIR/VERSION`（已部署版本）和 `$SKILL_DIR/VERSION`（源版本），
遍历 `migrations/vX.Y.Z.sh`，只跑**版本号严格大于已部署版本、且小于等于源版本**的脚本。
