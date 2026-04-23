---
title: "AI agent 的小样本偏好学习：Laplace 平滑 + 集中度 × 样本因子"
subtitle: "一个让 LLM 不过拟合的工程化方案"
date: 2026-04-23
tags: [AI Agent, 偏好学习, 推荐系统, Laplace 平滑, ε-greedy, 薯灵, LLM]
reading_time: 18 分钟
series: 薯灵推广 · 第三篇
author: 薯灵作者
---

> 金句先放这里：**Weight 是对单个类型的倾向。Confidence 是对整个判断的信心。混用它们，是 AI 工程里最隐蔽的坑。**

前两篇分别聊了 [Skill-as-Brain 架构](./blog-1-skill-as-brain.md) 和 [BRAIN.HANDS.CALIB 版本号](./blog-2-semver.md)。有读者在评论里问我：

> "你说薯灵（[AI-flower/shuling](https://github.com/AI-flower/shuling)）能学用户口味，那它到底怎么学的？我也想给自己的 agent 加一套偏好学习，但每次都跑偏——用户选一次 A，AI 就只推 A 了。"

这一篇就把这件事讲透。本文的目标读者是做 **推荐系统、用户建模、Agent 个性化** 的工程师，篇幅最长、数学也最密，但我保证每一个公式都能直接抄到你自己的项目。

核心论点只有一句：

> **LLM 套壳做个性化最常见的错误是"过拟合小样本"。薯灵 §4.1 的公式组合（Laplace 平滑 + 集中度×样本因子 + ε-greedy + 回弹机制）可以系统性解决。**

---

## 1. 场景 + 陷阱：2 次选择就"学会"了？

设想这样一个场景：

你在用一个 AI 写作助手。它每天早上会问你：

> "今天发哪一篇？A. AI 工具测评  B. 代码教程  C. 行业快讯"

第一天你选了 A。第二天它继续问，你又选了 A。

**问题来了：AI 该多信你？**

工程师的直觉反应一般有三种：

- **朴素派**："两次都选 A，那就认定你喜欢 A 呗，下次直接推 A。"
- **保守派**："才两次，样本太小，还是随机推吧。"
- **佛系派**："让 LLM 自己判断，反正它看过历史记录。"

这三种都有坑。朴素派最危险——写成代码就是：

```python
# 危险版：朴素比例
weight = chosen / (chosen + skipped)
```

第 2 次选 A 后，`weight_A = 2 / (2 + 0) = 1.0`。AI 直接进入"1 选模式"，完全失去多样性。用户的第 3 次选择根本看不到 B 和 C，于是 `weight_A` 永远锁死在 1.0——典型的 **反馈回音室**。

保守派也不优雅——"样本太小就不学"这句话听着合理，但用户体验上你等不起。用户用了一周，你告诉他"还不够呢再选几次"，用户已经卸载了。

佛系派最玄学。你把历史数据塞进 prompt："用户选过 A、A、B、A"，让 LLM 自己推断。问题是 LLM 没有 **数学先验**——它无法区分"2 次选 A"和"20 次选 A"在置信度上的差异。prompt 里写"根据用户历史偏好推荐"，在小样本下几乎等同于投硬币。

这就是 **LLM 套壳做个性化的典型陷阱**：把统计问题塞给模型靠"理解"解决，本质是把确定性的数学规律变成了概率性的自然语言推理。该用贝叶斯的地方用贝叶斯，该用 ε-greedy 的地方用 ε-greedy，别让 LLM 替你做本来一个公式就能搞定的事。

薯灵 SKILL.md §4.1 给了一套组合拳。下面我们一条一条拆。

---

## 2. Laplace 平滑：小样本的数学直觉

朴素比例的问题本质是 **没有先验**。第 1 次选择，分母就是 1；第 0 次，分母为 0 直接炸。解法用了 200 年了：Laplace 平滑（又叫"加一平滑"）。

公式极简：

```python
def weight(chosen: int, skipped: int) -> float:
    return (chosen + 1) / (chosen + skipped + 2)
```

"+1 / +2" 背后的贝叶斯解释是：**Beta(1, 1) 先验**。

- Beta(1, 1) 是 [0, 1] 上的均匀分布。翻译成人话：在没看到任何数据之前，我认为"用户喜欢 A"的概率是 50%。
- 每观察到一次"选"，相当于 Beta 分布的 α 参数 +1；每观察到一次"跳"，β 参数 +1。
- 后验分布的期望就是 `(α + chosen) / (α + β + chosen + skipped)`，代入 α=β=1 得 `(chosen + 1) / (chosen + skipped + 2)`。

如果你数学直觉没跟上也没关系，看这张对照表就够：

| chosen / skipped | 朴素比例 | Laplace 平滑 |
|---|---|---|
| 0 / 0 | 未定义（除零）| **0.50** |
| 1 / 0 | 1.00 | **0.67** |
| 2 / 0 | 1.00 | **0.75** |
| 10 / 0 | 1.00 | **0.92** |
| 2 / 3 | 0.40 | **0.43** |
| 50 / 50 | 0.50 | **0.50** |

几个直观的读法：

- **样本为 0 时，默认值是 0.50**（中立），不是 NaN 或"全 0"。这让初始化不需要特判。
- **样本小时自动保守**：2 选 0 跳只给 0.75，不是朴素的 1.0。2 次不够让我全信你。
- **样本大时逼近真实比例**：50/50 时 Laplace 和朴素都是 0.5，先验的影响被数据"冲淡"。
- **对极端值的天然抗性**：朴素下 10/0 和 100/0 都是 1.0，Laplace 下分别是 0.92 和 0.99——样本越多越自信。

薯灵里 `weight` 的语义是 **单个类型（比如"AI 工具"这个 topic）被用户选中的倾向概率**。它只描述单一维度。

为什么强调这一点？因为下一节要出场的是 `confidence`——**整体判断的信心度**。这两个东西有无数工程师搞混过。

---

## 3. Weight ≠ Confidence：两个维度的分离（本文最核心）

先把结论放在最前面：

> **Weight 是对单个类型的倾向。Confidence 是对整个判断的信心。混用它们，是 AI 工程里最隐蔽的坑。**

SKILL.md §4.1 在这里有一条 **严正提示**——原文大意是："高水平 AI 实测会踩这个坑。别把 `chosen/(chosen+skipped)` 当成 confidence，那是 weight 的公式，混用会导致 N 选 M 永远触不到阈值、收敛机制失效。"

我自己第一版实现就踩了。一个看起来人畜无害的笔误，让整个收敛流程报废。我们看公式：

### 3.1 Confidence 的正确公式

```python
def confidence(weights: dict[str, float], total_choices: int) -> float:
    if not weights:
        return 0.0
    sorted_w = sorted(weights.values(), reverse=True)
    top2_sum = sorted_w[0] + (sorted_w[1] if len(sorted_w) >= 2 else 0)
    concentration = top2_sum / sum(weights.values())
    sample_factor = min(total_choices / 10, 1.0)
    return round(concentration * sample_factor, 2)
```

两个组件各司其职：

- **concentration（集中度）**：top2 的 weight 之和 / 全部 weight 之和。反映"用户口味是否集中"。全选一个类型 → 趋近 1.0；平均分给 N 个类型 → 趋近 2/N。
- **sample_factor（样本因子）**：`min(total_choices / 10, 1.0)`。反映"我看到的数据够不够多"。前 10 次线性增长，之后封顶在 1.0。

**相乘的意义**：两个条件都要满足才给高 confidence。口味集中 + 样本够多 = AI 可以放心收敛；口味集中但样本少 = 可能是偶然，AI 保持警觉；样本多但口味分散 = 用户本来就是多元爱好者，AI 别强行简化。

### 3.2 数值演示：5 行对照表

场景设定：用户在 3 个 topic 维度上选择（AI 工具 / 代码 / 快讯）。

| 场景 | weight_ai_tools | weight_coding | weight_news | confidence_level |
|---|---|---|---|---|
| 初始（0/0, 0/0, 0/0） | 0.50 | 0.50 | 0.50 | **0.00**（sample_factor=0） |
| 3 次全选 ai_tools | 0.80 | 0.20 | 0.20 | **0.25**（concentration 0.83 × 0.3） |
| 10 次全选 ai_tools | 0.92 | 0.08 | 0.08 | **0.92** |
| 10 次：6 ai_tools + 4 coding | 0.58 | 0.42 | 0.08 | **0.92** |
| 10 次：3/3/4 平均分给 3 类 | 0.33 | 0.33 | 0.42 | **0.69**（分散→低信心） |

仔细看第 2 行和第 3 行的对比：

- 3 次全选 `ai_tools`：朴素派会说"太 100% 了，直接 1 选档"；Laplace 给出的 `weight_ai_tools` 已经降到 0.80，但 `confidence` 只有 0.25——**样本因子把它摁住了**。
- 10 次全选：样本因子到 1.0，concentration 也到 0.92，`confidence` 终于到 0.92——这时 AI 才真的"确信"。

再看第 3 行和第 4 行：

- 10 次全选 `ai_tools`：`confidence = 0.92`。
- 10 次里 6 个 `ai_tools` + 4 个 `coding`：`confidence` 同样 0.92。

为什么两者一样？因为 **top2 集中度**——不管是 top1 吃掉全部，还是 top1+top2 分食全部，只要不分到第 3 类，集中度就接近 1.0。这符合产品直觉：用户同时喜欢 AI 工具和代码教程也是"集中的口味"，不一定要 100% 单选一类才叫集中。

最后看第 5 行：10 次平均分给 3 类，`confidence` 掉到 0.69。这是正常的——用户本身就是"全栈兴趣"，AI 不应该强行选边站。

### 3.3 为什么分离两个维度：工程意义

把 weight 和 confidence 分开后，你可以写出这样的分支逻辑：

```python
# weight 驱动"推什么"
top_topic = max(weights, key=weights.get)

# confidence 驱动"推几个"
if confidence >= 0.75:
    options_count = 1
elif confidence >= 0.5:
    options_count = 2
else:
    options_count = 3
```

如果你只有一个维度（比如混用成 weight），你要么永远保守（全 3 选）、要么永远激进（1 选锁死）。只有把"倾向"和"信心"拆开，才能做到 **小样本保守、大样本收敛** 的优雅过渡。

这条分离原则在推荐系统里其实老生常谈——CTR 预估分 pCTR 和 exploration uncertainty；多臂老虎机分 arm value 和 confidence bound。但在 **LLM 套壳 agent** 这个新场景里，很多人会下意识地把两者塞进一个 number、一句 prompt，于是就踩坑。

---

## 4. 选项递减：confidence 驱动的交互设计

有了 `confidence` 这把尺子，交互设计就有了依据。薯灵的策略如下：

```python
if confidence_level >= 0.75:
    # 基础：推 1 个选题 + 1 份草稿（"发/换"）
    ...
    if need_exploration(last_exploration_at, today):
        # 额外追加 1 个"探索项"（见下一节 ε-greedy）
        ...
elif confidence_level >= 0.5:
    # 推 2 个选题 + 1 份草稿（附备选标题）
    ...
else:
    # 推 3 个选题 + 2 份草稿
    ...
```

三个阈值的设计依据：

**≥ 0.75（1 选档）**：高置信 + 样本够，用户明确的口味 AI 可以"直接执行"。这时的交互从"选择题"变成"决定题"——AI 给你一个具体的文章草稿，你只需要回答"发"或"换"。认知负担最低。

**≥ 0.5（2 选档）**：中置信，AI 缩圈但不封顶。给 2 个接近用户偏好的候选，让用户做一次二选一的对比。好处是比 3 选档决策快，又保留了选择感。

**< 0.5（3 选档）**：低置信。要么是样本少，要么是口味分散。这时 AI 的最优策略是 **展示多样性**——给 3 个差异较大的选题 + 2 份不同风格的草稿，收集更多的"选/跳"信号。

为什么不是"3 选档就死定"？因为下一节的 ε-greedy 提供了保底——即使进了 1 选档，也会定期强制出探索项。这套设计的哲学是：**收敛是目标，但永远保留退出的通道**。

另外一个细节：**选项数量必须是 "递减"——从 3 到 2 到 1，不能跳**。如果你直接从 3 选档跳到 1 选档，用户会有强烈的"AI 怎么突然这么自信"的割裂感。渐进式才符合直觉。

---

## 5. ε-greedy 探索保底：防"口味回音室"

1 选档最大的风险是什么？

**AI 永远只推你喜欢的，你忘了自己其实也能吃别的。**

这是典型的 filter bubble 问题。推荐系统界早就有现成的解法：**ε-greedy**——以 1-ε 的概率选最优，以 ε 的概率随机探索。

薯灵的 ε-greedy 做了工程化改造，不是纯随机，而是 **时间窗口 + 冷门类型筛选**：

```python
from datetime import date, timedelta

def need_exploration(last_exp: date | None, today: date, days: int = 7) -> bool:
    return last_exp is None or (today - last_exp).days >= days

def pick_exploration_topic(weights: dict[str, float],
                           recent_shown_topics: set[str],
                           threshold: float = 0.3) -> str | None:
    # 从 weight < 0.3 且最近 14 天未推过的类型里抽一个
    candidates = [
        topic for topic, w in weights.items()
        if w < threshold and topic not in recent_shown_topics
    ]
    return random.choice(candidates) if candidates else None
```

触发规则：当 `confidence >= 0.75`（1 选档）时，如果距离上次探索 ≥ 7 天（或从未探索过），追加 1 个探索项。这时推荐变成 "1 主推 + 1 探索"——主推服从用户偏好，探索打破回音室。

每个参数都有工程直觉：

- **7 天**：为什么不是每天？用户会烦（今天又推个我没兴趣的）。为什么不是每月？太稀疏，失去打破回音室的意义。一周一次大约是"能接受的偶然惊喜频率"。
- **weight < 0.3**：下限，太高（比如 < 0.5）就不叫"冷门"了，会混进次优选项；太低（比如 < 0.1）候选太少，经常抽不到。0.3 是一个让"被忽视但还没完全淘汰的类型"有机会的阈值。
- **最近 14 天未推过**：防止同一个探索项刷屏。如果上次探索推了"行业快讯"用户没点，下次别再推它。

探索成功（用户点了）会怎样？`chosen_news += 1`，下次 `weight_news` 上来，可能就进不了冷门候选池了——**用户的口味图谱被动态更新**。

### 5.1 ε-greedy vs Thompson Sampling

老派推荐系统工程师会问："为什么不用 Thompson Sampling？理论更优雅。"

我的选择：工程上 ε-greedy 更好讲、更好调、更好解释给产品经理。Thompson Sampling 需要维护每个 arm 的 posterior 分布、每次 draw sample，实现成本高。对于薯灵这种 **每天 1 次交互** 的低频场景，ε-greedy 的次优性损失可以忽略，换来的是代码简单、可观测性强。

这是推荐系统的老话题：**理论最优 ≠ 工程最优**。

---

## 6. 回弹机制：防"AI 钻牛角尖"

现在聊一个反向的坑。

假设 AI 进了 1 选档（confidence = 0.8），给你推了选题 A。你说"换"。AI 再推 B。你又说"换"。

这时候问题来了：AI 是不是应该 **主动降置信**？

朴素做法是不动 confidence，继续在 1 选档推第 3、4、5 个。但这样很快就会耗尽候选，而且用户体验差——用户已经连续说了 2 次"不对"，AI 却没意识到"我可能整个方向都错了"。

薯灵的回弹机制：

```python
# 每次用户"换"
consecutive_rejects += 1
confidence_level -= 0.10   # 主动降置信
# 本次临时扩展选项（+2 个选题或 +1 份草稿）

if consecutive_rejects >= 2:
    confidence_level = min(confidence_level, 0.45)   # 强制回 3 选档
    consecutive_rejects = 0

# 每次用户"发"（正常采纳）
consecutive_rejects = 0
```

几个参数都是调出来的，不是拍脑袋的：

**-= 0.10（而不是 -= 0.05）**：原始设计是 0.05，测试时发现回弹太慢——用户换了 5 次才勉强跌出 0.75。0.10 对应"每次换掉一个 topic 的 full 权重"，回弹速度刚好。

**consecutive_rejects >= 2 才强制**：1 次不够（可能用户只是今天心情不好、想看点别的）；3 次太多（用户已经在吐槽 AI 了）。2 次是 "够明确但还没激怒用户" 的窗口。

**强制值是 0.45**：刚好低于 0.5 的 2 选档阈值，直接跳到 3 选档。为什么不直接 0.0？因为 AI 此前积累的信息不是全错——用户只是 **这个 session** 下不对，历史偏好还是有参考价值。0.45 让 AI "把嗓子清一清重新来"，但不至于把记忆全抹了。

**用户"发"就 reset**：一次采纳说明 AI 的方向对了，之前的 rejects 不用继续记账。

这个机制我叫它 "**防钻牛角尖**"——AI 在 confidence 高时容易陷入"我肯定对的"惯性，需要一个外部信号强行让它低头。用户说"换"就是那个信号。

---

## 7. Pattern 生命周期：把"偏好"升级为"规律"

偏好学习是 "用户喜欢什么"。但薯灵还有更上一层——Pattern。

> **Pattern = 什么内容会成功。**

举例：
- 偏好："用户喜欢 AI 工具类"
- Pattern："标题里带问号 + 第一段有具体工具名 + 配图用截图而非插图 → 这种文章的 24h 收藏率通常 >5%"

Pattern 是数据沉淀下来的 **可复用规律**，比偏好更接近 "方法论"。

薯灵的 Pattern 生命周期：

```text
experimental (试验)  →  medium (中)  →  high (高)
     ↓                                       ↓
 anti-patterns  ←  连续 3 次失效        deprecated (老化)
```

具体规则：

- **进入 experimental**：某条文章的收藏率 ≥ 5%（触发"这可能是个规律"）。
- **experimental → medium**：连续 3 次验证有效（>2% 收藏率）。
- **medium → high**：再连续 3 次验证有效。
- **high → deprecated**：连续 3 次失效（<2% 收藏率）。
- **experimental → anti-patterns**：连续 3 次失效。
- **patterns.md 活跃数上限 ≤ 15 条**：超过就淘汰 confidence 最低的。

每个参数背后的设计考量：

**收藏率 5% 阈值**：小红书体系下平均收藏率在 1-2%，5% 是明显高于平均的信号。太低（3%）混进噪声；太高（10%）样本稀缺，升级太慢。

**连续 3 次**：单次成功可能是偶然，3 次才能排除噪声。这是经典的"三次法则"——统计学里 3 次同向事件大约对应 p < 0.125，已经是合理的弱信号。

**上限 15 条**：人（或 LLM）一次能参考的规律数量有限。超过 15 条，pattern 之间开始冲突，LLM 的注意力被稀释。15 是"信息量饱满但不溢出"的经验值。

**为什么不全用 LLM 推荐？** 你完全可以把所有文章塞给 LLM，让它总结"什么样的文章会成功"。问题是：LLM 的总结 **不可验证、不可积累、不可回溯**。今天它说"带问号的标题好"，明天你问它同一个问题，它可能说"不带问号更好"。数据驱动的 Pattern 生命周期提供了 **可审计的规律沉淀**——每一条都有具体的验证次数、收藏率样本、升级时间戳。

这也是薯灵整体架构的核心哲学：**LLM 负责理解和生成，数据驱动的公式负责决策和收敛**。两者分工，互不越界。

---

## 8. 踩坑警告：5 个常见错误

做过这套的人应该能在踩坑名单上看到自己。我按"常见程度 × 坑深度"排序：

### 坑 1：weight 和 confidence 混用（最常见）

用 `chosen / (chosen + skipped)` 当 confidence，或者反过来用带 sample_factor 的公式做单类型权重。后果：N 选 M 永远触不到阈值，或者 1 次选择就进 1 选档。前面第 3 节反复讲过。

**自查**：函数返回前，打印一次所有的 weight 和 confidence，对着第 3.2 节的对照表人肉核对。

### 坑 2：没有 ε-greedy，1 选档永远不出新

实现时觉得 "1 选档简单，先上线再说"，结果用户用了两周发现 AI 永远推同一类。典型的工程偷懒。

**自查**：对着线上日志查"过去 14 天推荐过的 topic 分布"，如果前 1 种占 > 90%，说明探索机制失效。

### 坑 3：没有时间衰减，1 年前的数据和昨天一样权重

用户口味会漂移。1 年前你写科普，现在你写娱乐——如果 weight 按 lifetime 累加，AI 会永远用"你 1 年前的自己"画像你。

薯灵的可选时间衰减：30 天前的 choice_log 记录，每超出 14 天 × 0.5 衰减。

```python
def time_decayed_count(log_entry: dict, today: date) -> float:
    delta_days = (today - log_entry["date"]).days
    if delta_days <= 30:
        return 1.0
    # 超出 30 天的部分，每 14 天衰减一半
    decay_steps = (delta_days - 30) // 14
    return 0.5 ** decay_steps
```

**自查**：老用户的 weight 分布和新用户差异是否合理。如果老用户的 weight 越来越固化，衰减机制可能没上。

### 坑 4：Pattern 没有淘汰机制，越堆越多

patterns.md 膨胀到 50 条以上，LLM 的 prompt 被塞满，生成质量直线下降。或者互相冲突的 pattern 让 LLM 陷入纠结。

**自查**：patterns.md 文件长度、Pattern 之间是否有逻辑冲突（比如"带问号"和"不带问号"同时在高 confidence 列表里）。

### 坑 5：回弹阈值设太高（比如 ≥ 5 次），用户早跑了

见过有团队把 `consecutive_rejects >= 5` 当触发条件，理由是"更稳健"。结果用户连续说 5 次换的时候，早就把 app 关了。

**自查**：看用户流失漏斗——在第几次 "换" 之后用户不再回来。那个数字就是你的触发上限。

---

## 9. 扩展到其他场景

这套组合拳不只适用于写作助手。本文的核心思路可以迁移到至少 4 个场景：

### 9.1 推荐系统：新用户冷启动

经典问题。老做法是"推默认热门榜"——但对用户画像没有任何学习速度。Laplace 先验天然解决：

```python
def recsys_score(chosen_in_category: int, shown_in_category: int) -> float:
    return (chosen_in_category + 1) / (shown_in_category + 2)
```

新用户 0/0 时所有品类 0.5，一次交互后开始分化。比冷启动用热门榜更个性化、比用 LLM 推断更有数学保障。

### 9.2 A/B 实验：置信区间

`concentration × sample_factor` 的设计思想和 A/B 实验的置信区间高度同构——都是 **效应大小 × 样本充分度**。你完全可以用这个公式做轻量版的"实验可信度"：两组转化率差距大（concentration 高）+ 样本量够（sample_factor 高）才给出"可发布"的置信信号。

### 9.3 Chatbot 偏好：用户反馈学习

用户在 chatbot 里给 👍 / 👎，本质也是 chosen / skipped 信号。把回复拆成 N 个维度（简洁度、风格、长度、是否用列表 ...），每个维度独立 Laplace 平滑，再用 confidence 决定生成策略。这就是一个可收敛的 chatbot tuning loop。

### 9.4 IDE 补全：采纳率权重

补全建议的 "accepted / shown" 是天然的 chosen / skipped。Laplace 平滑可以让新写的语言模型在小样本下不至于推荐质量崩坏。GitHub Copilot 的 telemetry 如果公开的话，大概率能看到类似设计。

共通的配方：

```text
1. 任何"用户选/跳"的场景 → Laplace 平滑做 weight
2. 任何"要不要收敛"的决策 → concentration × sample_factor 做 confidence
3. 任何"怕陷入局部最优"的场景 → ε-greedy 定期探索
4. 任何"用户反复拒绝"的场景 → 回弹机制主动降置信
```

---

## 10. 结语 + CTA

最后收一收。这篇文章的三句话：

> **小样本判决是 LLM 个性化最容易出错的地方——2 次选择就认定口味，和没学过一样。**

> **Weight 是对单个类型的倾向。Confidence 是对整个判断的信心。混用它们，是 AI 工程里最隐蔽的坑。**

> **LLM 负责理解和生成，数据驱动的公式负责决策和收敛。两者分工，互不越界。**

如果你在做 AI agent、chatbot、推荐系统、IDE 助手——任何需要"学用户口味"的产品——上面这套 Laplace + concentration × sample_factor + ε-greedy + 回弹机制可以直接抄。薯灵的 [SKILL.md §4.1](https://github.com/AI-flower/shuling/blob/main/SKILL.md) 有完整的原文、阈值、回退规则，也有所有参数的调优日志。

薯灵是 MIT 开源的，欢迎 Star、Issue、PR。我们也在讨论把这套偏好学习抽成一个独立的 skill，让任意 Claude / Codex agent 都能一行接入——进度会在 GitHub Discussions 同步。

---

## Related Links

- GitHub 仓库：[AI-flower/shuling](https://github.com/AI-flower/shuling)
- SKILL.md §4.1 完整算法：[SKILL.md](https://github.com/AI-flower/shuling/blob/main/SKILL.md)
- 系列第一篇：[Skill-as-Brain：把 AI 人格变成可版本化的资产](./blog-1-skill-as-brain.md)
- 系列第二篇：[给 AI Skill 设计的语义化版本号：BRAIN.HANDS.CALIB](./blog-2-semver.md)
- 参考阅读：
  - *Bayesian Methods for Hackers*（免费在线书）Chapter 6 关于 Beta-Binomial 先验的直观讲解
  - Sutton & Barto《Reinforcement Learning: An Introduction》第 2 章 Multi-Armed Bandits
  - Chris Anderson "The Long Tail"——为什么多样性和个性化必须共存
- 下一篇预告：**第四篇：薯灵的可复用治理——把产品偏好写成可升级的 Pattern 文件**
