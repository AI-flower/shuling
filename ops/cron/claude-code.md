# Claude Code 定时触发指南（薯灵 v3.1）

> Claude Code 使用 `/loop` 命令实现定时触发，由 `superpowers:loop` skill 提供。
>
> **v3.1 起 draft-only**：`/loop` 默认只生成候选草稿和复盘，不会自动动账号。

## 安装

确保 Claude Code 已加载 superpowers:loop skill（默认带）。

## 用法

```
/loop 4h 使用 shuling skill：根据当前时间和 state 生成候选草稿，等待用户确认，不要发布
```

## 推荐节奏

- **每日草稿**：`/loop 6h 使用 shuling skill：生成本时段候选草稿，等待用户确认，不要发布`
- **复盘**：手动触发，说"复盘一下，不要发布或评论"
- **周回顾**：周日手动 "看看本周整体，不要发布或评论"

## 会话级 /loop 不能直接进入发布

`/loop` 触发的会话只走到 `draft_ready`，不会自动跳到 `04-publish-flow`。
账号写操作（发布、评论、Cookie 导入）必须等用户**显式回复"发"**后，
才能进入 approval flow（见 `docs/runbooks/account-safety.md`），由薯灵向用户讨要一次性授权后再执行。

`draft_ready` 是 non-mutating 信号，永远不等于 publish_allowed。

## 与 hermes 的差异

claude-code 的 `/loop` 是会话级（关 session 即停），不是 OS 级 cron；
适合开发期 / 本机测试，不适合无人值守生产。
