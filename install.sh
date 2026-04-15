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

# 图片生成配置提示
if [ -f "$INSTALL_ROOT/config/runtime.env" ] && ! grep -q "IMAGE_GEN_PROVIDER" "$INSTALL_ROOT/config/runtime.env"; then
    printf '\n=== 图片生成配置 ===\n'
    printf '用于自动生成小红书配图（未配置则全部走 HTML 截图）。\n'
    printf '  1) OpenAI / 兼容 API（gpt-image-1 等）\n'
    printf '  2) Google Gemini（Nano Banana，有免费额度）\n'
    printf '  3) 暂不配置（全部走 HTML 截图）\n'
    read -p "选择 [1/2/3] (默认 3): " img_choice
    img_choice=${img_choice:-3}
    case $img_choice in
        1)
            read -p "OpenAI API Key: " img_key
            read -p "Base URL (留空用 https://api.openai.com/v1): " img_url
            img_url=${img_url:-https://api.openai.com/v1}
            read -p "模型名 (留空用 gpt-image-1): " img_model
            img_model=${img_model:-gpt-image-1}
            {
                echo ""
                echo "# ---- 图片生成配置 ----"
                echo "IMAGE_GEN_PROVIDER=openai"
                echo "IMAGE_GEN_API_KEY=$img_key"
                echo "IMAGE_GEN_BASE_URL=$img_url"
                echo "IMAGE_GEN_MODEL=$img_model"
                echo "IMAGE_GEN_SIZE=1024x1024"
            } >> "$INSTALL_ROOT/config/runtime.env"
            printf '  图片生成配置已写入（OpenAI）\n'
            ;;
        2)
            printf '\n  Gemini API Key 获取地址: https://aistudio.google.com/api-keys\n'
            read -p "Gemini API Key (AIza...): " img_key
            read -p "模型名 (留空用 gemini-2.0-flash-preview-image-generation): " img_model
            img_model=${img_model:-gemini-2.0-flash-preview-image-generation}
            read -p "宽高比 (留空用 3:4): " img_ratio
            img_ratio=${img_ratio:-3:4}
            {
                echo ""
                echo "# ---- 图片生成配置（Gemini）----"
                echo "IMAGE_GEN_PROVIDER=gemini"
                echo "IMAGE_GEN_API_KEY=$img_key"
                echo "IMAGE_GEN_MODEL=$img_model"
                echo "IMAGE_GEN_ASPECT_RATIO=$img_ratio"
            } >> "$INSTALL_ROOT/config/runtime.env"
            printf '  图片生成配置已写入（Gemini）\n'
            ;;
        *)
            printf '  跳过图片生成配置，将使用 HTML 截图模式\n'
            ;;
    esac
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
