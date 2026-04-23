---
title: 薯灵文档目录索引
status: active
created: 2026-04-23
maintainer: team
---

# 薯灵 `docs/` 目录索引

> 本目录按**文档生命周期**与**用途**分层。2026-04-23 v2.4.0 docs 重组后生效。
> 业务流程、发版流程、使用说明请看根目录。

## 目录结构

```
docs/
├── adr/          # Architecture Decision Records — 架构决策记录
├── plans/        # 活跃的实施计划与特性设计
├── runbooks/     # 安装、部署、运维操作手册
├── reference/    # 参考资料（能力清单、API 概览等）
└── archive/      # 已完成 / 已废止 / 已被取代的历史文档
```

## 子目录用途

| 目录 | 写什么 | 不写什么 |
|---|---|---|
| `adr/` | 影响架构/系统形态的关键决策、原则、tradeoff | 日常 plan、运维操作 |
| `plans/` | 尚未完成、仍在追踪的 Implementation Plan 或特性设计 | 已发版完成的（→ `archive/`） |
| `runbooks/` | 一步步照做的操作指南（安装、配置、诊断） | 设计理由、权衡讨论 |
| `reference/` | 静态、查阅性资料（能力清单、术语表、接口表） | 随时间变化的状态、计划 |
| `archive/` | 历史文档，均含归档说明 block 与 frontmatter | 任何仍需追踪的工作 |

## 入口文档快速指引

| 你想了解… | 入口 |
|---|---|
| **业务流程 / 日常操作** | 根目录 `SKILL.md` |
| **当前发版状态** | 根目录 `CHANGELOG.md` + `VERSION` |
| **v2.4.0 优化路线图** | [`plans/2026-04-21-project-optimization-roadmap.md`](plans/2026-04-21-project-optimization-roadmap.md) |
| **升级基础设施设计** | [`adr/agent-upgrade-design.md`](adr/agent-upgrade-design.md) |
| **知识库健康诊断** | [`adr/2026-04-23-kb-health-diagnosis.md`](adr/2026-04-23-kb-health-diagnosis.md) |
| **xiaohongshu-mcp 安装配置** | [`runbooks/mcp-setup.md`](runbooks/mcp-setup.md) |
| **完整能力清单** | [`reference/capability-overview.md`](reference/capability-overview.md) |
| **已有账号接入（v2.2.0）** | [`plans/existing-creator-onboarding.md`](plans/existing-creator-onboarding.md) （archived） |
| **历史 plan / spec** | [`archive/`](archive/) |

## 文档头部约定

所有本目录下的 `.md` 文件都应携带 YAML frontmatter：

```yaml
---
title: <文档标题>
status: active | archived
moved_from: <原路径，若曾移动>
moved_at: <YYYY-MM-DD，若曾移动>
original_date: <首次创建日期，若知道>
---
```

归档文件额外在正文第一段加"归档说明"block，注明 reason（completed / superseded / obsolete）与替代文档链接。含 checkbox 的归档 plan 额外声明 "Checkbox 状态 reconcile"。

## 归档原则

出现以下情况把文档移入 `archive/`：

- **completed** — 该计划/特性已发版落地，`CHANGELOG.md` 有对应条目
- **superseded** — 已有更新的设计/规格接替，保留原文仅为脉络
- **obsolete** — 未落地且当前架构已偏离，需要继续追踪的另开新 plan

归档文档不再勾选 checkbox、不再更新内容，只读。
