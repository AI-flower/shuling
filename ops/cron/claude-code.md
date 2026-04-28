# Claude Code 定时触发指南（薯灵 v3.0）

> Claude Code 使用 `/loop` 命令实现定时触发，由 `superpowers:loop` skill 提供。

## 安装

确保 Claude Code 已加载 superpowers:loop skill（默认带）。

## 用法

```
/loop 4h 使用 shuling skill：根据当前时间和 state 执行下一步业务
```

## 推荐节奏

- **每日发布**：`/loop 6h ...` 让 AI 每 6 小时自检一次
- **复盘**：手动触发，说"复盘一下"
- **周回顾**：周日手动 "看看本周整体"

## 与 hermes 的差异

claude-code 的 `/loop` 是会话级（关 session 即停），不是 OS 级 cron；
适合开发期 / 本机测试，不适合无人值守生产。
