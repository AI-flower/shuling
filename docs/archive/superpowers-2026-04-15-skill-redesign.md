# Xiaohongshu Skill Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the shuling from a Python-script-heavy architecture to a Skill-as-Brain design where SKILL.md contains all business logic and 4 thin scripts handle physical operations only.

**Architecture:** SKILL.md is the single source of truth for all workflow logic (topic research, draft creation, self-evolution). Four scripts (xhs.sh, image.py, screenshot.cjs, db.sh) handle MCP calls, image generation, screenshots, and SQLite operations. Platform adapters (Hermes/Claude Code/Codex) provide scheduling and user interaction.

**Tech Stack:** Bash (xhs.sh, db.sh), Python 3 (image.py), Node.js + Playwright (screenshot.cjs), SQLite, Markdown + JSON knowledge base.

**Remote access:** All files live on `weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling`. Use SSH for all file operations.

**Existing assets to reuse:**
- `skills/xiaohongshu/scripts/mcp-call.sh` → basis for `scripts/xhs.sh`
- `workflow/xhs-automation/scripts/gemini-generate-image.py` → basis for `scripts/image.py`
- `skills/xhs-content-generator/scripts/screenshot.cjs` → copy to `scripts/screenshot.cjs`
- `workflow/xhs-automation/data/content-rules.md` → copy to `data/content-rules.md`

---

### Task 1: Create New Project Structure

**Files:**
- Create: `scripts/` directory
- Create: `data/` directory
- Create: `knowledge-base/` directory (with .gitkeep)
- Create: `templates/` directory
- Create: `platform/` directory

- [ ] **Step 1: Create directory skeleton on remote machine**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  mkdir -p scripts data knowledge-base templates platform"
```

- [ ] **Step 2: Add .gitkeep for empty dirs**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  touch knowledge-base/.gitkeep templates/.gitkeep"
```

- [ ] **Step 3: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add scripts data knowledge-base templates platform && \
  git commit -m 'chore: create new project structure for skill redesign'"
```

---

### Task 2: Build scripts/xhs.sh — Unified MCP Entry Point

**Files:**
- Create: `scripts/xhs.sh`
- Reference: `skills/xiaohongshu/scripts/mcp-call.sh` (existing MCP logic)

This wraps the existing MCP protocol logic into a user-friendly CLI with subcommands. Key difference from mcp-call.sh: auto-starts MCP if not running, outputs clean JSON, adds `publish` subcommand that reads meta.json.

- [ ] **Step 1: Write scripts/xhs.sh**

The script should:
- Accept subcommands: `search`, `recommend`, `detail`, `publish`, `comment`, `status`, `login`, `user`
- Reuse the MCP JSON-RPC protocol from mcp-call.sh (initialize → notification → tools/call)
- Auto-detect MCP URL from env or default to localhost:18060
- For `publish`: read a meta.json file and call `publish_content` with its contents
- For `status`: call `check_login_status` and output clean JSON
- All output as JSON for Agent parsing
- Auto-start MCP if connection fails (call start-mcp.sh from known skill paths)

- [ ] **Step 2: Test basic commands**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  chmod +x scripts/xhs.sh && \
  scripts/xhs.sh status"
```

Expected: JSON with login status (MCP is running on the 69 machine, but we test connectivity from 110)

- [ ] **Step 3: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add scripts/xhs.sh && \
  git commit -m 'feat: add scripts/xhs.sh — unified MCP entry point'"
```

---

### Task 3: Build scripts/image.py — Gemini Image Generation

**Files:**
- Create: `scripts/image.py`
- Reference: `workflow/xhs-automation/scripts/gemini-generate-image.py` (existing Gemini logic)

Simplified version: remove runtime.env coupling, use env vars directly, keep --check/--set-key/generate modes.

- [ ] **Step 1: Write scripts/image.py**

Adapt gemini-generate-image.py:
- Remove `load_runtime_env()` dependency — read `IMAGE_GEN_API_KEY` from env directly
- Keep `--check`, `--set-key`, and generate modes
- Add `--set-key` that writes to a simple `.env` file in the skill's data/ directory
- Keep the Gemini API call logic unchanged (it works)
- Output path to stdout on success for Agent to capture

- [ ] **Step 2: Test --check**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  python3 scripts/image.py --check"
```

Expected: exit 2 (no key configured yet) or exit 0 if key exists in env

- [ ] **Step 3: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add scripts/image.py && \
  git commit -m 'feat: add scripts/image.py — Gemini image generation'"
```

---

### Task 4: Copy scripts/screenshot.cjs

**Files:**
- Create: `scripts/screenshot.cjs`
- Reference: `skills/xhs-content-generator/scripts/screenshot.cjs` (copy directly)

- [ ] **Step 1: Copy screenshot.cjs**

```bash
ssh weiyong@100.79.106.110 "cp /Users/weiyong/Documents/10/shuling/skills/xhs-content-generator/scripts/screenshot.cjs \
  /Users/weiyong/Documents/10/shuling/scripts/screenshot.cjs"
```

- [ ] **Step 2: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add scripts/screenshot.cjs && \
  git commit -m 'feat: add scripts/screenshot.cjs — HTML to PNG screenshots'"
```

---

### Task 5: Build scripts/db.sh — SQLite Wrapper

**Files:**
- Create: `scripts/db.sh`

Thin shell wrapper around sqlite3 for the 5-table schema defined in the spec. Agent calls this to persist and query data.

- [ ] **Step 1: Write scripts/db.sh**

The script should:
- Accept subcommands: `init`, `add-post`, `add-metrics`, `log-choice`, `query-posts`, `query-metrics`, `query-preferences`, `query-patterns`
- Database location: `$SKILL_DIR/data/xhs.db` (auto-detect skill directory)
- `init`: create all 5 tables (posts, post_metrics, user_choices, topic_candidates, comment_insights)
- `add-post`: accept JSON arg, insert into posts table, output `{"id": N}`
- `add-metrics`: accept JSON arg, insert into post_metrics
- `log-choice`: accept JSON arg, insert into user_choices
- `query-posts`: support `--today`, `--days N`, output JSON array
- `query-metrics`: support `--post-id N`, output JSON array
- `query-preferences`: aggregate user_choices to compute weights, output JSON
- All output as JSON using sqlite3 JSON mode

- [ ] **Step 2: Test init and basic operations**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  chmod +x scripts/db.sh && \
  scripts/db.sh init && \
  scripts/db.sh add-post '{\"date\":\"2026-04-15\",\"slot\":\"noon\",\"title\":\"测试帖子\",\"content\":\"测试内容\",\"tags\":\"[\\\"AI\\\",\\\"测试\\\"]\",\"status\":\"draft\"}' && \
  scripts/db.sh query-posts --today"
```

Expected: JSON output with the inserted post

- [ ] **Step 3: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add scripts/db.sh && \
  git commit -m 'feat: add scripts/db.sh — SQLite wrapper for 5-table schema'"
```

---

### Task 6: Copy and Adapt data/content-rules.md

**Files:**
- Create: `data/content-rules.md`
- Reference: `workflow/xhs-automation/data/content-rules.md`

- [ ] **Step 1: Copy content-rules.md**

Copy the existing file, it's already well-written and comprehensive.

```bash
ssh weiyong@100.79.106.110 "cp /Users/weiyong/Documents/10/shuling/workflow/xhs-automation/data/content-rules.md \
  /Users/weiyong/Documents/10/shuling/data/content-rules.md"
```

- [ ] **Step 2: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add data/content-rules.md && \
  git commit -m 'feat: add data/content-rules.md — content compliance rules'"
```

---

### Task 7: Write SKILL.md — The Core Brain

**Files:**
- Create: `SKILL.md` (at project root, replacing the old one which lives in skills/xiaohongshu/)

This is the most critical file. It must be a complete, executable playbook that any Agent can follow. Structure matches spec section 6 exactly.

- [ ] **Step 1: Write SKILL.md**

Full content following the spec:
- Section 1: Trigger words and use cases
- Section 2: First-time setup (blogger profile creation + cold-start seeding)
- Section 3: Daily workflow (topic research → draft → images → publish)
- Section 4: Daily review (data collection → insights → daily report)
- Section 5: Self-evolution engine (preference learning, content analysis, weekly evolution)
- Section 6: Content compliance rules (reference to data/content-rules.md)
- Section 7: Tool reference (all 4 scripts with usage examples)
- Section 8: Data structure reference (knowledge-base files + SQLite schema)

Key requirements:
- Every step must be "Agent-executable" — not "see research.py" but "do these specific actions"
- Include concrete scoring criteria, not vague "evaluate quality"
- Include the confidence_level → options reduction logic
- Include pattern lifecycle management rules
- Reference scripts by relative path: `scripts/xhs.sh`, `scripts/db.sh`, etc.

- [ ] **Step 2: Verify SKILL.md is readable and complete**

Read the file back and check: could an Agent with no prior context execute every section?

- [ ] **Step 3: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add SKILL.md && \
  git commit -m 'feat: add SKILL.md — complete Agent-executable playbook'"
```

---

### Task 8: Write Platform Adapters

**Files:**
- Create: `platform/hermes.md`
- Create: `platform/claude-code.md`
- Create: `platform/codex.md`

- [ ] **Step 1: Write platform/hermes.md**

Contents:
- Installation steps (copy skill to ~/.hermes/skills/social-media/xiaohongshu/)
- 2 cron job definitions (daily publish + daily review)
- Telegram interaction format
- Troubleshooting (MCP connectivity, login refresh)

- [ ] **Step 2: Write platform/claude-code.md**

Contents:
- Installation steps (copy to ~/.claude/skills/)
- Usage via /xiaohongshu command
- /loop configuration for daily automation
- Terminal interaction format

- [ ] **Step 3: Write platform/codex.md**

Contents:
- Installation steps (copy to ~/.codex/skills/)
- Usage instructions

- [ ] **Step 4: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add platform/ && \
  git commit -m 'feat: add platform adapters for Hermes, Claude Code, Codex'"
```

---

### Task 9: Write install.sh

**Files:**
- Create: `install.sh` (replace existing)

Simplified installer that:
1. Detects available platforms
2. Copies skill files to appropriate locations
3. Initializes SQLite database
4. Optionally configures Gemini API key
5. Verifies MCP connectivity

- [ ] **Step 1: Write install.sh**

- [ ] **Step 2: Test dry run**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  bash install.sh --dry-run"
```

- [ ] **Step 3: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add install.sh && \
  git commit -m 'feat: add simplified install.sh'"
```

---

### Task 10: Write HTML Template

**Files:**
- Create: `templates/post.html`

A reusable HTML template for generating XHS-style content cards (1080x1440px, 3:4 ratio). Agent fills in content, screenshot.cjs captures it.

- [ ] **Step 1: Write templates/post.html**

The template should:
- Use CSS variables for easy style switching (warm/dark/minimal)
- Each `.page` div is 1080x1440px
- Include Google Fonts (Noto Sans SC + Inter)
- Provide component classes: `.page-header`, `.info-card`, `.code-block`, `.tip-card`, `.cta-box`
- Be a complete, self-contained HTML file with placeholder content

- [ ] **Step 2: Test screenshot**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  NODE_PATH=\"\$(npm root -g)\" node scripts/screenshot.cjs templates/post.html /tmp/xhs-test/"
```

Expected: PNG files generated for each .page

- [ ] **Step 3: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add templates/post.html && \
  git commit -m 'feat: add HTML template for XHS content cards'"
```

---

### Task 11: Update README.md

**Files:**
- Modify: `README.md`

Update to reflect the new architecture and installation process.

- [ ] **Step 1: Rewrite README.md**

New structure:
- What this is (one paragraph)
- Quick start (3 steps: install, configure, first run)
- Architecture overview (Skill-as-Brain diagram)
- Supported platforms
- File structure
- How self-evolution works (brief)

- [ ] **Step 2: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git add README.md && \
  git commit -m 'docs: update README for new skill-as-brain architecture'"
```

---

### Task 12: End-to-End Verification

- [ ] **Step 1: Verify file structure**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  find . -not -path './.git/*' -not -path './skills/*' -not -path './workflow/*' -not -name '.DS_Store' -not -path './.idea/*' -not -path './.session-recorder/*' | sort"
```

Expected: Clean new structure with SKILL.md, scripts/, data/, knowledge-base/, templates/, platform/

- [ ] **Step 2: Verify scripts are executable**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  chmod +x scripts/xhs.sh scripts/db.sh && \
  scripts/db.sh init && echo 'DB OK' && \
  python3 scripts/image.py --check; echo \"image.py exit: \$?\""
```

- [ ] **Step 3: Verify SKILL.md is complete**

Read SKILL.md and confirm every section from the spec is present and actionable.

- [ ] **Step 4: Final commit with tag**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && \
  git tag -a v2.0.0 -m 'Skill-as-Brain redesign complete'"
```
