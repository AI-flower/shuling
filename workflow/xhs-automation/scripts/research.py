"""XHS 自动化系统 - 晨间研究：GitHub trending + XHS 竞品分析"""
import json
import os
import sys
import urllib.request
import urllib.parse
import re
from datetime import date

sys.path.insert(0, os.path.dirname(__file__))
import db

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, "data")


def resolve_mcp_script(script_name):
    candidates = [
        os.environ.get(f"XHS_{script_name.upper().replace('.', '_')}"),
        os.path.expanduser(f"~/.agents/skills/xiaohongshu/scripts/{script_name}"),
        os.path.expanduser(f"~/.claude/skills/xiaohongshu/scripts/{script_name}"),
        os.path.expanduser(f"~/.codex/skills/xiaohongshu/scripts/{script_name}"),
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return path
    return os.path.expanduser(f"~/.agents/skills/xiaohongshu/scripts/{script_name}")


MCP_CALL = resolve_mcp_script("mcp-call.sh")

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


def fetch_github_trending(language="", since="daily"):
    """抓取 GitHub trending 页面，提取仓库信息"""
    url = f"https://github.com/trending/{language}?since={since}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "Accept": "text/html"
    })
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        html = resp.read().decode("utf-8")
    except Exception as e:
        print(f"GitHub trending 抓取失败: {e}", file=sys.stderr)
        return []

    repos = []
    seen_repos = set()
    # 匹配仓库链接和描述
    repo_pattern = re.compile(
        r'<h2 class="h3 lh-condensed">.*?<a href="(/[^"]+)"',
        re.DOTALL
    )
    star_pattern = re.compile(
        r'class="d-inline-block float-sm-right">\s*(\d[\d,]*)\s*stars today',
        re.DOTALL | re.IGNORECASE
    )
    desc_pattern = re.compile(
        r'<p class="col-9[^"]*">\s*(.*?)\s*</p>',
        re.DOTALL
    )

    repo_matches = repo_pattern.findall(html)
    # 备用正则：GitHub 页面结构可能变化
    if not repo_matches:
        repo_matches = re.findall(r'<a[^>]*href="(/[^/]+/[^/]+)"[^>]*class="[^"]*"[^>]*>\s*\n', html)
    if not repo_matches:
        # 用更宽松的模式
        article_pattern = re.compile(
            r'<article[^>]*>.*?<a href="(/[^/]+/[^/"]+)".*?</article>',
            re.DOTALL
        )
        repo_matches = article_pattern.findall(html)

    for repo_path in repo_matches[:25]:
        repo_path = repo_path.strip().strip("/")
        # 清理：移除 /stargazers 等后缀
        if "/stargazers" in repo_path or "/issues" in repo_path:
            repo_path = "/".join(repo_path.split("/")[:2])
        if "/" not in repo_path or repo_path.count("/") != 1:
            continue
        if repo_path in seen_repos:
            continue
        seen_repos.add(repo_path)
        repos.append({
            "repo": repo_path,
            "url": f"https://github.com/{repo_path}"
        })

    return repos


def fetch_github_api_search(query="AI", sort="stars", min_stars=500, limit=20):
    """使用 GitHub API 搜索高星 AI 项目（无需 token）"""
    # 搜索最近3个月活跃的项目
    from datetime import timedelta
    since = (date.today() - timedelta(days=90)).isoformat()
    q = f"{query} stars:>{min_stars} pushed:>{since}"
    url = f"https://api.github.com/search/repositories?q={urllib.parse.quote(q)}&sort={sort}&order=desc&per_page={limit}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "XHS-Automation/1.0",
        "Accept": "application/vnd.github.v3+json"
    })
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        data = json.loads(resp.read())
        return [{
            "repo": item["full_name"],
            "url": item["html_url"],
            "description": item.get("description", ""),
            "stars": item["stargazers_count"],
            "language": item.get("language", ""),
            "topics": item.get("topics", [])
        } for item in data.get("items", [])[:limit]]
    except Exception as e:
        print(f"GitHub API 搜索失败: {e}", file=sys.stderr)
        return []


def clean_text(text):
    text = text or ""
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"`{1,3}[^`]+`{1,3}", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def enrich_repo_info(repo_name):
    """通过 GitHub API 获取仓库详情"""
    url = f"https://api.github.com/repos/{repo_name}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "XHS-Automation/1.0",
        "Accept": "application/vnd.github.v3+json"
    })
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        data = json.loads(resp.read())
        return {
            "repo": repo_name,
            "url": data["html_url"],
            "description": data.get("description", ""),
            "stars": data["stargazers_count"],
            "forks": data.get("forks_count", 0),
            "language": data.get("language", ""),
            "topics": data.get("topics", []),
            "created_at": data.get("created_at", ""),
            "updated_at": data.get("updated_at", "")
        }
    except Exception as e:
        print(f"  获取 {repo_name} 详情失败: {e}", file=sys.stderr)
        return {"repo": repo_name, "stars": 0}


def fetch_readme(repo_name):
    """拉取 README 原始内容（截取前 3000 字符，够用就好）"""
    for branch in ["main", "master"]:
        url = f"https://raw.githubusercontent.com/{repo_name}/{branch}/README.md"
        req = urllib.request.Request(url, headers={"User-Agent": "XHS-Automation/1.0"})
        try:
            resp = urllib.request.urlopen(req, timeout=15)
            text = resp.read().decode("utf-8", errors="ignore")
            # 去掉纯图片行、badge 行
            lines = []
            for line in text.split("\n"):
                stripped = line.strip()
                if stripped.startswith("[![") or stripped.startswith("!["):
                    continue
                if stripped.startswith("<img") or stripped.startswith("<p align"):
                    continue
                lines.append(line)
            cleaned = "\n".join(lines).strip()
            return cleaned[:3000]
        except Exception:
            continue
    return ""


def score_xhs_fit(repo_info):
    """根据“小红书可写性”给候选项目打附加分。"""
    repo = (repo_info.get("repo", "") or "").lower()
    desc = clean_text(repo_info.get("description", "")).lower()
    readme = clean_text(repo_info.get("readme", "")).lower()
    topics = " ".join(t.lower() for t in repo_info.get("topics", []))
    text = " ".join([repo, desc, readme[:1200], topics])
    focus_text = " ".join([repo, desc, topics])

    score = 0

    # 当前主赛道：skills / openclaw / 自动化 / 小白可理解的工具
    strong_positive = [
        "openclaw", "skill", "skills", "claude code", "agent", "workflow",
        "memory", "browser", "record", "document", "pdf", "docx", "xlsx",
        "media", "speech", "voice", "automation", "review", "qa"
    ]
    for kw in strong_positive:
        if kw in text:
            score += 4

    # 容易写成收藏帖的场景词
    scenario_positive = [
        "productivity", "developer-tools", "developer tools", "testing",
        "design", "debug", "video", "audio", "transcript", "markdown",
        "office", "document", "report", "browser"
    ]
    for kw in scenario_positive:
        if kw in text:
            score += 2

    # 容易写成“仓库介绍”而不是“收藏帖”的方向
    negative = [
        "framework", "sdk", "dataset", "benchmark", "training", "research paper",
        "course", "curriculum", "tutorial collection", "awesome list", "awesome-",
        "archive", "ebook", "paper", "resource list", "curated list"
    ]
    for kw in negative:
        if kw in text:
            score -= 4

    # 当前账号阶段不优先的漂移赛道
    drift_negative = [
        "database", "sql client", "postgresql", "mysql", "oracle", "gis",
        "rocket", "minecraft", "tax", "trading"
    ]
    for kw in drift_negative:
        if kw in text:
            score -= 5

    # 有明确“一个人能用 / 直接能用 / 帮你省一步”的口吻更适合小红书
    if any(kw in text for kw in ["save time", "faster", "automate", "local-first", "repeatable", "step by step", "best way to start"]):
        score += 6

    # 强制给当前主线更高权重
    if "openclaw" in text:
        score += 18
    if "skill" in repo or "skills" in repo:
        score += 14
    elif "skill" in text or "skills" in text:
        score += 10

    # 当前阶段不希望再回到“平台介绍/万能平台”选题
    if any(kw in text for kw in ["platform", "copilot", "guide", "assistant", "tutor", "studio"]):
        score -= 6

    # 如果既不是 openclaw 也不是 skill 主线，当前阶段强制压低
    core_focus_tokens = [
        "openclaw", "skill", "skills", "claude code", "claude", "memory",
        "browser", "record", "pdf", "docx", "xlsx", "review", "qa", "voice"
    ]
    if not any(kw in focus_text for kw in core_focus_tokens):
        score -= 70

    return score


def score_titleability(repo_info):
    """判断这个项目是否容易写成具体标题，而不是空泛说明书。"""
    repo = repo_info.get("repo", "")
    name = repo.split("/")[-1].lower()
    desc = clean_text(repo_info.get("description", "")).lower()
    topics = " ".join(t.lower() for t in repo_info.get("topics", []))
    text = " ".join([name, desc, topics])

    score = 0

    if any(kw in text for kw in ["skill", "memory", "browser", "record", "review", "qa", "pdf", "docx", "xlsx", "voice", "audio", "video"]):
        score += 10

    # 当前更偏好“单功能 / 单动作 / 单人群”可写法
    if any(kw in text for kw in ["memory", "record", "pdf", "docx", "xlsx", "browser", "review", "qa", "voice"]):
        score += 6

    if any(kw in text for kw in ["platform", "framework", "library", "sdk", "engine", "kit"]) and "skill" not in text:
        score -= 8

    if len(name) > 18 and "-" not in name and "_" not in name:
        score -= 2

    if len(name) > 24:
        score -= 4

    if "awesome" in name and "skill" not in name:
        score -= 6

    # 不在当前 focus 主线里的项目，即使 star 高也要压一手
    if not any(kw in text for kw in ["openclaw", "skill", "skills", "memory", "browser", "record", "pdf", "docx", "xlsx", "review", "qa"]):
        score -= 12

    return score


def is_mainline_candidate(repo_info):
    """判断候选是否属于当前账号主线。"""
    repo = (repo_info.get("repo", "") or "").lower()
    desc = clean_text(repo_info.get("description", "")).lower()
    readme = clean_text(repo_info.get("readme", "")).lower()
    topics_list = [t.lower() for t in repo_info.get("topics", [])]
    topics = " ".join(topics_list)
    text = " ".join([repo, desc, topics, readme[:800]])

    hard_positive = [
        "memory", "browser", "record", "pdf", "docx", "xlsx",
        "review", "qa", "voice", "audio", "video", "skill", "skills"
    ]
    hard_negative = [
        "database", "sql client", "postgresql", "mysql", "oracle",
        "dataset", "benchmark", "tutorial collection", "course",
        "ebook", "resource list", "curated list", "minecraft", "rocket", "tax"
    ]
    platform_like = [
        "context database", "database designed specifically", "filesystem paradigm",
        "unifies the management", "platform for", "builder for ai coding",
        "studio", "copilot", "assistant platform", "knowledge graph",
        "managed agents platform", "agents as teammates", "full agent lifecycle",
        "workspace-level isolation", "one dashboard for", "cloud runtimes",
        "multi-workspace", "self-hosted infrastructure", "teammates"
    ]

    positive_hit = any(kw in text for kw in hard_positive)
    negative_hit = any(kw in text for kw in hard_negative)
    platform_hit = any(kw in text for kw in platform_like)

    # 只保留“能直接写成具体 skill / 顺序 / 避坑”的题。
    repo_name = repo.split("/")[-1]
    explicit_skill_hit = (
        "skill" in repo_name
        or "skills" in repo_name
        or any("skill" in t for t in topics_list)
    )
    direct_function_hit = any(kw in text for kw in [
        "memory", "browser", "record", "pdf", "docx", "xlsx",
        "review", "qa", "voice", "audio", "video"
    ])
    openclaw_focus_hit = "openclaw" in text and (explicit_skill_hit or direct_function_hit)

    return positive_hit and (explicit_skill_hit or direct_function_hit or openclaw_focus_hit) and not negative_hit and not platform_hit


def check_xhs_competition(keyword):
    """调用 XHS MCP search_feeds 检查小红书上的竞品情况"""
    import subprocess
    try:
        result = subprocess.run(
            [MCP_CALL, "search_feeds", json.dumps({"keyword": keyword}, ensure_ascii=False)],
            capture_output=True, text=True, timeout=30,
            cwd=os.path.expanduser("~/.xiaohongshu")
        )
        if result.returncode != 0:
            print(f"  XHS 搜索 '{keyword}' 失败: {result.stderr}", file=sys.stderr)
            return {"count": 0, "top_likes": 0, "has_viral": False}

        output = result.stdout
        # 解析 MCP 返回的搜索结果
        try:
            data = json.loads(output)
            feeds = data if isinstance(data, list) else data.get("items", data.get("feeds", []))
        except json.JSONDecodeError:
            # 可能是文本格式，简单计数
            feeds = []
            like_matches = re.findall(r'(\d+)\s*(?:赞|likes?|❤)', output, re.IGNORECASE)
            if like_matches:
                max_likes = max(int(x) for x in like_matches)
                return {
                    "count": len(like_matches),
                    "top_likes": max_likes,
                    "has_viral": max_likes > 1000
                }

        count = len(feeds) if isinstance(feeds, list) else 0
        top_likes = 0
        if isinstance(feeds, list):
            for f in feeds:
                likes = f.get("likes", f.get("liked_count", 0))
                if isinstance(likes, (int, float)) and likes > top_likes:
                    top_likes = int(likes)

        return {
            "count": count,
            "top_likes": top_likes,
            "has_viral": top_likes > 1000
        }
    except subprocess.TimeoutExpired:
        print(f"  XHS 搜索 '{keyword}' 超时", file=sys.stderr)
        return {"count": 0, "top_likes": 0, "has_viral": False}
    except Exception as e:
        print(f"  XHS 搜索异常: {e}", file=sys.stderr)
        return {"count": 0, "top_likes": 0, "has_viral": False}


def score_candidate(repo_info, xhs_info):
    """给候选项目打分：高星 + 低竞争 = 高分"""
    score = 0
    stars = repo_info.get("stars", 0)

    # 星数加分
    if stars > 10000:
        score += 40
    elif stars > 5000:
        score += 30
    elif stars > 1000:
        score += 20
    elif stars > 500:
        score += 10

    # AI 相关加分
    desc = (repo_info.get("description", "") or "").lower()
    topics = [t.lower() for t in repo_info.get("topics", [])]
    ai_keywords = ["ai", "llm", "gpt", "agent", "machine-learning", "deep-learning",
                    "neural", "transformer", "chatbot", "nlp", "computer-vision"]
    for kw in ai_keywords:
        if kw in desc or kw in " ".join(topics):
            score += 10
            break

    # XHS 竞争度：低竞争加分
    xhs_count = xhs_info.get("count", 0)
    if xhs_count == 0:
        score += 30  # 蓝海话题
    elif xhs_count < 3:
        score += 20
    elif xhs_count < 10:
        score += 10

    # 有爆款说明话题热度高，但竞争也大，适中加分
    if xhs_info.get("has_viral"):
        score += 5

    score += score_xhs_fit(repo_info)
    score += score_titleability(repo_info)

    return score


def run_research(date_str=None):
    """执行完整研究流程"""
    if date_str is None:
        date_str = date.today().isoformat()

    db.init_db()
    knowledge = load_knowledge_weights()
    if knowledge:
        print(f"\U0001F4DA 知识库已加载（phase={knowledge.get('phase', '?')}, post_count={knowledge.get('post_count', '?')}）")
    print(f"=== XHS 晨间研究 {date_str} ===\n")

    # 1. 获取 GitHub trending
    print("📡 抓取 GitHub trending...")
    trending = fetch_github_trending()
    print(f"  找到 {len(trending)} 个 trending 项目")

    # 2. 搜索高星 AI 项目（补充 trending 结果）
    print("🔍 搜索 GitHub AI 项目...")
    ai_repos = fetch_github_api_search("OpenClaw skill", min_stars=200, limit=10)
    ai_repos += fetch_github_api_search("Claude Code skill", min_stars=200, limit=10)
    ai_repos += fetch_github_api_search("agent workflow tool", min_stars=500, limit=8)
    ai_repos += fetch_github_api_search("AI tool", min_stars=1000, limit=6)
    print(f"  找到 {len(ai_repos)} 个 AI 项目")

    # 3. 合并去重
    seen = set()
    all_repos = []
    for r in trending + ai_repos:
        repo = r["repo"]
        if repo not in seen and not db.is_topic_used(repo):
            seen.add(repo)
            all_repos.append(r)
    print(f"  去重后 {len(all_repos)} 个候选\n")

    # 4. 获取详情 + XHS 竞品分析
    candidates = []
    for i, r in enumerate(all_repos[:15]):  # 最多分析 15 个
        repo = r["repo"]
        print(f"[{i+1}/{min(len(all_repos), 15)}] 分析 {repo}...")

        # 获取 GitHub 详情
        if "stars" not in r or r.get("stars", 0) == 0:
            info = enrich_repo_info(repo)
        else:
            info = r

        # 过滤非 AI 相关（stars 太低也跳过）
        if info.get("stars", 0) < 100:
            print(f"  跳过（星数太低: {info.get('stars', 0)}）")
            continue

        # 抓取 README
        print(f"  📄 拉取 README...")
        readme = fetch_readme(repo)
        info["readme"] = readme
        if readme:
            print(f"    README {len(readme)} 字")
        else:
            print(f"    README 获取失败，跳过不影响")

        # 提取关键词用于 XHS 搜索
        name = repo.split("/")[-1]
        search_keyword = name.replace("-", " ").replace("_", " ")
        print(f"  XHS 搜索: '{search_keyword}'")
        xhs = check_xhs_competition(search_keyword)

        # 打分
        score = score_candidate(info, xhs)
        candidate = {
            **info,
            "xhs_competition": xhs,
            "score": score
        }
        candidates.append(candidate)
        print(f"  ⭐ {info.get('stars', '?')} | XHS竞品: {xhs['count']} | 得分: {score}")

        # 写入 topics 表
        db.add_topic(
            date_str=date_str,
            github_repo=repo,
            topic_keyword=search_keyword,
            xhs_competition=xhs.get("count", 0),
            selected=False,
            reason=f"score={score}, stars={info.get('stars', 0)}"
        )

    # 5. 按分数排序，优先选主线候选
    candidates.sort(key=lambda x: (x["score"], x.get("stars", 0)), reverse=True)
    mainline_candidates = [c for c in candidates if is_mainline_candidate(c)]
    fallback_candidates = [c for c in candidates if not is_mainline_candidate(c)]

    print(f"  主线候选 {len(mainline_candidates)} 个，非主线候选 {len(fallback_candidates)} 个")

    if len(mainline_candidates) >= 2:
        selected = mainline_candidates[:2]
    elif len(mainline_candidates) == 1:
        selected = mainline_candidates + fallback_candidates[:1]
    else:
        selected = candidates[:2] if len(candidates) >= 2 else candidates
    for s in selected:
        db.add_topic(
            date_str=date_str,
            github_repo=s["repo"],
            topic_keyword=s["repo"].split("/")[-1],
            xhs_competition=s.get("xhs_competition", {}).get("count", 0),
            selected=True,
            reason=f"TOP PICK: score={s['score']}"
        )

    # 6. 输出 candidates JSON
    output_file = os.path.join(DATA_DIR, f"candidates-{date_str}.json")
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump({
            "date": date_str,
            "total_analyzed": len(candidates),
            "selected": selected,
            "all_candidates": candidates
        }, f, ensure_ascii=False, indent=2)

    print(f"\n✅ 研究完成！")
    print(f"  分析了 {len(candidates)} 个项目")
    print(f"  选中 {len(selected)} 个:")
    for i, s in enumerate(selected):
        print(f"    {i+1}. {s['repo']} (⭐{s.get('stars', '?')}, 得分{s['score']})")
    print(f"  输出: {output_file}")

    return selected


if __name__ == "__main__":
    date_str = sys.argv[1] if len(sys.argv) > 1 else None
    run_research(date_str)
