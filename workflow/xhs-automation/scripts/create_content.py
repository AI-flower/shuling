"""XHS 自动化系统 - 内容生成编排：读取候选 → Claude 生成 HTML → 截图 → meta.json"""
import html
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(__file__))
import config_loader
import db

config_loader.load_runtime_env()

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, "data")
POSTS_DIR = os.path.join(BASE_DIR, "posts")
RULES_FILE = os.path.join(DATA_DIR, "content-rules.md")

KNOWLEDGE_BASE_DIR = os.path.join(BASE_DIR, "knowledge-base")


def build_knowledge_context():
    """从 knowledge-base/ 读取活跃 pattern 和规则，构建 prompt 注入片段"""
    context_parts = []

    readme_path = os.path.join(KNOWLEDGE_BASE_DIR, "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            readme = f.read()
        context_parts.append(f"## 当前运营知识\n{readme}")

    patterns_path = os.path.join(KNOWLEDGE_BASE_DIR, "patterns.md")
    if os.path.exists(patterns_path):
        with open(patterns_path, "r", encoding="utf-8") as f:
            patterns = f.read()
        active_sections = []
        for section in patterns.split("\n### "):
            if "[DEPRECATED]" not in section and section.strip():
                active_sections.append(section)
        if active_sections:
            active_text = "\n### ".join(active_sections)
            context_parts.append(f"## 已验证有效的内容模式（请参考但不要机械套用）\n{active_text}")

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


def _find_executable(name, candidates=None):
    candidates = candidates or []
    for candidate in candidates:
        expanded = os.path.expanduser(candidate)
        if os.path.exists(expanded) and os.access(expanded, os.X_OK):
            return expanded
    found = shutil.which(name)
    if found:
        return found
    return None


def _resolve_screenshot_js():
    env_override = os.environ.get("XHS_SCREENSHOT_JS")
    candidates = [
        env_override,
        os.path.expanduser("~/.claude/skills/xhs-content-generator/scripts/screenshot.cjs"),
        os.path.expanduser("~/.agents/skills/xhs-content-generator/scripts/screenshot.cjs"),
        os.path.expanduser("~/.codex/skills/xhs-content-generator/scripts/screenshot.cjs"),
    ]
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    return os.path.expanduser("~/.claude/skills/xhs-content-generator/scripts/screenshot.cjs")


SCREENSHOT_JS = _resolve_screenshot_js()
NODE_PATH = os.environ.get("XHS_NODE_PATH") or os.environ.get("NODE_PATH")
NODE_BIN = _find_executable("node", [
    os.environ.get("XHS_NODE_BIN"),
    "~/.nvm/versions/node/v24.14.0/bin/node",
    "/opt/homebrew/bin/node",
    "/usr/local/bin/node",
])
CLAUDE_BIN = _find_executable("claude", [
    os.environ.get("XHS_CLAUDE_BIN"),
    "~/.local/bin/claude",
])


def load_candidates(date_str):
    """加载当天的候选项目"""
    candidates_file = os.path.join(DATA_DIR, f"candidates-{date_str}.json")
    if not os.path.exists(candidates_file):
        print(f"候选文件不存在: {candidates_file}", file=sys.stderr)
        return []
    with open(candidates_file, "r") as f:
        data = json.load(f)
    return data.get("selected", [])


def load_rules():
    """加载 XHS 合规规则"""
    if os.path.exists(RULES_FILE):
        with open(RULES_FILE, "r") as f:
            return f.read()
    return ""


def _clean_text(value):
    return re.sub(r"\s+", " ", (value or "")).strip()


def _strip_markdown_links(text):
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"`{1,3}[^`]+`{1,3}", "", text)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"https?://\S+", "", text)
    return _clean_text(text)


def _pick_readme_points(readme, limit=4):
    points = []
    seen = set()
    for raw in (readme or "").splitlines():
        text = _strip_markdown_links(raw.strip())
        text = re.sub(r"^[\-\*\d\.\)\s]+", "", text)
        text = _clean_text(text)
        if len(text) < 20 or len(text) > 120:
            continue
        if text.startswith(("http", "<", "##", "#", "```")):
            continue
        if text.lower() in seen:
            continue
        if any(bad in text.lower() for bad in ["license", "contributing", "discord", "twitter", "linkedin", "sponsor"]):
            continue
        seen.add(text.lower())
        points.append(text)
        if len(points) >= limit:
            break
    return points


def _candidate_name(candidate):
    repo = candidate.get("repo", "")
    return repo.split("/")[-1] if repo else "这个工具"


def _sanitize_readme_for_prompt(readme, limit=1800):
    lines = []
    for raw in (readme or "").splitlines():
        text = _strip_markdown_links(raw)
        if not text:
            continue
        if len(text) < 12:
            continue
        if any(bad in text.lower() for bad in ["license", "contributing", "discord", "twitter", "linkedin", "sponsor", "download", "website"]):
            continue
        lines.append(text)
        if len("\n".join(lines)) >= limit:
            break
    return "\n".join(lines)[:limit]


def _build_default_schedule_at(date_str, slot):
    default_hour = 13 if slot == "noon" else 22
    target = datetime.fromisoformat(f"{date_str}T{default_hour:02d}:00:00")
    now = datetime.now()
    min_allowed = now + timedelta(minutes=65)
    if target.date() == now.date() and target <= min_allowed:
        target = min_allowed.replace(second=0, microsecond=0)
        if target.minute == 0:
            target = target.replace(minute=30)
        elif target.minute <= 30:
            target = target.replace(minute=30)
        else:
            target = (target + timedelta(hours=1)).replace(minute=0)
    return f"{target.strftime('%Y-%m-%dT%H:%M:%S')}+08:00"


def generate_html_fallback(candidate, slot):
    """当 Claude 生成失败时，使用本地模板兜底。"""
    name = _candidate_name(candidate)
    stars = candidate.get("stars", 0)
    desc = _clean_text(candidate.get("description", ""))
    topics = candidate.get("topics", [])[:6]
    readme_points = _pick_readme_points(candidate.get("readme", ""), limit=4)
    top_line = desc or "这个项目最近在开源社区热度挺高。"
    scenario_points = []

    if topics:
        lowered = " ".join(t.lower() for t in topics)
        if any(k in lowered for k in ["database", "sql", "postgresql", "mysql"]):
            scenario_points = [
                "适合天天查库、改 SQL、看数据的人",
                "更适合拿来做提效，不是拿来炫技",
                "如果你总在几个数据库之间切来切去，会很有感",
            ]
            noon_title = "一个工具管多库"
            evening_title = "查库的人先别乱装"
        elif any(k in lowered for k in ["agent", "workflow", "automation", "mcp"]):
            scenario_points = [
                "适合想把重复流程交给 AI 的人",
                "比较适合先做一个小场景，不适合一口气做全能助手",
                "如果你老在重复点网页、查资料、搬内容，这类工具很容易出效果",
            ]
            noon_title = "总在重复做事的人看"
            evening_title = "先别把它想太复杂"
    if not scenario_points:
        scenario_points = [
            "适合想先做出第一版的人",
            "比较适合明确场景，不适合一上来就做大而全",
            "如果你经常重复做同一类事，这种工具更容易出效果",
        ]
        noon_title = "这个工具先别急着跳过"
        evening_title = "新手先别这样用"

    feature_cards = readme_points or [
        top_line,
        "它不是只能展示，重点是能把一件事做顺。",
        "更适合拿来做第一版，而不是一步到位做成很复杂的系统。",
        "先从一个具体场景试，再决定要不要继续加功能。",
    ]

    if slot == "noon":
        title = noon_title
        hook = f"我最近重新看了 {name}，发现它最值钱的不是噱头，而是一些真的能替你省时间的细节。"
    else:
        title = evening_title
        hook = f"我觉得很多人第一次用 {name} 都容易走偏，不是不会用，而是上来就把它想复杂了。"

    title = title[:20]
    title_html = html.escape(title)
    subtitle_html = html.escape(top_line[:80])
    hook_html = html.escape(hook)
    name_html = html.escape(name)
    repo_html = html.escape(candidate.get("repo", ""))
    cards_html = "\n".join(
        f'<div class="card"><h3>{html.escape(str(idx + 1))}</h3><p>{html.escape(point)}</p></div>'
        for idx, point in enumerate(feature_cards[:4])
    )
    scenario_html = "\n".join(f"<li>{html.escape(item)}</li>" for item in scenario_points)
    topic_html = " / ".join(html.escape(t) for t in topics[:4]) if topics else "适合先从一个小场景开始试"

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title_html}</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ display:flex; flex-direction:column; align-items:center; gap:32px; padding:32px; background:#f4f1ea; font-family:'Noto Sans SC', sans-serif; }}
  .page {{ width:1080px; height:1440px; border:6px solid #111; box-shadow:14px 14px 0 #111; overflow:hidden; }}
  .shell {{ height:100%; padding:48px; display:flex; flex-direction:column; gap:18px; }}
  .cover {{ background:#ffe14f; }}
  .page2 {{ background:#d7f6ff; }}
  .page3 {{ background:#ffd7e6; }}
  .page4 {{ background:#fff7ef; }}
  .page5 {{ background:#defee0; }}
  h1, h2 {{ font-family:'Arial Black','Noto Sans SC',sans-serif; line-height:1.05; }}
  h1 {{ font-size:96px; }}
  h2 {{ font-size:52px; }}
  .tag {{ display:inline-block; border:4px solid #111; background:#fff; padding:10px 16px; font-size:22px; font-weight:900; }}
  .note, .card, .warn, .cta {{ border:5px solid #111; background:#fff; padding:22px 24px; }}
  .note p, .card p, .warn li, .cta p {{ font-size:28px; line-height:1.65; font-weight:600; }}
  .grid {{ display:grid; grid-template-columns:1fr 1fr; gap:16px; }}
  .card h3 {{ font-size:30px; margin-bottom:8px; }}
  .stats {{ display:grid; grid-template-columns:repeat(3,1fr); gap:16px; }}
  .stat {{ border:5px solid #111; background:#fff7ef; padding:18px 20px; }}
  .stat .big {{ font-size:44px; font-weight:900; }}
  .stat .small {{ font-size:18px; line-height:1.5; font-weight:700; margin-top:6px; }}
  ul {{ padding-left:24px; }}
</style>
</head>
<body>
  <section class="page cover"><div class="shell">
    <div class="tag">OPENCLAW / 自动兜底稿</div>
    <h1>{title_html}</h1>
    <div class="note"><p>{hook_html}</p></div>
    <div class="stats">
      <div class="stat"><div class="big">{stars:,}</div><div class="small">开源社区 star</div></div>
      <div class="stat"><div class="big">看点</div><div class="small">{subtitle_html}</div></div>
      <div class="stat"><div class="big">适合</div><div class="small">{topic_html}</div></div>
    </div>
    <div class="cta"><p>{name_html} 这类工具我更建议先拿一个小场景试，不要一上来就做大。</p></div>
  </div></section>
  <section class="page page2"><div class="shell">
    <h2>我先看见了什么</h2>
    <div class="note"><p>{html.escape(top_line)}</p></div>
    <div class="grid">{cards_html}</div>
  </div></section>
  <section class="page page3"><div class="shell">
    <h2>它更适合谁</h2>
    <div class="warn"><ul>{scenario_html}</ul></div>
    <div class="note"><p>仓库：{repo_html}</p></div>
  </div></section>
  <section class="page page4"><div class="shell">
    <h2>如果是我会怎么开始</h2>
    <div class="grid">
      <div class="card"><h3>先做小</h3><p>先让它只解决一个最常见问题，先有一个能顺手用的版本。</p></div>
      <div class="card"><h3>先看资料</h3><p>先确认项目到底在解决什么，再决定是不是值得继续折腾。</p></div>
      <div class="card"><h3>先测真实问题</h3><p>别只看 demo，要拿你自己真的会遇到的问题去试。</p></div>
      <div class="card"><h3>别一口吃太多</h3><p>先把一个点用顺，再考虑要不要继续加功能和自动化。</p></div>
    </div>
  </div></section>
  <section class="page page5"><div class="shell">
    <h2>最后我会怎么判断</h2>
    <div class="note"><p>如果它能帮我省掉一件重复小事，我就觉得值。如果只是看起来很强，但我用不上，那就先不折腾。</p></div>
    <div class="cta"><p>想看我把 {name_html} 再拆成更小白的用法，我可以继续往下写。</p></div>
  </div></section>
</body>
</html>"""


def generate_html_with_claude(candidate, slot, rules):
    """调用 Claude CLI 生成帖子 HTML"""
    repo = candidate.get("repo", "")
    name = repo.split("/")[-1] if repo else "AI工具"
    desc = candidate.get("description", "")
    stars = candidate.get("stars", 0)
    forks = candidate.get("forks", 0)
    language = candidate.get("language", "")
    topics = candidate.get("topics", [])
    readme = candidate.get("readme", "")

    # 准备 README 摘要（只取最有用的部分）
    readme_section = ""
    if readme:
        cleaned_readme = _sanitize_readme_for_prompt(readme)
        readme_section = f"""
## 项目 README 原文（节选）
```
{cleaned_readme}
```
从 README 里提取：核心功能点、使用场景、安装命令、实际效果截图描述等具体信息，融入内容中。
"""

    if slot == "noon":
        writing_angle = f"""
写作角度：**"我发现了一个宝藏项目，手把手教你用"** 的真实分享感

**内容结构（每页都要有实质内容，不能是大标题+一句话）：**

第1页（封面）：
- 用数字或结果导向的标题，例如"3分钟搞定XXX"、"0基础也能用的XXX神器"
- 副标题点出核心价值，一句话
- CTA：告诉我你想用AI做什么，我来出教程

第2页（痛点共鸣）：
- 描述一个真实场景：具体到"每天花X分钟做某事"、"做到第N步就卡住了"
- 写出这个痛点有多烦，引发共鸣
- 自然引出"后来我发现了这个"

第3页（项目介绍）：
- 用大白话解释这工具是干什么的（假设读者不懂技术）
- 列出3-4个具体使用场景，每个场景用"如果你要XXX，它能帮你YYY"格式
- 从README提取最有说服力的数据或对比

第4页（保姆级上手教程）— 这是最重要的一页，必须够详细：
- 先写"准备工作"清单（需要什么环境/账号/文件，1-3项）
- 然后写3-5个步骤，每步格式：
  - 步骤标题（做什么）
  - 具体操作（实际命令/设置项/点击位置，用代码块展示命令）
  - 成功标志（"完成后你会看到XXX"）
- 最后写1-2个新手常见错误和解决办法

第5页（效果展示）：
- 用"以前我需要..."和"现在只要..."对比
- 写真实感受，可以有优缺点，不要全是优点
- 适合什么人用、不适合什么人

第6页（总结引导）：
- 一句话总结
- 评论区互动引导
"""
    else:
        writing_angle = f"""
写作角度：**"教你一个我摸索出来的实操方法"** 的技巧分享感

**内容结构（每页都要有实质内容）：**

第1页（封面）：
- 直接点明能解决什么问题，例如"0基础也能XXX""用{name}自动化YYY的完整教程"
- CTA：告诉我你想用AI做什么，我来出教程

第2页（背景说明）：
- 一句话介绍这工具是什么（给完全没听过的人看）
- 说明今天要实现的具体目标是什么

第3页（核心原理/功能介绍）：
- 解释这个技巧为什么有用
- 从README找到实际功能，用具体例子说明

第4页（完整操作教程）— 核心页，必须够详细：
- 第一步：准备工作（列出需要安装的工具、需要的账号、前置条件）
  - 每个准备项都要说为什么需要它
- 第2-5步：实际操作步骤
  - 每步必须有：做什么 + 具体命令（代码块展示） + 预期结果
  - 命令要完整可运行，不能只写"安装XX"
- 踩坑提醒：2-3个新手会遇到的错误，每个给出解决方法

第5页（效果验证）：
- 展示最终效果
- "以前我..."对比"现在用这个方法..."
- 说清楚节省了多少时间/解决了什么问题

第6页（总结）：
- 总结一下这个方法适合谁
- 引导收藏和互动
"""

    knowledge_context = build_knowledge_context()
    knowledge_section = ""
    if knowledge_context:
        knowledge_section = f"""

## 历史运营数据洞察（参考，不要照搬）
{knowledge_context}

基于以上洞察，在写作时优先参考 confidence 为 medium/high 的 pattern。
"""

    prompt = f"""你是一个真实的科技博主，在小红书上分享 GitHub 开源项目。品牌叫 OpenClaw（开源龙虾🦞）。

你不是机器人，你是一个真实使用过这些工具的人，用大白话分享自己的发现和体验。

## 今天要写的项目

**项目名称：** {name}
**GitHub：** {repo}（⭐{stars:,} · 🍴{forks:,}）
**简介：** {desc}
**主要语言：** {language}
**标签：** {', '.join(topics[:6])}
{readme_section}{knowledge_section}

## 写作要求
{writing_angle}

## 语言风格（非常重要）
- 用第一人称，像和朋友说话
- 多用口语：啊、哦、哈哈、真的、绝了、太好用了、没想到
- 偶尔用感叹句、省略号
- 不要用"综上所述"、"总的来说"等书面语
- 标题口语化，可以用疑问句或感叹句
- **每一页文字要有实质内容**，不能只有大标题+一句话
- **教程步骤要具体**：写命令要写完整命令，写操作要写具体点哪里，让没用过的人也能跟着做
- 不要默认生成 `X到底值不值`、`X别乱上手`、`X适合谁` 这类标题
- 标题优先写成人群、错误、顺序、结果这四类
- 不要把仓库名或 README 原句直接拿来当标题
- 不要把 README 的英文句子直接搬进正文

## 内容质量要求（最重要）
- 读者看完第4页应该能真正上手，不需要再去搜索其他教程
- 每个步骤不能只写标题，要有具体说明
- 命令/代码要完整，不能写"安装依赖"这种模糊描述，要写`pip install xxx`
- 对新手不友好的地方要特别说明（"这里注意"、"很多人会在这步卡住"）

## 合规规则（必须严格遵守）
{rules}

## HTML 技术要求
- 生成完整 HTML（含所有内联 CSS），不要任何解释，从 <!DOCTYPE html> 开始
- 设计风格：内容优先，简洁清晰。用卡片式布局（圆角 12px、轻阴影）而不是过于花哨的装饰
- 颜色系统：主色 #2563EB（蓝）/ 强调 #F59E0B（黄）/ 绿 #10B981 / 红 #EF4444 / 背景 #F8FAFC / 文字 #111827
- 字体：Google Fonts - Inter（英文）+ Noto Sans SC（中文）
- 每页 1080px × 1440px，class="page"，内容要填满页面，不能留大片空白
- 页数：5-6 页，按写作角度里的结构要求来
- body 样式：display:flex; flex-direction:column; align-items:center; gap:40px; padding:40px; background:#E2E8F0;
- 每页内 padding 至少 48px，文字不贴边
- 代码/命令用等宽字体块展示，背景 #1E293B，文字 #86EFAC，padding 16px，圆角 8px
- 步骤编号用圆形色块（背景蓝色，白色数字），每步内容包含：操作说明 + 代码块（如有）+ 成功提示（用绿色小标签"✓ 完成标志"）
- 重要提醒用黄色背景卡片展示（如"⚠️ 新手常见错误"）
- 对比内容用左右分栏：左边灰色背景"以前"，右边绿色背景"现在"

## 输出
只输出 HTML，从 <!DOCTYPE html> 开始，不要任何解释文字。"""

    try:
        claude_bin = CLAUDE_BIN or "claude"
        env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
        env["PATH"] = os.path.expanduser("~/.local/bin") + ":" + env.get("PATH", "")
        result = subprocess.run(
            [claude_bin, "--dangerously-skip-permissions", "--print", "-p", prompt],
            capture_output=True, text=True, timeout=180,
            env=env
        )
        if result.returncode != 0:
            err = result.stderr.strip() or result.stdout.strip()[:200]
            print(f"Claude 生成失败 (rc={result.returncode}): {err}", file=sys.stderr)
            return None

        html = result.stdout.strip()
        # 提取 HTML（有时 Claude 会加 ```html 包裹）
        if "```html" in html:
            html = html.split("```html", 1)[1]
            html = html.rsplit("```", 1)[0]
        elif "```" in html and "<!DOCTYPE" in html:
            parts = html.split("```")
            for p in parts:
                if "<!DOCTYPE" in p:
                    html = p
                    break
        html = html.strip()

        if not html.startswith("<!DOCTYPE") and not html.startswith("<html"):
            print("Claude 输出不是有效 HTML", file=sys.stderr)
            return None

        return html
    except subprocess.TimeoutExpired:
        print("Claude 生成超时（120s）", file=sys.stderr)
        return None
    except FileNotFoundError:
        print("claude CLI 未找到，请确认已安装", file=sys.stderr)
        return None


def extract_title_from_html(html):
    """从 HTML 中提取标题"""
    import re
    # 尝试从封面页提取
    patterns = [
        r'<h1[^>]*>(.*?)</h1>',
        r'class="[^"]*title[^"]*"[^>]*>(.*?)<',
        r'class="[^"]*cover[^"]*".*?<[^>]+>(.*?)<',
    ]
    for pat in patterns:
        m = re.search(pat, html, re.DOTALL | re.IGNORECASE)
        if m:
            title = re.sub(r'<[^>]+>', '', m.group(1)).strip()
            if 3 <= len(title) <= 20:
                return title
    return None


def take_screenshots(html_path, output_dir):
    """调用 Playwright 截图"""
    try:
        if not os.path.exists(SCREENSHOT_JS):
            print(f"截图失败: 未找到截图脚本 {SCREENSHOT_JS}", file=sys.stderr)
            return []
        if not NODE_BIN:
            print("截图失败: 未找到 node 可执行文件", file=sys.stderr)
            return []
        env = {
            **os.environ,
            "PATH": os.path.dirname(NODE_BIN) + ":" + os.environ.get("PATH", ""),
        }
        if NODE_PATH:
            env["NODE_PATH"] = NODE_PATH
        result = subprocess.run(
            [NODE_BIN, SCREENSHOT_JS, html_path, output_dir],
            capture_output=True, text=True, timeout=60,
            env=env,
        )
        if result.returncode != 0:
            print(f"截图失败: {result.stderr}", file=sys.stderr)
            return []

        # 查找生成的 PNG 文件
        import glob
        pngs = sorted(glob.glob(os.path.join(output_dir, "*.png")))

        # 重命名为 page-N.png 格式
        renamed = []
        for i, png in enumerate(pngs, 1):
            new_name = os.path.join(output_dir, f"page-{i}.png")
            if png != new_name:
                os.rename(png, new_name)
            renamed.append(new_name)

        return renamed
    except Exception as e:
        print(f"截图异常: {e}", file=sys.stderr)
        return []


def create_post(candidate, date_str, slot, post_number):
    """创建完整帖子：HTML → 截图 → meta.json → DB"""
    post_dir_name = f"{date_str}-post{post_number}"
    post_dir = os.path.join(POSTS_DIR, post_dir_name)
    os.makedirs(post_dir, exist_ok=True)

    print(f"\n{'='*50}")
    print(f"📝 创建帖子: {slot} ({post_dir_name})")
    print(f"  项目: {candidate.get('repo', 'N/A')}")
    print(f"{'='*50}\n")

    rules = load_rules()

    # 1. 生成 HTML
    print("🤖 调用 Claude 生成 HTML...")
    html = generate_html_with_claude(candidate, slot, rules)
    if not html:
        print("⚠️ Claude 生成失败，启用本地兜底模板...")
        html = generate_html_fallback(candidate, slot)
    if not html:
        print("❌ HTML 生成失败")
        return None

    html_path = os.path.join(post_dir, "post.html")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"  ✅ HTML 保存: {html_path}")

    # 2. 截图
    print("📸 Playwright 截图...")
    images = take_screenshots(html_path, post_dir)
    if not images:
        print("❌ 截图失败")
        return None
    print(f"  ✅ 生成 {len(images)} 张图片")

    # 3. 提取标题
    title = extract_title_from_html(html)
    if not title:
        name = candidate.get("repo", "").split("/")[-1]
        title = f"这个AI工具绝了！{name}"
        if len(title) > 20:
            title = title[:18] + "..."
    print(f"  标题: {title}")

    # 4. 构造 meta.json
    schedule_at = _build_default_schedule_at(date_str, slot)

    # 生成标签
    name = candidate.get("repo", "").split("/")[-1]
    tags = ["AI", "效率提升", "打工人"]
    if name:
        tags.append(name)
    topics = candidate.get("topics", [])
    for t in topics[:3]:
        if t not in tags and len(tags) < 8:
            tags.append(t)
    if len(tags) < 6:
        tags.extend(["AI工具", "开源", "自动化"][:8 - len(tags)])

    # 生成正文 content（用于 XHS 搜索展示，要有实质内容）
    desc = candidate.get("description", "")
    stars = candidate.get("stars", 0)
    repo = candidate.get("repo", "")
    readme = candidate.get("readme", "")

    # 从 README 提取一段有用的介绍（取第一个非标题段落）
    readme_intro = ""
    if readme:
        for line in readme.split("\n"):
            stripped = line.strip()
            if stripped and not stripped.startswith("#") and len(stripped) > 30:
                readme_intro = stripped[:150]
                break

    if slot == "noon":
        hook = f"GitHub {stars:,}⭐ 的开源项目 {repo.split('/')[-1]}，用了一周，真的改变了我的工作方式。"
    else:
        hook = f"分享一个 {repo.split('/')[-1]} 的隐藏用法，我摸索了好久才发现的，给你们省时间。"

    content_parts = [hook]
    if desc:
        content_parts.append(desc[:150])
    if readme_intro:
        content_parts.append(readme_intro)
    content_parts.append("详细教程在图里，点开看👆")
    content_parts.append("评论区告诉我你想用AI做什么，我来出教程🦞")

    content = "\n\n".join(content_parts)
    if len(content) > 1000:
        content = content[:997] + "..."

    meta = {
        "title": title,
        "content": content,
        "tags": tags,
        "schedule_at": schedule_at,
        "is_original": True
    }

    meta_path = os.path.join(post_dir, "meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print(f"  ✅ meta.json 保存")

    # 5. 写入 DB
    post_id = db.add_post(
        date_str=date_str,
        slot=slot,
        post_dir=os.path.abspath(post_dir),
        title=title,
        content=content,
        tags=tags,
        post_type="tool_recommend" if slot == "noon" else "skill_tip",
        github_repo=candidate.get("repo"),
        github_stars=candidate.get("stars"),
        scheduled_at=schedule_at
    )
    print(f"  ✅ DB 记录: post_id={post_id}")

    return {
        "post_id": post_id,
        "post_dir": post_dir,
        "title": title,
        "slot": slot,
        "images": len(images)
    }


def slot_already_exists(date_str, slot):
    """检查该 date+slot 是否已有有效记录（draft/scheduled/published），避免重复创建"""
    rows = db.get_posts_by_date(date_str, slot)
    active = [r for r in rows if r["status"] in ("draft", "scheduled", "published")]
    return len(active) > 0


def run_create(date_str=None):
    """执行完整内容创建流程"""
    if date_str is None:
        date_str = date.today().isoformat()

    db.init_db()
    print(f"=== XHS 内容创建 {date_str} ===\n")

    candidates = load_candidates(date_str)
    if not candidates:
        print("没有候选项目，请先运行 research.py")
        return []

    results = []

    # Noon 帖子（工具推荐）
    if len(candidates) >= 1:
        if slot_already_exists(date_str, "noon"):
            print(f"⏭️  跳过 noon：{date_str} 已有有效帖子")
        else:
            r = create_post(candidates[0], date_str, "noon", 1)
            if r:
                results.append(r)

    # Evening 帖子（技巧分享）
    if len(candidates) >= 2:
        if slot_already_exists(date_str, "evening"):
            print(f"⏭️  跳过 evening：{date_str} 已有有效帖子")
        else:
            r = create_post(candidates[1], date_str, "evening", 2)
            if r:
                results.append(r)

    print(f"\n{'='*50}")
    print(f"✅ 内容创建完成！共 {len(results)} 篇")
    for r in results:
        print(f"  {r['slot']}: 「{r['title']}」({r['images']} 张图)")
    print(f"{'='*50}")

    return results


if __name__ == "__main__":
    date_str = sys.argv[1] if len(sys.argv) > 1 else None
    run_create(date_str)
