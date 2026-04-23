<!--
Reviewer's note
---------------
Platform targets:
  - Primary: Dev.to (frontmatter below is Dev.to-compatible; set `published: true` when ready)
  - Cross-post: Medium (import via Dev.to -> Medium, or paste directly; remove frontmatter)
  - Submission: Lobste.rs (tag: practices, ai)

Series positioning:
  - Part 2 of a 3-part series on building LLM-native agents
  - Part 1 (Skill-as-Brain): blog-1-skill-as-brain.en.md
    Link in prose: "In the last post I argued business logic belongs in Markdown, not Python..."
  - Part 3 (upcoming): "Self-evolving agents: preference learning + confidence + anti-ban"

Intentional divergence from the Chinese original:
  - Opened with a concrete dilemma (the "is it Minor or Patch?" question) instead of
    the Chinese narrative "上一篇聊完..."; Western tech readers want the problem first.
  - Subheadings converted to question/action format ("Why SemVer breaks on skills",
    not "1. 痛点").
  - Preserved the three-step decision walkthrough verbatim because it IS the argument.
  - Kept the final quote ("BRAIN changed? Your AI got a new personality. That's breaking.")
    as the closing line — it's the tweetable payload of the post.
  - Condensed the "适用边界" section slightly — the one-sentence heuristic is the keeper.

Suggested cover image:
  - A stylized version tag `v1.2.3` re-rendered as `BRAIN.HANDS.CALIB`, with each
    segment color-coded (brain=pink/purple, hands=blue, calib=gray). Plus a strike-through
    on `major.minor.patch`.
  - Alternative: a split diagram showing "SemVer thinks: software = tool" vs
    "Reality: skill = role."
  - 1000x420 works well for Dev.to cover_image.

Word count: ~2,350 words (target was 2,000-2,500).

Tags considered: ai, agents, versioning, skills. Dev.to allows up to 4.
-->

---
title: "BRAIN.HANDS.CALIB: Why SemVer Is Wrong for AI Skills (and What to Use Instead)"
published: false
description: "A three-part version scheme for AI agents that captures what SemVer can't: when you changed your agent's personality vs. just its tools."
tags: ai, agents, versioning, skills
canonical_url:
cover_image:
---

> **BRAIN changed? Your AI got a new personality. That's breaking — not a new feature.**

Someone asked me last week: "I tweaked the prompt in my agent's skill file. Is that a Patch bump, or a Minor?"

I stared at the question for a minute. The honest answer is: **SemVer doesn't know, and neither did I the first three times I shipped a skill.**

In the last post I argued that business logic for an LLM-native agent belongs in Markdown, not Python — what I called *Skill-as-Brain*. The follow-up question I keep getting is less philosophical and more operational: **once your skill is a living thing with personality and judgment, how do you version it?**

My agent [ShuLing](https://github.com/AI-flower/shuling) (MIT-licensed, coaches creators on **Xiaohongshu — RED, China's largest lifestyle-sharing platform**) is on v2.3.0 now. It got there by repeatedly tripping over SemVer, until I replaced it with a three-part scheme called **BRAIN.HANDS.CALIB**. This post covers why SemVer misfires on skills, what the three segments mean, and a real v2.2.0 → v2.3.0 decision where the "obvious" answer was wrong.

Copy the scheme wholesale if you like. MIT, no attribution needed.

---

## Why SemVer breaks on skills

SemVer (Major.Minor.Patch) is the old friend of software engineering. Its implicit model is:

> "Software is a tool. It has an API, it has behavior. A breaking change is an API signature change. A non-breaking change is a new interface or a bugfix."

That model is basically fine for libraries, frameworks, and CLIs. But on a skill like ShuLing — a thing with a persona, a decision flow, and continuous learning — I hit three situations SemVer couldn't answer.

### Situation 1: I tweaked a prompt. Minor or Patch?

SemVer's verdict: a prompt is "text content." No API broke. No new feature. Therefore: **Patch.**

The problem: one word's difference in a prompt can completely change the AI's output style. Last week my user felt "ShuLing talks like a friend." This week suddenly it's "ShuLing sounds like a consulting pitch deck." From the user's perspective, **the role's personality changed** — that is obviously not a bugfix-sized event.

### Situation 2: I migrated the DB schema but the business didn't change. Major?

ShuLing v2.1.0 introduced a `request_log` table for MCP call tracing. This change:

- Zero perceived impact on user business flow
- But you **must** run a migration, or the new version crashes on boot

SemVer says: not breaking (no API change). The user's actual experience: **they must execute a migration or the thing won't start.** That mismatch quietly burns people.

### Situation 3: The AI's decision style changed. Users need to re-orient.

v2.0 → v2.1 introduced "Anti-Ban Shield" — throttling, quotas, and risk-control decisions. From the API perspective, every MCP interface signature was unchanged. SemVer says: Minor.

From the user's perspective: **"it used to send 10 posts when I told it to"** vs. **"now it judges for itself, refuses, or delays"** — these are two different agents. That *is* breaking. SemVer just can't see it.

---

The core problem is philosophical:

> **SemVer assumes software is a tool. A skill is a role. Role upgrades shouldn't be versioned like tool upgrades.**

A tool's breaking change is "the interface changed, callers must update their code."
A role's breaking change is "the personality changed, users must rebuild their mental model."

These are not the same thing.

## The three segments: BRAIN.HANDS.CALIB

So ShuLing v2.3.0 switched to a three-part version:

```
v<BRAIN>.<HANDS>.<CALIB>
     ↑       ↑        ↑
   brain    hands   knobs
  changed  changed  turned
```

Here are the definitions, a real ShuLing example for each, and a "don't accidentally pick the wrong segment" warning.

### BRAIN: core decisions / self-evolution algorithms / business capability

**Definition:** SKILL.md core flow refactors, self-evolution algorithm generation changes, business capability jumps. **Breaking** — users must explicitly migrate or re-understand the role.

**Real example:** v2.0.0 → v2.1.0 "Anti-Ban Shield." On the surface it just added throttling and quotas (looks like HANDS+1). But what it actually introduced was **risk-control decision-making** as a new business capability — the AI went from "obedient executor" to "agent with risk awareness." That's a personality change. BRAIN+1.

**Warning:** don't bump BRAIN just because "a lot of files changed." If the algorithm files got rewritten but the user-perceived decision flow didn't change (say, you rewrote it in a different language), that's still HANDS. **The BRAIN test is "did output/behavior characteristics change?" — not lines of code.**

### HANDS: execution layer / data layer / interface layer

**Definition:** new or rewritten `scripts/`, DB schema migrations, MCP interface replacements, sub-skill directory changes, dependency requirement changes. **Generally backward-compatible** — may need a migration run.

**Real example:** v2.1.0 → v2.1.1 "Request Log." Looks like a bugfix (CALIB+1 territory), but actually added the `request_log` table + `scripts/log_request.py` + a migration. **New table = HANDS+1.** CALIB doesn't get to carry schema changes on its back.

**Warning:** don't count "edited `scripts/` but no new capability" (say, pure bugfix) as HANDS. The test: **did you introduce a new capability unit (new script, new table, new interface)?** Flipping an `if` branch in an existing script to fix a bug is still CALIB.

### CALIB: parameters / thresholds / prompt nudges / docs

**Definition:** threshold/keyword/throttle parameter adjustments, bugfixes, prompt nudges, CHANGELOG/doc updates. **Zero breaking** — users upgrade without noticing.

**Real example:** v2.1.1 → v2.1.2 "Release Polish." Added the CHANGELOG / UPGRADE / RELEASING triplet + a migrations skeleton. Pure process hygiene, zero new business capability. CALIB+1, perfect fit.

**Warning:** **"prompt nudge" and "prompt template rewrite" are two different animals.** The former is CALIB (rewording, temperature tweak, reorder). The latter is HANDS (new template file, template engine logic change) — v2.3.0 is exactly the latter, more on that below.

---

Rolled up into a cheat sheet:

| Dimension         | BRAIN+1                 | HANDS+1                    | CALIB+1                  |
| ----------------- | ----------------------- | -------------------------- | ------------------------ |
| Surface of change | SKILL.md core flow      | scripts/ DB MCP interfaces | parameters/prompts/docs  |
| User perception   | Role's personality shifted | Might need a migration   | None                     |
| Breakage          | Breaking                | Generally compatible       | Zero                     |
| Typical trigger   | Algorithm gen, capability jump | New table, new script, rewrite | Bugfix, text nudge |
| Migration action  | Explicit upgrade + rebuild mental model | Run migrations | Just `git pull`       |

## Real walkthrough: v2.2.0 → v2.3.0 "Pure Image Pipeline"

This is the most important section. Definitions are easy; **judging edge cases is the hard part.** Below is the real decision process for ShuLing v2.3.0 — where the obvious answer was wrong.

### The changeset

v2.3.0, codenamed "Pure Image Pipeline":

```bash
# Removed
- scripts/screenshot.cjs            # Killed HTML-screenshot fallback path
- templates/post.html               # Killed HTML template
- skills/xhs-content-generator/     # Deleted entire sub-skill directory

# Added
+ prompts/image_prompt.txt          # 77-line new prompt template
+ prompts/image_prompt_short.txt    # 6-line fallback short template
+ migrations/v2.3.0.sh              # Idempotent migration script

# Rewritten
~ scripts/image.py                  # ~240-line diff, added render_prompt /
                                    # _gen_gemini_native / _load_reference_image /
                                    # --short flag
~ scripts/image.py CLI              # New --topic / --outline-file / multiple --reference

# Config change
~ Gemini API Key: optional → required

# Doc changes
~ SKILL.md §0 step 2: image API optional → required
~ SKILL.md §2.3: image generation flow rewritten
~ SKILL.md §8: error handling — HTML fallback → hard stop
~ landing/index.html: version badge now dynamic
~ CHANGELOG / UPGRADE / RELEASING synced
```

Looks big — killed a fallback path, rewrote a core script, added `prompts/`, deleted a sub-skill, flipped Gemini Key from optional to required.

First instinct: "Hard-stop for existing users, must be BRAIN+1, right?"

Walk through the three-step decision process:

### Step 1: Did the algorithm layer change?

Checks:

- `preference_learning` (preference-learning formula): **unchanged**
- `confidence` (confidence scoring): **unchanged**
- `drafting` (draft generation formula): **unchanged**
- §0a business routing logic: **not a character touched**

**Verdict: not BRAIN.**

Core business capability (ShuLing's "brain") is fully untouched. How it understands user intent, how it routes tasks, how it learns from historical data — all the decision behaviors are identical.

### Step 2: Is it only parameters or bugs?

Checks:

- Removed an entire fallback path (screenshot.cjs + post.html): **not a bug**
- Rewrote 240 lines of image.py: **not a bug**
- Added a new `prompts/` directory: **structural change**
- User-facing behavior shift: no Gemini Key = no go: **dependency requirement changed**

**Verdict: not CALIB.**

CALIB's floor is "users upgrade without noticing." v2.3.0 obviously can't pull that off — an existing user who only had the HTML-screenshot path configured and no Gemini Key will `git pull` and immediately break.

### Step 3: Only HANDS is left

- `scripts/image.py` rewrite → classic HANDS signal
- New `prompts/` directory → a new capability unit
- Deleted `skills/xhs-content-generator/` sub-skill → structural change
- Gemini Key required → dependency requirement change
- `migrations/v2.3.0.sh` must be run → the HANDS trademark

**Final verdict: HANDS+1 → v2.3.0.**

### The counterintuitive bit: why not BRAIN?

This call felt wrong to my gut — "config optional → required" sounds breaking. I sat with it for a while, and here's how I eventually talked myself into HANDS:

1. **The user-perceived "removal of fallback" is at the config layer.** Before, missing key → HTML fallback. Now, missing key → immediate error. The behavioral difference lives on the "missing-config" edge path, not the main business path. For a normally-configured user (has the key), output quality improves but the decision style is identical.

2. **The AI's personality didn't change.** §0a routing logic, not a character touched. ShuLing is still ShuLing — understands intent the same way, learns from history the same way. It just swapped tools in its "hands" (HTML → native image model).

3. **The counter-example:** if I'd simultaneously rewritten the flow semantics in SKILL.md §2.3 (say: "each image sheet learns its own reference, cross-sheet style consistency"), then I'd have to bump BRAIN — because *that* would be a decision-style change.

Which gives us a high-value heuristic:

> **"Swapped tools" vs. "personality changed."** — New tool is HANDS. New personality is BRAIN.

image.py going from "HTML-screenshot + Gemini two-lane" to "pure Gemini" is a tool swap. No personality change. HANDS+1.

---

Full version history walked through the same lens, as a reference table:

| Version               | Codename                      | Main changes                                      | Decision |
| --------------------- | ----------------------------- | ------------------------------------------------- | -------- |
| v2.0.0 → v2.1.0       | Anti-Ban Shield               | Throttle + quota + **risk-control decisions**     | BRAIN+1  |
| v2.1.0 → v2.1.1       | Request Log                   | MCP calls persisted to table (**new table**)      | HANDS+1  |
| v2.1.1 → v2.1.2       | Release Polish                | CHANGELOG/UPGRADE/RELEASING triplet               | CALIB+1  |
| v2.1.2 → v2.1.3       | Friendly Onboarding           | install.sh 6 modes + preflight human mode         | CALIB+1  |
| v2.1.3 → v2.2.0       | Existing Creator Support      | §0c intake + import-existing.sh + DB `source` col | HANDS+1  |
| v2.2.0 → v2.2.1       | Migration Safety Fix          | Pure bugfix                                       | CALIB+1  |
| v2.2.1 → v2.3.0       | Pure Image Pipeline           | image.py rewrite + kill fallback + new prompts/   | HANDS+1  |

v2.1.3 → v2.2.0 was another borderline call (§0c is purely additive — doesn't change existing flows — but the DB added a `source` column). I ruled it HANDS+1 because "new field + new script" crosses the line. The rule for these edge cases is simple: **any time you touch schema or `scripts/`, it's at least HANDS+1.**

## The supporting artifacts

Three-part version numbers alone don't do the work. To make this usable for skill authors *and* users, you need a small set of conventions around it. ShuLing has five:

### 1. Dual-column CHANGELOG

Every release gets two columns:

```markdown
## [v2.3.0] Pure Image Pipeline - 2026-04-20

### User-visible changes
- Image generation fully switched to Gemini 2.0 Flash — covers more stable
- New --topic / --outline-file / --reference CLI parameters
- Gemini API Key is now required (was optional)

### How to upgrade
1. bash migrations/v2.3.0.sh
2. Add GEMINI_API_KEY to .env
3. Re-run preflight --human to verify
```

"User-visible changes" is the business-level narrative. "How to upgrade" is the concrete action list. Readers don't have to mine migration steps out of a diff.

### 2. migrations/vX.Y.Z.sh

Every HANDS+1 or above release ships an idempotent, retryable migration script:

```bash
#!/bin/bash
# migrations/v2.3.0.sh
set -euo pipefail

# Idempotent: safe to re-run
if [ -f "scripts/screenshot.cjs" ]; then
  rm scripts/screenshot.cjs
  echo "[v2.3.0] removed legacy screenshot.cjs"
fi

# Preflight: Gemini Key is now required
if ! grep -q "GEMINI_API_KEY" .env 2>/dev/null; then
  echo "[v2.3.0] ERROR: GEMINI_API_KEY missing in .env"
  exit 1
fi
```

Two principles: **idempotent** (run N times, same result) + **preflight checks** (fail early on missing config).

### 3. UPGRADE.md

One place for all migration instructions, organized by "from → to":

```markdown
## Upgrade from v2.2.x to v2.3.0
1. ...
## Upgrade from v2.1.x to v2.3.0
1. First run v2.2.0 migration
2. Then run the v2.3.0 migration above
```

Users don't have to stitch together CHANGELOG entries.

### 4. RELEASING.md

A release SOP to reduce finger-fumble. Mine looks roughly like:

```markdown
1. Decide BRAIN / HANDS / CALIB segment
2. Update VERSION file
3. Write dual-column CHANGELOG
4. If HANDS+ bumped, write migrations/vX.Y.Z.sh
5. Update UPGRADE.md
6. Run preflight + migration self-test
7. git tag + push
```

### 5. VERSION file: pin the capability list

This is the one I'd most recommend stealing. ShuLing's `VERSION` isn't a single line — it's 60 lines of YAML explicitly enumerating what BRAIN / HANDS / CALIB contains at the current version:

```yaml
version: "2.3.0"
codename: "Pure Image Pipeline"
released: "2026-04-20"

brain:
  # Core decisions / business capabilities
  - preference-learning    # preference learning
  - confidence-scoring     # confidence scoring
  - anti-ban-shield        # risk-control (introduced v2.1.0)
  - business-routing       # §0a routing

hands:
  # Execution / data / interfaces
  - request-log            # MCP call logging (v2.1.1)
  - import-existing        # Existing-creator intake (v2.2.0)
  - image-pipeline-pure    # Pure-Gemini image pipeline (v2.3.0)

calib:
  # Parameters / text / docs
  - prompts/image_prompt.txt
  - prompts/image_prompt_short.txt
  - thresholds/*.yaml
```

This makes "the changeset" a first-class citizen. Every release, you have one specific action: **move or add an item in VERSION.** Once you've done that, the version number picks itself.

## When (not) to use BRAIN.HANDS.CALIB

Not a silver bullet.

**Skip it if:**

- **IDE plugins, tool libraries, CLI frameworks.** "Software is a tool" — your users consume an API. Stick with SemVer.
- **Pure no-judgment agents.** Simple Q&A bots, single-task script skills. No "role," no "decision flow" — three segments would be over-engineering.
- **One-shot skills.** Disposable scripts. `v1` / `v2` is plenty.

**Use it if:**

- You have explicit decision flows and business routing (like ShuLing's §0a / §0b / §0c)
- The skill self-evolves continuously (prompt iteration, threshold tuning, algorithm upgrades)
- There's real migration cost on the user side (DB dependencies, external API dependencies, config requirements)
- Users have expectations about the "role's personality" (daily assistant, content creator, coach-like agent)

**One-line test:**

> If your skill is "a living thing" and not "a hammer," it's worth using BRAIN.HANDS.CALIB.

## The one-liner

Opening quote, restated — it's the whole post compressed:

> **BRAIN changed? Your AI got a new personality. That's breaking — not a new feature.**

SemVer was born when "software is a tool." It can't see personality because it was never designed to. AI skills are **things with personalities, evolution arcs, and symbiotic relationships with users** — their version numbers need to express three tiers of change: "the brain moved," "the hands swapped tools," "we turned a knob."

BRAIN.HANDS.CALIB isn't a standard. It's the convention ShuLing walked into after four versions of tripping. If you're writing your own skill, copy it — MIT. Version scheme, dual-column CHANGELOG, VERSION YAML, migration convention. No attribution required.

Next time someone asks why you didn't use SemVer, just send them this post.

## Try it / argue with it

- **Repo:** [github.com/AI-flower/shuling](https://github.com/AI-flower/shuling) — MIT. Star it if this helped you think through your own versioning.
- **Previous post in the series:** *Skill-as-Brain: I Replaced My Agent's Python Business Logic with 1,208 Lines of Markdown*
- **Next post (preview):** *ShuLing's self-evolution stack: preference learning + confidence + anti-ban in practice*

If you're building a skill with interesting edge cases in versioning — especially ones where BRAIN.HANDS.CALIB still feels wrong — drop them in the comments or file them as issues on the repo. I'm actively collecting edge cases for a future "hard calls" post.
