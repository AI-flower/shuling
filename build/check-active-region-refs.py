#!/usr/bin/env python3
"""
build/check-active-region-refs.py — 扫描 active 区域是否引用 inactive / legacy 路径
"""

import os, re, sys, json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ACTIVE = ["SKILL.md", "agent", "ops", "build"]
INACTIVE_PATTERNS = [
    r"\blegacy/",
    r"docs/archive/",
    r"\bskills/shuling/",
]

# 白名单：本文件路径不参与扫描（这些文件引用 v2 路径是合理的）
EXEMPT_FILES = {
    # verify check 脚本本身要扫 legacy/ docs/archive/ —— 它们的工作就是引用这些路径
    "ops/verify/checks/13-package-no-inactive-dirs.sh",
    "ops/verify/checks/15-active-region-no-old-paths.sh",
    "ops/verify/checks/16-active-region-no-legacy-refs.sh",
    "ops/verify/checks/17-active-region-no-tech-bias.sh",
    "ops/verify/checks/18-legacy-readme-coverage.sh",
    "ops/verify/checks/31-algorithm-uniqueness.sh",
    "ops/verify/checks/README.md",
    # xhs.sh 含 v2 install path 兼容 fallback（用户老 install 仍叫 skills/shuling）
    "agent/scripts/xhs.sh",
    # 自身
    "build/check-active-region-refs.py",
    # build README 解释了 verify 工具会扫哪些 inactive 路径，必须能写这些路径名
    "build/README.md",
    # schemas/v2-README.md 是 v2 schemas/ 的原 README（已 git mv，仅历史引用）
    "agent/schemas/v2-README.md",
}

def scan_file(p):
    try:
        text = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return []
    found = []
    for pat in INACTIVE_PATTERNS:
        for m in re.finditer(pat, text):
            found.append({"file": str(p.relative_to(REPO)), "match": m.group(0), "pattern": pat})
    return found

errors = []
for active in ACTIVE:
    p = REPO / active
    if not p.exists():
        continue
    if p.is_file():
        rel = str(p.relative_to(REPO))
        if rel not in EXEMPT_FILES:
            errors.extend(scan_file(p))
    else:
        for f in p.rglob("*"):
            if f.is_file() and f.suffix in (".md", ".sh", ".py", ".json", ".yaml", ".txt"):
                rel = str(f.relative_to(REPO))
                if rel in EXEMPT_FILES:
                    continue
                errors.extend(scan_file(f))

out = {"status": "ok" if not errors else "fail", "violations": len(errors), "details": errors[:20]}
print(json.dumps(out, ensure_ascii=False))
sys.exit(0 if not errors else 1)
