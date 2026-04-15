---
name: xhs-content-generator
description: 根据主题自动搜索资料，生成多页小红书风格内容图（封面 + 内容页），3:4 竖版比例，Playwright 截图输出 PNG
triggers:
  - 小红书内容图
  - xhs 内容
  - 生成小红书图文
  - 小红书多页图
version: 1.0.0
author: yl
---

# 小红书内容图生成器

根据用户提供的主题，自动搜索最新资料，生成多页小红书风格内容图片（封面 + 多页内容卡片）。

## 使用方式

```
/xhs-content-generator <主题>
/xhs-content-generator <主题> --pages <页数> --style <风格>
```

示例：
- `/xhs-content-generator OpenClaw 技能分享`
- `/xhs-content-generator React 19 新特性 --pages 5`
- `/xhs-content-generator 比特币减半分析 --style dark`

## 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| 主题 | 必填 | 内容主题关键词 |
| --pages | 5-6 | 生成页数（含封面，最少 3 页，最多 8 页） |
| --style | warm | 风格：warm（暖橙卡通）/ dark（深色科技）/ minimal（简约白） |
| --output | 当前工作目录 | 输出目录路径 |

## 执行流程

### 第 1 步：搜索资料

使用 WebSearch 搜索主题相关的最新信息，收集：
- 核心概念和定义
- 关键数据和统计
- 分类/列表信息
- 最新趋势和动态
- 实用建议/教程

**搜索策略：**
- 至少进行 2 次搜索（中文 + 英文）
- 优先获取 2026 年最新数据
- 如有官方文档，用 WebFetch 获取详细内容

### 第 2 步：规划内容结构

根据搜索结果，规划 N 页内容（含封面）：

**固定结构：**
- 第 1 页：封面（标题 + 副标题 + 核心数据 + 吉祥物/图标）
- 第 2 页：概念介绍（是什么 + 工作原理）
- 第 3-N-1 页：核心内容（分类/排行/教程/趋势等，根据主题灵活安排）
- 最后一页：总结/行动指南 + CTA（收藏点赞引导）

**内容原则：**
- 每页 2-4 个信息模块，不能太密
- 标题简短有力，正文口语化
- 善用 emoji 增加趣味性
- 数据要有来源支撑

### 第 3 步：生成 HTML

生成一个包含所有页面的 HTML 文件。

**HTML 规范：**
- 每页用 `<div class="page pageN">` 包裹
- 固定尺寸：1080px × 1440px（3:4 比例）
- 使用 Google Fonts：Noto Sans SC（中文）+ Inter（英文）
- 页面之间用 `gap: 40px` 分隔
- body 使用 `display: flex; flex-direction: column; align-items: center;`

**三种风格的 CSS 变量：**

**warm（暖橙卡通，默认）：**
- 背景：#FFFBF5（内容页）/ 暖橙渐变（封面）
- 主色：#FF6348
- 卡片：白色圆角，轻阴影
- 装饰：emoji + blob 背景 + 星星

**dark（深色科技）：**
- 背景：#0f0c29 → #302b63 渐变
- 主色：金色渐变 #f7971e → #ffd200
- 卡片：半透明玻璃态
- 装饰：光晕 + 网格线

**minimal（简约白）：**
- 背景：#FFFFFF
- 主色：#333333
- 卡片：细线边框，无阴影
- 装饰：极简线条

**页面组件库（在 HTML 中直接使用的 CSS class）：**

```
.page-header       → 页面顶部标题栏（序号 + 标题）
.info-card          → 信息卡片（左边框高亮）
.cat-grid           → 2列分类网格
.cat-card           → 分类卡片（图标 + 名称 + 数量）
.skill-list         → 排行榜列表
.skill-item         → 排行榜条目（序号 + 内容 + 标签）
.trend-card         → 趋势卡片（图标 + 标题 + 徽章 + 描述）
.warning-box        → 警告提示框
.code-block         → 代码块（深色背景）
.tip-card           → 提示卡片（绿色背景）
.cta-box            → 行动号召框（渐变背景）
.diagram-box        → 流程图容器（深色背景）
.stats-row          → 数据统计行
.stat-card          → 单个统计卡片
.page-footer        → 页脚（页码）
```

### 第 4 步：Playwright 截图

使用 Playwright 逐页截图，生成独立的 PNG 文件。

**截图脚本路径：** `{{SKILL_DIR}}/scripts/screenshot.cjs`

**执行命令：**
```bash
NODE_PATH="$(npm root -g)" node {{SKILL_DIR}}/scripts/screenshot.cjs <html_file_path> <output_dir>
```

**截图规范：**
- viewport: 1080 × 10000（足够容纳所有页面）
- 用 `.page` selector 逐个定位每页元素
- 输出命名：`xhs-<主题缩写>-page-<N>.png`

### 第 5 步：清理 & 输出

1. 删除临时 HTML 文件
2. 列出所有生成的 PNG 文件
3. 用 Read 工具展示每张图片给用户预览
4. 报告完成信息

## 输出示例

```
<output_dir>/
├── xhs-openclaw-page-1.png    # 封面
├── xhs-openclaw-page-2.png    # 概念介绍
├── xhs-openclaw-page-3.png    # 分类一览
├── xhs-openclaw-page-4.png    # 热门排行
├── xhs-openclaw-page-5.png    # 趋势分析
└── xhs-openclaw-page-6.png    # 安装指南
```

## 依赖

- Node.js（已安装）
- Playwright Chromium（需已安装到本机，可通过 `npx playwright install chromium` 安装）
- NODE_PATH: 建议使用 `npm root -g` 的输出，或在环境变量里显式指定

## 注意事项

- 不需要任何 API Key，完全本地运行
- 图片尺寸固定 1080×1440（小红书标准 3:4）
- 内容页背景默认浅色，封面可用渐变色
- 所有文字使用 Google Fonts，确保中英文渲染美观
- 如果 Playwright 报错 browser not found，运行：`npx playwright install chromium`
