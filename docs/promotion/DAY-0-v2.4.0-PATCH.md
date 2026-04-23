# Day 0 · v2.4.0 补丁 — 线上同步到 v2.4 + 发 Release

> 这是为"让线上仓库达到投稿就绪状态"的 4 步。完成后即可投 awesome 列表 / anthropics/skills。
> 不含任何"发内容到第三方平台"的动作——按用户调整后的方案。

---

## Step A · commit 当前 docs/promotion/ 未提交的物料

Mac 项目 `~/Documents/10/shuling/docs/promotion/` 里已有但未 commit 的文件：
- 重新组织后的 `README.md`（物料包索引更新）
- `DAY-0-v2.4.0-PATCH.md`（本文件）
- `RUNBOOK.md`（重写为纯采纳版）
- `github-release-v2.4.0.md`
- `archived-content-campaign/` 整个目录（归档的博客/社群物料）
- 其他由 scp 进去的文件

```bash
cd ~/Documents/10/shuling
git add docs/promotion/
git status   # 检查一下要 add 的内容
git commit -m "docs(promotion): narrow to third-party adoption strategy, archive content-distribution assets

Promotion strategy adjusted: only pursue acceptance into third-party
registries (awesome lists, anthropics/skills). All self-publishing
assets (blogs, HN posts, social posts, v2.4 pitch, anti-faq) archived
under docs/promotion/archived-content-campaign/ for future re-activation.

Active assets focus on the adoption pipeline:
- awesome-prs-ready-to-submit.md (field research + per-list channels)
- anthropics-skills-pr.md (official marketplace PR body)
- awesome-listings.md (10 one-line variants)
- architecture-diagram.md + demo.tape (PR README assets)
- LICENSE / SECURITY.md / github-release-v2.4.0.md (submission prereqs)
- RUNBOOK.md / DAY-0-*.md (execution timeline)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin main
```

---

## Step B · 同步 README + landing badge 到 v2.4.0

```bash
cd ~/Documents/10/shuling

sed -i '' \
  -e 's|version-2\.3\.0-blue|version-2.4.0-blue|g' \
  -e 's|codename-Pure%20Image%20Pipeline-green|codename-Agent-Friendly%20Upgrade%20Infrastructure-green|g' \
  -e 's|📦 \*\*v2\.3\.0\*\*|📦 **v2.4.0**|g' \
  README.md

sed -i '' \
  -e 's|v2\.3\.0</span>|v2.4.0</span>|g' \
  -e 's|v2\.3\.0 · CURRENT|v2.4.0 · CURRENT|g' \
  -e 's|>Pure Image Pipeline<|>Agent-Friendly Upgrade Infrastructure<|g' \
  -e 's|BRIEFING · AGENT INSTALL · v2\.3\.0|BRIEFING · AGENT INSTALL · v2.4.0|g' \
  landing/index.html

# 验证
grep -E 'version-|codename-|📦 ' README.md | head -3
grep -c 'v2\.4\.0' landing/index.html   # 应 ≥ 5

# commit + push
git add README.md landing/index.html
git commit -m "docs(v2.4.0): sync README + landing badges to Agent-Friendly Upgrade Infrastructure"
git push origin main
```

---

## Step C · 创建 GitHub Release v2.4.0（浏览器）

1. 打开 https://github.com/AI-flower/shuling/releases/new
2. Choose a tag → 选 `v2.4.0`（已在远程，Mac 上 `git tag -l` 可见）
3. Release title → `v2.4.0 — Agent-Friendly Upgrade Infrastructure`
4. Description → 复制 `docs/promotion/github-release-v2.4.0.md` 全文
   - ⚠️ 顶部的 HTML 注释块（`<!-- ... -->`）请手工删掉，那是给你看的 meta 信息
5. ✅ Set as the latest release
6. **Publish**

---

## Step D · 验证线上

```bash
echo "LICENSE:       $(curl -s -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/AI-flower/shuling/main/LICENSE)"
echo "SECURITY.md:   $(curl -s -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/AI-flower/shuling/main/SECURITY.md)"
echo "README badge:  $(curl -s https://raw.githubusercontent.com/AI-flower/shuling/main/README.md | grep -o 'version-2\.4\.0' | head -1)"
echo "Release v2.4:  $(curl -s -o /dev/null -w '%{http_code}' https://api.github.com/repos/AI-flower/shuling/releases/tags/v2.4.0)"
```

应输出：
```
LICENSE:       200
SECURITY.md:   200
README badge:  version-2.4.0
Release v2.4:  200
```

**4 项全绿 = 投稿就绪**，立刻跳 `RUNBOOK.md` 的 Step 2 开始投 e2b-dev/awesome-ai-agents。

---

## 🔁 回滚（如果 Step A/B 发现问题）

```bash
cd ~/Documents/10/shuling
git log --oneline -5
git reset --hard <好的那个 commit hash>
git push --force-with-lease origin main    # ⚠️ 只有这是你的个人项目才能 force push
```

Release 出问题：GitHub 网页 → Releases → Edit → Delete。

---

## 下一步

**不要**发博客、不要发社群——按 `RUNBOOK.md` 走"投稿采纳"路径。
Day 3 投第一个 awesome 列表（e2b-dev/awesome-ai-agents）。
