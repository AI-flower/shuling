# Day 0 速启动 · 今天 1 小时搞定准备工作

> 所有命令可以复制粘贴直接跑。按顺序，不要跳。遇到报错停下来问我。

---

## Step 1 · 解压物料包（30 秒）

```bash
cd ~/Downloads
tar xzf shuling-promotion.tar.gz
ls shuling-promotion/    # 确认 16 个文件在
```

---

## Step 2 · 复制 LICENSE 和 SECURITY.md 到项目（30 秒）

```bash
PROMO=~/Downloads/shuling-promotion
PROJ=~/Documents/10/shuling

cp "$PROMO/LICENSE"      "$PROJ/LICENSE"
cp "$PROMO/SECURITY.md"  "$PROJ/SECURITY.md"

ls -la "$PROJ/LICENSE" "$PROJ/SECURITY.md"   # 确认
```

---

## Step 3 · 同步 README + landing 的 v2.3.0 badge（2 分钟）

```bash
cd "$PROJ"

# 先备份当前脏工作区（以防万一）
git diff README.md landing/index.html > /tmp/shuling-dirty-before-badge.patch

# README 顶部 badge（3 处替换）
sed -i '' \
  -e 's|version-2\.2\.0-blue|version-2.3.0-blue|g' \
  -e 's|codename-Existing%20Creator%20Support-green|codename-Pure%20Image%20Pipeline-green|g' \
  -e 's|📦 \*\*v2\.2\.0\*\*|📦 **v2.3.0**|g' \
  README.md

# landing/index.html 硬编码当前版本（不改 "v2.2.0+" since 语义）
sed -i '' \
  -e 's|v2\.2\.0</span>|v2.3.0</span>|g' \
  -e 's|v2\.2\.0 · CURRENT|v2.3.0 · CURRENT|g' \
  -e 's|>Existing Creator Support<|>Pure Image Pipeline<|g' \
  -e 's|BRIEFING · AGENT INSTALL · v2\.2\.0|BRIEFING · AGENT INSTALL · v2.3.0|g' \
  landing/index.html

# 验证
echo '--- README 顶部 badge ---'
grep -E 'version-|codename-|📦' README.md | head -5

echo '--- landing v2.2.0 剩余（应只剩 v2.2.0+ since 语义）---'
grep -c 'v2\.2\.0[^+]' landing/index.html

echo '--- landing v2.3.0 出现次数（应 ≥ 5）---'
grep -c 'v2\.3\.0' landing/index.html
```

> ⚠️ 看一下 `git diff README.md landing/index.html` 确认只改了版本号，没破坏别的。

---

## Step 4 · 把推广物料包也放进项目（1 分钟，可选但推荐）

```bash
mkdir -p "$PROJ/docs/promotion"
cp -r "$PROMO"/*.md "$PROMO/patches" "$PROJ/docs/promotion/"
cp "$PROMO/LICENSE" "$PROJ/docs/promotion/LICENSE.md"   # 避免和项目根 LICENSE 混

ls "$PROJ/docs/promotion/"
```

> 这一步是"把推广当工程做"——所有物料进 git 可查、可协作。

---

## Step 5 · Commit + Tag（1 分钟）

```bash
cd "$PROJ"
git status   # 看一下要提交什么

# 分两次 commit 语义更清楚
git add LICENSE SECURITY.md
git commit -m "chore: add LICENSE (MIT) and SECURITY.md"

git add README.md landing/index.html
git commit -m "docs(v2.3.0): sync README + landing badges to Pure Image Pipeline"

git add docs/promotion/
git commit -m "docs: add v2.3.0 promotion materials package"

# tag v2.3.0（如果还没 tag）
git tag -l | grep v2.3.0 || git tag -a v2.3.0 -m "Pure Image Pipeline"
```

---

## Step 6 · Push 到 GitHub（30 秒）

```bash
git push origin main --tags
```

---

## Step 7 · 创建 GitHub Release v2.3.0（5 分钟）

**方式 A · 用 gh CLI（推荐）**
```bash
cd "$PROJ"
gh release create v2.3.0 \
  --title "v2.3.0 — Pure Image Pipeline" \
  --notes-file "$PROMO/github-release-v2.3.0.md"
```

**方式 B · 用浏览器**
1. 打开 https://github.com/AI-flower/shuling/releases/new
2. Choose a tag → 选 `v2.3.0`
3. Release title → `v2.3.0 — Pure Image Pipeline`
4. Describe this release → 粘贴 `$PROMO/github-release-v2.3.0.md` 全文
5. ✅ Set as the latest release
6. Publish

---

## Step 8 · 验证线上状态（1 分钟）

```bash
# LICENSE 能下载（不能 404）
curl -s -o /dev/null -w "%{http_code}\n" https://raw.githubusercontent.com/AI-flower/shuling/main/LICENSE

# README 显示 v2.3.0
curl -s https://raw.githubusercontent.com/AI-flower/shuling/main/README.md | grep -E 'version-|codename-|📦' | head -3

# Release 可访问
open https://github.com/AI-flower/shuling/releases/tag/v2.3.0
```

---

## ✅ Day 0 完成标志

- [ ] 线上 LICENSE 可下载（curl 返回 200）
- [ ] 线上 README 顶部 badge 显示 v2.3.0
- [ ] GitHub Release v2.3.0 已发布
- [ ] 工作目录干净（`git status` 全绿）

**满足以上 4 条**，你就完成了投递前的全部硬阻断。

---

## 🚀 下一步：Day 1

按 `RUNBOOK.md` 的 Day 1-2 执行：
- 发第一篇博客到少数派/掘金（`blog-1-skill-as-brain.md`）
- （可选）录 demo GIF

**不要今天就冲 awesome 列表**——stars 还不够（当前 2 个），等 Day 3 社群发完再冲。

---

## 🆘 如果卡住

- **badge sed 没替换**：可能当前脏工作区冲突，手工打开 README.md 第 5-6 行和 12 行，用 VS Code 查找替换
- **git push 被拒**：`git pull --rebase origin main` 再 push
- **gh release 报错**：先 `gh auth status` 确认登录
- **landing/index.html 结构乱了**：`git checkout landing/index.html` 回滚，按 `patches/01-version-sync.patch` 的详细说明手工改

任何问题直接问我，我通过 SSH 帮你诊断。
