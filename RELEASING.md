# 发版 SOP（RELEASING）

本项目发版流程标准化文档。每次发版**严格按本 SOP 执行**，保证版本档案完整、用户升级可依。

---

## 版本号决策树（BRAIN.HANDS.CALIB）

在开始 commit 前问自己三个问题：

### 1️⃣ 核心流程 / 算法 / 业务能力变化了吗？

- SKILL.md 的主流程章节重写？
- 自进化算法（偏好学习、confidence、探索）公式换代？
- AI 行为方式对用户可感知地改变？

→ **是** ⇒ **BRAIN +1**，重置 HANDS 和 CALIB 为 0
  - 例：v1.x → v2.0.0 "Skill-as-Brain"
  - 这是 **breaking change**，必须在 UPGRADE.md 写明迁移步骤

### 2️⃣ 脚本 / DB schema / MCP 接口变化了吗？

- `scripts/` 新增或重写文件？
- DB schema 有新表或字段？
- 新增/修改 MCP 工具接口？
- `install.sh` 结构变化？

→ **是** ⇒ **HANDS +1**，重置 CALIB 为 0
  - 例：v2.1.0（节流+限额）、v2.1.1（request_log 表）
  - 一般非 breaking，但可能需要 `bash scripts/db.sh init` 之类 migration

### 3️⃣ 只调了阈值 / 文档 / bugfix / 小重构？

- 节流参数调整？
- 关键词字典更新？
- README / CHANGELOG / UPGRADE 内容变化？
- 修了一个 bug，代码行为不变大方向？

→ **是** ⇒ **CALIB +1**
  - 例：v2.1.2 "Release Polish"
  - 非 breaking，用户可无感升级

### 🤔 同时命中多个？

取最高级。举例：
- 改了脚本（HANDS）+ 调了节流阈值（CALIB）⇒ **HANDS+1**
- 重写了 SKILL.md 核心节（BRAIN）+ 调参数（CALIB）⇒ **BRAIN+1**

---

## 发版前检查清单

- [ ] 功能已在本地跑通，至少做一次 **end-to-end 冒烟测试**
- [ ] `VERSION` 文件：`version`、`released`、`codename`、`brain/hands/calib` 各字段已更新
- [ ] `CHANGELOG.md`：新版本条目按模板写全（📦 用户可见 / ✋/🧠/🎛 分类 / ⬆️ 如何升级）
- [ ] `UPGRADE.md`：如果有 breaking 或新增环境变量 / DB 迁移，必须补一节
- [ ] `SKILL.md` frontmatter：`version` / `codename` / `last_updated` 三个字段已同步
- [ ] 如有 DB schema 变化：在 `migrations/vX.Y.Z.sh` 放幂等脚本
- [ ] 如有新环境变量：README 的环境变量表已更新
- [ ] `git status` 干净，只剩要 commit 的文件
- [ ] `bash -n scripts/*.sh` 全部语法通过

---

## 发版标准命令序列

```bash
# ─── 1. 最后一次 sanity check ───
cd /path/to/shuling
git status
bash -n scripts/xhs.sh scripts/db.sh
bash install.sh   # 确认跑得通

# ─── 2. 暂存并 commit（conventional commits + HEREDOC 消息）───
git add VERSION CHANGELOG.md UPGRADE.md SKILL.md scripts/ migrations/ README.md
# 禁止 git add -A —— 防止 .env / xhs.db / bak 文件污染

VERSION_NEW="2.1.2"
CODENAME="Release Polish"
git commit -m "$(cat <<EOF
feat(v${VERSION_NEW}): ${CODENAME} — <一句话描述>

<Why：动机>

Brain: <如有变化>
Hands: <如有变化>
Calib: <如有变化>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"

# ─── 3. 打 annotated tag ───
git tag -a "v${VERSION_NEW}" -m "$(cat <<EOF
薯灵 v${VERSION_NEW} — ${CODENAME}

<一段话总结本版本价值>

新增：
- ...

版本号含义: BRAIN.HANDS.CALIB
- BRAIN: <是否变，为什么>
- HANDS: <是否变，为什么>
- CALIB: <是否变，为什么>

升级: 见 UPGRADE.md
EOF
)"

# ─── 4. 推送（--follow-tags 会连带推送 annotated tag）───
git push origin main --follow-tags

# ─── 5. 创建 GitHub Release ───
gh release create "v${VERSION_NEW}" \
    --title "v${VERSION_NEW} — ${CODENAME}" \
    --notes-file <(git tag -l --format='%(contents)' "v${VERSION_NEW}")
```

---

## 如果忘了 `--follow-tags`

```bash
# tag 没推上去时补推：
git push origin v2.1.2
```

验证 tag 在远程：
```bash
git ls-remote --tags origin | grep v2.1.2
```

---

## GitHub Release 模板

Release 标题：`v<X.Y.Z> — <Codename>`
Release 正文（直接从 CHANGELOG 对应版本抄，简化后如下）：

```markdown
## 📦 用户可见改动
<从 CHANGELOG 该版本的 📦 节抄过来>

## ⬆️ 如何升级
<从 CHANGELOG 该版本的 ⬆️ 节抄过来>

## 📝 完整变更
详见 [CHANGELOG.md](https://github.com/AI-flower/shuling/blob/main/CHANGELOG.md#X-Y-Z---YYYY-MM-DD-Codename)

## 🔧 技术细节
<从 CHANGELOG 该版本的 🧠/✋/🎛 节抄过来>
```

---

## 回滚（如发版后发现严重问题）

```bash
# 1. 删本地和远程 tag
git tag -d v2.1.2
git push origin :refs/tags/v2.1.2

# 2. 删 GitHub Release（如已创建）
gh release delete v2.1.2

# 3. revert commit（不建议 reset --hard，保留历史）
git revert <commit-sha>
git push origin main
```

---

## 常见坑

| 坑 | 教训 |
|---|---|
| `git push origin main` 忘 `--follow-tags` | tag 还在本地，远程看不到。补推：`git push origin vX.Y.Z` |
| 直接 `git add -A` | 会带上 `.env` / `data/*.db` / `*.bak.*`。总是显式列文件 |
| CHANGELOG 只写"开发者视角" | 真实用户看不懂。必须有 📦 用户可见改动 节 |
| 没写 UPGRADE.md 就发 HANDS+1 | 用户升级时踩坑：表没建、env 没设 |
| 版本号跳级 | 比如从 2.1.1 直接跳到 2.2.0 而没有 2.1.x 收尾。不是错，但 CHANGELOG 要解释为什么 |
| Breaking change 没在 BRAIN 位升级 | 用户以为 CALIB/HANDS 可以无感升，结果崩了 |

---

## 自动化检查（未来工作）

- [ ] pre-tag hook：校验 CHANGELOG 有对应版本条目
- [ ] pre-tag hook：校验 VERSION 文件已更新
- [ ] CI：PR 合入 main 前检查 VERSION 是否要 bump
