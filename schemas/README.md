# schemas/

本目录存放薯灵运行时状态文件的 JSON Schema 定义。

**目的**：给 AI 智能体在**写入 knowledge-base/ 或 config/ 文件前**自校验字段名与类型，防止字段漂移（`created_at` vs `createdAt`、weight 越界等）。

---

## 文件

| Schema | 对应文件 | 来源章节 |
|---|---|---|
| [`state.schema.json`](state.schema.json) | `config/state.json` | `SKILL.md §0a` 业务路由 |
| [`profile.schema.json`](profile.schema.json) | `knowledge-base/profile.json` | `SKILL.md §1` 首次使用 |
| [`preferences.schema.json`](preferences.schema.json) | `knowledge-base/preferences.json` | `SKILL.md §4.1` 偏好学习 |

---

## AI 自校验流程

写入上述任一文件前：

1. 读对应 schema
2. 按 schema 构造 JSON object（**必填字段不得缺**、**类型匹配**、**enum 字段用允许值**）
3. 写入目标文件
4. 可选：用 `python3 -m jsonschema -i <target.json> <schema.json>` 验证（若环境有 `jsonschema` 包）

**非目标**：不要求 AI 每次都调用 jsonschema validator，schema 主要作为"写入协议文档"。真实保障来自 AI 的结构化遵守。

---

## 扩展规则

- 所有 schema 默认 `additionalProperties: true`，允许向前演化
- 新增字段：先在 schema 加 property（不放 required），更新 `CHANGELOG.md` 说明；下个 HANDS 版本再考虑提 required
- 删字段：走 BRAIN 版本号，`UPGRADE.md` 给 migration 步骤

---

## 与 VERSION 的关系

schemas 不独立版本化，跟随项目主版本。如果 schema 出现**破坏性**变化（字段 rename、type 换类型），版本号必须走 BRAIN +1（详见 `RELEASING.md`）。
