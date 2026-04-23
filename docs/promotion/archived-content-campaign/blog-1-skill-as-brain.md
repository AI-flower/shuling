---
title: "Skill-as-Brain：我把业务逻辑写成 Markdown 而不是代码"
subtitle: "一个 1208 行 SKILL.md 驱动 AI agent 的真实实践"
date: 2026-04-23
tags: [AI Agent, LLM, Claude Code, Skill, Architecture, Markdown, Prompt Engineering]
reading_time: 15 min
author: 薯灵 (ShuLing) 作者
---

## 1. 引子：一个尴尬的 v1

薯灵（ShuLing）的第一个版本是一个非常"正统"的 AI agent 项目：Python 写主干，OpenAI SDK 调模型，几个 `.py` 文件里塞满 prompt template，一堆 `if/else` 控制流程，再加几个 f-string 拼出一个四五百行的 system prompt。

听起来很熟悉是吧？这大概是 2024 年几乎所有"认真"做 agent 的团队的默认架构。

然后问题就开始了。

我要加一个"博主画像首次接入"的流程，需要让 AI 先问清楚博主现在几个粉丝、哪个赛道、最近哪篇笔记爆了；然后基于答案决定下一步。于是我改了 `prompt_templates/onboarding.py`，加了两百行。跑起来发现原本"日常选题"的流程也被影响了 —— 因为新的 system prompt 把对话历史里的某个状态搞混了。

我回去改代码，给 AI 加了个 "current_stage" 的 state 字段，代码里用 `if stage == "onboarding"` 切换 prompt 版本。然后发现 —— AI 看不到这个 state。这东西只在我的 Python 代码里存着，AI 不知道自己在哪个阶段。我得在 prompt 里再说一遍 "You are currently in stage X"，但这又增加了一处飘移源。

几周之后，我面对的是：

- **改 prompt 怕影响代码逻辑** —— 因为某些分支判断藏在 prompt 里
- **改代码怕影响 AI 判断** —— 因为某些状态 AI 会看着代码的注释"推断"
- **prompt 和代码两处飘移** —— 一份业务逻辑，两个事实来源
- **想迁移到 Codex 或 Hermes 要整个重做** —— Python 代码不跨平台，prompt 也是绑死 OpenAI SDK 的

最让我崩溃的一次，我想把"这条逻辑"回滚到上周的版本。但"这条逻辑"横跨 `onboarding.py`、`router.py` 和三个 prompt 文件 —— `git revert` 下去，别的地方全乱了。

那天晚上我盯着 VS Code 愣了十分钟。然后意识到：**我在用错误的介质表达业务逻辑。**

## 2. 顿悟：代码 vs Markdown 的语义差异

这个顿悟听起来有点玄，但它其实很朴素：

> 代码是给 CPU 执行的，Markdown 是给 LLM 阅读的。执行 ≠ 阅读。

过去几十年软件工程里，我们习惯把业务逻辑写成代码，因为代码是唯一能被机器"理解"并"执行"的东西。但 LLM 不执行代码 —— LLM 阅读代码。这两件事是根本不同的：

**LLM 读代码是"解读"：**

- Token 贵 —— 每一个 `def`、每一对 `()`、每一个 `self.` 都在烧 token，但它们对 LLM 的决策几乎没信息量
- 理解易错 —— 代码里充满了"技术性噪音"（变量命名、类型注解、装饰器），LLM 要先把这些过滤掉才能提取业务意图
- 调试困难 —— 当 AI 做错了决定，你很难分辨是它没读懂某个函数，还是没读懂代码背后的业务规则

**LLM 读 Markdown 是"阅读"：**

- Token 省 —— 同样的业务规则，Markdown 表达通常是代码的 30%-50%
- 理解直接 —— 你写的"如果粉丝数 < 1000，跳过爆款分析环节"，LLM 读到的就是这句话，不用解码
- Review 快 —— 人也能直接读懂，PM 能看，新成员能看，git diff 一眼就是 code review

对于**业务逻辑这种"决策密集 + 规则清晰"的内容**，Markdown 是比代码更自然的载体。代码该做的是"手脚活儿"—— 调 API、读写数据库、处理文件 —— 那些确定性的、不需要决策的部分。

换句话说：**代码的本职是确定性执行，而业务规则的本职是决策。**过去我们混在一起，是因为没有更好的选择。现在有 LLM 了，该分开了。

## 3. Skill-as-Brain 的三层架构

薯灵 v2.3.0 的架构是这样的：

```
┌───────────────────────────────────────────────────┐
│   大脑层 (Brain)                                 │
│   SKILL.md (1208 行)                              │
│   §0a 业务路由 / §0b 平台识别 / §0c 老博主接入     │
│   §0 安装 / §1 画像 / §2 日常流程 / §3 复盘        │
│   §4 自进化 / §5 合规 / §6 工具参考                │
│   §7 数据结构 / §8 异常处理                        │
└─────────────────┬─────────────────────────────────┘
                  │ AI reads, decides
                  ▼
┌───────────────────────────────────────────────────┐
│   手脚层 (Hands)                                  │
│   scripts/ (11 个脚本)                            │
│   xhs.sh (MCP 调用) / db.sh (SQLite 读写)         │
│   image.py (Gemini 生图) / preflight.py (预检)    │
│   noterx-diagnose.sh (第三方诊断) ...              │
└─────────────────┬─────────────────────────────────┘
                  │ Scripts write
                  ▼
┌───────────────────────────────────────────────────┐
│   记忆层 (Memory)                                 │
│   knowledge-base/                                 │
│     profile.json (长期：博主画像)                 │
│     preferences.json (长期：偏好学习)              │
│     patterns.md (长期：有效模式)                  │
│     evolution-log.md (长期：自进化日志)            │
│   data/shuling.db                                 │
│     9 张 SQLite 表（短期：每次运行状态）           │
└───────────────────────────────────────────────────┘
```

**大脑层（SKILL.md）** 是 AI 的决策中枢。所有分支、判断、规则、状态机全在这一个 Markdown 文件里。AI 启动的时候先把 SKILL.md 读进 context，然后就知道该怎么办了。

**手脚层（scripts/）** 是 AI 做不了的物理操作。LLM 不能直接调 MCP，不能直接读写 SQLite，不能直接调 Gemini API。这些事情封装成脚本，大脑通过"调用脚本"来驱动手脚。

**记忆层** 分长期和短期。`knowledge-base/` 是长期记忆 —— 博主画像、学到的偏好、有效模式 —— 这些东西跨会话存在。`data/shuling.db` 是短期记忆，每次运行的状态、这条笔记的 metrics、这次诊断的结果。

举个具体的例子。`SKILL.md §0a 业务路由`是一张 Markdown 表格：

```markdown
## §0a 业务路由表

| 用户输入关键词       | 前置条件                      | 跳转章节 |
|----------------------|-------------------------------|----------|
| "我是新博主"         | profile.json 不存在           | §1 画像  |
| "我有账号了"         | profile.json 不存在           | §0c 接入 |
| "今天发什么"         | profile.json 存在             | §2 日常  |
| "复盘一下"           | 最近 7 天有发文               | §3 复盘  |
| "检查一下环境"       | 任何时候                      | preflight |
| "我感觉选题不准"     | preferences.json 存在         | §4 自进化 |
| 未识别               | 任何时候                      | 请用户澄清 |
```

这就是一个状态机。用 Python 写，至少是一个 `match/case` + 多层 `if`，加起来 50 行，而且 LLM 读的时候还得推断"这个条件组合下应该走哪个分支"。

写成 Markdown 表，LLM 一眼就懂。人也一眼就懂。改的时候加一行删一行，`git diff` 清清楚楚。

整个 SKILL.md 里类似的表格有几十张 —— 每张都是一个局部决策规则。整合起来就是一个完整的业务大脑，而它的物理形态是一个 1208 行的 Markdown 文件。

## 4. 三个意外收益

当我把业务逻辑从代码里抽出来写进 SKILL.md 之后，出现了三个没预期到的好处。

**其一，换 AI 平台成本接近零。**

薯灵现在同时支持三个平台：Claude Code、Codex、Hermes。这三个平台的 skill 机制完全不一样 —— Claude Code 原生支持 `.claude/skills/`，Codex 需要通过自定义 memory 注入，Hermes 通过 cron + 预读 hook 实现。

但你猜怎么着？三个平台共用**同一份** SKILL.md。`platform/` 目录下每个平台只有一个很薄的适配层，大概是这样：

```
platform/
├── claude-code/
│   └── README.md      # "把仓库放进 ~/.claude/skills/ 即可"
├── codex/
│   └── inject.sh      # 把 SKILL.md 写进 Codex memory
└── hermes/
    └── cron.conf      # 5 次/日的自动触发配置
```

每个平台大概 20-50 行。没有业务逻辑，只有"怎么把 SKILL.md 喂给这个平台的 AI"。迁移一个新平台基本上就是写这个适配层的工作量 —— 一个下午。

**其二，流程改动零编译、零部署。**

传统 Python agent 改一个流程，流程是：改代码 → 跑测试 → 打包 → 部署。薯灵改一个流程：改 SKILL.md → `git commit` → 下次 AI 读到的就是新版本。

没有编译。没有部署。没有灰度。`git log SKILL.md` 就是完整的业务演化历史。

更妙的是，**code review 的对象变成了业务规则本身**。过去 PR 里全是 `prompt_templates["onboarding_v3"] = f"""..."""`，reviewer 要在字符串里找业务变化。现在 reviewer 直接看 Markdown diff —— 哪条规则加了，哪个分支删了，一目了然。

**其三（副产物），非技术 stakeholder 能看懂业务。**

这个不是我的目标，但发生了。薯灵有一次让一个运营朋友看了 §2 日常流程那一章，她读完说："哦你们做选题是这么个逻辑，那 §2.3 这个点我觉得应该改成……"

那一刻我意识到，Markdown 是一个天然的跨角色对齐介质。PM、运营、开发，三方都能读懂同一份文件 —— 这在传统 "prompt + code" 架构里是做不到的。

当然这是副产物，不是目标。目标始终是让 AI 执行得更可靠。但能顺便把"业务知识图谱"的问题解了，不亏。

## 5. 代价与边界

我不想写一篇"Skill-as-Brain 秒杀一切"的传教文。这个架构有真实的代价，我诚实讲三个。

**其一，SKILL.md 会 token 膨胀。**

我的 SKILL.md 现在 1208 行，喂给 AI 大约 5000 token。Hermes 平台上每天 cron 跑 5 次，每次都要重新 load 整个文件（没有跨调用的 context 复用）。算一下：

```
5000 token/load × 5 load/day × 30 day = 750,000 token/month  (per 博主)
```

如果覆盖 3 个博主，就是 225 万 token/月白烧在"重复读同一份 SKILL.md"上。这还没算输出和对话历史。

v2.4 正在做**瘦身**：

- 主干 SKILL.md 压到 ≤300 行，只保留路由 + 索引
- 拆出 `skill-chapters/` 子目录，`§1-profile.md`、`§2-daily.md` 等，AI 需要用到哪章才 load 哪章
- 预计能把每次 load 的 token 降到 1500 以内

这个问题用代码架构其实也有（prompt 长），但 Markdown 让问题更显性 —— 因为你一眼能看到"哦这 1208 行是不是有点多了"。

**其二，AI 会偶尔"飘走"。**

LLM 不是确定性执行器。偶尔它会把 §2.3 和 §2.4 的逻辑混淆，偶尔它会在 profile.json 不存在的时候"脑补"出一个画像，偶尔它会输出一个 schema 不合法的 JSON。

薯灵的兜底是两层：

1. **JSON Schema 契约** —— `schemas/` 目录下四份 JSON Schema（profile / preferences / post_metrics / generated_image），每次 AI 写入 JSON 文件前强制校验
2. **§0b 写入前校验** —— SKILL.md 里明确规定"写入 knowledge-base/ 前必须先跑 `scripts/validate.sh`，失败则 retry，两次失败则报错给用户"

这不是银弹。但 Schema + 明确的 write-validate-retry 规则把 AI 飘走造成的脏数据问题压到了可接受范围（过去 3 个月 zero incident）。

**其三，需要配套的版本号语义。**

传统 SemVer（major.minor.patch）在这个架构下不够用。因为现在有三个东西在独立演化：

- SKILL.md（大脑）的版本
- scripts/（手脚）的版本
- knowledge-base/ schema（记忆结构）的版本

我搞了一套叫 `BRAIN.HANDS.CALIB` 的三段式版本号（v2.3.0 里的 2 是 BRAIN，3 是 HANDS，0 是 CALIB），专门表达这三者的独立演化。下一篇博客讲这个。

## 6. 适用边界：什么场景该用 Skill-as-Brain

把这套搬到任何 agent 项目之前，先问自己三个问题。

**什么场景适合 Skill-as-Brain：**

- **决策密集 + 规则清晰** —— 大部分逻辑是"在条件 A 下做 X，条件 B 下做 Y"这种可以列表格的决策，而不是数值计算
- **用户交互复杂、多分支状态机** —— 对话式 agent、任务编排、流程自动化
- **需要演化** —— 业务规则经常改，需要频繁 review diff、快速迭代
- **多平台部署** —— 同一份业务逻辑要跑在不同 AI 平台上

**什么场景不适合：**

- **纯计算密集** —— 如果你的 agent 本质是在做数值计算、矩阵运算、图像处理，应该写代码，让 AI 只负责调用
- **无 AI 决策，纯机械工具** —— 如果流程是固定的、不需要 AI 判断，那写 Makefile / Airflow DAG 比写 SKILL.md 合适
- **对 token 成本极端敏感的低价值场景** —— 如果单次调用预算 <$0.01，每次 load 5000 token 的大脑就太贵了

**一句话判断法：**

> 如果你的 prompt 里有大量 "if / else / when / unless" 这种决策词，而且这些规则会经常变 —— 你需要 Skill-as-Brain。如果你的 prompt 大部分是"调用这个 API、解析这个 JSON、返回这个格式"—— 你需要的是一个普通的 function-calling agent。

薯灵属于第一类。小红书博主成长是典型的"决策密集 + 规则演化"场景 —— 每个博主的赛道不同、阶段不同、偏好不同、平台规则还在变。这些东西写进代码里，三个月后就改不动了。写进 SKILL.md 里，三个月后还是清清楚楚。

## 7. 结语

回到开头那个尴尬的 v1。当时的我以为问题是"prompt 写得不够好"或"代码架构不够优雅"。直到我把业务逻辑整个搬到 Markdown 里，才意识到真正的问题是：

**我在用错误的介质表达业务逻辑。**

过去几十年软件工程教我们把一切变成代码。但 LLM 改变了游戏规则 —— 现在我们有一个能直接阅读自然语言规则的"执行器"了，继续把业务规则塞进代码里，反而是最笨的选择。

> Skill-as-Brain 不是一种偏好，是 LLM-native 应用的必然形态。

当你的 agent 足够复杂、规则足够多、需要跨平台、需要演化 —— 你会自然地走到这一步。我只是比大多数人早走了一点。

薯灵 v2.3.0 已经在 GitHub 上开源（MIT），1208 行 SKILL.md、11 个脚本、9 张 SQLite 表，全部可读可改。如果你在做 agent，非常推荐去翻一翻 —— 至少 SKILL.md 的结构和 §0a 路由表那一段，我觉得值得借鉴。

**下一篇**讲 `BRAIN.HANDS.CALIB` —— 为什么传统 SemVer 在 agent 项目里不够用，以及薯灵怎么用三段式版本号表达大脑、手脚、校准的独立演化。

---

## Related Links

- GitHub: [github.com/AI-flower/shuling](https://github.com/AI-flower/shuling)
- 官网: [shuling.pages.dev](https://shuling.pages.dev)
- License: MIT
- 如果这篇文章对你有启发，欢迎在 GitHub 上点个 star，让更多 agent 开发者看到 Skill-as-Brain 这个范式
