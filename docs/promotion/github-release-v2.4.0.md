<!--
  INSTRUCTION BLOCK — How to use this file
  ----------------------------------------
  This is the body content for the GitHub Release at:
    https://github.com/AI-flower/shuling/releases/new

  - Release title:  v2.4.0 — Agent-Friendly Upgrade Infrastructure
  - Tag:            v2.4.0
  - Target branch:  main
  - Previous tag:   v2.3.0
  - Paste everything BELOW the horizontal rule into the Release body.
  - Do NOT include this HTML comment block when pasting.
-->

---

## TL;DR

**ShuLing v2.4.0 — "Agent-Friendly Upgrade Infrastructure"** — released **2026-04-23**.

v2.3.0 shipped 48 hours ago. During that upgrade my agent manually pushed 9 steps — backup, rsync, run migrations, patch `runtime.env`, migrate preferences, update scheduler prompt, `pip install`, run preflight, validate schemas. This release codifies all of that into **one command**: `bash install.sh upgrade-all`. Pure `HANDS+1` engineering — SKILL.md is byte-identical to v2.3.0.

> 薯灵 v2.4.0 把上次 v2.2.1→v2.3.0 agent 手推的 9 步升级，固化成一条命令 + 一组幂等迁移 + 一层 JSON 可观测性。业务流程、自进化算法、AI 行为与 v2.3.0 完全一致，零破坏性变更。

---

## Highlights

### One-command upgrade across all install targets
`bash install.sh upgrade-all [--dry-run] [--json] [--target=<name>]` discovers every installed instance under `~/.codex/skills/*`, `~/.hermes/skills/**`, `~/.claude/skills/*` and upgrades them uniformly through 6 steps per target, with **independent failure isolation** — one broken target never blocks the rest.

### JSON observability everywhere
Every step — `backup / rsync / migration / upgrade_hook / pip_install / preflight` — emits single-line machine-readable JSON. Agents can now audit why each step ran, skipped, or changed what, without scraping log prose.

### Idempotent migrations + contiguous version line
The 4 existing migrations are now guard-wrapped (safe to rerun), and new `v2.2.1.sh` / `v2.3.0.sh` stubs keep the version line unbroken. A new `__migrations` table tracks applied versions (`scripts/db.sh init` tables: **10 → 11**).

### Upgrade hooks codified
`upgrade-hooks/v2.3.0/` ships 3 hooks the next agent doesn't have to re-derive: runtime-env 4-field sync, `preferences.json` schema flat→nested migration, Hermes `jobs.json` wording update ("HTML 截图" → "Gemini 生图"). All idempotent, all JSON stdout, all non-interactive.

### Schema drift validator caught a real bug
`python3 scripts/validate.py --target <path>` validates `state / profile / preferences / audit-report` against their schemas. Exit codes `0/1/2`. On first run it caught a codex target whose `state.json` was missing `setup_completed` — a silent drift no one had noticed.

---

## Breaking Changes

**NONE — this is a pure engineering upgrade. SKILL.md is unchanged.**

Business flow, self-evolution algorithm, AI behavior, preference inference logic, image pipeline contract — all byte-identical to v2.3.0. If you already run v2.3.0 successfully, v2.4.0 changes nothing you can see as a human user; it only changes what your *agent* sees when it upgrades you.

> 存量用户零行为变更。v2.4.0 只升级"升级本身"。

---

## What's New

### 🧠 Brain (SKILL.md)

**Unchanged.** `SKILL.md` diff vs. v2.3.0 = 0 lines. The Brain/Hands/Calib contract made this possible: infrastructure work is a `HANDS+1` bump, no `BRAIN+1` required.

### ✋ Hands (scripts, migrations, hooks)

- **`install.sh` — 487 → 979 lines.** New `upgrade-all` subcommand with a 6-step per-target pipeline (discover → backup → rsync → migrate → hooks → preflight). `--dry-run` prints plans without mutation. `--json` switches all output to NDJSON. `--target=<name>` scopes to one install.
- **`migrations/_applied_table.sql` + `_guard.sh`** — shared idempotency primitives. Every migration now opens with the guard and writes its version into `__migrations` on success.
- **4 existing migrations converted** to guard-wrapped, single-line JSON output. Safe to rerun; no-ops on second invocation.
- **`migrations/v2.2.1.sh` / `v2.3.0.sh`** — stub placeholders so the version line is contiguous. Future agents can grep the directory and get a complete history.
- **`scripts/db.sh init`** also creates `__migrations`. `.tables` count: **10 → 11**.
- **`upgrade-hooks/README.md` + `v2.3.0/`** with 3 hooks:
  - `01-runtime-env-sync.sh` — ensures the 4 required env fields exist, non-destructive.
  - `02-preferences-migrate.sh` — flat → nested schema for `preferences.json`.
  - `03-hermes-jobs-update.sh` — updates the scheduler prompt wording.
- **`requirements.txt`** — derived by grepping real `import` statements in `scripts/*.py`. Currently just `jsonschema>=4.0,<5.0`; `image.py` and `preflight.py` remain pure stdlib.
- **`scripts/validate.py`** (new) — schema drift checker. Glob support for `audit-*.json`. Exit codes: `0 = clean`, `1 = drift`, `2 = error`.
- **`scripts/preflight.py`** — new `check_schemas()` section; drift is reported as `action="optional"` so it never hard-stops existing installs.

### 🎛 Calib (docs)

- **`docs/` reorganised** into five subdirectories: `adr/`, `plans/`, `runbooks/`, `reference/`, `archive/`.
- **11 historical docs** `git mv`-d into the new layout, **preserving file history**.
- **195 dangling checkboxes** in old superpowers plans archived with reconcile notes — so nothing looks "in-progress" that isn't.
- **`docs/README.md`** — single entry-point index into the new tree.

### 🔀 Migration strategy

Zero-friction by design:
1. `bash install.sh upgrade-all --dry-run` — prints the full plan, mutates nothing.
2. `bash install.sh upgrade-all --json | jq '.'` — pipe to `jq` for audit.
3. Each target is processed independently; a failure in target A does not block targets B/C.
4. All migrations are idempotent; rerunning the command on an already-upgraded install is a no-op (and the JSON output proves it).

---

## Installation / Upgrade

### New users

```bash
git clone https://github.com/AI-flower/shuling.git
cd shuling
bash install.sh
```

No change from v2.3.0 for first-time installs.

### Existing users (upgrading from v2.3.0)

**Recommended first step — dry-run:**

```bash
cd /path/to/shuling
git pull
bash install.sh upgrade-all --dry-run --json | jq '.'
# Inspect the plan. No state is mutated.
```

**Then execute:**

```bash
bash install.sh upgrade-all
# Or, scoped to one install:
bash install.sh upgrade-all --target=codex-main

# Optional — validate schemas across all targets:
python3 scripts/validate.py --target ~/.codex/skills/shuling
```

> 升级命令：`git pull && bash install.sh upgrade-all --dry-run` 先看计划，再 `bash install.sh upgrade-all` 真正执行。每个 target 失败隔离，不会互相拖垮。

---

## Full Changelog

- Detailed change log: [`CHANGELOG.md`](https://github.com/AI-flower/shuling/blob/v2.4.0/CHANGELOG.md)
- Compare view: https://github.com/AI-flower/shuling/compare/v2.3.0...v2.4.0

---

## Acknowledgments

This release exists because the v2.2.1 → v2.3.0 upgrade 48 hours ago was **painful in a specific, reproducible way**: my agent had to manually drive 9 distinct steps, each with its own failure mode, no shared logging format, no dry-run, no rollback breadcrumbs. That experience was captured in [`docs/adr/agent-upgrade-design.md`](https://github.com/AI-flower/shuling/blob/v2.4.0/docs/adr/agent-upgrade-design.md) and turned into this release's design spec.

- **The v2.3.0 upgrade session itself** — for being annoying enough to be worth automating.
- **ADR `docs/adr/agent-upgrade-design.md`** — the design doc that scoped `upgrade-all` before a single line was written.
- **Early testers** running ShuLing across multiple parallel installs — your dogfooding surfaced the target-isolation requirement.

> 感谢 48 小时前那次痛苦的手动升级，也感谢先写 ADR 再写代码的纪律。

---

## What's Next — v2.5.0 Preview

**v2.5.0: SKILL.md Slimming (A1 · P1 on the roadmap).** The current `SKILL.md` is 1208 lines — large enough that agents pay real context cost on every invocation. v2.5.0 will split it into a **≤300-line main file** plus chapters loaded on demand, without changing the Brain/Hands/Calib contract or any external behavior. The ceiling for the main file is a hard budget, not a suggestion.

Roadmap item A1 P1 ("Brain size as a first-class metric") is the driver; this release's zero-touch upgrade infrastructure is a prerequisite for confidently landing that refactor in existing installs.

---

*ShuLing is an MIT-licensed open-source growth skill for Xiaohongshu creators, built on a Skill-as-Brain architecture (`SKILL.md` as the brain, `scripts/` as the hands). Version numbers follow `BRAIN.HANDS.CALIB`. Landing page: https://shuling.pages.dev*
