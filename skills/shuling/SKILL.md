---
name: shuling
description: |
  小红书内容工具。使用场景：
  - 搜索小红书内容
  - 获取首页推荐列表
  - 获取帖子详情（包括互动数据和评论）
  - 发表评论到帖子
  - 获取用户个人主页
  - "跟踪一下小红书上的XX热点"
  - "分析小红书上关于XX的讨论"
  - "小红书XX话题报告"
  - "生成XX的小红书舆情报告"
---

# 小红书 MCP Skill

基于 [xiaohongshu-mcp](https://github.com/xpzouying/xiaohongshu-mcp) 封装。

> **完整文档请查看 [README.md](README.md)**

## 快速参考

| 脚本 | 用途 |
|------|------|
| `install-check.sh` | 检查依赖是否安装 |
| `start-mcp.sh` | 启动 MCP 服务 |
| `stop-mcp.sh` | 停止 MCP 服务 |
| `status.sh` | 检查登录状态 |
| `search.sh <关键词>` | 搜索内容 |
| `recommend.sh` | 获取推荐列表 |
| `post-detail.sh <feed_id> <xsec_token>` | 获取帖子详情 |
| `comment.sh <feed_id> <xsec_token> <内容>` | 发表评论 |
| `user-profile.sh <user_id>` | 获取用户主页 |
| `track-topic.sh <话题> [选项]` | 热点跟踪报告 |
| `export-long-image.sh` | 帖子导出为长图（白底黑字+图片拼接） |
| `mcp-call.sh <tool> [args]` | 通用工具调用 |

## 快速开始

```bash
cd scripts/

# 1. 检查依赖
./install-check.sh

# 2. 启动服务
./start-mcp.sh

# 3. 检查状态
./status.sh

# 4. 搜索内容
./search.sh "春节旅游"
```

## MCP 工具

| 工具名 | 描述 |
|--------|------|
| `check_login_status` | 检查登录状态 |
| `search_feeds` | 搜索内容 |
| `list_feeds` | 获取首页推荐 |
| `get_feed_detail` | 获取帖子详情和评论 |
| `post_comment_to_feed` | 发表评论 |
| `reply_comment_in_feed` | 回复评论 |
| `user_profile` | 获取用户主页 |
| `like_feed` | 点赞/取消 |
| `favorite_feed` | 收藏/取消 |
| `publish_content` | 发布图文笔记 |
| `publish_with_video` | 发布视频笔记 |

## 热点跟踪

```bash
./track-topic.sh "DeepSeek" --limit 5
./track-topic.sh "春节旅游" --limit 10 --output report.md
./track-topic.sh "iPhone 16" --limit 5 --feishu
```

## 长图导出

搜索结果或帖子详情导出为带文字注释的 JPG 长图：

```bash
# 准备 posts.json（搜索+拉详情后整理）
cat > posts.json << 'EOF'
[
  {
    "title": "帖子标题",
    "author": "作者名",
    "stats": "1.3万赞 100收藏",
    "desc": "正文摘要，支持\n换行",
    "images": ["https://...webp", "https://...webp"],
    "per_image_text": {"1": "第2张图的专属说明"}
  }
]
EOF

./export-long-image.sh --posts-file posts.json -o output.jpg
```

样式：白底黑字（模仿小红书原样），每个帖子前有文字块（标题+作者+正文），帖子间有分隔线。

**per_image_text** 可选：如果原帖文字明确指向某张图（如"图7-9是青龙桥"），把说明放在对应图片上方。未指定则所有文字集中在文字块。

**字体**：自动检测系统中文字体（STHeiti > Hiragino > Arial Unicode > Noto CJK）。

## 注意事项

- 首次运行会下载 headless 浏览器（~150MB）
- 同一账号避免多客户端同时使用
- 发布限制：标题≤20字符，正文≤1000字符，日发布≤50条
- Linux 服务器需要从本地获取 cookies，详见 [README.md](README.md)

## 自进化知识库

本 Skill 具备跨周期学习能力，通过 knowledge-base/ 目录积累运营经验。

### 首次初始化

如果 `knowledge-base/README.md` 不存在（相对 skill 根目录），按顺序执行：

**第一步：配置 LLM**

询问用户：
> 这个子 skill 仅做小红书 MCP 调用。如果作为薯灵主 skill 的一部分使用，主 SKILL.md 会负责 LLM 决策。
> 请选择：
> 1. Claude API (Anthropic)
> 2. OpenAI API
> 3. 兼容 OpenAI 格式的其他服务（DeepSeek/通义/本地模型等）

根据选择，编辑 `config/runtime.env` 中的 LLM_PROVIDER、LLM_API_KEY、LLM_BASE_URL、LLM_MODEL。

**第二步：竞品分析播种**

1. 用 search_feeds 搜索 3 组关键词：
   - "GitHub 开源项目推荐"
   - "AI工具 推荐 教程"
   - "程序员 效率工具"
2. 每组取互动量 top 5，共约 15 条
3. 对 top 10 调 get_feed_detail 获取完整内容
4. 归纳提取：
   - 标题模式 3-5 个（模板 + 示例 + 适用场景）
   - 正文结构 2-3 个
   - 高频标签 top 10
   - 互动引导话术 2-3 个
5. 写入文件：
   - `knowledge-base/patterns.md`（初始 pattern，标记 source: competitor, confidence: low）
   - `knowledge-base/rules.json`（初始规则，合并 data/content-rules.md 中的约束）
   - `knowledge-base/README.md`（索引，阶段: cold-start）

### 创作时的知识读取

进行选题或内容创作前：

1. 读 `knowledge-base/README.md` — 了解当前阶段和有效 pattern 摘要
2. 读 `knowledge-base/patterns.md` — 获取活跃 pattern 详情
3. 融入创作思考：
   - confidence 为 high/medium 的 pattern 优先参考
   - cold-start 阶段 competitor 来源的 pattern 权重较低，鼓励探索
   - 不要机械套模板，pattern 是方向参考，结合选题灵活调整
4. 如果 `knowledge-base/reviews/` 下有最近的周复盘，浏览关键发现

### 知识库维护

知识库的定期更新由薯灵主 skill 的每日复盘流程负责（详见薯灵主 SKILL.md 第 3 节），由助手按 SKILL.md 决策、调用 fetch-metrics/fetch-comments/noterx-diagnose 等脚本完成。

但如果用户在交互中明确要求（如"分析一下最近的数据"、"更新知识库"），可以手动读取 data/exports/ 下的数据文件，执行分析并更新 knowledge-base/。
