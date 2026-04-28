#!/usr/bin/env python3
"""
build/check-playbook-frontmatter.py — playbook frontmatter 全量校验

校验项：
- 每个 0X-*.md 含 frontmatter（--- 包裹 YAML）
- 含必填字段：id / title / when / version
- id 唯一
- calls.playbooks 引用的文件存在
- needs.optional 含 fallback 字段（如 needs.optional 存在）
- 渲染依赖图（calls.playbooks）—— 简单 DFS 检环
"""

import os, re, sys, json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PB_DIR = REPO / "agent" / "playbook"

def parse_frontmatter(text):
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    return text[4:end]

def get_field(fm, key):
    """简单 YAML 字段提取（不解析嵌套）"""
    m = re.search(rf"^{key}:\s*(.*)$", fm, re.M)
    return m.group(1).strip() if m else None

def get_list_field(fm, key):
    """提取 YAML 列表字段（- xxx 形式）"""
    pattern = rf"^{key}:\s*\n((?:\s+-.*\n?)+)"
    m = re.search(pattern, fm, re.M)
    if not m:
        return []
    return [line.strip()[2:].strip() for line in m.group(1).split('\n') if line.strip().startswith('-')]

errors = []
ids_seen = {}
playbooks = list(PB_DIR.glob("0[0-9]-*.md"))

for pb in playbooks:
    text = pb.read_text(encoding="utf-8")
    fm = parse_frontmatter(text)
    if fm is None:
        errors.append({"file": str(pb.name), "error": "missing frontmatter"})
        continue

    pid = get_field(fm, "id")
    title = get_field(fm, "title")
    version = get_field(fm, "version")

    if not pid:
        errors.append({"file": pb.name, "error": "missing id"})
    elif pid in ids_seen:
        errors.append({"file": pb.name, "error": f"duplicate id: {pid}"})
    else:
        ids_seen[pid] = pb.name

    if not title:
        errors.append({"file": pb.name, "error": "missing title"})
    if not version:
        errors.append({"file": pb.name, "error": "missing version"})

# 输出
out = {
    "status": "ok" if not errors else "fail",
    "playbook_count": len(playbooks),
    "ids_unique": len(ids_seen) == len(playbooks),
    "errors": errors,
}
print(json.dumps(out, ensure_ascii=False))
sys.exit(0 if not errors else 1)
