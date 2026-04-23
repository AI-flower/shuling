# Day 0 速启动 · 投稿前置就绪

> 聚焦一件事：让线上仓库达到"可被 awesome 列表 / anthropics/skills 采纳"的最低门槛。
> 耗时：1 小时。

---

## 目标（投稿前硬阻断）

- ☐ 线上 LICENSE 存在
- ☐ 线上 SECURITY.md 存在
- ☐ README badge 显示当前版本（v2.4.0）
- ☐ GitHub Release v2.4.0 已发布
- ☐ demo.gif 在 README 顶部或 docs/images/

---

## ✅ 已完成部分（v2.3 Day 0 当时做的）

```bash
# 这些已上线，只记录不重做
curl -s -o /dev/null -w "LICENSE HTTP %{http_code}\n" https://raw.githubusercontent.com/AI-flower/shuling/main/LICENSE
# 应返回 200
curl -s -o /dev/null -w "SECURITY HTTP %{http_code}\n" https://raw.githubusercontent.com/AI-flower/shuling/main/SECURITY.md
# 应返回 200
```

---

## 🔴 还需做的（v2.4 追加）

详见 **`DAY-0-v2.4.0-PATCH.md`** —— 里面有 4 步复制粘贴命令：
- Step A · commit docs/promotion/ 未提交的物料
- Step B · sed 改 README + landing badge 到 v2.4.0
- Step C · 浏览器创建 Release v2.4.0（用 `github-release-v2.4.0.md`）
- Step D · 验证线上

**完成 A-D 即投稿就绪**。

---

## 🎨 可选增强（但强烈推荐）

### 录 demo GIF（10 分钟）
```bash
brew install vhs
cd ~/Documents/10/shuling/docs/promotion
vhs demo.tape          # 产生 demo.gif（~75 秒）
mkdir -p ../images
mv demo.gif ../images/demo.gif
cd ..
git add images/demo.gif
git commit -m "docs: add demo GIF for skill marketplace submissions"
git push
```

然后在 README 顶部加：
```markdown
![薯灵 demo](docs/images/demo.gif)
```

### 导出 3 张架构图（5 分钟）
- 打开 `docs/promotion/architecture-diagram.md`
- 每块 mermaid 粘贴到 https://mermaid.live（主题选 dark）
- Export SVG → 保存到 `docs/images/architecture-{overview,routing,evolution}.svg`
- README 的 "Architecture" 段引用

---

## ✅ Day 0 完成标志

全部满足：
- `curl https://raw.githubusercontent.com/AI-flower/shuling/main/LICENSE` 返回 200
- `curl https://raw.githubusercontent.com/AI-flower/shuling/main/README.md | grep version-` 显示 2.4.0
- 打开 https://github.com/AI-flower/shuling/releases/tag/v2.4.0 可见
- README 有 demo GIF 或架构图之一（提高 PR 通过率）

---

## 下一步

按 `RUNBOOK.md` 的 **Step 2（Day 3 投 e2b-dev/awesome-ai-agents）** 执行。

**不要**：发博客 / 发推 / 发社群贴（按用户本次调整已移除这条路径）。
