# Business Anti-Patterns

> 本文件由 `agent/playbook/05-review.md` 自动追加，**不要手工编辑**。
>
> 业务反模式 = 看起来表现好但不带来真实业务信号的内容套路。最常见的是「高流量低价值」「高互动低信任」。
> 一旦命中，应降低本类内容在选题推荐中的权重，避免账号资产被流量数据误导。
>
> 详见 `docs/plans/v3.2-creator-business-intelligence-plan.md` §5.6 / §9.3。

## 示范条目（safe to delete on first user write）

## high-traffic-knowledge-collection

- confidence: experimental
- source: shuling_review
- evidence:
  - post_id: 0
  - signal: save_signal=high, lead_signal=low, sales_signal=low
  - representative_comments:
    - "收藏了"
    - "有用"
    - "学到了"
- triggered_when:
  - primary_goal in {get_leads, drive_sales}
  - performance_tier in {excellent, mixed}
  - main_attribution=content_depth
- interpretation:
  收藏率高 + 评论无下一步意图 → 知识收藏型内容。可作为涨粉/信任内容保留，但不应作为转化 pattern 晋级。
- next_action:
  下次同主题加一个明确行动入口（"想要模板的评论区说模板" / "私信发表格"），用一次实验把该选题从 anti-pattern 转为 pattern。
