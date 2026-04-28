# build/ — v3.0 打包与发版前置校验

5 个工具，统一约定：

- `set -euo pipefail`（shell）/ `sys.exit(0/1)`（python）
- 退出码 `0` = ok / `>=1` = fail
- stdout 为单行 JSON（机器可读）；详细错误走 stderr

## 工具一览

| 工具 | 用途 |
|------|------|
| `package-skill.sh` | 把仓库里的 v3.0 skill 内核（`SKILL.md` / `VERSION` / `agents/` / `agent/`）按白名单 rsync 到 `dist/shuling-agent-skill/`，剔除 DB、runtime.env、knowledge-base 私密产物、`__pycache__` / `*.bak.*` / `.DS_Store` |
| `check-package.sh` | 校验 `dist/shuling-agent-skill/` 仅含 4 个允许的顶级条目，且不含 `*.db` / `runtime.env` / `state.json` / `profile.json` / `preferences.json` / `__pycache__` / `.DS_Store`，也不含 `docs/site/marketing/legacy/ops/build/dist` 这类 inactive 目录。可选参数：自定义 dist 路径 |
| `check-version-sync.sh` | 比较 `VERSION` 顶部 `version: "X.Y.Z"` 与 `SKILL.md` frontmatter 的 `version: X.Y.Z`，不一致即 fail |
| `check-playbook-frontmatter.py` | 扫 `agent/playbook/0[0-9]-*.md`，要求每份都有 frontmatter 且包含 `id` / `title` / `version`，`id` 唯一 |
| `check-active-region-refs.py` | 在 active 区（`SKILL.md` / `agent/` / `ops/` / `build/`）扫 `legacy/` / `docs/archive/` / `skills/shuling/` 等 inactive 路径引用，避免发版包里残留旧路径硬编码 |

## 一次跑全部

```bash
bash build/package-skill.sh          && \
bash build/check-package.sh          && \
bash build/check-version-sync.sh     && \
python3 build/check-playbook-frontmatter.py && \
python3 build/check-active-region-refs.py
```

任一非零退出即视为发版门未过。建议接进 `agent/scripts/pre-submit-verify.sh`（v2.4.2+ 的 21 项发版门）作为 v3.0 增量。
