---
id: 03-daily-flow
title: Daily Flow (Topic → Draft → Image)
when:
  - "用户问今天发什么"
  - "用户说帮我写一条"
  - "cron 触发午间档/晚间档"
needs:
  required:
    - agent/knowledge-base/profile.json
    - agent/knowledge-base/preferences.json
    - agent/knowledge-base/patterns.md
    - agent/policies/content-rules.md
    - agent/playbook/_shared/emoji-dictionary.md
    - agent/playbook/_shared/confidence-mapping.md
    - agent/playbook/_shared/outline-template.txt
  db_tables:
    - posts
    - user_choices
  env_vars:
    - IMAGE_GEN_API_KEY
    - MCP_URL
calls:
  scripts:
    - agent/scripts/db.sh
    - agent/scripts/xhs.sh
    - agent/scripts/image.py
  playbooks:
    - 04-publish-flow.md
    - 06-learning-loop.md
    - 08-compliance.md
    - 09-troubleshooting.md
writes:
  files:
    - agent/data/xhs.db (user_choices)
  emits:
    - draft_ready
preconditions:
  - state.setup_completed == true
  - state.cold_start_done == true
on_failure:
  - 09-troubleshooting.md
version: 3.0.0
last_updated: 2026-04-27
---

# 03 Daily Flow

每天执行两次（午间档 + 晚间档），每次走完完整流程：选题研究 → 草稿生成 → 图片生成。下游 04 接管发布。

**核心心法**（贯穿 §2.2 草稿生成全流程）：

1. **图为主，文为辅**：小红书用户在信息流里只看封面 → 点进去主要划图 → 正文很多人不看。所以**图片才是信息载体**（每页装一个完整信息点），正文只是"上下文胶水 + 收藏理由"。
2. **结构化卡片，不写大段文字**：每页 4-8 行就够，留白多，不堆砌。
3. **emoji 是结构标记，不是装饰**：用语义 emoji 引导视觉锚点（→ `agent/playbook/_shared/emoji-dictionary.md`）。
4. **禁用 markdown**（小红书不渲染）：直接用纯文本 + emoji + 简单符号（• / ✅ / ⚠️）。

## Trigger

- 用户主动："今天发什么 / 帮我写一条 / 我要发小红书"
- cron：午间档（默认 12:00）和晚间档（默认 19:30）由 hermes cron 唤起
- 上游 `02-cold-start.md` 完成后 `cold_start_done == true` 起，本 playbook 进入常规调度

## Read This When

- `state.setup_completed == true` 且 `state.cold_start_done == true`
- 不要在选题阶段调用 publish（那是 → `04-publish-flow.md` 的职责）
- 不要重复问画像；`profile.json` 已存在则直接读

## Inputs

- `agent/knowledge-base/profile.json` — 博主画像（领域 / 受众）
- `agent/knowledge-base/preferences.json` — 偏好权重 + 当前 `confidence_level`
- `agent/knowledge-base/patterns.md` — 文字 pattern 库
- `agent/knowledge-base/image-patterns.md`（可选） — 图片 pattern 库
- `agent/policies/content-rules.md` — 合规规则（draft-time 摘要见下文）
- 用户原始主题（如已选定）

**Draft-time 合规摘要**（≤15 行，权威定义见 → `agent/playbook/08-compliance.md`）：

- 标题/正文不出现绝对化词（"最 / 第一 / 唯一 / 国家级"等）
- 不做医疗、金融、法律、考试通过、减肥效果等承诺
- 不出现引战、擦边、政治敏感、未成年人不当内容
- 引用他人作品/观点要标明来源
- 商业内容（含品牌名 / 链接 / 折扣码）按"是否带货"做标记，让 §2.4 决定是否切到 `is_original=false`
- 不抄袭其他平台原文，转述也要重写
- emoji 总量受控（标题 1-2 个；正文每段 ≤1 个）
- 完整规则、禁用词列表、灰区判定 → `agent/playbook/08-compliance.md`

## Procedure

### 2.1 Topic Research

**步骤**：

1. **读取知识库**
   - `agent/knowledge-base/profile.json` → 了解博主领域和受众
   - `agent/knowledge-base/preferences.json` → 了解用户偏好权重和当前信心度
   - `agent/knowledge-base/patterns.md` → 了解有效 pattern

2. **获取候选选题**（按博主领域选择通用数据源）

   - 用 WebSearch 搜索该领域的最新热点、季节节点、用户需求和趋势变化
   - 用 `agent/scripts/xhs.sh recommend` 获取推荐流中的相关内容
   - 用 `agent/scripts/xhs.sh search "领域关键词"` 搜索当前热门话题
   - 回看最近评论与 `comment_insights`，把高频提问、吐槽和需求转成候选选题
   - 如果该领域有明确外部信号源，可补充 1-2 个垂直来源（如电商榜单、节假日热点、城市活动、招聘趋势、品牌新品），但不要默认绑定任何单一行业或平台来源

3. **去重过滤**
   - 调 `agent/scripts/db.sh query-posts --days 30` 获取最近发布过的帖子
   - 排除已发布过的选题

4. **对每个候选打分**（你自己判断，参考以下维度）
   - **受众匹配度**（0-30分）：与 profile.json 的受众是否一致
   - **内容可写性**（0-25分）：能否写成具体的教程/清单/故事，而不是空泛的介绍
   - **竞品密度**（0-25分）：用 `agent/scripts/xhs.sh search "候选关键词"` 检查，结果少=蓝海=高分
   - **用户偏好匹配**（0-20分）：与 preferences.json 中高权重的主题类型是否一致

5. **决定输出选题数量**：根据 `confidence_level` 决定输出 1/2/3 个候选；信心度→数量的映射、`last_exploration_at` 探索项追加、`consecutive_rejects` 强制回退三套规则统一在 → `agent/playbook/_shared/confidence-mapping.md`。weight 与 confidence 公式权威定义在 → `agent/playbook/06-learning-loop.md`。

6. **返回选题列表**
   - 每个选题包含：主题名 + 一句话推荐理由 + 竞品密度（"蓝海"/"中等"/"红海"）
   - 如果只 1 个：附加"回复'换'我再找一个"
   - 输出后等待用户回应（hermes 负责把内容送到用户，并把回复喂回来）

7. **记录用户选择**
   ```bash
   agent/scripts/db.sh log-choice '{"choice_type":"topic","offered_count":3,"chosen_index":2,"chosen_label":"办公室收纳","skipped_labels":"[\"通勤穿搭\",\"周末亲子活动\"]"}'
   ```

### 2.2 Draft Generation

用户选定选题后，**分两步**生成草稿：先出大纲（决定每页装什么信息 + 配图建议），再出文案（标题/正文/标签的最终文本）。这是借鉴 RedInk 的核心范式——**不是写一篇推文，是写一组卡片**。

> Emoji 词典（按语义用，不要乱花；标题 1-2 个、正文每段 ≤1 个、不要 4 个 emoji 排排坐）→ `agent/playbook/_shared/emoji-dictionary.md`

**第 1 步：读取规则**

```bash
cat agent/policies/content-rules.md  # 合规
cat agent/knowledge-base/patterns.md 2>/dev/null  # 文字 pattern 库
cat agent/knowledge-base/profile.json  # 博主画像
```

**第 2 步：生成大纲**（每页一个信息点 + 配图建议）

按下面的格式输出 6-9 页大纲。**严格用 `<page>` 分隔**，每页第一行写类型 `[封面] / [内容] / [总结]`，**最后一行**写"配图建议：xxx"（图像生成会读这一行）。

> 完整范例（手冲咖啡，~70 行）→ `agent/playbook/_shared/outline-template.txt`，照这个结构仿写。

**大纲硬规则**：

- 6-9 页（封面 1 + 内容 4-7 + 总结 1）
- 每页只装**一个**信息点（步骤/工具/技巧/对比）
- 每页 4-8 行，超过 10 行就拆页
- 列表用 `•` 不用 `-`（小红书更常见）
- 数字+单位连写（`92-96℃` 不要 `92 - 96 ℃`）
- emoji 按词典用，不堆砌
- **禁止**任何 markdown（`#` `**` `[]()` 都不要）
- 最后一行强制 `配图建议：xxx`

**第 3 步：基于大纲生成最终文案**（标题 + 正文 + 标签）

按下面的 JSON 严格输出（这是给数据库存的，不是给用户看的）：

```json
{
  "titles": [
    "主推标题（最吸眼球，15-25 字，1 个 emoji，用爆款技巧）",
    "备选标题 1",
    "备选标题 2"
  ],
  "copywriting": "正文 200-300 字，开头 hook，分段 2-4 行，emoji 适度，结尾互动引导",
  "tags": ["主标签", "热门 1", "热门 2", "精准 1", "精准 2", "长尾"]
}
```

**标题硬规则**（3 个候选）：
- 长度 15-25 字（不超 30）
- 用 5 种**爆款技巧**至少 1 种：
  - 数字（`5 个`/`3 步`/`10 分钟`）
  - 疑问（`为什么...`/`你不知道...`）
  - 惊叹（`绝了！`/`真香警告`）
  - 对比（`vs`/`不再是`/`从 0 到 1`）
  - 痛点（`再也不用`/`告别 X`/`一键解决`）
- 1-2 个 emoji（主题相关）
- 第一个是主推，差异化明显

**正文硬规则**（200-300 字，**不超 500**）：
- 开头 1-2 行 **hook**（共鸣痛点 / 悬念 / 反直觉），抓住"不滑走"那 3 秒
- 中段分 2-3 个小段，每段 2-4 行，**段间空一行**
- 适度 emoji（每段最多 1 个，结构标记优先用 💡⚠️✅）
- 结尾 1 行**互动引导**（`你们也试试？` / `评论区聊聊` / `还有什么坑没踩过的？`）
- **不写大纲已经在图里的内容**（图说步骤、文说感受/原因/补充）
- **禁用 markdown**

**标签硬规则**（5-8 个，**不带 # 号**，逗号分隔或数组）：
- 第 1 个是**主标签**（领域核心词）
- 2-3 个**热门大标签**（流量入口）
- 2-3 个**精准小众标签**（目标受众）
- 1 个**长尾标签**（差异化）

**第 4 步：决定输出份数**：信心度→份数映射 + `consecutive_rejects ≥ 1` 强制 2 份等回退规则 → `agent/playbook/_shared/confidence-mapping.md`。weight/confidence 公式 → `agent/playbook/06-learning-loop.md`。

**第 5 步：返回给用户**

把大纲（用户看结构）+ 文案（用户看最终文字）一起展示。
- 如果 2 份："选 1 还是 2？"
- 如果 1 份："回复'发'确认，或'换'重新生成"

**第 6 步：记录用户选择**

```bash
agent/scripts/db.sh log-choice '{"choice_type":"draft","offered_count":2,"chosen_index":1,"chosen_label":"清单体","skipped_labels":"[\"教程体\"]"}'
```

> **下一步：第 2.3 节图像生成**会**直接吃这份大纲**——每页的"配图建议"行会成为该页图像的 prompt。所以大纲写得越具体、越视觉化，图越好。

### 2.3 Image Generation

用户确认草稿后，生成配图。

> **核心范式（向 RedInk 5.2k⭐ 学的）**：中文 prompt 模板 + "小红书"锚词 + 两阶段参考图。**不翻译成英文**、**不禁止 AI 画文字**、**每张图都带完整大纲**。这三条是让生图"像小红书"的根因。

**步骤**：

1. **准备工作区 + 整篇大纲落盘**

   生图模板需要"整篇大纲原文"作为上下文，所以先把 2.2 节生成的大纲写到文件里：
   ```bash
   mkdir -p /tmp/xhs-post
   # 把 2.2 节最终确认的大纲原文（含所有 <page> 分隔 + 配图建议行）写进去
   cat > /tmp/xhs-post/outline.txt <<'OUTLINE_EOF'
   <整篇大纲原文粘贴到这里>
   OUTLINE_EOF
   ```

2. **读图片 pattern 库（可选增益）**
   ```bash
   cat agent/knowledge-base/image-patterns.md 2>/dev/null  # 没有就跳过
   ```
   - 如有 `confidence ≥ medium` 的 pattern → 把 pattern 描述**追加到该页 `--page-content` 末尾**（不是替换 prompt，是作为补充视觉线索）
   - 没有就跳过——模板里的"小红书爆款图文风格"锚词已经足够
   - confidence 阈值定义 → `agent/playbook/06-learning-loop.md`

3. **检查图片生成能力**
   ```bash
   python3 agent/scripts/image.py --check
   ```
   - 返回 0 → 走 AI 生图（下面的第 4 步）
   - 返回 2 → **硬停**。告诉用户："图像生成 API Key 未配置，薯灵需要图像生成 API（Gemini 或 OpenAI gpt-image-2，二选一）才能继续"，不要尝试降级任何 HTML 截图路径

4. **AI 生图路径**（中文模板驱动，两阶段生成）

   **强制使用结构化 CLI**（加载 `agent/prompts/image_prompt.txt`，自动注入 4 变量）：

   ```bash
   # 阶段 a：封面（无参考图）
   python3 agent/scripts/image.py \
       --page-type "封面" \
       --page-content "$(extract_page_content_from_outline 1)" \
       --outline-file /tmp/xhs-post/outline.txt \
       --topic "<用户原始主题原文>" \
       --output /tmp/xhs-post/page-1.png

   # 阶段 b：每张内容页带封面作参考图
   python3 agent/scripts/image.py \
       --page-type "内容" \
       --page-content "$(extract_page_content_from_outline 2)" \
       --outline-file /tmp/xhs-post/outline.txt \
       --topic "<用户原始主题原文>" \
       --output /tmp/xhs-post/page-2.png \
       --reference /tmp/xhs-post/page-1.png

   # 总结页
   python3 agent/scripts/image.py \
       --page-type "总结" \
       --page-content "<总结页大纲原文>" \
       --outline-file /tmp/xhs-post/outline.txt \
       --topic "<用户原始主题原文>" \
       --output /tmp/xhs-post/page-N.png \
       --reference /tmp/xhs-post/page-1.png
   ```

   **参数硬规则**：
   - `--page-type` **只能是** `封面` / `内容` / `总结` 三选一（模板按这三型激活不同子约束）
   - `--page-content` = 2.2 节大纲里该页的**完整原文**（包括 `配图建议：xxx` 那一行，一起喂进去）
   - `--outline-file` = **必传**。让模型看到全篇上下文，自动协调跨页视觉
   - `--topic` = 用户原始输入，给模型定方向
   - 非封面页**必须** `--reference <封面路径>`，这是多页风格统一的核心

   **提示词理念**（跟 RedInk 对齐，**不要违反**）：
   - **禁止自己写英文 prompt**——模板已经是中文的 77 行完整约束
   - **禁止说"不要包含文字"**——Gemini 3 Pro 的中文字形渲染已过关，强制"文字必须完整呈现"反而更像小红书
   - **禁止用 `IMAGE_BRAND_STYLE` 拼前缀**——模板里"小红书爆款图文风格"这个锚词就是品牌风格的最高表达
   - **推荐模型**：`gemini-3-pro-image-preview`（Nano Banana Pro，中文文字 + multimodal 参考图都最准）

   **极短 prompt 兜底**（仅当 API 上下文受限）：加 `--short` 切到 `agent/prompts/image_prompt_short.txt`（6 行极简版）。

   **记录**：每张图生成后，写到 `generated_images` 表（自进化的数据基础）：
   ```bash
   sqlite3 agent/data/xhs.db "INSERT INTO generated_images (post_id, image_index, prompt, image_path, gen_model, gen_strategy, gen_status) VALUES (<post_id>, <0/1/2...>, '<该页 page_content 原文，不用存整个渲染后 prompt>', '<绝对路径>', '<model 名>', 'ai', 'success');"
   ```
   存 `page_content`（短）而不是整个渲染后 prompt（长且重复），既节省空间又便于 pattern 学习。

5. **组装 meta.json**

   将草稿内容和图片路径组装为发布数据，写入 `/tmp/xhs-post/meta.json`。完整字段定义（title / content / tags / images / is_original 等） → `agent/playbook/_shared/post-meta-schema.json`。

## Writes

- `agent/data/xhs.db`：
  - `user_choices`（topic 选择 + draft 选择）
  - `generated_images`（每张图一行）
- `/tmp/xhs-post/`（每次运行新建）：
  - `outline.txt`（整篇大纲原文）
  - `page-1.png ... page-N.png`
  - `meta.json`（→ 04 直接消费）
- 事件：`draft_ready` 触发 → `04-publish-flow.md`

## Failure Handling

- 任何 `agent/scripts/xhs.sh` / `agent/scripts/image.py` 调用非零退出 → 转 → `09-troubleshooting.md`
- `image.py --check` 返回 2 → **硬停**，提示用户配置图像生成 API Key（Gemini 或 OpenAI gpt-image-2），不降级 HTML
- WebSearch / `xhs.sh search` 节流命中 → 用现有 `comment_insights` + `patterns.md` 兜底，本轮少出 1 个候选可接受
- AI 模型 API 报错最多 1 次重试（→ `agent/playbook/09-troubleshooting.md`）

## Anti-Patterns

- 不在选题阶段调用 publish_content
- 不复述 weight/confidence 公式（cross-ref → 06-learning-loop.md）
- 不跳过合规检查（必读 agent/policies/content-rules.md）
- 不复述 emoji 词典（cross-ref → _shared/emoji-dictionary.md）
- 不在本文件 inline 大纲咖啡范例（cross-ref → _shared/outline-template.txt）
- 不在本文件 inline meta.json 字段表（cross-ref → _shared/post-meta-schema.json）
- 不自己写英文图像 prompt、不禁止 AI 画文字、不拼 `IMAGE_BRAND_STYLE` 前缀
- 不把信心度→数量映射规则在本文件抄第二遍（cross-ref → _shared/confidence-mapping.md）

## Cross-Refs

- → `agent/playbook/04-publish-flow.md`（草稿确认后接管发布）
- → `agent/playbook/06-learning-loop.md`（weight / confidence 公式权威）
- → `agent/playbook/08-compliance.md`（完整合规规则）
- → `agent/playbook/09-troubleshooting.md`（脚本失败 / 节流 / 重试）
- → `agent/playbook/_shared/emoji-dictionary.md`
- → `agent/playbook/_shared/outline-template.txt`
- → `agent/playbook/_shared/confidence-mapping.md`
- → `agent/playbook/_shared/post-meta-schema.json`
