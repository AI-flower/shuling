# 小红书内容自进化系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add cross-cycle self-evolution capability to the existing shuling project — the system learns from engagement data to automatically refine content patterns, rules, and scoring weights.

**Architecture:** Three-component collaboration: (1) knowledge-base/ as file-based memory (4 files + 1 directory), (2) workflow Python scripts enhanced with multi-timepoint collection and weekly evolution analysis, (3) SKILL.md updated with cold-start and knowledge-reading instructions. LLM calls in scripts are provider-agnostic via a unified `llm.py` module.

**Tech Stack:** Python 3 (existing), SQLite (existing), Markdown + JSON for knowledge base, Anthropic/OpenAI SDK for LLM calls.

**Remote access:** All files live on `weiyong@100.79.106.110:/Users/weiyong/Documents/10/shuling`. Use SSH for all operations.

**Path prefix:** `workflow/xhs-automation/` is referred to as `$WF` below. Full path: `/Users/weiyong/Documents/10/shuling/workflow/xhs-automation/`.

---

### Task 1: Knowledge Base Directory Structure

**Files:**
- Create: `$WF/knowledge-base/.gitkeep`
- Create: `$WF/knowledge-base/reviews/.gitkeep`
- Modify: `$WF/.gitignore` (or create if not exists)

- [ ] **Step 1: Create knowledge-base directory skeleton**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling/workflow/xhs-automation && mkdir -p knowledge-base/reviews && touch knowledge-base/.gitkeep knowledge-base/reviews/.gitkeep"
```

- [ ] **Step 2: Create .gitignore to keep skeleton but ignore runtime content**

Write `$WF/knowledge-base/.gitignore`:
```
# Ignore runtime-generated knowledge files, keep directory structure
*.md
*.json
!.gitkeep
reviews/*.md
!reviews/.gitkeep
```

- [ ] **Step 3: Verify structure**

```bash
ssh weiyong@100.79.106.110 "find /Users/weiyong/Documents/10/shuling/workflow/xhs-automation/knowledge-base -type f"
```
Expected: `.gitkeep` files and `.gitignore` only.

- [ ] **Step 4: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add workflow/xhs-automation/knowledge-base/ && git commit -m 'feat: add knowledge-base directory skeleton for self-evolution'"
```

---

### Task 2: LLM Configuration

**Files:**
- Modify: `$WF/config/runtime.env.example`
- Create: `$WF/scripts/llm.py`

- [ ] **Step 1: Update runtime.env.example with LLM config fields**

Replace the existing `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL` lines with provider-agnostic fields. Add at top of file, keeping existing fields intact:

```bash
# ---- LLM 配置（workflow 脚本的后台 LLM 调用）----
LLM_PROVIDER=claude           # claude | openai | openai-compatible
LLM_API_KEY=
LLM_BASE_URL=                 # 留空用官方默认，填自定义地址覆盖
LLM_MODEL=claude-sonnet-4-20250514

# ---- 以下为兼容旧配置，新安装可忽略 ----
ANTHROPIC_AUTH_TOKEN=
ANTHROPIC_BASE_URL=
```

- [ ] **Step 2: Create llm.py unified LLM interface**

Write `$WF/scripts/llm.py`:

```python
"""统一 LLM 调用接口 — 根据 runtime.env 中的 LLM_PROVIDER 路由。"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import config_loader

config_loader.load_runtime_env()


def call_llm(prompt, system=None, max_tokens=4096):
    """调用配置的 LLM，返回文本响应。失败返回 None。"""
    provider = os.environ.get("LLM_PROVIDER", "claude")
    api_key = os.environ.get("LLM_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN", "")
    base_url = os.environ.get("LLM_BASE_URL") or None
    model = os.environ.get("LLM_MODEL", "claude-sonnet-4-20250514")

    if not api_key:
        print("LLM_API_KEY 未配置，跳过 LLM 调用", file=sys.stderr)
        return None

    try:
        if provider == "claude":
            return _call_anthropic(prompt, system, max_tokens, api_key, base_url, model)
        else:
            return _call_openai(prompt, system, max_tokens, api_key, base_url, model)
    except Exception as e:
        print(f"LLM 调用失败 ({provider}): {e}", file=sys.stderr)
        return None


def _call_anthropic(prompt, system, max_tokens, api_key, base_url, model):
    from anthropic import Anthropic
    client = Anthropic(api_key=api_key, base_url=base_url) if base_url else Anthropic(api_key=api_key)
    kwargs = {"model": model, "max_tokens": max_tokens, "messages": [{"role": "user", "content": prompt}]}
    if system:
        kwargs["system"] = system
    resp = client.messages.create(**kwargs)
    return resp.content[0].text


def _call_openai(prompt, system, max_tokens, api_key, base_url, model):
    from openai import OpenAI
    client = OpenAI(api_key=api_key, base_url=base_url) if base_url else OpenAI(api_key=api_key)
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    resp = client.chat.completions.create(model=model, max_tokens=max_tokens, messages=messages)
    return resp.choices[0].message.content
```

- [ ] **Step 3: Verify llm.py loads without import errors**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling/workflow/xhs-automation && python3 -c 'import scripts.llm; print(\"llm.py OK\")'"
```

Expected: `llm.py OK` (no import errors; actual LLM call will fail without API key, which is fine).

- [ ] **Step 4: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add workflow/xhs-automation/scripts/llm.py workflow/xhs-automation/config/runtime.env.example && git commit -m 'feat: add unified LLM interface and provider-agnostic config'"
```

---

### Task 3: Database Migration — Checkpoint Field

**Files:**
- Modify: `$WF/scripts/db.py`

- [ ] **Step 1: Add checkpoint column to post_metrics table schema**

In `db.py`, find the `CREATE TABLE IF NOT EXISTS post_metrics` block and add the `checkpoint` column:

```python
    CREATE TABLE IF NOT EXISTS post_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id INTEGER REFERENCES posts(id),
        checked_at TEXT NOT NULL,
        likes INTEGER DEFAULT 0,
        saves INTEGER DEFAULT 0,
        comments INTEGER DEFAULT 0,
        shares INTEGER DEFAULT 0,
        checkpoint TEXT DEFAULT 'review'
    );
```

- [ ] **Step 2: Add migration for existing databases**

Add to `migrate_db()` function in `db.py`, after the existing `angle`/`style` migration:

```python
    # post_metrics: checkpoint 字段
    cursor = conn.execute("PRAGMA table_info(post_metrics)")
    pm_columns = {row["name"] for row in cursor.fetchall()}
    if "checkpoint" not in pm_columns:
        conn.execute("ALTER TABLE post_metrics ADD COLUMN checkpoint TEXT DEFAULT 'review'")
    conn.commit()
    conn.close()
```

- [ ] **Step 3: Update add_metrics() to accept checkpoint parameter**

Replace the existing `add_metrics` function:

```python
def add_metrics(post_id, likes=0, saves=0, comments=0, shares=0, checkpoint="review"):
    conn = get_conn()
    conn.execute(
        "INSERT INTO post_metrics (post_id, checked_at, likes, saves, comments, shares, checkpoint) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (post_id, datetime.now().isoformat(), likes, saves, comments, shares, checkpoint)
    )
    conn.commit()
    conn.close()
```

- [ ] **Step 4: Add new query functions**

Append to `db.py`:

```python
def has_metric_at_checkpoint(post_id, checkpoint):
    """检查是否已采集该时间点的数据"""
    conn = get_conn()
    row = conn.execute(
        "SELECT COUNT(*) as cnt FROM post_metrics WHERE post_id=? AND checkpoint=?",
        (post_id, checkpoint)
    ).fetchone()
    conn.close()
    return row["cnt"] > 0


def get_published_posts_with_notes():
    """获取所有已发布且有 note_id 的帖子"""
    conn = get_conn()
    rows = conn.execute(
        "SELECT id, xhs_note_id, published_at FROM posts WHERE status='published' AND xhs_note_id IS NOT NULL"
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_posts_between_dates(start_date, end_date):
    """获取日期范围内的帖子及最新指标，用于周复盘导出"""
    conn = get_conn()
    rows = conn.execute("""
        SELECT p.id, p.date, p.slot, p.title, p.angle, p.style, p.github_repo,
               p.github_stars, p.status, p.xhs_note_id
        FROM posts p
        WHERE p.date >= ? AND p.date <= ? AND p.status = 'published'
        ORDER BY p.date, p.slot
    """, (start_date, end_date)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_all_metrics_for_post(post_id):
    """获取帖子的所有 checkpoint 指标，用于增长曲线"""
    conn = get_conn()
    rows = conn.execute(
        "SELECT checkpoint, likes, saves, comments, shares, checked_at FROM post_metrics WHERE post_id=? ORDER BY checked_at",
        (post_id,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_draft_score_for_post(post_id):
    """获取帖子对应的草稿预测分"""
    conn = get_conn()
    row = conn.execute("""
        SELECT ds.total_score FROM draft_scores ds
        JOIN drafts d ON d.id = ds.draft_row_id
        JOIN posts p ON p.date = d.date AND p.slot = d.slot
        WHERE p.id = ? AND d.selected = 1
        ORDER BY ds.total_score DESC LIMIT 1
    """, (post_id,)).fetchone()
    conn.close()
    return row["total_score"] if row else None
```

- [ ] **Step 5: Verify migration runs cleanly**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling/workflow/xhs-automation && python3 -c '
import scripts.db as db
db.init_db()
db.migrate_db()
# Verify checkpoint column exists
conn = db.get_conn()
cursor = conn.execute(\"PRAGMA table_info(post_metrics)\")
cols = [r[\"name\"] for r in cursor.fetchall()]
conn.close()
assert \"checkpoint\" in cols, f\"checkpoint not found in {cols}\"
print(\"Migration OK, columns:\", cols)
'"
```

- [ ] **Step 6: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add workflow/xhs-automation/scripts/db.py && git commit -m 'feat: add checkpoint field to post_metrics for multi-timepoint collection'"
```

---

### Task 4: Multi-Timepoint Data Collection (keepalive.py)

**Files:**
- Modify: `$WF/scripts/keepalive.py`

- [ ] **Step 1: Add imports and db initialization at top of keepalive.py**

After the existing imports (`import telegram`), add:

```python
import db
from review import get_note_metrics
from datetime import datetime, timedelta
```

- [ ] **Step 2: Add collect_pending_metrics function**

Add before `main()`:

```python
def collect_pending_metrics():
    """检查已发布帖子是否需要采集 T+1h/6h/24h/72h 数据"""
    db.init_db()
    db.migrate_db()
    posts = db.get_published_posts_with_notes()
    now = datetime.now()
    collected = 0

    for post in posts:
        published_at = post.get("published_at")
        if not published_at:
            continue
        try:
            pub_time = datetime.fromisoformat(published_at)
        except (ValueError, TypeError):
            continue

        for hours in [1, 6, 24, 72]:
            checkpoint = f"T+{hours}h"
            target_time = pub_time + timedelta(hours=hours)
            diff_seconds = abs((now - target_time).total_seconds())

            # ±2 小时窗口内，且未采集过
            if diff_seconds < 7200 and not db.has_metric_at_checkpoint(post["id"], checkpoint):
                log(f"采集 post_id={post['id']} {checkpoint} 数据...")
                metrics = get_note_metrics(post["xhs_note_id"])
                if metrics:
                    db.add_metrics(post["id"], checkpoint=checkpoint, **metrics)
                    log(f"  {checkpoint}: ❤️{metrics['likes']} ⭐{metrics['saves']} 💬{metrics['comments']}")
                    collected += 1
                else:
                    log(f"  {checkpoint}: 获取失败，下次重试")

    if collected:
        log(f"本轮采集 {collected} 条指标")
```

- [ ] **Step 3: Call collect_pending_metrics in main()**

In `main()`, add at the end before the final log line:

```python
    # 3. 多时间点数据采集
    log("📊 检查待采集指标...")
    try:
        collect_pending_metrics()
    except Exception as e:
        log(f"指标采集异常: {e}")

    log("=== 保活检测结束 ===")
```

Replace the existing `log("=== 保活检测结束 ===")` line (move it after the new block).

- [ ] **Step 4: Verify keepalive.py imports work**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling/workflow/xhs-automation/scripts && python3 -c 'import keepalive; print(\"keepalive imports OK\")'"
```

- [ ] **Step 5: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add workflow/xhs-automation/scripts/keepalive.py && git commit -m 'feat: add multi-timepoint metrics collection to keepalive'"
```

---

### Task 5: Weekly Evolution Engine (review.py)

**Files:**
- Modify: `$WF/scripts/review.py`

- [ ] **Step 1: Add imports**

At the top of review.py, after existing imports, add:

```python
import llm
from datetime import date, datetime, timedelta
import glob
```

(`datetime` imports may already exist — merge, don't duplicate.)

- [ ] **Step 2: Add KNOWLEDGE_BASE_DIR constant and helper**

After `BASE_DIR` definition:

```python
KNOWLEDGE_BASE_DIR = os.path.join(BASE_DIR, "knowledge-base")
REVIEWS_DIR = os.path.join(KNOWLEDGE_BASE_DIR, "reviews")
EXPORTS_DIR = os.path.join(BASE_DIR, "data", "exports")
```

- [ ] **Step 3: Add update_knowledge_phase function**

```python
def update_knowledge_phase():
    """更新 knowledge-base/README.md 中的帖子计数和阶段"""
    readme_path = os.path.join(KNOWLEDGE_BASE_DIR, "README.md")
    if not os.path.exists(readme_path):
        return  # 知识库尚未初始化（冷启动未执行），跳过

    post_count = db.get_published_post_count()
    if post_count < 10:
        phase = "cold-start"
    elif post_count < 30:
        phase = "growth"
    else:
        phase = "mature"

    try:
        content = open(readme_path, "r", encoding="utf-8").read()
        # 替换阶段行
        new_line = f"当前: {phase}（{post_count} 篇）"
        content = re.sub(r"当前: .+", new_line, content)
        with open(readme_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  知识库阶段: {phase}（{post_count} 篇）")
    except Exception as e:
        print(f"  更新知识库阶段失败: {e}", file=sys.stderr)
```

- [ ] **Step 4: Add export_week_data function**

```python
def export_week_data(date_str):
    """导出本周数据为 Markdown，供进化分析使用"""
    today = date.fromisoformat(date_str)
    week_start = today - timedelta(days=today.weekday())
    week_end = week_start + timedelta(days=6)
    week_id = today.strftime("%Y-W%W")

    posts = db.get_posts_between_dates(week_start.isoformat(), week_end.isoformat())
    if not posts:
        return None, None

    lines = [f"# {week_id} 周数据（{week_start} - {week_end}）\n"]
    total_likes = total_saves = total_comments = 0
    best_post = None
    best_save_rate = 0

    post_sections = []
    for i, p in enumerate(posts, 1):
        metrics_list = db.get_all_metrics_for_post(p["id"])
        latest = metrics_list[-1] if metrics_list else {"likes": 0, "saves": 0, "comments": 0, "shares": 0}
        total_likes += latest.get("likes", 0)
        total_saves += latest.get("saves", 0)
        total_comments += latest.get("comments", 0)

        # 增长曲线
        curve_parts = []
        for m in metrics_list:
            cp = m.get("checkpoint", "review")
            curve_parts.append(f"{cp}({m['likes']}/{m['saves']}/{m['comments']})")
        curve = " → ".join(curve_parts) if curve_parts else "无数据"

        # 收藏率
        save_rate = (latest["saves"] / max(latest["likes"], 1)) * 100
        if save_rate > best_save_rate:
            best_save_rate = save_rate
            best_post = p

        # 预测分
        predicted = db.get_draft_score_for_post(p["id"])
        predicted_str = f"{predicted:.0f}" if predicted else "无"

        section = f"""### #{i:02d} | {p['date']} {p['slot']}
- 标题: "{p['title']}"
- 角度: {p.get('angle', '无')} | 风格: {p.get('style', '无')}
- 预测分: {predicted_str}
- 实际: 👍{latest['likes']} ⭐{latest['saves']} 💬{latest['comments']}
- 增长曲线: {curve}
- 收藏率: {save_rate:.1f}%"""
        post_sections.append(section)

    # 总览
    follower = get_user_followers()
    lines.append("## 总览")
    lines.append(f"- 发布: {len(posts)} 篇 | 总点赞: {total_likes} | 总收藏: {total_saves} | 总评论: {total_comments}")
    if follower:
        lines.append(f"- 粉丝: {follower}")
    if best_post:
        lines.append(f"- 最佳帖子: #{posts.index(best_post)+1:02d} 收藏率 {best_save_rate:.1f}%")
    lines.append("\n## 逐篇数据\n")
    lines.extend(post_sections)

    content = "\n".join(lines)

    # 写入 reviews/ 目录
    os.makedirs(REVIEWS_DIR, exist_ok=True)
    review_path = os.path.join(REVIEWS_DIR, f"{week_id}.md")
    with open(review_path, "w", encoding="utf-8") as f:
        f.write(content)

    return week_id, content
```

- [ ] **Step 5: Add weekly_evolution function**

```python
EVOLUTION_PROMPT = """你是小红书内容运营分析师。分析以下周数据，输出进化建议。

## 本周数据
{week_data}

## 当前 Pattern 库
{patterns_content}

## 当前规则
{rules_content}

## 任务
1. 表现好的帖子（收藏率 > 5%）用了什么共性？提炼为 pattern
2. 表现差的帖子（收藏率 < 2%）有什么共性？标记需要避免的模式
3. 已有 pattern 中，被使用且效果好的 → confidence 升级
4. 已有 pattern 连续表现差的 → 建议标记 deprecated
5. 根据数据调整 angle_weights 和 style_weights
6. 预测分 vs 实际收藏率的偏差分析

## 输出格式
严格输出 JSON，不要其他文字：
{{
  "new_patterns": [
    {{"id": "P0X-简短id", "name": "模式名", "template": "模板", "example": "示例", "applicable": "适用场景", "confidence": "low"}}
  ],
  "pattern_updates": [
    {{"id": "P01", "action": "upgrade|downgrade|deprecate", "reason": "原因", "new_confidence": "medium|high|deprecated"}}
  ],
  "rules_update": {{
    "angle_weights": {{"pain-point": 0.35, "tutorial": 0.35, "discovery": 0.30}},
    "style_weights": {{"casual-sharing": 0.40, "step-by-step": 0.35, "comparison": 0.25}},
    "preferred_patterns": ["P01", "P02"]
  }},
  "weekly_summary": "本周关键发现（1-2 句话）",
  "calibration_note": "评分校准观察"
}}"""


def weekly_evolution(date_str):
    """周日运行：导出数据 → LLM 分析 → 程序化更新知识库"""
    today = date.fromisoformat(date_str)
    if today.weekday() != 6:  # 不是周日
        return

    if not os.path.exists(os.path.join(KNOWLEDGE_BASE_DIR, "README.md")):
        print("  知识库未初始化，跳过进化分析")
        return

    print("\n🧬 周进化分析...")

    # 1. 导出周数据
    week_id, week_data = export_week_data(date_str)
    if not week_data:
        print("  本周无数据，跳过")
        return

    # 帖子数 < 3 则样本不足
    post_count = db.get_published_post_count()
    if post_count < 3:
        print(f"  帖子总数 {post_count} < 3，跳过进化（样本不足）")
        return

    # 2. 读取当前知识库
    patterns_path = os.path.join(KNOWLEDGE_BASE_DIR, "patterns.md")
    rules_path = os.path.join(KNOWLEDGE_BASE_DIR, "rules.json")
    patterns_content = ""
    rules_content = "{}"
    if os.path.exists(patterns_path):
        patterns_content = open(patterns_path, "r", encoding="utf-8").read()
    if os.path.exists(rules_path):
        rules_content = open(rules_path, "r", encoding="utf-8").read()

    # 3. 调 LLM 分析
    prompt = EVOLUTION_PROMPT.format(
        week_data=week_data,
        patterns_content=patterns_content or "（空，尚无 pattern）",
        rules_content=rules_content
    )
    response = llm.call_llm(prompt, system="你是小红书数据分析专家，只输出 JSON。")
    if not response:
        print("  LLM 调用失败，跳过进化")
        return

    # 4. 解析 JSON
    try:
        # 提取 JSON（LLM 可能包裹在 ```json ``` 中）
        json_text = response.strip()
        if "```json" in json_text:
            json_text = json_text.split("```json")[1].split("```")[0]
        elif "```" in json_text:
            json_text = json_text.split("```")[1].split("```")[0]
        result = json.loads(json_text)
    except (json.JSONDecodeError, IndexError) as e:
        print(f"  LLM 返回的 JSON 解析失败: {e}", file=sys.stderr)
        print(f"  原始返回: {response[:500]}", file=sys.stderr)
        return

    # 5. 程序化更新 patterns.md
    _apply_pattern_updates(patterns_path, patterns_content, result)

    # 6. 程序化更新 rules.json
    _apply_rules_updates(rules_path, rules_content, result)

    # 7. 更新 README.md 摘要
    _update_readme_summary(result, week_id)

    # 8. 清理旧复盘（保留最近 4 周）
    _cleanup_old_reviews(keep=4)

    print("  ✅ 周进化分析完成")


def _apply_pattern_updates(patterns_path, current_content, result):
    """根据 LLM 分析结果更新 patterns.md"""
    lines = current_content.split("\n") if current_content else []

    # 应用 pattern_updates（upgrade/downgrade/deprecate）
    for update in result.get("pattern_updates", []):
        pid = update["id"]
        action = update["action"]
        new_conf = update.get("new_confidence", "")
        for i, line in enumerate(lines):
            if line.startswith(f"### {pid} "):
                if action == "deprecate":
                    lines[i] = line.replace(f"### {pid}", f"### ~~{pid}~~ [DEPRECATED]")
                else:
                    # 替换 confidence
                    lines[i] = re.sub(r"confidence: \w+", f"confidence: {new_conf}", line)
                break

    # 追加新 pattern
    for np in result.get("new_patterns", []):
        lines.append(f"\n### {np['id']} | {np['name']} | confidence: {np.get('confidence', 'low')} | source: self-data")
        lines.append(f"- **模板**: {np.get('template', '')}")
        lines.append(f"- **示例**: \"{np.get('example', '')}\"")
        lines.append(f"- **适用**: {np.get('applicable', '')}")
        lines.append(f"- **来源**: 自己数据提炼")
        lines.append(f"- **自己数据**: 首次发现")
        lines.append(f"- **使用次数**: 0 | **平均收藏率**: 待统计")

    # 淘汰：活跃 pattern 超过 15 条时移除 confidence 最低的
    # （简单实现：deprecated 的段落移除）
    content = "\n".join(lines)
    deprecated_count = content.count("[DEPRECATED]")
    if deprecated_count > 3:
        # 移除最早的 deprecated 段落
        sections = content.split("\n### ")
        active = [s for s in sections if "[DEPRECATED]" not in s]
        deprecated = [s for s in sections if "[DEPRECATED]" in s]
        kept_deprecated = deprecated[-3:]  # 只保留最近 3 个
        content = "\n### ".join(active + kept_deprecated)

    # 更新头部统计
    active_count = content.count("\n### ") - content.count("[DEPRECATED]")
    content = re.sub(r"活跃数: \d+", f"活跃数: {max(active_count, 0)}", content)
    content = re.sub(r"最后更新: .+?\|", f"最后更新: {date.today().isoformat()} |", content)

    with open(patterns_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  patterns.md 已更新（活跃 {active_count} 条）")


def _apply_rules_updates(rules_path, current_content, result):
    """根据 LLM 分析结果更新 rules.json"""
    try:
        rules = json.loads(current_content) if current_content.strip() else {}
    except json.JSONDecodeError:
        rules = {}

    rules_update = result.get("rules_update", {})
    if rules_update.get("angle_weights"):
        rules["angle_weights"] = rules_update["angle_weights"]
    if rules_update.get("style_weights"):
        rules["style_weights"] = rules_update["style_weights"]
    if rules_update.get("preferred_patterns"):
        rules.setdefault("title", {})["preferred_patterns"] = rules_update["preferred_patterns"]

    rules["version"] = date.today().strftime("%Y-W%W")
    rules["post_count"] = db.get_published_post_count()

    phase_count = rules["post_count"]
    if phase_count < 10:
        rules["phase"] = "cold-start"
    elif phase_count < 30:
        rules["phase"] = "growth"
    else:
        rules["phase"] = "mature"

    with open(rules_path, "w", encoding="utf-8") as f:
        json.dump(rules, f, ensure_ascii=False, indent=2)
    print(f"  rules.json 已更新（phase={rules['phase']}）")


def _update_readme_summary(result, week_id):
    """更新 README.md 中的摘要区块"""
    readme_path = os.path.join(KNOWLEDGE_BASE_DIR, "README.md")
    if not os.path.exists(readme_path):
        return

    content = open(readme_path, "r", encoding="utf-8").read()

    # 更新 Top Pattern
    preferred = result.get("rules_update", {}).get("preferred_patterns", [])
    if preferred:
        top_text = ", ".join(preferred[:5])
        content = re.sub(
            r"(## 当前生效的 Top Pattern\n).*?(\n## )",
            f"\\1{top_text}\n\n\\2",
            content, flags=re.DOTALL
        )

    # 更新本周关键发现
    summary = result.get("weekly_summary", "")
    calibration = result.get("calibration_note", "")
    findings = summary
    if calibration:
        findings += f"\n评分校准: {calibration}"
    content = re.sub(
        r"(## 本周关键发现\n).*?(\n## )",
        f"\\1{findings}\n\n\\2",
        content, flags=re.DOTALL
    )

    # 更新近期复盘
    reviews = sorted(glob.glob(os.path.join(REVIEWS_DIR, "*.md")), reverse=True)[:4]
    review_links = "\n".join(f"- [{os.path.basename(r)}](reviews/{os.path.basename(r)})" for r in reviews)
    content = re.sub(
        r"(## 近期复盘\n).*$",
        f"\\1{review_links}\n",
        content, flags=re.DOTALL
    )

    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(content)


def _cleanup_old_reviews(keep=4):
    """保留最近 N 周的复盘文件"""
    if not os.path.exists(REVIEWS_DIR):
        return
    files = sorted(glob.glob(os.path.join(REVIEWS_DIR, "*.md")), reverse=True)
    for old in files[keep:]:
        os.remove(old)
        print(f"  清理旧复盘: {os.path.basename(old)}")
```

- [ ] **Step 6: Integrate into run_review()**

At the end of `run_review()`, before `return posts_data`, add:

```python
    # 10. 更新知识库阶段
    print("\n🧠 更新知识库状态...")
    try:
        update_knowledge_phase()
    except Exception as e:
        print(f"  知识库阶段更新失败: {e}", file=sys.stderr)

    # 11. 周日触发进化分析
    try:
        weekly_evolution(date_str)
    except Exception as e:
        print(f"  周进化分析失败: {e}", file=sys.stderr)
```

- [ ] **Step 7: Verify review.py imports work**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling/workflow/xhs-automation/scripts && python3 -c 'import review; print(\"review imports OK\")'"
```

- [ ] **Step 8: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add workflow/xhs-automation/scripts/review.py && git commit -m 'feat: add weekly evolution engine to review.py'"
```

---

### Task 6: Knowledge Injection — research.py

**Files:**
- Modify: `$WF/scripts/research.py`

- [ ] **Step 1: Add knowledge reading helper**

After imports and constants, add:

```python
KNOWLEDGE_BASE_DIR = os.path.join(BASE_DIR, "knowledge-base")


def load_knowledge_weights():
    """从 knowledge-base/rules.json 读取权重，用于调整评分"""
    rules_path = os.path.join(KNOWLEDGE_BASE_DIR, "rules.json")
    if not os.path.exists(rules_path):
        return None
    try:
        with open(rules_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return None
```

- [ ] **Step 2: Inject knowledge into run_research()**

In `run_research()`, after `db.init_db()`, add:

```python
    # 读取知识库权重（如果存在）
    knowledge = load_knowledge_weights()
    if knowledge:
        print(f"📚 知识库已加载（phase={knowledge.get('phase', '?')}, post_count={knowledge.get('post_count', '?')}）")
```

- [ ] **Step 3: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add workflow/xhs-automation/scripts/research.py && git commit -m 'feat: add knowledge-base reading to research.py'"
```

---

### Task 7: Knowledge Injection — create_content.py

**Files:**
- Modify: `$WF/scripts/create_content.py`

- [ ] **Step 1: Add knowledge reading helper**

After imports and constants, add:

```python
KNOWLEDGE_BASE_DIR = os.path.join(BASE_DIR, "knowledge-base")


def build_knowledge_context():
    """从 knowledge-base/ 读取活跃 pattern 和规则，构建 prompt 注入片段"""
    context_parts = []

    # 读取 README 摘要
    readme_path = os.path.join(KNOWLEDGE_BASE_DIR, "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            readme = f.read()
        context_parts.append(f"## 当前运营知识\n{readme}")

    # 读取活跃 pattern
    patterns_path = os.path.join(KNOWLEDGE_BASE_DIR, "patterns.md")
    if os.path.exists(patterns_path):
        with open(patterns_path, "r", encoding="utf-8") as f:
            patterns = f.read()
        # 只保留非 deprecated 的段落
        active_sections = []
        for section in patterns.split("\n### "):
            if "[DEPRECATED]" not in section and section.strip():
                active_sections.append(section)
        if active_sections:
            active_text = "\n### ".join(active_sections)
            context_parts.append(f"## 已验证有效的内容模式（请参考但不要机械套用）\n{active_text}")

    # 读取规则
    rules_path = os.path.join(KNOWLEDGE_BASE_DIR, "rules.json")
    if os.path.exists(rules_path):
        try:
            with open(rules_path, "r", encoding="utf-8") as f:
                rules = json.load(f)
            angle_w = rules.get("angle_weights", {})
            style_w = rules.get("style_weights", {})
            if angle_w:
                ranked_angles = sorted(angle_w.items(), key=lambda x: x[1], reverse=True)
                angle_text = "、".join(f"{a}({w:.0%})" for a, w in ranked_angles)
                context_parts.append(f"## 角度偏好（按历史效果排序）\n{angle_text}")
            if style_w:
                ranked_styles = sorted(style_w.items(), key=lambda x: x[1], reverse=True)
                style_text = "、".join(f"{s}({w:.0%})" for s, w in ranked_styles)
                context_parts.append(f"## 风格偏好（按历史效果排序）\n{style_text}")
        except (json.JSONDecodeError, IOError):
            pass

    return "\n\n".join(context_parts) if context_parts else ""
```

- [ ] **Step 2: Inject into generate_html_with_claude()**

In `generate_html_with_claude()`, before the `prompt = f"""你是一个真实的科技博主...` line, add:

```python
    # 注入知识库上下文
    knowledge_context = build_knowledge_context()
    knowledge_section = ""
    if knowledge_context:
        knowledge_section = f"""

## 历史运营数据洞察（参考，不要照搬）
{knowledge_context}

基于以上洞察，在写作时优先参考 confidence 为 medium/high 的 pattern。
"""
```

Then in the prompt string, insert `{knowledge_section}` after the `{readme_section}` variable:

Find: `{readme_section}`
Replace with: `{readme_section}{knowledge_section}`

- [ ] **Step 3: Verify create_content.py imports work**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling/workflow/xhs-automation/scripts && python3 -c 'import create_content; print(\"create_content imports OK\")'"
```

- [ ] **Step 4: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add workflow/xhs-automation/scripts/create_content.py && git commit -m 'feat: inject knowledge-base context into content generation prompt'"
```

---

### Task 8: SKILL.md Self-Evolution Section

**Files:**
- Modify: `skills/xiaohongshu/SKILL.md`

- [ ] **Step 1: Append self-evolution section to SKILL.md**

Add the following at the end of the existing SKILL.md:

```markdown

## 自进化知识库

本 Skill 具备跨周期学习能力，通过 knowledge-base/ 目录积累运营经验。

### 首次初始化

如果 `workflow/xhs-automation/knowledge-base/README.md` 不存在，按顺序执行：

**第一步：配置 LLM**

询问用户：
> workflow 后台脚本（定时选题/创作/复盘）需要独立的 LLM 调用能力。
> 请选择：
> 1. Claude API (Anthropic)
> 2. OpenAI API
> 3. 兼容 OpenAI 格式的其他服务（DeepSeek/通义/本地模型等）

根据选择，编辑 `workflow/xhs-automation/config/runtime.env` 中的 LLM_PROVIDER、LLM_API_KEY、LLM_BASE_URL、LLM_MODEL。

**第二步：竞品分析播种**

1. 用 search_feeds 搜索 3 组关键词：
   - "GitHub 开源项目推荐"
   - "AI工具 推荐 教程"
   - "程序员 效率工具"
2. 每组取互动量 top 5，共约 15 条
3. 对 top 10 调 get_feed_detail 获取完整内容
4. 归纳提取：
   - 标题模式 3-5 个（模板 + 示例 + 适用场景）
   - 正文结构 2-3 个
   - 高频标签 top 10
   - 互动引导话术 2-3 个
5. 写入文件：
   - `knowledge-base/patterns.md`（初始 pattern，标记 source: competitor, confidence: low）
   - `knowledge-base/rules.json`（初始规则，合并 data/content-rules.md 中的约束）
   - `knowledge-base/README.md`（索引，阶段: cold-start）

### 创作时的知识读取

进行选题或内容创作前：

1. 读 `knowledge-base/README.md` — 了解当前阶段和有效 pattern 摘要
2. 读 `knowledge-base/patterns.md` — 获取活跃 pattern 详情
3. 融入创作思考：
   - confidence 为 high/medium 的 pattern 优先参考
   - cold-start 阶段 competitor 来源的 pattern 权重较低，鼓励探索
   - 不要机械套模板，pattern 是方向参考，结合选题灵活调整
4. 如果 `knowledge-base/reviews/` 下有最近的周复盘，浏览关键发现

### 知识库维护

知识库的定期更新由 workflow 后台脚本自动完成（review.py 每周日触发进化分析），Skill 层不负责写入复盘和更新规则。

但如果用户在交互中明确要求（如"分析一下最近的数据"、"更新知识库"），可以手动读取 data/exports/ 下的数据文件，执行分析并更新 knowledge-base/。
```

- [ ] **Step 2: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add skills/xiaohongshu/SKILL.md && git commit -m 'feat: add self-evolution knowledge-base section to SKILL.md'"
```

---

### Task 9: Install Script Update

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add knowledge-base directory creation to install.sh**

In `install.sh`, after the `mkdir -p "$INSTALL_ROOT"...` line, add:

```bash
mkdir -p "$INSTALL_ROOT/knowledge-base/reviews"
```

- [ ] **Step 2: Add LLM configuration prompt at end of install.sh**

Before the final `cat <<EOF` help text, add:

```bash
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
```

- [ ] **Step 3: Update the help text**

In the final `cat <<EOF` block, add after "5. Manual workflow test:":

```
7. (Optional) Seed knowledge base via the skill's cold-start flow:
   Use your agent tool to trigger the xiaohongshu skill's first-time initialization.
```

- [ ] **Step 4: Commit**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git add install.sh && git commit -m 'feat: add knowledge-base setup and LLM config to install script'"
```

---

### Task 10: Integration Verification

- [ ] **Step 1: Verify all imports work end-to-end**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling/workflow/xhs-automation/scripts && python3 -c '
import db; import llm; import review; import keepalive; import research; import create_content
db.init_db(); db.migrate_db()
print(\"All imports OK\")
print(\"DB path:\", db.DB_PATH)
print(\"Published posts:\", db.get_published_post_count())
'"
```

- [ ] **Step 2: Verify knowledge-base directory structure**

```bash
ssh weiyong@100.79.106.110 "ls -la /Users/weiyong/Documents/10/shuling/workflow/xhs-automation/knowledge-base/"
```

- [ ] **Step 3: Run a dry test of export_week_data**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling/workflow/xhs-automation/scripts && python3 -c '
import review
result = review.export_week_data(\"2026-04-15\")
print(\"Export result:\", result[0] if result[0] else \"No data (expected for new account)\")
'"
```

- [ ] **Step 4: Verify git status is clean**

```bash
ssh weiyong@100.79.106.110 "cd /Users/weiyong/Documents/10/shuling && git status && git log --oneline -10"
```

- [ ] **Step 5: Final commit with all remaining changes (if any)**

Only if there are uncommitted changes from minor fixes during verification.
