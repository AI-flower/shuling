<!--
Reviewer's note
---------------
Platform targets:
  - Primary: Dev.to (frontmatter below is Dev.to-compatible; set `published: true` when ready)
  - Cross-post: Medium (import via Dev.to -> Medium, or paste directly; remove frontmatter)
  - Submission: Hacker News (title suggestion for HN: "Skill-as-Brain: I replaced Python business logic with 1,208 lines of Markdown")

Intentional divergence from the Chinese original:
  - Opened with a punchier hook (numbers + claim) instead of the narrative "那天晚上我盯着 VS Code"
    moment; the Chinese reader is patient, the English tech reader skims.
  - Subheadings converted to question/action format (e.g., "Why Markdown beats code for
    business rules", not "2. 顿悟").
  - Added context on Xiaohongshu (RED) since Western readers won't know it.
  - Collapsed the Chinese section "6. 适用边界" into a shorter "When (not) to use this" block;
    the one-sentence heuristic is the keeper.
  - Strengthened the end CTA: GitHub star + Twitter/X follow + comment-with-your-stack prompt.
  - Kept all pull quotes, the three-layer diagram, the routing table, and BRAIN.HANDS.CALIB
    teaser verbatim (all load-bearing for the series).

Suggested cover image:
  - A split image: left side a dense Python file with prompt strings highlighted, right side
    a clean Markdown table. Caption: "Execution vs. Reading."
  - Alternative: the three-layer architecture diagram (Brain / Hands / Memory) rendered in
    a single tall SVG. If using Dev.to, 1000x420 works well as cover_image.

Word count: ~2,850 words (target was 2,500-3,500).

Tags considered: ai, agents, claude, skills. Dev.to allows up to 4.
-->

---
title: "Skill-as-Brain: I Replaced My Agent's Python Business Logic with 1,208 Lines of Markdown"
published: false
description: "A real-world Claude Code skill architecture where all branching, state, and business rules live in a single Markdown file — and why this is where LLM-native apps are headed."
tags: ai, agents, claude, skills
canonical_url:
cover_image:
---

Last quarter I deleted ~10,000 lines of Python from my AI agent and replaced it with a single 1,208-line Markdown file. The agent got more reliable, cheaper to change, and suddenly portable across three different AI platforms (Claude Code, Codex, Hermes) without any business logic duplication.

This post is about why that happened, and why I now think **putting business logic in code was the wrong default all along — at least for LLM-driven agents**.

## The embarrassing v1

ShuLing ("薯灵") is an AI agent that coaches creators on **Xiaohongshu (RED, China's largest lifestyle-sharing platform)** — think of it as a mix between an editorial assistant, a growth advisor, and a post-mortem coach for content creators.

Version 1 was a very "respectable" AI agent stack: Python skeleton, OpenAI SDK, a handful of `.py` files stuffed with prompt templates, a maze of `if/else` statements orchestrating flow, and a 400-line system prompt glued together from f-strings.

Sound familiar? This was more or less the default for anyone "serious" about building agents in 2024.

Then it started breaking.

I wanted to add an onboarding flow — the agent should ask a new creator about their follower count, niche, and most recent viral post, then branch based on their answers. So I added 200 lines to `prompt_templates/onboarding.py`. Ran it. The *daily content-planning* flow broke, because the new system prompt confused a state variable from earlier turns.

So I added a `current_stage` field to the Python state, gated prompt variants with `if stage == "onboarding"`, and shipped. Then I realized: **the AI had no idea what stage it was in.** The stage lived in my Python. The AI just saw whatever prompt I assembled. I had to re-state the stage inside the prompt itself — creating a second source of truth that would inevitably drift.

A few weeks in, here's what my life looked like:

- **Touching a prompt risked breaking code logic** (because some branches lived inside prompt strings)
- **Touching code risked breaking AI judgment** (because the AI was reading my code comments to "infer" context)
- **Two sources of truth were drifting apart** — one business rule, two representations
- **Porting to a different AI platform meant rewriting everything** — Python doesn't cross platforms, and the prompts were wired to OpenAI's SDK

The breaking point: I tried to revert "that one rule" to last week's version. But "that one rule" was spread across `onboarding.py`, `router.py`, and three prompt files. A naive `git revert` blew up everything else.

That night I stared at VS Code for ten minutes and finally admitted it:

> **I was expressing business logic in the wrong medium.**

## Why Markdown beats code for business rules

Here's the insight, stripped down:

> Code is for CPU execution. Markdown is for LLM reading. Execution ≠ reading.

We've spent decades assuming business logic *must* be code, because code was the only thing a machine could "understand" and execute. But **LLMs don't execute code — they read it.** And reading is a fundamentally different operation from executing.

**When an LLM reads code, it's decoding:**

- Token cost — every `def`, every `()`, every `self.` burns tokens but carries almost zero decision-relevant signal
- Error-prone comprehension — code is dense with technical noise (variable names, type annotations, decorators) that the LLM has to filter before it can extract business intent
- Hard to debug — when the agent makes a wrong call, you can't tell whether it misread a function or misread the business rule *behind* that function

**When an LLM reads Markdown, it's actually reading:**

- Token efficient — the same business rule in Markdown is typically 30-50% of the code equivalent
- Direct — you wrote "if follower count < 1000, skip viral-post analysis," and the LLM reads exactly that
- Reviewable by humans — PMs read it, new engineers read it, and `git diff` *is* code review

For **decision-dense, rule-clear content** (read: most business logic), Markdown is a more natural medium than code. Code should handle what it's actually good at — the deterministic plumbing: calling APIs, reading/writing databases, processing files. The bits that don't require judgment.

Put differently: **code's job is deterministic execution. Business rules' job is decision-making.** We only ever conflated them because we had no choice. Now we have LLMs. Time to separate them.

## The Skill-as-Brain architecture

Here's the shape of ShuLing v2.3.0:

```
┌───────────────────────────────────────────────────┐
│   Brain                                           │
│   SKILL.md (1,208 lines)                          │
│   §0a routing / §0b platform detect / §0c intake  │
│   §0 install / §1 profile / §2 daily / §3 review  │
│   §4 self-evolve / §5 compliance / §6 tools ref   │
│   §7 data schema / §8 error handling              │
└─────────────────┬─────────────────────────────────┘
                  │ AI reads, decides
                  ▼
┌───────────────────────────────────────────────────┐
│   Hands                                           │
│   scripts/ (11 scripts)                           │
│   xhs.sh (MCP calls) / db.sh (SQLite I/O)         │
│   image.py (Gemini image gen) / preflight.py      │
│   noterx-diagnose.sh (third-party diagnostics)... │
└─────────────────┬─────────────────────────────────┘
                  │ Scripts write
                  ▼
┌───────────────────────────────────────────────────┐
│   Memory                                          │
│   knowledge-base/                                 │
│     profile.json (long-term: creator profile)     │
│     preferences.json (long-term: learned prefs)   │
│     patterns.md (long-term: proven patterns)      │
│     evolution-log.md (long-term: self-evolution)  │
│   data/shuling.db                                 │
│     9 SQLite tables (short-term: run state)       │
└───────────────────────────────────────────────────┘
```

**Brain layer (SKILL.md)** is the agent's decision core. Every branch, check, rule, and state machine lives in one Markdown file. At startup, the AI loads SKILL.md into context and immediately knows what to do.

**Hands layer (scripts/)** is everything the LLM *can't* do directly. LLMs can't call MCP servers, can't read/write SQLite, can't hit the Gemini API. Those get wrapped as scripts, and the brain drives the hands by invoking them.

**Memory layer** splits long-term and short-term. `knowledge-base/` is long-term — creator profiles, learned preferences, proven patterns — stuff that survives across sessions. `data/shuling.db` is short-term: current run state, this post's metrics, today's diagnostic output.

A concrete example. `SKILL.md §0a Routing` is literally a Markdown table:

```markdown
## §0a Business routing table

| User input keyword    | Precondition                | Jump to  |
|-----------------------|-----------------------------|----------|
| "I'm a new creator"   | profile.json doesn't exist  | §1 Profile |
| "I already have an account" | profile.json doesn't exist | §0c Intake |
| "What should I post today" | profile.json exists    | §2 Daily |
| "Let's do a review"   | posted in the last 7 days   | §3 Review |
| "Check my environment" | any time                   | preflight |
| "My topic picks feel off" | preferences.json exists | §4 Self-evolve |
| (unrecognized)        | any time                    | Ask user to clarify |
```

That's a state machine. If I'd written it in Python, it would be at least a `match/case` plus nested `if`s — 50+ lines — and the LLM would still have to infer "given these conditions, which branch applies."

As a Markdown table? The LLM gets it at a glance. So do humans. Adding a row is one line. `git diff` shows exactly what changed.

There are dozens of tables like this in SKILL.md. Each is a local decision rule. Stitched together, they form a complete business brain — whose physical form is a single 1,208-line Markdown file.

## Three benefits I didn't see coming

Three bonuses I didn't plan for when I moved business logic out of Python and into SKILL.md.

### 1. Platform portability is nearly free

ShuLing now runs on three platforms: Claude Code, Codex, and Hermes. Their skill mechanisms are completely different — Claude Code natively supports `.claude/skills/`, Codex needs custom memory injection, Hermes uses cron + pre-read hooks.

But here's the thing: all three platforms share the **same** SKILL.md. Each gets a thin adapter layer in `platform/`:

```
platform/
├── claude-code/
│   └── README.md      # "Drop this repo into ~/.claude/skills/"
├── codex/
│   └── inject.sh      # Writes SKILL.md into Codex memory
└── hermes/
    └── cron.conf      # 5x/day auto-trigger config
```

Each is 20-50 lines. Zero business logic — just "how do I hand SKILL.md to this platform's AI?" Adding a new platform is roughly "write this adapter" — an afternoon of work.

### 2. Zero-compile, zero-deploy iteration

Changing a flow in a traditional Python agent goes: edit code → run tests → build → deploy.

Changing a flow in ShuLing: edit SKILL.md → `git commit` → next AI invocation sees the new version.

No compile. No deploy. No staged rollout. `git log SKILL.md` is the complete history of how the business logic evolved.

Even better: **code review is now reviewing the business rules directly.** Old PRs were walls of `prompt_templates["onboarding_v3"] = f"""..."""` and reviewers had to hunt for business changes inside string literals. Now reviewers see the Markdown diff — rule added, branch removed — obvious.

### 3. (Bonus) Non-technical stakeholders can read the business

This wasn't a goal, but it happened. I showed a friend in ops the §2 Daily chapter once. She read through and said, "Oh, that's the logic you use for topic selection? I think §2.3 should actually be..."

That's when it clicked: **Markdown is a natural cross-role alignment medium.** PMs, ops, engineers all read the same file. You can't do that with "prompt + code."

It's a byproduct, not a goal. The goal is still making the agent more reliable. But fixing the "business knowledge graph" problem as a side effect? I'll take it.

## The costs (this isn't free)

I don't want to evangelize Skill-as-Brain as a silver bullet. There are real trade-offs. Here are the three I've actually lived with.

### Cost 1: Token bloat

My SKILL.md is 1,208 lines, ~5,000 tokens on load. On Hermes, cron fires 5x/day per creator and reloads the whole file (no cross-call context reuse). Math:

```
5,000 tokens/load × 5 loads/day × 30 days = 750,000 tokens/month (per creator)
```

At three creators, that's 2.25M tokens/month just re-reading the same SKILL.md. And that's before output or conversation history.

v2.4 is addressing this with a **slim-down**:

- Main SKILL.md capped at ≤300 lines — routing + index only
- Chapters split into `skill-chapters/` — `§1-profile.md`, `§2-daily.md`, etc.
- AI loads only the chapter it needs
- Projected per-load: <1,500 tokens

This problem exists in code-based architectures too (big prompts are big), but Markdown makes it *more visible* — you can literally see "okay, 1,208 lines is a lot."

### Cost 2: The AI will drift

LLMs aren't deterministic executors. Occasionally mine will conflate §2.3 and §2.4 logic, hallucinate a profile when `profile.json` doesn't exist, or emit a JSON that doesn't pass schema validation.

ShuLing's defense is two layers:

1. **JSON Schema contracts** — `schemas/` contains four JSON Schemas (profile / preferences / post_metrics / generated_image). Every AI JSON write is validated before hitting disk.
2. **§0b write-time validation** — SKILL.md mandates: "Before writing to `knowledge-base/`, run `scripts/validate.sh`. On failure retry; on second failure surface the error to the user."

Not a silver bullet. But Schema + explicit write-validate-retry discipline has kept "AI drift → dirty data" incidents at zero for the last three months.

### Cost 3: You need new versioning semantics

Traditional SemVer (`major.minor.patch`) doesn't cut it here. Three things evolve independently:

- SKILL.md (brain) version
- scripts/ (hands) version
- knowledge-base/ schema (memory structure) version

I ended up with a three-part scheme I call `BRAIN.HANDS.CALIB` — in `v2.3.0`, `2` is BRAIN, `3` is HANDS, `0` is CALIB. It's the topic of my next post.

## When to use Skill-as-Brain (and when not)

Before porting this pattern to your agent project, a quick gut-check.

### Good fit

- **Decision-dense, rules-clear logic** — most of your logic is "under condition A do X, condition B do Y" (table-able), not numerical computation
- **Complex user interaction with multi-branch state** — conversational agents, task orchestration, workflow automation
- **Frequent evolution** — business rules change often; you need fast diff reviews and fast iteration
- **Multi-platform targets** — same business logic needs to run on different AI platforms

### Bad fit

- **Compute-heavy** — if your agent is fundamentally doing math, matrix ops, or image processing, keep it in code and let the AI just *invoke* it
- **No AI decision-making, purely mechanical tooling** — if the flow is fixed and no judgment is required, a Makefile or Airflow DAG is better than SKILL.md
- **Cost-sensitive, low-value calls** — if your per-call budget is under $0.01, loading a 5,000-token brain every time is too expensive

### The one-sentence test

> If your prompts are full of "if / else / when / unless" decision words, and those rules change often — you want Skill-as-Brain. If your prompts are mostly "call this API, parse this JSON, return this format" — you want a plain function-calling agent.

ShuLing is textbook category 1. Xiaohongshu creator growth is inherently decision-dense and evolution-heavy — every creator has a different niche, stage, preference, and the platform's own rules keep shifting. Bake all that into Python and three months later you can't touch it. Bake it into SKILL.md and three months later it's still legible.

## The bigger claim

Let's come back to that embarrassing v1. Back then I thought the problem was "the prompts aren't good enough" or "the code architecture isn't clean enough." It took moving the entire business layer to Markdown before I understood what was actually wrong:

> **I was expressing business logic in the wrong medium.**

Software engineering has spent decades teaching us to turn everything into code. But LLMs change the game — we now have an "executor" that reads natural-language rules directly. Continuing to shove business rules into code is, frankly, the dumb move.

> Skill-as-Brain isn't a preference. It's the inevitable shape of LLM-native applications.

When your agent gets complex enough, your rules numerous enough, and you need cross-platform support and active evolution — you'll end up here. I just got here a little earlier than most.

## Try it / break it / tell me I'm wrong

ShuLing v2.3.0 is open source on GitHub under MIT. 1,208-line SKILL.md, 11 scripts, 9 SQLite tables — all of it readable and forkable. If you're building agents, I genuinely recommend at least reading the SKILL.md structure and the §0a routing table — I think they're worth studying even if you don't adopt the rest.

- GitHub: [github.com/AI-flower/shuling](https://github.com/AI-flower/shuling) — star it if this was useful; it helps other agent builders find this pattern
- Website: [shuling.pages.dev](https://shuling.pages.dev)
- License: MIT

**Next post:** `BRAIN.HANDS.CALIB` — why traditional SemVer isn't enough for agent projects, and how ShuLing's three-part version scheme captures independent evolution of brain, hands, and calibration.

If you're building an agent, drop a comment: **what does your "business logic" currently live in — Python, prompt strings, YAML, something weirder?** I'm collecting real-world architectures for a future post.
