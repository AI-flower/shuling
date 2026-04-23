---
title: "给 AI Skill 设计的语义化版本号"
subtitle: "为什么 SemVer 不够用，BRAIN.HANDS.CALIB 怎么更合身"
date: 2026-04-23
tags: [AI Skill, Versioning, SemVer, Claude, 工程实践, 薯灵]
reading_time: 12 分钟
series: 薯灵推广 · 第二篇
---

> 金句先放这里：**BRAIN 改了，用户的 AI 就"变性格"了——这是 breaking，不是新功能。**

上一篇聊完 "Skill-as-Brain" 架构之后，很多朋友私下问我同一件事：

> "你这个 skill 版本号 `v2.3.0` 是怎么算出来的？我写自己的 skill 时，改了 prompt 到底算 Patch 还是 Minor？"

这个问题我自己也纠结过很久。薯灵（ShuLing，GitHub: [AI-flower/shuling](https://github.com/AI-flower/shuling)，MIT 开源）从 v2.0.0 一路迭代到 v2.3.0，我发现传统 SemVer 在 AI skill 身上**持续错位**，最后干脆换了一套：**BRAIN.HANDS.CALIB**。

这一篇我会把设计动机、完整语义、以及一次真实版本号决策（v2.2.0 → v2.3.0）都摊开讲，让想做 skill 的朋友可以直接抄。

---

## 1. 痛点：SemVer 在 skill 上会错位

SemVer（Major.Minor.Patch）是软件工程的老熟人。它的隐含假设是：

> "软件是一个工具，有 API，有行为。breaking change 就是改了 API 签名，非 breaking 就是加了新接口或者修了 bug。"

这个模型在库、框架、CLI 工具上基本够用。但我在薯灵这种"有人格、有决策流程、有持续学习"的 skill 上，遇到至少三个决不了的场景：

**场景一：我改了 prompt，到底算 Minor 还是 Patch？**

SemVer 会说：prompt 是"文本内容"，不破坏任何 API，也没加新功能——那是 Patch。

但问题在于，prompt 一字之差，AI 的输出风格可能完全变掉。用户上周还觉得"薯灵会说人话"，这周突然变得"特别商务范儿"，对使用者来说这是**角色性格变了**，明显不是 bugfix 量级的事。

**场景二：换了 DB schema 但业务没变，算 Major 吗？**

薯灵 v2.1.0 引入 `request_log` 表做 MCP 调用追踪。这个改动：
- 对用户业务流程零感知
- 但要跑 migration，否则新版本启动就 crash

SemVer 说这不 breaking（API 没变），但用户实际操作上**必须执行迁移**——这个错位会让用户踩坑。

**场景三：AI 的决策方式变了，老用户要重新适应**

薯灵 v2.0 → v2.1 加了 "Anti-Ban Shield"，引入节流 + 限额 + 风控决策。站在 API 视角，所有 MCP 接口签名都没变，SemVer 判定 Minor。

但站在用户视角，**"以前我让它连发 10 条，它就发 10 条"** 和 **"现在它会自己判断、拒绝、延后"**，完全是两种角色。这是 breaking——但 SemVer 看不到。

---

核心问题是哲学层面的：

> **SemVer 假设"软件是工具"，skill 是"角色"。角色升级不该用工具的版本号。**

工具的 breaking 是"接口变了，调用方代码要改"。
角色的 breaking 是"性格变了，使用者的心智模型要重建"。

这俩完全不一样。

## 2. BRAIN.HANDS.CALIB 的三段设计

于是薯灵 v2.3.0 把版本号换成了三段：

```
v<BRAIN>.<HANDS>.<CALIB>
     ↑       ↑        ↑
   脑子变    手变     参数变
```

下面是完整定义 + 薯灵真实案例 + 边界警戒。

### BRAIN：核心决策 / 自进化算法 / 业务能力

**定义**：SKILL.md 核心流程重构、自进化算法换代、业务能力跃迁。**breaking**，用户需要显式迁移或重新理解角色。

**实例**：v2.0.0 → v2.1.0 "Anti-Ban Shield"。表面看只是加了节流和限额（像 HANDS+1），但实际上它引入了**风控决策**这个新的业务能力——AI 从"服从型执行器"变成"有风险意识的 agent"。这是性格变化，BRAIN+1。

**边界警戒**：不要因为"文件改得多"就动 BRAIN。算法文件大改、但用户感知的决策流程没变（比如只是换了实现语言），那还是 HANDS。**判定 BRAIN 看的是"输出/行为特征是否变"，不是代码行数。**

### HANDS：执行层 / 数据层 / 接口层

**定义**：`scripts/` 新增或重写、DB schema 迁移、MCP 接口替换、子 skill 目录变化、依赖要求变化。**一般向后兼容**，可能需要运行 migrations。

**实例**：v2.1.0 → v2.1.1 "Request Log"。看起来像 bugfix（CALIB+1 起步），但实际加了 `request_log` 表 + `scripts/log_request.py` + migration——有新表就得 HANDS+1，CALIB 不背 schema 变更的锅。

**边界警戒**：不要把"改 scripts/ 但没加新能力"（比如只修 bug）算 HANDS。判定标准是：**是否引入新的能力单元（新脚本、新表、新接口）**。纯修 scripts/ 里一个 if 分支的 bug，那还是 CALIB。

### CALIB：参数 / 阈值 / prompt 微调 / 文档

**定义**：阈值/关键词/节流参数调整、bugfix、prompt 微调、CHANGELOG/文档更新。**无 breaking**，用户无感升级。

**实例**：v2.1.1 → v2.1.2 "Release Polish"。加了 CHANGELOG / UPGRADE / RELEASING 三件套 + migrations 骨架。纯流程规范化，没加任何业务能力，CALIB+1 刚好。

**边界警戒**：**"prompt 微调"和"prompt 模板重写"是两件事**。前者是 CALIB（改措辞、改温度、调排序），后者是 HANDS（加新模板文件、改模板引擎逻辑）——v2.3.0 就是后者，稍后会细讲。

---

总结成一张对照表：

| 维度       | BRAIN+1           | HANDS+1             | CALIB+1           |
| ---------- | ----------------- | ------------------- | ----------------- |
| 改动面     | SKILL.md 核心流程 | scripts/ DB MCP 接口 | 参数/prompt/文档   |
| 用户感知   | 角色性格变了      | 可能要跑 migration   | 无感              |
| 破坏性     | breaking          | 一般兼容             | 零                 |
| 典型触发   | 算法换代、能力跃迁 | 新表、新脚本、重写   | bugfix、文本微调   |
| 迁移动作   | 显式升级 + 重训心智 | 跑 migrations       | 直接 pull          |

## 3. 真实决策复盘：v2.2.0 → v2.3.0 "Pure Image Pipeline"

这是全文最重要的一节。光给定义容易，难的是**边界案例怎么判**。下面是薯灵 v2.3.0 的真实版本号决策过程。

### 改动清单

v2.3.0 代号 "Pure Image Pipeline"，改动如下：

```bash
# 删除
- scripts/screenshot.cjs            # 删除 HTML 截图降级路径
- templates/post.html               # 删除 HTML 模板
- skills/xhs-content-generator/     # 删除整个子 skill 目录

# 新增
+ prompts/image_prompt.txt          # 77 行新 prompt 模板
+ prompts/image_prompt_short.txt    # 6 行兜底短模板
+ migrations/v2.3.0.sh              # 幂等迁移脚本

# 重写
~ scripts/image.py                  # ~240 行 diff，加入 render_prompt /
                                    # _gen_gemini_native / _load_reference_image /
                                    # --short flag
~ scripts/image.py CLI              # 新增 --topic / --outline-file / 多个 --reference

# 配置变更
~ Gemini API Key 从 optional → required

# 文档变更
~ SKILL.md §0 第 2 步：图片 API optional → 必需
~ SKILL.md §2.3 图片生成流程重写
~ SKILL.md §8 异常处理：HTML 截图降级 → 硬停
~ landing/index.html 版本号动态化
~ CHANGELOG / UPGRADE / RELEASING 同步
```

看起来挺大——删了一个完整的降级路径、重写了核心脚本、加了新 prompts/ 目录、砍了一个子 skill、还让 Gemini Key 从可选变必需。

第一反应可能会说：这都"硬停"了，肯定 BRAIN+1 啊。

但我们按三段决策流程走一遍。

### Step 1：算法层动了吗？

检查项：
- `preference_learning`（偏好学习公式）：**没变**
- `confidence`（置信度计算）：**没变**
- `drafting`（草稿生成公式）：**没变**
- §0a 业务路由逻辑：**一字没改**

**结论：不是 BRAIN。**

核心业务能力（薯灵的"脑子"）完全没动。它该怎么理解用户意图、怎么路由任务、怎么从历史数据学习——这些决策方式一样不变。

### Step 2：只是参数或 bug 吗？

检查项：
- 删了整个降级路径（screenshot.cjs + post.html）：**不是 bug**
- 重写 image.py 240 行：**不是 bug**
- 加了新 prompts/ 目录：**结构层变动**
- 用户行为变：没 Gemini Key 不能用了：**配置要求变了**

**结论：不是 CALIB。**

CALIB 的底线是"用户无感升级"。v2.3.0 显然做不到——老用户如果只配了 HTML 截图、没配 Gemini，直接 pull 下来就不能用了。

### Step 3：剩下就是 HANDS

- `scripts/image.py` 重写 → HANDS 典型信号
- 新增 `prompts/` 目录 → 新的能力单元
- 删除 `skills/xhs-content-generator/` 子 skill → 目录结构变动
- Gemini Key 必需 → 依赖要求变化
- migrations/v2.3.0.sh 需要跑 → HANDS 的招牌特征

**最终判定：HANDS+1 → v2.3.0。**

### 附加思辨：为什么不算 BRAIN？

这个决策其实反直觉——"配置从 optional 变 required"听起来像 breaking。我当时也纠结了半天，最后想通了：

1. **用户感知的"去降级路径"其实是配置层面的**。以前没 Key 时走 HTML 降级，现在没 Key 直接报错——行为差异是在"缺配置"这个边缘路径上，不是在主业务路径上。正常使用（有 Key）的用户，输出质量更好，但决策方式没变。

2. **AI 的"性格"没变**。§0a 业务路由逻辑一字没改。薯灵还是那个薯灵，理解用户意图的方式一样，从历史数据学习的方式一样。只是它的"手"换了工具（HTML → 原生图像模型）。

3. **反例：如果同时重构了 SKILL.md §2.3 的流程语义**（比如改为"每页图独立参考、跨图风格一致性学习"），那就必须 BRAIN+1——那才是决策方式变了。

这里有一条很有价值的判定启发式：

> **"工具换了" vs "性格变了"** —— 换工具是 HANDS，变性格是 BRAIN。

image.py 从"HTML 截图+Gemini 双路"换成"纯 Gemini"，工具换了，性格没变。HANDS+1。

---

顺手把薯灵整个版本史用三段法走一遍，当对照表：

| 版本                | 代号                          | 改动重点                              | 决策判定 |
| ------------------- | ----------------------------- | ------------------------------------- | -------- |
| v2.0.0 → v2.1.0     | Anti-Ban Shield              | 节流 + 限额 + **风控决策**             | BRAIN+1  |
| v2.1.0 → v2.1.1     | Request Log                   | MCP 调用全量落表（**加新表**）          | HANDS+1  |
| v2.1.1 → v2.1.2     | Release Polish                | CHANGELOG/UPGRADE/RELEASING 三件套     | CALIB+1  |
| v2.1.2 → v2.1.3     | Friendly Onboarding           | install.sh 六模式 + preflight 人类模式  | CALIB+1  |
| v2.1.3 → v2.2.0     | Existing Creator Support      | §0c 老博主接入 + import-existing.sh + DB 加 source | HANDS+1  |
| v2.2.0 → v2.2.1     | Migration Safety Fix          | 纯 bugfix                             | CALIB+1  |
| v2.2.1 → v2.3.0     | Pure Image Pipeline           | scripts/image.py 重写 + 去降级 + 新 prompts/ | HANDS+1  |

v2.1.3 → v2.2.0 当时也纠结过（§0c 是 additive，不改变原有流程，但 DB 加了 source 字段），最后按"加了新表字段+新脚本"判 HANDS+1。这类边界案例的规则很简单：**只要碰了 schema 或 scripts/，至少 HANDS+1。**

## 4. 配套工程：让版本号落地

光有三段版本号定义不够，要真正让 skill 作者和用户都吃到好处，还要有配套的工程约定。薯灵目前跑通的组合是这几件：

### 4.1 CHANGELOG 双栏

每个版本同时给两栏：

```markdown
## [v2.3.0] Pure Image Pipeline - 2026-04-20

### 📦 用户可见改动
- 图片生成全面改用 Gemini 2.0 Flash，封面更稳定
- 新增 --topic / --outline-file / --reference 等 CLI 参数
- Gemini API Key 从可选变为必需

### ⬆️ 如何升级
1. bash migrations/v2.3.0.sh
2. 在 .env 中补上 GEMINI_API_KEY
3. 重新运行 preflight --human 确认环境
```

"用户可见改动" 写业务感知，"如何升级" 写具体动作。两栏分开，读者不用在一堆变更里自己挖迁移步骤。

### 4.2 migrations/vX.Y.Z.sh

每个 HANDS+1 及以上的版本，都配一个幂等、可重试的迁移脚本：

```bash
#!/bin/bash
# migrations/v2.3.0.sh
set -euo pipefail

# 幂等：多次执行结果一致
if [ -f "scripts/screenshot.cjs" ]; then
  rm scripts/screenshot.cjs
  echo "[v2.3.0] removed legacy screenshot.cjs"
fi

# 检查前置：Gemini Key 现在必需
if ! grep -q "GEMINI_API_KEY" .env 2>/dev/null; then
  echo "[v2.3.0] ERROR: GEMINI_API_KEY missing in .env"
  exit 1
fi
```

两个关键原则：**幂等**（跑 N 次结果一样）+ **前置检查**（缺东西早报错）。

### 4.3 UPGRADE.md

集中写所有版本的迁移步骤，用户不用翻 CHANGELOG 找。按"从哪到哪"组织：

```markdown
## 从 v2.2.x 升级到 v2.3.0
1. ...
## 从 v2.1.x 升级到 v2.3.0
1. 先走 v2.2.0 的迁移
2. 再走本节的 v2.3.0 迁移
```

### 4.4 RELEASING.md

发版 SOP，减少手滑。我的版本大概长这样：

```markdown
1. 确定 BRAIN / HANDS / CALIB 段位
2. 更新 VERSION 文件
3. 写 CHANGELOG 双栏
4. 如果 HANDS+ ，写 migrations/vX.Y.Z.sh
5. 更新 UPGRADE.md
6. 跑 preflight + migration 自测
7. git tag + push
```

### 4.5 VERSION 文件：把"能力清单"写死

这是我觉得最值得抄的一条。薯灵的 `VERSION` 不只是一行版本号，而是 60 行 YAML，显式枚举当前版本下 BRAIN/HANDS/CALIB 各自包含了什么能力：

```yaml
version: "2.3.0"
codename: "Pure Image Pipeline"
released: "2026-04-20"

brain:
  # 核心决策 / 业务能力
  - preference-learning    # 偏好学习
  - confidence-scoring     # 置信度
  - anti-ban-shield        # 风控决策（v2.1.0 引入）
  - business-routing       # §0a 业务路由

hands:
  # 执行层 / 数据 / 接口
  - request-log            # MCP 调用记录（v2.1.1）
  - import-existing        # 老博主接入（v2.2.0）
  - image-pipeline-pure    # 纯 Gemini 图片链路（v2.3.0）

calib:
  # 参数 / 文本 / 文档
  - prompts/image_prompt.txt
  - prompts/image_prompt_short.txt
  - thresholds/*.yaml
```

这让"变更集"成为一等公民——你每次发版要做的事情很具体：**去 VERSION 里挪动一项，或添加一项。** 版本号自然就定了。

## 5. 局限与适用边界

BRAIN.HANDS.CALIB 不是银弹，它**不适合这些场景**：

- **IDE 插件、工具库、CLI 框架**：这些本质是"软件是工具"，用户消费的是 API。继续用 SemVer。
- **无业务逻辑的纯 agent**：比如单纯问答机器人、单任务脚本型 skill。它们没有"角色"，没有"决策流程"，三段法反而是过度设计。
- **不会持续演化的 skill**：一次性工具、一锤子买卖，用个 `v1`/`v2` 就够了。

**它适合这些场景**：

- 有明确决策流程、有业务路由的 skill（比如薯灵的 §0a、§0b、§0c 路由）
- 会持续自进化（prompt 迭代、阈值调整、算法升级）
- 有用户侧迁移成本（DB 依赖、外部 API 依赖、配置要求）
- 用户对"角色性格"有预期（比如日常助手、内容创作者、教练型 agent）

简单判据：**如果你的 skill 是"一个活的东西"而不是"一把锤子"，那就值得用 BRAIN.HANDS.CALIB。**

## 6. 结语：角色的版本号

文章开头那句话再说一遍，这是我用了四个版本才想明白的：

> **BRAIN 改了，用户的 AI 就变性格了——这是 breaking，不是新功能。**

SemVer 看不见"性格"这件事，因为它诞生在"软件是工具"的年代。但 AI skill 是**有人格、会演化、和用户共生的东西**，它的版本号需要能表达"脑子动了"、"手变了"、"参数调了"这三种层次分明的变化。

BRAIN.HANDS.CALIB 不是标准，只是薯灵跑通的一套约定。如果你在写自己的 skill，欢迎直接抄过去——版本号、CHANGELOG 双栏、VERSION YAML、migrations 约定，都是 MIT 协议，不用客气。

如果有人质疑你为什么不用 SemVer，指这篇给他看就行。

---

### 相关链接

- 薯灵开源仓库：[github.com/AI-flower/shuling](https://github.com/AI-flower/shuling)（MIT）
- 系列第一篇：**《Skill-as-Brain：把 AI Skill 当大脑而不是插件写》**
- 系列下一篇（预告）：**《薯灵的自进化算法：偏好学习 + 置信度 + 风控三件套是怎么跑起来的》**

如果你也在做 skill，欢迎来 Issues 区交流版本号决策——我特别想看各种边界案例的判定过程。

---

*本文是薯灵推广系列第二篇。转载请注明来源。如果觉得有用，给 GitHub 仓库点个 star 是最大的鼓励。*
