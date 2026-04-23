# ============================================================
# demo.tape — ShuLing v2.3.0 demo recording for vhs
# ------------------------------------------------------------
# Render:   vhs demo.tape  ->  demo.gif  (~60-90s, 800x600)
# Install:  brew install vhs
#
# Structure (adjust any section by editing the block below):
#   1. Intro + repo layout                  (~8s)
#   2. Preflight check (install.sh --check) (~9s)
#   3. Claude Code: "帮我发小红书"          (~10s)
#   4. Topic selection (3 options)          (~8s)
#   5. User picks topic 1                   (~5s)
#   6. Outline generation (6 pages)         (~12s)
#   7. Image generation progress            (~10s)
#   8. Publish success + note_id            (~8s)
#   9. SQLite record preview                (~8s)
#
# Total target: ~75s at default speed.
# To shorten: reduce `Sleep` values.
# To slow down typing: raise `Type@` milliseconds.
# ============================================================

# --- Output & canvas ----------------------------------------
Output demo.gif
Set Shell "bash"
Set FontSize 14
Set Width 800
Set Height 600
Set Theme "Dracula"
Set TypingSpeed 50ms
Set PlaybackSpeed 1.0
Set Padding 20

# Start from a clean mock workspace so we don't depend on the
# real shuling repo being present on the recording machine.
# Everything below uses echo/cat/printf to simulate agent output.
Hide
Type "cd /tmp && rm -rf shuling-demo && mkdir shuling-demo && cd shuling-demo"
Enter
Type "clear"
Enter
Show

# ============================================================
# SECTION 1 — Intro + repo layout
# ============================================================
Type@80ms "# ShuLing v2.3.0 — Skill-as-Brain demo"
Enter
Sleep 1s
Type@80ms "ls"
Sleep 300ms
Enter
Hide
Type `printf 'SKILL.md          install.sh        preflight.py\nscripts/          skills/           knowledge-base/\nprompts/          migrations/       config/\ntemplates/        README.md         LICENSE\n'`
Enter
Show
Sleep 3s

Type@80ms "tree -L 1 skills/shuling/ 2>/dev/null || ls skills/"
Sleep 300ms
Enter
Hide
Type `printf 'skills/shuling/\n  SKILL.md            # 1208-line brain\n  platform/           # claude-code / codex / hermes adapters\n  knowledge-base/     # profile, preferences, patterns\n  prompts/            # image_prompt.txt (77 lines)\n'`
Enter
Show
Sleep 4s

# ============================================================
# SECTION 2 — Preflight check
# ============================================================
Type@80ms "clear && bash install.sh --check"
Sleep 400ms
Enter
Hide
Type `printf '\033[1;36m== ShuLing preflight (human mode) ==\033[0m\n'`
Enter
Sleep 400ms
Type `printf '\033[32m[ok]\033[0m  python3 >= 3.10                    (3.11.8)\n'`
Enter
Sleep 200ms
Type `printf '\033[32m[ok]\033[0m  sqlite3 CLI available               (3.45.1)\n'`
Enter
Sleep 200ms
Type `printf '\033[32m[ok]\033[0m  xiaohongshu-mcp reachable            (v0.4.1)\n'`
Enter
Sleep 200ms
Type `printf '\033[32m[ok]\033[0m  GEMINI_API_KEY configured            (gemini-3-pro-image)\n'`
Enter
Sleep 200ms
Type `printf '\033[32m[ok]\033[0m  SKILL.md brain version               (BRAIN=2 HANDS=3 CALIB=0)\n'`
Enter
Sleep 200ms
Type `printf '\033[32m[ok]\033[0m  knowledge-base/ writable\n'`
Enter
Sleep 200ms
Type `printf '\033[32m[ok]\033[0m  migrations applied                   (9/9 tables up-to-date)\n'`
Enter
Sleep 200ms
Type `printf '\nAll checks passed. Exit 0.\n'`
Enter
Show
Sleep 3s

# ============================================================
# SECTION 3 — Claude Code launch + user prompt
# ============================================================
Type@80ms "clear && claude"
Sleep 400ms
Enter
Hide
Type `printf '\033[1;35m● Claude Code\033[0m  (model: claude-opus-4-7)\n'`
Enter
Type `printf '\033[2m loaded skill: shuling (BRAIN=2.3.0)\033[0m\n\n'`
Enter
Show
Sleep 1500ms

Type@100ms "帮我发小红书"
Sleep 500ms
Enter
Hide
Type `printf '\n\033[1;34mAgent:\033[0m 好的，先读取你的博主画像 + 最近表现…\n'`
Enter
Sleep 600ms
Type `printf '  \033[2m> reading knowledge-base/profile.json\033[0m\n'`
Enter
Sleep 300ms
Type `printf '  \033[2m> reading knowledge-base/preferences.json  (Bayesian, 18 posts)\033[0m\n'`
Enter
Sleep 300ms
Type `printf '  \033[2m> reading knowledge-base/patterns/*.md      (3 high, 5 medium)\033[0m\n\n'`
Enter
Show
Sleep 2s

# ============================================================
# SECTION 4 — Topic selection (3 options)
# ============================================================
Hide
Type `printf '\033[1;34mAgent:\033[0m 根据你的画像，今天推荐 3 个选题（ε=0.2, 1 个探索型）：\n\n'`
Enter
Sleep 400ms
Type `printf '  \033[1;33m[1]\033[0m  副业周记 · 我用 AI 写小红书的第 30 天\n'`
Enter
Type `printf '       pattern: 真实复盘 · high confidence (0.84)\n'`
Enter
Type `printf '       predicted save-rate: 7.2%% (+2.1%% vs baseline)\n\n'`
Enter
Sleep 500ms
Type `printf '  \033[1;33m[2]\033[0m  5 个让我少走 3 年弯路的 AI 工作流\n'`
Enter
Type `printf '       pattern: 数字清单 · medium (0.61)\n'`
Enter
Type `printf '       predicted save-rate: 5.8%% (+0.7%% vs baseline)\n\n'`
Enter
Sleep 500ms
Type `printf '  \033[1;33m[3]\033[0m  探索：一张图讲明白 Skill-as-Brain\n'`
Enter
Type `printf '       \033[2mpattern: ε-greedy exploration · experimental\033[0m\n'`
Enter
Type `printf '       \033[2mpredicted save-rate: unknown (exploring)\033[0m\n\n'`
Enter
Show
Sleep 3s

# ============================================================
# SECTION 5 — User picks 1
# ============================================================
Type@120ms "1"
Sleep 400ms
Enter
Hide
Type `printf '\n\033[1;34mAgent:\033[0m 好，选题锁定《副业周记 · 我用 AI 写小红书的第 30 天》\n\n'`
Enter
Show
Sleep 1500ms

# ============================================================
# SECTION 6 — Outline generation (6 pages)
# ============================================================
Hide
Type `printf '\033[1;34mAgent:\033[0m 生成 6 页大纲中…\n\n'`
Enter
Sleep 500ms
Type `printf '  \033[32m●\033[0m P1 封面     — 30 天我用 AI 发了 24 篇，3 篇破 1k 赞\n'`
Enter
Sleep 300ms
Type `printf '  \033[32m●\033[0m P2 钩子     — 一开始我也以为 AI 就是套模板\n'`
Enter
Sleep 300ms
Type `printf '  \033[32m●\033[0m P3 转折     — 直到我把流程变成一个 skill\n'`
Enter
Sleep 300ms
Type `printf '  \033[32m●\033[0m P4 干货 1   — 选题交给贝叶斯学习器，不再靠感觉\n'`
Enter
Sleep 300ms
Type `printf '  \033[32m●\033[0m P5 干货 2   — 图用 Gemini 3 Pro 回灌首图，9 页一致\n'`
Enter
Sleep 300ms
Type `printf '  \033[32m●\033[0m P6 CTA      — 评论区聊聊你最想让 AI 接管哪一步\n\n'`
Enter
Sleep 500ms
Type `printf '  \033[2m> outline.json validated against schemas/outline.schema.json  ✓\033[0m\n'`
Enter
Show
Sleep 3s

# ============================================================
# SECTION 7 — Image generation progress
# ============================================================
Hide
Type `printf '\n\033[1;34mAgent:\033[0m 开始生成 6 张图（Gemini 3 Pro Image · 两阶段回灌）…\n\n'`
Enter
Sleep 400ms
Type `printf '  [P1 cover ] \033[33m●●●●●●●●●●\033[0m 100%% (8.3s)  reference=none\n'`
Enter
Sleep 500ms
Type `printf '  [P2 page  ] \033[33m●●●●●●●●●●\033[0m 100%% (7.1s)  reference=P1\n'`
Enter
Sleep 400ms
Type `printf '  [P3 page  ] \033[33m●●●●●●●●●●\033[0m 100%% (6.9s)  reference=P1\n'`
Enter
Sleep 400ms
Type `printf '  [P4 page  ] \033[33m●●●●●●●●●●\033[0m 100%% (7.4s)  reference=P1\n'`
Enter
Sleep 400ms
Type `printf '  [P5 page  ] \033[33m●●●●●●●●●●\033[0m 100%% (7.0s)  reference=P1\n'`
Enter
Sleep 400ms
Type `printf '  [P6 page  ] \033[33m●●●●●●●●●●\033[0m 100%% (6.8s)  reference=P1\n\n'`
Enter
Sleep 400ms
Type `printf '  \033[32mAll 6 images written to artifacts/2026-04-23/images/\033[0m\n'`
Enter
Show
Sleep 3s

# ============================================================
# SECTION 8 — Publish + note_id
# ============================================================
Hide
Type `printf '\n\033[1;34mAgent:\033[0m 调用 xiaohongshu-mcp 发布…\n'`
Enter
Sleep 600ms
Type `printf '  \033[2m> publish.call(title, body, images[6])\033[0m\n'`
Enter
Sleep 1200ms
Type `printf '\n  \033[1;32m✔ 发布成功\033[0m\n'`
Enter
Type `printf '    note_id : 663f8b1c0000000012034a7d\n'`
Enter
Type `printf '    url     : https://www.xiaohongshu.com/explore/663f8b1c0000000012034a7d\n'`
Enter
Type `printf '    status  : published · visible · no_review_flag\n\n'`
Enter
Show
Sleep 3s

# ============================================================
# SECTION 9 — SQLite record preview
# ============================================================
Type@80ms "sqlite3 knowledge-base/shuling.db 'select id,topic,pages,status,published_at from posts order by id desc limit 1;'"
Sleep 400ms
Enter
Hide
Type `printf '25|副业周记 · 我用 AI 写小红书的第 30 天|6|published|2026-04-23T10:14:22+08:00\n'`
Enter
Show
Sleep 3s

Type@80ms "# 下次打开 Claude 再说『帮我复盘』，它会读这条数据、更新贝叶斯权重"
Enter
Sleep 3s

# End frame
Sleep 1500ms
