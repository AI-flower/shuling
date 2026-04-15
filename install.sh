#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_ROOT="${1:-$HOME/xhs-automation}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

printf 'Installing to %s\n' "$INSTALL_ROOT"

mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills"
mkdir -p "$INSTALL_ROOT" "$INSTALL_ROOT/logs" "$INSTALL_ROOT/posts" "$INSTALL_ROOT/output" "$INSTALL_ROOT/data" "$INSTALL_ROOT/config" "$INSTALL_ROOT/launchd" "$INSTALL_ROOT/knowledge-base/reviews"

rsync -a "$BUNDLE_ROOT/skills/xiaohongshu/" "$HOME/.agents/skills/xiaohongshu/"
ln -sfn "$HOME/.agents/skills/xiaohongshu" "$HOME/.claude/skills/xiaohongshu"
ln -sfn "$HOME/.agents/skills/xiaohongshu" "$HOME/.codex/skills/xiaohongshu"

rsync -a "$BUNDLE_ROOT/skills/xhs-content-generator/" "$HOME/.claude/skills/xhs-content-generator/"
ln -sfn "$HOME/.claude/skills/xhs-content-generator" "$HOME/.agents/skills/xhs-content-generator"
ln -sfn "$HOME/.claude/skills/xhs-content-generator" "$HOME/.codex/skills/xhs-content-generator"

rsync -a "$BUNDLE_ROOT/workflow/xhs-automation/" "$INSTALL_ROOT/"

if [ ! -f "$INSTALL_ROOT/config/runtime.env" ]; then
  cp "$INSTALL_ROOT/config/runtime.env.example" "$INSTALL_ROOT/config/runtime.env"
fi

mkdir -p "$LAUNCH_AGENTS_DIR"
for template in "$INSTALL_ROOT"/launchd-templates/*.template; do
  name="$(basename "$template" .template)"
  target="$INSTALL_ROOT/launchd/$name"
  sed "s|__WORKDIR__|$INSTALL_ROOT|g" "$template" > "$target"
done

chmod +x "$INSTALL_ROOT/publish.sh"
chmod +x "$HOME/.agents/skills/xiaohongshu/scripts/"*.sh


# LLM 配置提示
if [ ! -f "$INSTALL_ROOT/config/runtime.env" ] || ! grep -q "LLM_PROVIDER" "$INSTALL_ROOT/config/runtime.env"; then
    printf '\n=== LLM 配置 ===\n'
    printf 'workflow 后台脚本需要 LLM 调用能力。\n'
    printf '  1) Claude API (Anthropic)\n'
    printf '  2) OpenAI API\n'
    printf '  3) 兼容 OpenAI 格式的其他服务\n'
    read -p "选择 [1/2/3] (默认 1): " llm_choice
    llm_choice=${llm_choice:-1}
    case $llm_choice in
        1) llm_provider="claude"; llm_model="claude-sonnet-4-20250514" ;;
        2) llm_provider="openai"; llm_model="gpt-4o-mini" ;;
        3) llm_provider="openai-compatible"; llm_model="" ;;
    esac
    read -p "API Key: " llm_key
    read -p "Base URL (留空用默认): " llm_url
    if [ -n "$llm_provider" ]; then
        {
            echo ""
            echo "# ---- LLM 配置 ----"
            echo "LLM_PROVIDER=$llm_provider"
            echo "LLM_API_KEY=$llm_key"
            echo "LLM_BASE_URL=$llm_url"
            echo "LLM_MODEL=$llm_model"
        } >> "$INSTALL_ROOT/config/runtime.env"
        printf '  LLM 配置已写入 runtime.env\n'
    fi
fi
cat <<EOF

Install complete.

Installed workflow:
  $INSTALL_ROOT

Installed skills:
  $HOME/.agents/skills/xiaohongshu
  $HOME/.claude/skills/xhs-content-generator

Next steps:
1. Edit: $INSTALL_ROOT/config/runtime.env
2. Install xiaohongshu-mcp binaries, then run:
   $HOME/.agents/skills/xiaohongshu/scripts/install-check.sh
3. Start MCP:
   $HOME/.agents/skills/xiaohongshu/scripts/start-mcp.sh
4. Test login:
   $HOME/.agents/skills/xiaohongshu/scripts/status.sh
5. Manual workflow test:
   cd $INSTALL_ROOT
   python3 scripts/research.py 2026-04-14
   python3 scripts/create_content.py 2026-04-14
6. If everything is good, copy or load the plists from:
   $INSTALL_ROOT/launchd
   into:
   $LAUNCH_AGENTS_DIR

Launchctl example:
  cp $INSTALL_ROOT/launchd/*.plist $LAUNCH_AGENTS_DIR/
  launchctl unload $LAUNCH_AGENTS_DIR/com.yl.xhs-research.plist 2>/dev/null || true
  launchctl load $LAUNCH_AGENTS_DIR/com.yl.xhs-research.plist

EOF
