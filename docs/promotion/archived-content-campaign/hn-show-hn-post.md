# HN Show HN — Optimized

## Title variants (pick one on submission day based on current ShuLing framing)

### Variant A: architecture-forward (79 chars)
Show HN: Shuling – a 1208-line Markdown file drives a Xiaohongshu creator skill

### Variant B: pattern-forward (73 chars)
Show HN: Skill-as-Brain – one SKILL.md replaces our Python business logic

### Variant C: concrete-outcome-forward (80 chars)
Show HN: Shuling – a Xiaohongshu creator skill written as 1208 lines of Markdown

## Body (final, paste this)

Shuling is a Markdown-defined skill that turns Claude Code, Codex, or Hermes into a Xiaohongshu (RED) creator assistant: topic picking, outline, 9-page image generation, publishing, and engagement-based preference learning. What I want feedback on is the structure, not the product.

The pattern I'm calling "Skill-as-Brain": all business logic lives in a single 1208-line `SKILL.md`. The agent reads it and executes the flow. The `scripts/` directory only does mechanical I/O the model can't do — SQLite reads/writes, MCP calls to third-party `xiaohongshu-mcp`, Gemini 3 Pro image generation. `knowledge-base/` holds durable state (profile, preferences, mined content patterns). Switching between Claude Code, Codex, and Hermes is a platform adapter file, not a rewrite. Updating the posting flow is a Markdown diff, not a code change.

Because the "program" is a Markdown file, I ended up having to build some skill-grade infra around it: a `BRAIN.HANDS.CALIB` three-segment semver (flow / scripts / tuning, each bumps independently), JSON Schema contracts on every agent-written state file to catch drift, idempotent SQLite migrations across 9 tables, a dual-mode preflight check that emits JSON for agents and a colored table for humans, and a Laplace-smoothed Bayesian preference learner with ε-greedy exploration driven by actual save-rate on published posts — not vibes.

Tradeoffs I won't hide: Xiaohongshu has no public API, so publishing goes through a third-party `xiaohongshu-mcp` that drives the web client; breakage risk is real. v2.3.0 removed the HTML-screenshot fallback, so a Gemini API key is now mandatory. The preference-learning sample sizes at 2 stars / 71 commits / 8 releases over 2 months are small; I expect the model to change as more real posts land. Not SaaS, not automation/farming, no telemetry. MIT, fully local.

Repo: https://github.com/AI-flower/shuling
Site: https://shuling.pages.dev (written for agents to parse, not humans to admire)

What I'd find most useful: (1) does Skill-as-Brain generalize beyond content workflows, or does it break down the moment logic gets truly branchy; (2) is `BRAIN.HANDS.CALIB` the right axes, or are there 2 that collapse into one; (3) JSON Schema on agent outputs — justified belt-and-braces, or ceremony.

## Submission strategy

- **Best submit time**: Tuesday or Wednesday, 08:00-09:30 US Eastern (13:00-14:30 UTC). HN front-page velocity is highest mid-week morning US time; Monday is noisy with weekend backlog, Thursday/Friday decays fast. Avoid submitting from Beijing afternoon/evening (you'll hit HN at 01:00-04:00 ET — dead window). For Beijing, that means submit ~21:00-22:30 local.
- **First 2 hours strategy**:
  - Stay at the keyboard. HN's ranking weights early comment velocity heavily; missing the first hour of replies almost always kills a Show HN.
  - Reply to every top-level comment within 15 minutes. Short, concrete, no marketing voice.
  - If someone asks "why Markdown and not YAML/JSON/DSL?" — do not get defensive. Answer with a concrete failure mode you hit with the alternative.
  - If someone says "isn't this just a prompt template?" — acknowledge the surface similarity, then name the specific thing that's different (schema-checked agent outputs + versioned flow + platform adapters). Don't argue the label.
  - Never reply "great question!" or "thanks for the feedback!" — HN readers filter that as marketing signal.
- **Downvote triggers to avoid**:
  - Do NOT open with "I built X so you don't have to" — instant flag.
  - Do NOT use "revolutionary", "game-changer", "next-gen", "paradigm shift", or any emoji in the title/body. One subtle emoji in the repo is fine; none in the HN post.
  - Do NOT front-load "MIT open source!" — HN assumes it; saying it loudly reads as PR.
  - Do NOT hide the Xiaohongshu automation angle. The audience will find it in 30 seconds and feel misled. Name it and name the tradeoff (third-party MCP, no official API).
  - Do NOT claim "production-grade" or "enterprise-ready" at 2 GitHub stars. Let the artifact speak.
  - Do NOT mention the star count, commit count, or release cadence as a virtue. HN doesn't care.
  - Avoid "LLM" as a buzzword substitute — say "the agent" or "Claude/Codex" concretely.
- **Promote / don't-promote rules**:
  - Link the repo first, site second. HN readers click repo links 5-10x more than landing pages.
  - Only link `shuling.pages.dev` once, and only with the parenthetical "written for agents to parse" — that framing is the actual novel thing about the page, so it earns its link.
  - Do NOT link blog posts, Twitter threads, or Discord invites from the HN body. If a commenter asks for a deeper dive, reply with a link inline.
  - Do NOT link the v2.3.0 GitHub Release page directly — link the repo root. Release notes read as launch-PR on HN.
  - If the post gets traction, do NOT edit the body to add "EDIT: wow front page thanks!" — it's a known downvote magnet. Just keep replying in comments.
  - If the post stalls (no front-page movement in 90 minutes), do NOT re-submit the same day. Wait 48+ hours, change the title, try once more. Three failed submissions and the domain starts getting penalized.
