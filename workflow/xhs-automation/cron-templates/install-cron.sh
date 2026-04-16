#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== 安装 XHS 自动化 cron 任务 ==="
echo "工作目录: $WORKDIR"

# 创建日志目录
mkdir -p "$WORKDIR/logs"

# 替换模板中的占位符
CRON_CONTENT=$(sed "s|__WORKDIR__|$WORKDIR|g" "$SCRIPT_DIR/xhs-crontab")

# 获取现有 crontab（忽略 no crontab 错误）
EXISTING=$(crontab -l 2>/dev/null || true)

# 移除旧的 XHS 任务（如果有）
CLEANED=$(echo "$EXISTING" | grep -v "xhs-automation" | grep -v "XHS Automation" || true)

# 追加新任务
(echo "$CLEANED"; echo ""; echo "$CRON_CONTENT") | crontab -

echo ""
echo "✅ cron 任务已安装！"
echo ""
crontab -l | grep -c "xhs-automation" | xargs -I{} echo "已安装 {} 条 XHS 定时任务"
echo ""
echo "管理命令："
echo "  查看: crontab -l"
echo "  编辑: crontab -e"
echo "  日志: tail -f $WORKDIR/logs/research.log"
