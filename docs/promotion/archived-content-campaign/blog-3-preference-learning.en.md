<!--
Reviewer's note
---------------
Platform targets:
  - Primary: Dev.to (frontmatter below is Dev.to-compatible; set `published: true` when ready)
  - Cross-post: Medium (import via Dev.to -> Medium, or paste directly; remove frontmatter)
  - Cross-post: Towards Data Science on Medium (algorithm depth + real code = strong TDS fit;
    suggested TDS tags: machine-learning, recommendation-systems, bayesian-statistics,
    ai-agents, personalization)

Positioning:
  - This is Part 3 of a 3-part series on ShuLing's architecture:
      Part 1: Skill-as-Brain (blog-1-skill-as-brain.en.md)
      Part 2: BRAIN.HANDS.CALIB versioning (blog-2-semver.en.md)
      Part 3: Small-sample preference learning (this post)
  - Part 3 is the deepest on algorithm/math. TDS is the natural fit; Dev.to readers who
    liked Part 1 will tolerate the length if the payoff (copy-paste-ready formulas) is
    front-loaded.

Reading time: ~18 minutes (algorithm depth justifies the length; 3,000-4,000 words target).

Intentional divergence from the Chinese original:
  - Punchier numerical opening ("2 clicks, 100% overfit") instead of the leisurely
    Chinese "设想这样一个场景".
  - Subheadings converted to question/action format where natural.
  - Added Xiaohongshu (RED) context on first mention for Western readers.
  - All formulas rendered in inline code or fenced code blocks — NO LaTeX
    (Dev.to's LaTeX support is patchy and Medium strips it).
  - Pull quote on "Weight vs Confidence" preserved verbatim (it's the load-bearing line).
  - Kept the 5-row numerical comparison table verbatim — it IS the proof.
  - Softened the "高水平 AI 实测踩坑" line into a more collegial English phrasing without
    losing the warning.
  - End CTA points at GitHub star + "drop your stack in the comments" (same shape as Part 1).

Suggested cover image:
  - A plot showing two curves on the same axes: naive proportion (spiky, goes to 1.0 on
    sample 2) vs Laplace-smoothed weight (gentle asymptote). X-axis = sample count,
    Y-axis = weight. Caption: "Naive vs. Laplace on 2 clicks."
  - Alternative: the 5-row comparison table rendered as a clean image.
  - Dev.to cover image: 1000x420.

Tags for Dev.to (4 max): ai, machinelearning, recommendations, agents
Tags considered for Medium/TDS: machine-learning, recommendation-systems,
  bayesian-statistics, ai-agents, personalization, laplace-smoothing

Word count target: 3,000-4,000 (algorithm depth justifies upper-bound).
Current draft body sits around 4,300 words — on the high end but within the
"longer is ok for algorithm depth" allowance.
-->

---
title: "Small-Sample Preference Learning for AI Agents: Laplace Smoothing + Concentration x Sample Factor"
published: false
description: "How to stop your LLM agent from overfitting on 2 clicks — a Bayesian + epsilon-greedy recipe you can copy-paste into any personalization system."
tags: ai, machinelearning, recommendations, agents
canonical_url:
cover_image:
---

Two clicks. That's all it takes for a naive personalization system to decide it knows your user. User clicks "A" twice, naive proportion says `weight_A = 2 / 2 = 1.0`, the agent locks into single-choice mode, B and C never get shown again, and you just built a feedback echo chamber from the smallest possible sample.

This post is about the recipe I use to avoid that — and more importantly, about a subtle, extremely common bug I've seen in LLM-personalization code even in respectable teams: **treating weight and confidence as the same number.**

It's the longest of the three in this series and the most math-dense — but every formula can be copy-pasted straight into your project. The one-line thesis:

> **The most common mistake when you LLM-wrap personalization is overfitting on tiny samples. The recipe from ShuLing's SKILL.md §4.1 — Laplace smoothing + concentration x sample factor + epsilon-greedy + rebound — solves it systematically.**

This is Part 3 of my series on [ShuLing](https://github.com/AI-flower/shuling) (an MIT-licensed AI agent for creators on **Xiaohongshu (RED, China's largest lifestyle-sharing platform)**). Part 1 covered the [Skill-as-Brain architecture](./blog-1-skill-as-brain.en.md); Part 2 covered [BRAIN.HANDS.CALIB versioning](./blog-2-semver.en.md). You don't need them to follow this one.

## The scenario: 2 clicks and you "know" the user?

Imagine you're using an AI writing assistant. Every morning it asks:

> "Which one are you publishing today? A. AI tool reviews  B. Coding tutorial  C. Industry news"

Day 1 you pick A. Day 2 it asks again, and you pick A again.

**Question: how much should the AI now trust that signal?**

Engineers tend to default to one of three reactions:

- **The naive**: "They picked A twice, clearly they like A. Just push A from now on."
- **The conservative**: "Only two samples, way too small. Keep randomizing."
- **The Zen-master**: "Just stuff the history into the prompt and let the LLM figure it out."

All three have problems. The naive reaction is the most dangerous, and it's literally this code:

```python
# DANGEROUS: naive proportion
weight = chosen / (chosen + skipped)
```

After the second click, `weight_A = 2 / (2 + 0) = 1.0`. The agent enters single-choice mode, stops surfacing B and C, and the third interaction can't possibly move `weight_A` — it's already locked at 1.0. **Welcome to the feedback echo chamber.**

The conservative reaction sounds reasonable — "too small, don't learn yet" — but your UX can't afford it. If the user spends a week with your product and all you can say is "please keep picking, we're still gathering data," they've uninstalled already.

The Zen-master approach is the most mystical. You drop the history into the prompt — "user picked A, A, B, A" — and let the LLM infer. Problem: the LLM has **no mathematical prior**. It can't principled-ly distinguish "2 picks of A" from "20 picks of A" in confidence terms. A prompt that says "recommend based on user history" on a small sample is roughly equivalent to flipping a coin.

This is the textbook trap of LLM-wrapping personalization: you hand a statistical problem to the model and ask it to solve it "by understanding," and in doing so you convert a deterministic mathematical regularity into probabilistic natural-language inference. Use Bayes where Bayes belongs. Use epsilon-greedy where epsilon-greedy belongs. Don't make the LLM re-derive things that one formula already nails.

ShuLing's `SKILL.md §4.1` lays out a four-part combo that fixes this. Let me walk through each piece.

## Part 1: Laplace smoothing — a two-century-old trick for small samples

Naive proportion's core problem is that it has **no prior**. On the first sample, your denominator is 1. On zero samples, it's division by zero. The fix has been around for 200 years: Laplace smoothing (aka "add-one smoothing").

The formula is trivial:

```python
def weight(chosen: int, skipped: int) -> float:
    return (chosen + 1) / (chosen + skipped + 2)
```

The "+1 / +2" has a Bayesian interpretation: a **Beta(1, 1) prior**.

- `Beta(1, 1)` is the uniform distribution on `[0, 1]`. Translated: before I've seen any data, my belief about "user likes A" is 50%.
- Every observed "chose" bumps the Beta's `alpha` parameter by 1; every observed "skipped" bumps `beta` by 1.
- The expectation of the posterior is `(alpha + chosen) / (alpha + beta + chosen + skipped)`, which with `alpha = beta = 1` gives `(chosen + 1) / (chosen + skipped + 2)`.

If the Bayesian intuition isn't clicking, this table is enough:

| chosen / skipped | Naive proportion | Laplace smoothing |
|---|---|---|
| 0 / 0 | undefined (div by zero) | **0.50** |
| 1 / 0 | 1.00 | **0.67** |
| 2 / 0 | 1.00 | **0.75** |
| 10 / 0 | 1.00 | **0.92** |
| 2 / 3 | 0.40 | **0.43** |
| 50 / 50 | 0.50 | **0.50** |

A few ways to read it:

- **With zero samples, the default is 0.50** (neutral) — not `NaN`, not zero. You never need a special case for initialization.
- **Small samples are automatically conservative**: 2-for-2 gives 0.75, not the naive 1.0. Two picks aren't enough to fully trust you.
- **Large samples approach the true proportion**: at 50/50 Laplace and naive both say 0.5 — the prior is "washed out" by data.
- **Natural resistance to extremes**: naive says 10/0 and 100/0 are both 1.0; Laplace says 0.92 and 0.99 respectively. More data, more confidence.

In ShuLing, the semantics of `weight` are: **the tendency probability that a specific single type (e.g., the "AI tools" topic) gets chosen**. It describes one dimension, and one dimension only.

Why I'm hammering this: the next section introduces `confidence` — the **whole-judgment** belief. Countless engineers have conflated the two. This is the bug I promised you at the top.

## Part 2: Weight != Confidence — separating two dimensions (the core of this post)

Conclusion first:

> **Weight is your bias toward one type. Confidence is your faith in the whole judgment. Confusing the two is the most invisible bug in AI engineering.**

`SKILL.md §4.1` has an explicit warning at this point, and I'll paraphrase it: **even high-level AI agents tested on this code fall into the pit. Don't use `chosen / (chosen + skipped)` as your confidence — that's the weight formula. Conflating them means your "N-pick → M-pick" threshold never trips, and your convergence mechanism silently dies.**

I blew this on my first implementation. A completely innocent-looking typo destroyed the whole convergence flow. Here's how to do it right.

### The correct confidence formula

```python
def confidence(weights: dict[str, float], total_choices: int) -> float:
    if not weights:
        return 0.0
    sorted_w = sorted(weights.values(), reverse=True)
    top2_sum = sorted_w[0] + (sorted_w[1] if len(sorted_w) >= 2 else 0)
    concentration = top2_sum / sum(weights.values())
    sample_factor = min(total_choices / 10, 1.0)
    return round(concentration * sample_factor, 2)
```

Two components, each with a specific job:

- **`concentration`**: sum of the top-2 weights divided by the sum of all weights. It measures "how concentrated is the user's taste." All-in on one type? Approaches 1.0. Spread evenly over N types? Approaches `2/N`.
- **`sample_factor`**: `min(total_choices / 10, 1.0)`. It measures "have I seen enough data?" Linear growth for the first 10 picks, then capped at 1.0.

**Why multiply?** Because *both* conditions need to hold before confidence is high. Concentrated taste + enough samples = the agent can safely converge. Concentrated but few samples = might be coincidence, stay cautious. Many samples but diffuse taste = the user is genuinely a multi-topic creator; don't force a reduction.

### Numerical demonstration: 5 rows

Scenario: a user picks across three topic dimensions (AI tools / coding / news).

| Scenario | weight_ai_tools | weight_coding | weight_news | confidence_level |
|---|---|---|---|---|
| Initial (0/0, 0/0, 0/0) | 0.50 | 0.50 | 0.50 | **0.00** (sample_factor=0) |
| 3 picks, all ai_tools | 0.80 | 0.20 | 0.20 | **0.25** (concentration 0.83 x 0.3) |
| 10 picks, all ai_tools | 0.92 | 0.08 | 0.08 | **0.92** |
| 10 picks: 6 ai_tools + 4 coding | 0.58 | 0.42 | 0.08 | **0.92** |
| 10 picks: 3/3/4 split across 3 types | 0.33 | 0.33 | 0.42 | **0.69** (diffuse → low confidence) |

Look carefully at rows 2 and 3:

- 3 picks all on `ai_tools`: the naive view would scream "100%, go to single-choice mode immediately." Laplace drags `weight_ai_tools` down to 0.80, but `confidence` is still only 0.25 — **the sample factor is pinning it down**.
- 10 picks all on `ai_tools`: sample factor hits 1.0, concentration reaches 0.92, confidence finally lands at 0.92. That's when the agent is genuinely sure.

Now compare rows 3 and 4:

- 10 picks all on `ai_tools`: `confidence = 0.92`.
- 10 picks with 6 `ai_tools` + 4 `coding`: `confidence = 0.92`, identical.

Why the same? Because **top-2 concentration** doesn't care whether it's "top-1 eats everything" or "top-1 + top-2 split everything" — as long as no mass leaks to a third type, concentration stays near 1.0. This matches product intuition: a user who likes both AI tools AND coding tutorials has a "concentrated taste" in the relevant sense. Concentration doesn't require 100% monoculture.

Finally, row 5: 10 picks evenly across 3 types, confidence drops to 0.69. That's correct — this user genuinely has broad interests and the agent shouldn't force them to pick a lane.

### Why separating the two dimensions matters: the engineering payoff

Once weight and confidence are separated, you can write branching logic like this:

```python
# weight drives "WHAT to recommend"
top_topic = max(weights, key=weights.get)

# confidence drives "HOW MANY to recommend"
if confidence >= 0.75:
    options_count = 1
elif confidence >= 0.5:
    options_count = 2
else:
    options_count = 3
```

If you only had one dimension (because you collapsed weight and confidence into a single number), your choices would be: always conservative (3 options forever) or always aggressive (1-lock after two picks). Only by separating "preference" from "faith" can you have the graceful **small-sample-conservative / large-sample-convergent** transition.

This separation principle is old news in classic recommender systems — CTR prediction separates pCTR from exploration uncertainty; multi-armed bandits separate arm value from confidence bound. But in the **new scenario of LLM-wrapped agents**, many engineers instinctively shove both into a single number or a single prompt sentence, and the bug creeps in.

## Part 3: Shrinking the option set — confidence-driven UX

Once you have `confidence` as a proper scalar, UX design has something to stand on. ShuLing's strategy:

```python
if confidence_level >= 0.75:
    # Base: 1 topic pick + 1 draft ("post / swap")
    ...
    if need_exploration(last_exploration_at, today):
        # Append 1 extra "exploration item" (see next section: epsilon-greedy)
        ...
elif confidence_level >= 0.5:
    # 2 topic picks + 1 draft (with alt headlines)
    ...
else:
    # 3 topic picks + 2 drafts
    ...
```

The three thresholds each have a rationale.

**`>= 0.75` (single-choice mode)**: high confidence + enough samples. The user's taste is clear enough that the agent can "just execute." UX shifts from multiple choice to binary decision — the agent hands you one specific draft, and you answer "post" or "swap." Minimum cognitive load.

**`>= 0.5` (two-choice mode)**: medium confidence. The agent narrows the ring without sealing it. Two candidates close to the user's preference, so the user makes a quick A/B comparison. Faster than three-choice, still preserves a sense of agency.

**`< 0.5` (three-choice mode)**: low confidence. Either samples are scant or taste is diffuse. The agent's best move is to **display diversity** — 3 meaningfully different topic picks + 2 drafts in different styles — to gather more "chose/skipped" signal.

Why not "once you're in three-choice mode, you're stuck"? Because the next section's epsilon-greedy provides a safety valve: even after you're in single-choice mode, the agent periodically forces an exploration item. The philosophy: **convergence is the goal, but always leave a way out**.

One detail worth emphasizing: the option count must **decrease monotonically** — 3 → 2 → 1, never jumping. If you jump straight from 3 to 1, the user will feel a jarring "why is the AI suddenly so confident?" disconnect. Gradual feels natural.

## Part 4: Epsilon-greedy — safeguarding against the taste echo chamber

What's the biggest risk in single-choice mode?

**The agent only ever recommends what you already like, and you forget you could enjoy other things.**

This is the classic filter-bubble problem. Recommender-systems folks have had a solution for decades: **epsilon-greedy** — pick the best option with probability `1 - epsilon`, pick randomly with probability `epsilon`.

ShuLing's epsilon-greedy is engineered, not pure random — **time window + cold-type filter**:

```python
from datetime import date, timedelta

def need_exploration(last_exp: date | None, today: date, days: int = 7) -> bool:
    return last_exp is None or (today - last_exp).days >= days

def pick_exploration_topic(weights: dict[str, float],
                           recent_shown_topics: set[str],
                           threshold: float = 0.3) -> str | None:
    # From types with weight < 0.3 AND not shown in the last 14 days
    candidates = [
        topic for topic, w in weights.items()
        if w < threshold and topic not in recent_shown_topics
    ]
    return random.choice(candidates) if candidates else None
```

Trigger rule: when `confidence >= 0.75` (single-choice mode), if it's been ≥ 7 days since the last exploration (or never), append one exploration item. The recommendation becomes "1 main pick + 1 exploration" — main pick serves the user's preference, exploration breaks the echo chamber.

Every parameter has an engineering reason:

- **7 days**: Why not daily? The user gets annoyed ("again with something I don't care about"). Why not monthly? Too sparse to meaningfully break the bubble. Weekly is roughly the "acceptable surprise frequency."
- **`weight < 0.3`**: the lower bound. Too high (say `< 0.5`) and you're letting near-optimal items leak in as "exploration." Too low (say `< 0.1`) and the candidate pool is usually empty. 0.3 gives "ignored but not yet fully dismissed" types a shot.
- **Not shown in last 14 days**: prevents the same exploration item from spamming. If last week's exploration pushed "industry news" and the user ignored it, don't push it again next time.

What if exploration succeeds (the user picks it)? Then `chosen_news += 1`, `weight_news` rises next round, and the "news" type might no longer qualify as cold — **the user's taste graph updates dynamically**.

### Epsilon-greedy vs Thompson Sampling

The old-school recsys engineers will ask: "Why not Thompson Sampling? It's more principled."

My answer: engineering-wise, epsilon-greedy is easier to explain, easier to tune, and easier to sell to a PM. Thompson Sampling requires maintaining the posterior distribution per arm and drawing samples each turn — implementation cost goes up. For ShuLing's "once-a-day interaction" low-frequency scenario, the suboptimality loss of epsilon-greedy is negligible, and you get simple code and high observability in return.

This is the old recsys refrain: **theoretical optimum != engineering optimum**.

## Part 5: The rebound mechanism — don't let the agent dig in

Now let me flip to the opposite problem.

Say the agent is in single-choice mode (`confidence = 0.8`) and recommends topic A. You say "swap." It recommends B. You say "swap" again.

Question: should the agent **proactively drop its confidence**?

The naive implementation says no — stay in single-choice mode, keep cycling to the 3rd, 4th, 5th candidate. But you'll quickly exhaust candidates, and the UX suffers — the user just said "no" twice in a row, and the agent still hasn't clocked that maybe the entire direction is wrong.

ShuLing's rebound mechanism:

```python
# Every time the user says "swap"
consecutive_rejects += 1
confidence_level -= 0.10   # proactive confidence drop
# Also temporarily expand options this turn (+2 topics or +1 draft)

if consecutive_rejects >= 2:
    confidence_level = min(confidence_level, 0.45)   # force back to 3-choice mode
    consecutive_rejects = 0

# Every time the user says "post" (accepts the suggestion)
consecutive_rejects = 0
```

Each parameter is tuned, not guessed:

**`-= 0.10` (not `-= 0.05`)**: the original design was 0.05 and testing showed the rebound was too slow — the user had to swap 5 times before barely falling below 0.75. `0.10` corresponds to "one full topic's weight per swap," which lands on the right rebound speed.

**`consecutive_rejects >= 2` trigger threshold**: 1 isn't enough (user might just be in a bad mood, wanting something different today). 3 is too many (user is already venting at the agent). 2 is the "clear enough but hasn't angered the user yet" window.

**Forced value 0.45**: just below the 0.5 two-choice threshold, which forces a direct jump to three-choice mode. Why not 0.0? Because the agent's accumulated information isn't completely wrong — the user is just off **for this session**, and the historical preference still has value. 0.45 lets the agent "clear its throat and start over" without wiping its memory.

**"Post" resets**: one acceptance means the direction was right, so prior rejects don't need to keep accruing.

I call this mechanism "**the dig-in preventer**." When confidence is high, the agent naturally falls into "I'm definitely right" inertia, and it needs an external signal to force the climb-down. The user saying "swap" is that signal.

## Part 6: Pattern lifecycle — from "preference" to "proven rule"

Preference learning answers "what does the user like?" But ShuLing adds one more layer — **Pattern**.

> **Pattern = what kind of content succeeds.**

Example:
- Preference: "the user likes AI tool posts"
- Pattern: "headline with a question mark + first paragraph naming a specific tool + screenshot instead of illustration → this kind of post typically sees > 5% 24h save rate"

Pattern is a **reusable regularity** distilled from data — closer to "methodology" than preference.

ShuLing's Pattern lifecycle:

```text
experimental  →  medium  →  high
     ↓                         ↓
anti-patterns ← 3x failures  deprecated (aging out)
```

Concrete rules:

- **Entering `experimental`**: a single post has ≥ 5% save rate (triggers "this might be a pattern").
- **`experimental` → `medium`**: 3 consecutive validations effective (> 2% save rate).
- **`medium` → `high`**: another 3 consecutive validations effective.
- **`high` → `deprecated`**: 3 consecutive failures (< 2% save rate).
- **`experimental` → `anti-patterns`**: 3 consecutive failures.
- **`patterns.md` active count capped at ≤ 15**: past that, evict the lowest-confidence entry.

The reasoning behind each parameter:

**5% save rate threshold**: Xiaohongshu's platform average sits at 1-2%, so 5% is clearly above average — a real signal. Too low (say 3%) and noise slips in; too high (say 10%) and samples become rare, upgrades glacial.

**3 consecutive**: a single success might be coincidence; 3 rules out most noise. This is the classic "rule of three" — in statistics, 3 same-direction events corresponds roughly to `p < 0.125`, already a reasonable weak signal.

**Cap at 15**: humans (or LLMs) can only reference so many rules at once. Past 15, patterns start conflicting and the LLM's attention gets diluted. 15 is the empirically "information-rich but not overflowing" sweet spot.

**Why not let the LLM do all the pattern extraction?** You absolutely could — stuff every post into the prompt, ask the LLM to summarize "what kind of post succeeds." The problem: the LLM's summary is **unverifiable, non-accumulating, and non-auditable**. Today it says "question-mark headlines are good," tomorrow you ask the same question and it says "no question-mark is better." A data-driven Pattern lifecycle provides **auditable rule sedimentation** — every entry has a specific validation count, save-rate samples, and upgrade timestamps.

This is the core philosophy of ShuLing's architecture: **the LLM handles understanding and generation; data-driven formulas handle decisions and convergence**. Division of labor, no crossing lines.

## Common pitfalls: 5 bugs I see most often

Anyone who's built this kind of system should recognize themselves on this list. Sorted by "frequency x depth":

### Pitfall 1: Conflating weight and confidence (most common)

Using `chosen / (chosen + skipped)` as confidence, or conversely using the sample-factor formula as a per-type weight. Consequence: the N-pick → M-pick threshold never trips, or one click launches you into single-choice mode. See Part 2 above, which I hammered on for a reason.

**Self-check**: before returning from the function, print all weights and confidences, and hand-check them against the Part 2 table.

### Pitfall 2: No epsilon-greedy, single-choice mode never ships anything new

At implementation time you think "single-choice mode is easy, ship it first." Two weeks later the user reports the agent only ever suggests the same topic. Classic engineering shortcut tax.

**Self-check**: query production logs for "topic distribution over the last 14 days." If the top 1 type accounts for > 90%, your exploration mechanism is broken.

### Pitfall 3: No time decay, data from a year ago weighs the same as yesterday

User tastes drift. A year ago you wrote popular-science content, now you write entertainment — if weights accumulate over lifetime, the agent is forever painting "the you from a year ago."

ShuLing's optional time decay: for `choice_log` entries older than 30 days, decay by `x 0.5` for every 14 days past.

```python
def time_decayed_count(log_entry: dict, today: date) -> float:
    delta_days = (today - log_entry["date"]).days
    if delta_days <= 30:
        return 1.0
    # Past 30 days, halve every 14 days
    decay_steps = (delta_days - 30) // 14
    return 0.5 ** decay_steps
```

**Self-check**: compare weight distributions between veteran users and new users. If veterans' weights are increasingly ossified, decay probably isn't on.

### Pitfall 4: No Pattern eviction, the list grows forever

`patterns.md` balloons past 50 entries, the LLM prompt gets packed, generation quality craters. Or contradictory patterns send the LLM into analysis paralysis.

**Self-check**: `patterns.md` file length; logical conflicts between Patterns (e.g., both "question-mark headlines" and "no question-mark headlines" sitting in the high-confidence list at the same time).

### Pitfall 5: Rebound threshold set too high (e.g., ≥ 5), user is gone already

I've seen teams use `consecutive_rejects >= 5` as the trigger, rationale "more robust." Except: by the time the user says "swap" five times in a row, they've already closed the app.

**Self-check**: look at your user drop-off funnel — after which "swap" count do users never come back? That number is your trigger ceiling.

## Transferring this recipe to other domains

This four-part combo isn't just for writing assistants. The core idea transfers to at least four other domains.

### Recsys: new-user cold start

Classic problem. Old trick: "show the default trending list." But that doesn't personalize at all. Laplace prior handles it naturally:

```python
def recsys_score(chosen_in_category: int, shown_in_category: int) -> float:
    return (chosen_in_category + 1) / (shown_in_category + 2)
```

New users start at 0.5 across all categories, and one interaction differentiates them. More personalized than a trending list, more mathematically grounded than asking the LLM to guess.

### A/B experiments: confidence intervals

The design of `concentration x sample_factor` is structurally identical to how A/B confidence intervals work — **effect size x sample sufficiency**. You can build a lightweight "experiment trustworthiness" score from this formula: big gap between conversion rates (high concentration) + large sample size (high sample factor) → emit a "safe to publish" confidence signal.

### Chatbot preference: user-feedback learning

User 👍 / 👎 on chatbot replies is essentially a `chosen / skipped` signal. Break the reply into N dimensions (conciseness, tone, length, whether it used a bulleted list...), Laplace-smooth each dimension independently, then let `confidence` drive the generation strategy. That's a convergent chatbot tuning loop.

### IDE completion: acceptance-rate weighting

Completion suggestion's `accepted / shown` is a natural `chosen / skipped`. Laplace smoothing stops a newly trained language model from collapsing recommendation quality under tiny samples. If GitHub Copilot published its telemetry, I'd bet there's a similar design in there.

The common recipe:

```text
1. Any "user chose/skipped" signal  → Laplace-smooth it into weight
2. Any "should I converge?" decision → concentration x sample_factor for confidence
3. Any "stuck in local optimum" risk → epsilon-greedy for periodic exploration
4. Any "user keeps rejecting" situation → rebound mechanism for proactive de-confidence
```

## Closing + what to build with this

Three lines to take with you.

> **Small-sample judgment is where LLM personalization fails most often — deciding on two clicks is the same as not learning at all.**

> **Weight is your bias toward one type. Confidence is your faith in the whole judgment. Confusing the two is the most invisible bug in AI engineering.**

> **The LLM handles understanding and generation. Data-driven formulas handle decisions and convergence. Stay in your lane.**

If you're working on AI agents, chatbots, recommendation systems, IDE assistants — anything that needs to "learn user taste" — the combo above (Laplace + concentration x sample factor + epsilon-greedy + rebound) is copy-pasteable. ShuLing's [SKILL.md §4.1](https://github.com/AI-flower/shuling/blob/main/SKILL.md) has the full original text with thresholds, fallback rules, and the complete tuning log for every parameter.

ShuLing is MIT-licensed — Stars, Issues, and PRs welcome. We're also discussing extracting this preference-learning module into a standalone skill that any Claude / Codex agent can adopt with a one-line install. Progress tracked in GitHub Discussions.

---

## Related links

- GitHub: [AI-flower/shuling](https://github.com/AI-flower/shuling)
- Full algorithm in SKILL.md §4.1: [SKILL.md](https://github.com/AI-flower/shuling/blob/main/SKILL.md)
- Part 1 in this series: [Skill-as-Brain: I Replaced My Agent's Python Business Logic with 1,208 Lines of Markdown](./blog-1-skill-as-brain.en.md)
- Part 2 in this series: [BRAIN.HANDS.CALIB — why traditional SemVer isn't enough for agent projects](./blog-2-semver.en.md)
- Further reading:
  - *Bayesian Methods for Hackers* (free online) — Chapter 6 has an intuitive walkthrough of the Beta-Binomial prior
  - Sutton & Barto, *Reinforcement Learning: An Introduction* — Chapter 2 on Multi-Armed Bandits
  - Chris Anderson, *The Long Tail* — why diversity and personalization must coexist
- Coming next: **Part 4 — ShuLing's reusable governance: writing product preferences as upgradable Pattern files.**

---

If you're building a personalization layer right now, drop a comment: **what's your current stack for user preference — naive proportion, Bayesian smoothing, full MAB, or LLM-in-the-loop?** I'm collecting real-world architectures for a future deep-dive.
