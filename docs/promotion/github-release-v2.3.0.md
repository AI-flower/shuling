<!--
  INSTRUCTION BLOCK — How to use this file
  ----------------------------------------
  This is the body content for the GitHub Release at:
    https://github.com/AI-flower/shuling/releases/new

  - Release title:  v2.3.0 — Pure Image Pipeline
  - Tag:            v2.3.0
  - Target branch:  main
  - Previous tag:   v2.2.1
  - Paste everything BELOW the horizontal rule into the Release body.
  - Do NOT include this HTML comment block when pasting.
-->

---

## TL;DR

**ShuLing v2.3.0 — "Pure Image Pipeline"** — released **2026-04-21**.

This is a `HANDS+1` release: the image pipeline has been tightened to a single AI-native path. The HTML-screenshot fallback is gone, Gemini API Key is now mandatory, and multi-page cover consistency is dramatically improved via two-stage reference-image feedback. Algorithm layer is unchanged.

> 薯灵 v2.3.0 把图像管线从"AI 生图 + HTML 截图双通道"收紧为"纯 AI 生图单通道"，代价是 Gemini API Key 从可选变为必需，收益是多页封面风格一致性显著提升。

---

## Highlights

### Single-Source Image Pipeline
The HTML-screenshot degradation path is **completely removed**. No more `templates/post.html + Playwright screenshot` fallback, no more dual-rail failure surface. One pipeline, one contract.

### Two-Stage Cover-Reference Feedback
`image.py --reference <cover>` now injects the first cover back into every subsequent content page. Powered by Gemini 3 Pro Image (Nano Banana Pro) multimodal, this produces visibly more consistent 9-page posts — an idea inspired by the **RedInk** project.

### Prompt Templates, Externalised
Prompts are no longer hardcoded. `prompts/image_prompt.txt` (77 lines, full) and `prompts/image_prompt_short.txt` (6 lines, minimal fallback) are now first-class assets — you can iterate prompts without touching Python.

### Dynamic Landing Page
`shuling.pages.dev` now reads version from the GitHub Releases API. Publishing a release auto-syncs the landing page. No more manual version bumps.

### Legacy Sub-Skill Retired
`skills/xhs-content-generator/` has been removed. The main `shuling` skill is now the single source of truth for the post-generation flow.

---

## Breaking Changes

**Read this before upgrading.**

1. **Gemini API Key is now REQUIRED.** `install.sh` will hard-stop if no key is configured. Existing installs with a key already set will not be re-prompted.
2. **HTML screenshot fallback is gone.** If your existing deployment was silently relying on `scripts/screenshot.cjs` as a backup, **publishing will fail after upgrade** until you configure Gemini.
3. **`skills/xhs-content-generator/` is deleted.** If any of your internal automation referenced it directly, update the path to `skills/shuling/`.
4. **`generated_images.prompt` column semantics changed.** It now stores `page_content` (short semantic phrase) rather than the full raw prompt. Historical rows are untouched; new rows follow the new format.

> 存量用户请注意：之前靠 HTML 截图兜底发帖的部署，升级后必须先配好 Gemini Key，否则发帖链路会硬停。建议升级后立即执行 `python3 scripts/image.py --check`，返回 0 才算迁移完成。

---

## What's New

### 🧠 Brain (SKILL.md)

- **§0 Step 2** — Image generation API reclassified: `optional` → `required`. Wording replaced with hard-stop semantics.
- **§2.3** — Image generation flow rewritten around a single AI-native path, two-stage cover reference, and `--short` prompt fallback.
- **§8** — Exception matrix updated: "Gemini unavailable → HTML screenshot fallback" replaced with "hard-stop + prompt user to configure key".
- **DB schema** — `generated_images.prompt` column now stores `page_content` (short semantic), not the full prompt text.

### ✋ Hands (scripts & files)

- **`scripts/image.py` rewritten** (~240-line diff):
  - `render_prompt(page_type, page_content, full_outline, user_topic, short)` — template renderer.
  - `_gen_gemini_native()` — isolated gemini-native protocol branch.
  - `_load_reference_image()` — supports `--reference` cover re-injection.
  - `--short` flag — switches to the minimal prompt template.
  - CLI additions: `--topic`, `--outline-file`, repeatable `--reference`.
- **Deleted files:**
  - `scripts/screenshot.cjs` (HTML screenshot fallback)
  - `templates/post.html` (448-line HTML template)
  - `skills/xhs-content-generator/` (entire legacy sub-skill directory)
- **`scripts/preflight.py`** — image API status `optional` → `required`.
- **`install.sh`** — stronger warning + hard-stop when Gemini Key is missing.
- **`config/runtime.env.example`** — variable docs updated.

### 🎛 Calib

- `docs/capability-overview.md`, `docs/shuling-full-spec.md`, `docs/platform/hermes.md` — all HTML-screenshot paragraphs removed for consistency with the new single-pipeline contract.

### 🌐 Landing / Docs

- `landing/index.html` — version numbers are now fully dynamic (driven by GitHub Releases API).
- Future releases auto-propagate to `shuling.pages.dev` — no more manual edits.

### 🔀 Roadmap Adjustment

The originally planned v2.3.0 theme, **Human Rhythm (行为节奏模拟)**, has been deferred to **v2.4.0+**. This release's scope was pivoted to image-pipeline tightening based on real deployment feedback.

---

## Installation / Upgrade

### New users

```bash
git clone https://github.com/AI-flower/shuling.git
cd shuling
bash install.sh
# You will be asked for a Gemini API Key. This is mandatory.
```

### Existing users (upgrading from v2.2.x)

```bash
cd /path/to/shuling
git pull
bash install.sh
# If you already have GEMINI_API_KEY configured, you won't be re-prompted.
# If not, install.sh will now hard-stop until you provide one.

# Verify the new pipeline before running daily flows:
python3 scripts/image.py --check
# Must return exit code 0.
```

> 升级命令：`git pull && bash install.sh && python3 scripts/image.py --check`。`--check` 返回 0 才算升级成功。

---

## Full Changelog

- Detailed change log: [`CHANGELOG.md`](https://github.com/AI-flower/shuling/blob/v2.3.0/CHANGELOG.md)
- Compare view: https://github.com/AI-flower/shuling/compare/v2.2.1...v2.3.0

---

## Acknowledgments

- **RedInk** — the two-stage cover-reference idea (first-cover-as-reference for subsequent pages) originated from the RedInk project. Thank you for the inspiration.
- **Gemini 3 Pro Image (Nano Banana Pro)** team — the multimodal reference-image capability is the backbone of this release's consistency upgrade.
- **Community contributors** — every issue, patch, and real-world deployment report shaped this pipeline tightening. Keep them coming: PRs and issues are always welcome at [AI-flower/shuling](https://github.com/AI-flower/shuling).

> 感谢 RedInk 项目的"首图回灌"思路、感谢 Gemini 3 Pro Image 团队的多模态能力，也感谢每一位跑在真实部署上的早期用户。

---

## What's Next — v2.4.0 Preview

**v2.4.0: Agent-Friendly Upgrade Infrastructure.** The next release will focus on making ShuLing upgrades machine-readable and agent-friendly — version diff manifests, automated migration hints, and a structured capability surface that downstream agents can consume without parsing CHANGELOG.md by hand.

The deferred **Human Rhythm (行为节奏模拟)** theme is now scheduled for v2.4.0+.

---

*ShuLing is an MIT-licensed open-source growth skill for Xiaohongshu creators, built on a Skill-as-Brain architecture (SKILL.md as the brain, `scripts/` as the hands). Version numbers follow `BRAIN.HANDS.CALIB`. Landing page: https://shuling.pages.dev*
