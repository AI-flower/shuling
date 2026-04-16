"""XHS 自动化系统 - 多草稿并行生成器

接收选题候选 + 反馈洞察，用 asyncio 并行调用 Claude CLI 生成多份差异化草稿。
支持 lite(3份) / pro(8份) 两种模式。
"""
import asyncio
import json
import logging
import os
import re
import sys
from datetime import date, datetime

sys.path.insert(0, os.path.dirname(__file__))
import config_loader
import db

config_loader.load_runtime_env()

LOG = logging.getLogger(__name__)

CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "draft-config.json")

# 每个角度最适配的风格优先级（pro 模式每角度取前 2 个）
ANGLE_STYLE_AFFINITY = {
    "recommend": ["casual", "suspense", "professional"],
    "tutorial":  ["professional", "casual", "suspense"],
    "compare":   ["professional", "suspense", "casual"],
    "story":     ["suspense", "casual", "professional"],
}


def load_draft_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# 组合选择
# ---------------------------------------------------------------------------

def select_combinations(mode, config):
    """根据模式选择 angle-style 组合列表"""
    if mode == "pro":
        return _select_pro(config)
    return _select_lite(config)


def _select_pro(config):
    """Pro 模式: 4角度 x 2风格 = 8份"""
    combos = []
    for angle in config["angles"]:
        preferred = ANGLE_STYLE_AFFINITY.get(angle, config["styles"][:2])
        combos.append((angle, preferred[0]))
        combos.append((angle, preferred[1]))
    return combos


def _select_lite(config):
    """Lite 模式: 智能选 3 个组合"""
    combos = []

    # 1) 历史最优组合
    perf = db.get_history_performance()
    best = _best_performing_combo(perf)
    if best:
        combos.append(best)

    # 2) 蓝海探索 - 从最近未使用的角度中选
    recent_angles = db.get_recent_angles()
    all_angles = config["angles"]
    unused = [a for a in all_angles if a not in recent_angles]
    if unused:
        angle = unused[0]
        style = ANGLE_STYLE_AFFINITY.get(angle, config["styles"])[0]
        pair = (angle, style)
        if pair not in combos:
            combos.append(pair)

    # 3) 从默认组合中补充至 3 个
    defaults = _parse_default_combos(config)
    for pair in defaults:
        if len(combos) >= 3:
            break
        if pair not in combos:
            combos.append(pair)

    # 冷启动 fallback - 如果上面凑不满 3 个
    if not combos:
        combos = defaults[:3]
    while len(combos) < 3:
        for pair in defaults:
            if pair not in combos:
                combos.append(pair)
                break
        else:
            break

    return combos[:3]


def _best_performing_combo(perf_rows):
    """从历史表现数据中找平均互动最高的组合"""
    if not perf_rows:
        return None
    best = max(perf_rows,
               key=lambda r: (r.get("avg_likes", 0) or 0)
                            + (r.get("avg_saves", 0) or 0) * 2
                            + (r.get("avg_comments", 0) or 0) * 1.5)
    angle = best.get("angle")
    style = best.get("style")
    if angle and style:
        return (angle, style)
    return None


def _parse_default_combos(config):
    """解析配置中的默认组合字符串列表"""
    raw = config.get("lite_mode", {}).get("default_combos", [])
    combos = []
    for item in raw:
        parts = item.split("-", 1)
        if len(parts) == 2:
            combos.append((parts[0], parts[1]))
    return combos


# ---------------------------------------------------------------------------
# 反馈注入
# ---------------------------------------------------------------------------

def build_feedback_section():
    """从 DB 读取最新反馈，格式化为 prompt 片段"""
    feedback = db.get_latest_feedback(limit=3)
    if not feedback:
        return ""

    all_questions = []
    all_praise = []
    all_complaints = []
    all_requests = []

    for f in feedback:
        if f.get("top_questions"):
            try:
                all_questions.extend(json.loads(f["top_questions"]))
            except (json.JSONDecodeError, TypeError):
                pass
        if f.get("top_praise"):
            try:
                all_praise.extend(json.loads(f["top_praise"]))
            except (json.JSONDecodeError, TypeError):
                pass
        if f.get("top_complaints"):
            try:
                all_complaints.extend(json.loads(f["top_complaints"]))
            except (json.JSONDecodeError, TypeError):
                pass
        if f.get("content_requests"):
            try:
                all_requests.extend(json.loads(f["content_requests"]))
            except (json.JSONDecodeError, TypeError):
                pass

    if not any([all_questions, all_praise, all_complaints, all_requests]):
        section = ""
    else:
        section = "## 上期用户反馈（自动注入，请参考）\n"
    if all_questions:
        section += f"- 用户高频提问：{', '.join(all_questions[:5])}\n"
    if all_praise:
        section += f"- 用户好评点：{', '.join(all_praise[:5])}\n"
    if all_complaints:
        section += f"- 用户吐槽点：{', '.join(all_complaints[:5])}\n"
    if all_requests:
        section += f"- 用户内容需求：{', '.join(all_requests[:5])}\n"

    # 追加 NoteRx 诊断维度反馈
    diagnoses = db.get_recent_diagnoses(limit=3)
    if diagnoses:
        section += "\n## 近期帖子诊断维度（NoteRx 数据驱动）\n"
        for d in diagnoses:
            title = d.get("title", "")[:20]
            section += f"\n### 「{title}」{d.get('grade', '?')} {d.get('overall_score', 0):.0f}分\n"
            section += (
                f"- 内容质量: {d.get('content_score', 0):.0f} | "
                f"视觉表现: {d.get('visual_score', 0):.0f} | "
                f"增长策略: {d.get('growth_score', 0):.0f} | "
                f"用户反应: {d.get('user_reaction_score', 0):.0f}\n"
            )
            # 找出最低维度作为改进重点
            dims = {
                "内容质量": d.get("content_score", 50),
                "视觉表现": d.get("visual_score", 50),
                "增长策略": d.get("growth_score", 50),
                "用户反应": d.get("user_reaction_score", 50),
            }
            weakest = min(dims, key=dims.get)
            section += f"- 短板维度: {weakest}（{dims[weakest]:.0f}分），本次创作请重点优化\n"

            # 追加具体 issues/suggestions（如有完整诊断）
            issues = []
            if d.get("issues"):
                try:
                    issues = json.loads(d["issues"]) if isinstance(d["issues"], str) else d["issues"]
                except (json.JSONDecodeError, TypeError):
                    pass
            if issues:
                section += f"- 具体问题: {'; '.join(str(i) for i in issues[:3])}\n"

            suggestions = []
            if d.get("suggestions"):
                try:
                    suggestions = json.loads(d["suggestions"]) if isinstance(d["suggestions"], str) else d["suggestions"]
                except (json.JSONDecodeError, TypeError):
                    pass
            if suggestions:
                section += f"- 改进建议: {'; '.join(str(s) for s in suggestions[:2])}\n"

    return section


# ---------------------------------------------------------------------------
# JSON 解析
# ---------------------------------------------------------------------------

def parse_draft_json(text):
    """鲁棒解析 Claude 输出中的 JSON"""
    # 尝试直接解析
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # 尝试从 ```json ... ``` 中提取
    m = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass
    # 尝试找第一个 { 到最后一个 }
    start = text.find('{')
    end = text.rfind('}')
    if start >= 0 and end > start:
        try:
            return json.loads(text[start:end + 1])
        except json.JSONDecodeError:
            pass
    return None


# ---------------------------------------------------------------------------
# 单份草稿生成
# ---------------------------------------------------------------------------

claude_bin = os.environ.get("XHS_CLAUDE_BIN", "claude")


async def generate_one_draft(semaphore, candidate, angle, style, slot,
                             feedback_text, config):
    """调用 Claude CLI 生成一份草稿"""
    async with semaphore:
        draft_id = f"{slot}-{angle}-{style}"
        angle_desc = config["angle_descriptions"][angle]
        style_desc = config["style_descriptions"][style]

        repo_name = candidate.get("repo", candidate.get("name", "未知"))
        description = candidate.get("description", "")
        stars = candidate.get("stars", "N/A")

        prompt = f"""你是一个小红书内容创作专家。请为以下选题创作一篇小红书推文。

## 选题信息
- 项目名：{repo_name}
- 描述：{description}
- Stars：{stars}

## 创作要求
- 角度：{angle_desc}
- 风格：{style_desc}
- 标题：≤20字，包含核心关键词
- 正文：≤1000字
- 标签：5-8个相关标签
- 禁止提及其他平台名（抖音、微博等）
- 末尾需要 CTA 引导互动

{feedback_text}

请严格按以下 JSON 格式返回（不要加 markdown 代码块标记）：
{{
  "title": "标题",
  "content": "正文内容",
  "key_points": ["要点1", "要点2", "要点3"],
  "tags": ["#标签1", "#标签2"],
  "suggested_format": "image_text 或 image_only",
  "visual_style": "这篇帖子所有配图的统一视觉风格描述，30-50词英文，包含色调、构图、元素风格（如：warm orange gradient background, rounded info-cards with soft shadows, cute tech icons, lobster mascot in corner, low-saturation Xiaohongshu aesthetic）",
  "image_prompts": [
    "封面图：必须抓眼球，包含主题核心元素的插画描述，突出视觉冲击力",
    "第2页配图：与该页具体内容相关的插画描述",
    "第3页配图：与该页具体内容相关的插画描述"
  ]
}}

image_prompts 要求：
- 每个 prompt 用英文，30-60 词
- 封面图（第1个）要突出 eye-catching、vibrant，适合信息流点击
- 内容页配图要与该页的具体知识点相关，不要泛泛写 illustration for content
- 所有 prompt 共享 visual_style 中的色调和风格，保持多页一致性
- prompt 描述画面内容，不要写文字（文字由 HTML 截图处理）"""

        LOG.info("Generating draft %s ...", draft_id)
        proc = await asyncio.create_subprocess_exec(
            claude_bin, "--dangerously-skip-permissions", "--print", "-p", prompt,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=180)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            LOG.warning("Draft %s timed out", draft_id)
            return None

        if proc.returncode != 0:
            LOG.warning("Draft %s failed (rc=%d): %s",
                        draft_id, proc.returncode,
                        stderr.decode("utf-8", errors="replace")[:200])
            return None

        output = stdout.decode("utf-8").strip()
        draft_data = parse_draft_json(output)
        if not draft_data:
            LOG.warning("Draft %s: failed to parse JSON from output (%d chars)",
                        draft_id, len(output))
            return None

        draft_data["draft_id"] = draft_id
        draft_data["angle"] = angle
        draft_data["style"] = style
        draft_data["generated_at"] = datetime.now().isoformat()
        return draft_data


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------

async def generate_drafts(candidate, slot, date_str=None):
    """生成多份草稿，返回草稿列表"""
    config = load_draft_config()
    mode = os.environ.get("DRAFT_MODE", "lite")
    concurrency = int(os.environ.get("DRAFT_CONCURRENCY", "3"))
    date_str = date_str or date.today().isoformat()

    combos = select_combinations(mode, config)
    feedback_text = build_feedback_section()
    semaphore = asyncio.Semaphore(concurrency)

    LOG.info("Mode=%s, combos=%d, concurrency=%d", mode, len(combos), concurrency)

    tasks = [
        generate_one_draft(semaphore, candidate, angle, style, slot,
                           feedback_text, config)
        for angle, style in combos
    ]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    drafts = []
    for r in results:
        if isinstance(r, Exception):
            LOG.warning("Draft task raised: %s", r)
            continue
        if isinstance(r, dict) and r.get("title"):
            # 将 visual_style 嵌入 image_prompts 结构，统一存储
            raw_prompts = r.get("image_prompts", [])
            visual_style = r.get("visual_style", "")
            image_prompts_structured = {
                "visual_style": visual_style,
                "prompts": raw_prompts if isinstance(raw_prompts, list) else [],
            }

            row_id = db.add_draft(
                date_str, slot, r["draft_id"], r["angle"], r["style"],
                r["title"], r["content"], r.get("tags"),
                r.get("suggested_format", "image_text"),
                image_prompts_structured, r.get("key_points"),
            )
            r["db_id"] = row_id
            drafts.append(r)

    LOG.info("Generated %d/%d drafts for slot=%s", len(drafts), len(combos), slot)
    return drafts


def run(candidate, slot, date_str=None):
    """同步入口"""
    return asyncio.run(generate_drafts(candidate, slot, date_str))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    test_candidate = {
        "repo": "test/repo",
        "description": "A test project",
        "stars": 1000,
    }
    drafts = run(test_candidate, "noon")
    print(json.dumps(drafts, ensure_ascii=False, indent=2))
