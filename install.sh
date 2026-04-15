#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_ROOT="${1:-$HOME/xhs-automation}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

printf 'Installing to %s\n' "$INSTALL_ROOT"

mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills"
mkdir -p "$INSTALL_ROOT" "$INSTALL_ROOT/logs" "$INSTALL_ROOT/posts" "$INSTALL_ROOT/output" "$INSTALL_ROOT/data" "$INSTALL_ROOT/config" "$INSTALL_ROOT/launchd"

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
