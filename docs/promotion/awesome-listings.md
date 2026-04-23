# Awesome 列表一行介绍（多变体）

> 根据投放列表的主题和语言，挑合适变体。所有变体都 ≤100 字以内，遵循 Awesome 规范。

---

## 中文版

### 【通用版】偏架构向
```
- [shuling](https://github.com/AI-flower/shuling) — 小红书博主成长 AI Skill。Skill-as-Brain 架构，1208 行 SKILL.md 驱动选题→写稿→发布→复盘闭环；贝叶斯偏好学习自进化；三平台通用（Claude Code / Codex / Hermes）。
```

### 【awesome-claude-code / awesome-claude-skills 专用】
```
- [shuling](https://github.com/AI-flower/shuling) — 小红书运营 skill 参考实现。BRAIN.HANDS.CALIB 版本号、JSON Schema 契约、preflight 双模式、migrations 幂等——可借鉴的 skill 工程范式样板。
```

### 【awesome-ai-agents 专用】
```
- [shuling](https://github.com/AI-flower/shuling) — 单用户小红书博主助手 agent。完整自进化闭环：历史数据 → patterns 挖掘 → 偏好学习 → 选题加权 → 发布反馈。纯本地，MCP 集成。
```

### 【awesome-xiaohongshu / 小红书工具列表】
```
- [shuling](https://github.com/AI-flower/shuling) — AI 助手版小红书博主搭档。从选题到复盘全流程，越用越懂你。支持新博主冷启动 + 老博主存量接入（批量导入 200 条历史反推画像）。
```

### 【awesome-llm-apps / awesome-mcp-apps】
```
- [shuling](https://github.com/AI-flower/shuling) — LLM-native 小红书运营应用。通过 xiaohongshu-mcp + Gemini 3 Pro Image，演示"把业务写成 Markdown 而非代码"的 skill 范式。
```

---

## 英文版

### General (architecture-focused)
```
- [shuling](https://github.com/AI-flower/shuling) — Xiaohongshu creator-growth AI skill. Skill-as-Brain architecture: 1208-line SKILL.md drives full loop (topic → draft → publish → retrospect). Bayesian preference learning. Runs on Claude Code / Codex / Hermes.
```

### awesome-claude-code / awesome-skills
```
- [shuling](https://github.com/AI-flower/shuling) — Reference implementation for production-grade Claude skills. Features BRAIN.HANDS.CALIB semver, JSON Schema contracts, dual-mode preflight (JSON/human), idempotent migrations.
```

### awesome-ai-agents
```
- [shuling](https://github.com/AI-flower/shuling) — Single-user Xiaohongshu creator agent with full self-evolution loop: historical data → pattern mining → preference learning → weighted topic selection → publish feedback. Fully local, MCP-integrated.
```

### awesome-llm-apps
```
- [shuling](https://github.com/AI-flower/shuling) — LLM-native Xiaohongshu operations app. Demonstrates "business logic in Markdown, not code" skill paradigm via xiaohongshu-mcp + Gemini 3 Pro Image.
```

### awesome-mcp-servers (as MCP consumer)
```
- [shuling](https://github.com/AI-flower/shuling) — MCP-consuming AI skill (not server). Uses xiaohongshu-mcp for platform ops; shows how to build production agents on top of MCP tools with safety rails, quota profiles, request logging.
```

---

## 目标 Awesome 列表清单（PR 批次）

### 第一批（高匹配，优先投）
| 列表 | URL | 提交方式 |
|---|---|---|
| awesome-claude-code | https://github.com/hesreallyhim/awesome-claude-code | Fork + PR |
| awesome-ai-agents | https://github.com/e2b-dev/awesome-ai-agents | Fork + PR |
| awesome-llm-apps | https://github.com/Shubhamsaboo/awesome-llm-apps | Fork + PR |

### 第二批（弱相关，按条件投）
| 列表 | 策略 |
|---|---|
| awesome-mcp-servers | 注明"MCP consumer 示例"，可能被拒但值得试 |
| awesome-chinese-llm | 中文领域专用 |
| awesome-generative-ai-guide | 架构话题分类 |

### 第三批（细分领域）
| 列表 | 策略 |
|---|---|
| awesome-xiaohongshu（如存在） | 直接投，匹配度最高 |
| awesome-social-media-tools | 投"AI-native"分类 |

---

## PR 描述模板（awesome 列表通用）

```markdown
## New entry: shuling (薯灵)

Adds shuling — a production-grade AI skill for Xiaohongshu (RED) creator workflow automation.

### Why this fits

- Full self-contained agent loop (topic research → drafting → image gen → publish → retrospect)
- Distinctive "Skill-as-Brain" architecture: business logic in 1208-line Markdown, scripts only handle I/O
- Active development (71 commits, 8 releases in 2 months)
- MIT licensed, fully local, no telemetry
- Works across Claude Code / Codex / Hermes

### Checklist
- [x] Active repository (last commit < 7 days)
- [x] Clear README with install/usage
- [x] Licensed (MIT)
- [x] Passes language conventions for this list
```

---

## 提交礼仪

1. **先 star 再 PR**：被 merge 后也是一次站内流量
2. **按列表分类放对位置**：有的按字母序、有的按热度，仔细看上下文
3. **一次一个 PR**：不要把多个加入合并到一个 PR，会让 reviewer 难搞
4. **回应 reviewer 要快**：维护者通常当周活跃，错过窗口要等几周
