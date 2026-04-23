# 架构图（3 张 Mermaid）

> 用 https://mermaid.live 粘贴导出 SVG/PNG，放 README 顶部或博客配图。
> 或本地 `mmdc -i diagram.mmd -o diagram.svg -b transparent`。

---

## 图 1 · 全景架构（Skill-as-Brain）

这是最"招牌"的一张，放 README 顶部或 landing 首屏。

```mermaid
flowchart TB
    subgraph AI["🧠 AI Agent (Claude Code / Codex / Hermes)"]
        SKILL[SKILL.md<br/>1208 行<br/>业务大脑]
    end

    subgraph Hands["✋ scripts/ (手脚层)"]
        XHS[xhs.sh<br/>小红书 MCP 调用]
        DB[db.sh<br/>SQLite CRUD]
        IMG[image.py<br/>Gemini 生图]
        PRE[preflight.py<br/>环境预检]
        NRX[noterx-diagnose.sh<br/>五维诊断]
    end

    subgraph Memory["🗃️ knowledge-base/ (长期记忆)"]
        PROF[profile.json<br/>博主画像]
        PREF[preferences.json<br/>偏好学习]
        PAT[patterns.md<br/>有效模式]
        LOG[evolution-log.md<br/>进化日志]
    end

    subgraph Data["💾 data/ (事务数据)"]
        SQL[(xhs.db<br/>9 张表)]
        RULES[content-rules.md<br/>合规规则]
    end

    subgraph External["🌐 外部依赖"]
        MCP[xiaohongshu-mcp]
        GEM[Gemini 3 Pro Image]
        NOT[NoteRx API]
    end

    SKILL -->|"读/写"| Memory
    SKILL -->|"调用"| Hands
    Hands -->|"读/写"| Data
    XHS -->|"HTTP"| MCP
    IMG -->|"API"| GEM
    NRX -->|"API"| NOT

    style SKILL fill:#00ff88,stroke:#000,color:#000,stroke-width:2px
    style Hands fill:#00d4ff,stroke:#000,color:#000
    style Memory fill:#ff00ff,stroke:#000,color:#fff
    style Data fill:#ffb800,stroke:#000,color:#000
```

---

## 图 2 · 业务路由（§0a）

展示 AI 每次被调起时如何决定走哪条路径——解释"skill 不只是 prompt，是状态机"。

```mermaid
stateDiagram-v2
    [*] --> Preflight: AI skill 被调起

    Preflight: 跑 scripts/preflight.py
    Preflight --> CheckState: 读 state.json

    CheckState --> NewCreator: profile 未建 + 新博主
    CheckState --> ExistingCreator: profile 未建 + 用户说"已有账号"
    CheckState --> ColdStart: profile 已建 + cold_start 未跑
    CheckState --> DailyFlow: setup_completed=true
    CheckState --> FixMissing: 某 check 报 error

    NewCreator: §1 三问对话建画像
    NewCreator --> ColdStart

    ExistingCreator: §0c 五步老博主接入
    ExistingCreator: 1. 确认登录
    ExistingCreator: 2. 批量导入 200 条
    ExistingCreator: 3. AI 自动分类
    ExistingCreator: 4. AI 画像反推+用户确认
    ExistingCreator: 5. patterns 挖掘+体检报告
    ExistingCreator --> DailyFlow

    ColdStart: 竞品分析+patterns 播种
    ColdStart --> DailyFlow

    DailyFlow: §2 每日流程
    DailyFlow: 午间档 (11:30)
    DailyFlow: 晚间档 (20:30)
    DailyFlow: 夜间复盘 (22:00)
    DailyFlow: 周回顾 (周日 22:00)

    FixMissing: 仅修复缺失项
    FixMissing: 不重走整个安装
    FixMissing --> CheckState

    DailyFlow --> [*]
```

---

## 图 3 · 自进化引擎（§4）

展示偏好学习、选项递减、探索保底的完整决策链——解释"越用越懂你"到底怎么实现。

```mermaid
flowchart LR
    subgraph Input["📥 输入"]
        U[用户选择<br/>选题/草稿]
        P[帖子发布后<br/>互动数据]
    end

    subgraph Learn["🧬 偏好学习"]
        W["weight =<br/>(chosen+1)/(chosen+skipped+2)<br/>Laplace 平滑"]
        C["confidence =<br/>concentration × sample_factor"]
        W --> C
    end

    subgraph Decide["🎯 选项递减"]
        D1["≥0.75 → 1 选<br/>（回一个发字）"]
        D2["≥0.5 → 2 选"]
        D3["<0.5 → 3 选"]
        EXP["ε-greedy<br/>≥7 天追加探索项"]
        REJ["连续 2 次换<br/>→ confidence 强制回 0.45"]
    end

    subgraph Evolve["🌱 Pattern 生命周期"]
        E1["收藏率 ≥5%<br/>→ experimental"]
        E2["连续 3 次有效<br/>→ medium → high"]
        E3["连续 3 次失效<br/>→ anti-patterns"]
    end

    U --> W
    C --> D1
    C --> D2
    C --> D3
    D1 -.-> EXP
    U -.-> REJ

    P --> E1
    E1 --> E2
    E1 --> E3

    E2 -->|"回写"| Learn
    E3 -->|"回写"| Learn

    style W fill:#00ff88,stroke:#000,color:#000
    style C fill:#00ff88,stroke:#000,color:#000
    style EXP fill:#ffb800,stroke:#000,color:#000
    style REJ fill:#ff3366,stroke:#000,color:#fff
```

---

## 渲染建议

### 本地导出（推荐）

```bash
# 安装 mermaid CLI
npm install -g @mermaid-js/mermaid-cli

# 把每张图存成 .mmd 文件，导出
mmdc -i diagram-1.mmd -o diagram-1.svg -b transparent -t dark
```

### 在线渲染

1. 打开 https://mermaid.live/
2. 粘贴上面 mermaid 代码块
3. 选择 `neutral` / `dark` 主题（和 landing 的赛博风搭）
4. 下载 SVG 或 PNG

### 在 README 里引用

```markdown
![薯灵架构](docs/images/architecture.svg)
```

把导出的 SVG 放 `docs/images/`（新建目录），README 顶部引用。
