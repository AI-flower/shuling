#!/usr/bin/env bash
# ops/verify/checks/48-no-dbskill-raw-copy.sh — 守门：不复制 dbskill 原文
# severity: error
#
# 算法：
#   1. trigram (3-gram) Jaccard 相似度，对照 dbskill 标志短语逐条比对
#      title-formulas.json 每条 template；阈值 0.7 命中即 fail
#   2. 概念词原文连续照抄检测：在 KB / playbook 中扫描 dbskill 推主标志性概念词
#      允许出现概念词，但禁止 ≥30 字的整段连续重叠（用 5-gram 滑动比对）
#
# 注意：标志短语清单是经过抽象化简的描述，不是 dbskill 原文。本 check 是发版守门，
# 不是用来阻止合理引用术语，目标是阻止把 dbskill 原文逐字搬运。
set -uo pipefail

CHECK_NAME="48-no-dbskill-raw-copy"
SEVERITY="error"
ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"

emit() {
    local status="$1" message="$2"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
        "$CHECK_NAME" "$status" "$message" "$SEVERITY"
}

kb="$ROOT/agent/knowledge-base/title-formulas.json"
playbook_dir="$ROOT/agent/playbook"

if [ ! -f "$kb" ]; then
    emit "fail" "missing agent/knowledge-base/title-formulas.json"
    exit 2
fi
if [ ! -d "$playbook_dir" ]; then
    emit "fail" "missing agent/playbook directory"
    exit 2
fi

result=$(python3 - "$kb" "$playbook_dir" << 'PYEOF'
import json, os, sys, glob

kb_path, playbook_dir = sys.argv[1], sys.argv[2]

# dbskill 标志短语（标题模板侧，trigram Jaccard）
DBSKILL_TITLE_PHRASES = [
    "不是不会写",
    "为什么越努力越没结果",
    "为什么X反而会Y",
    "30天从X到Y",
    "99%的人都搞错了X",
]

# dbskill 标志性概念词（≥30 字段连续照抄检测）
DBSKILL_CONCEPT_TERMS = [
    "引流款",
    "利润款",
    "必死工作法",
    "小钱就是大钱",
    "快钱就是慢钱",
    "印钞机测试",
    "五重过滤",
    "75公式",
    "22项AI指纹",
]

def normalize(s):
    return "".join(c for c in s if not c.isspace() and c not in "{}[]<>「」（）()：:，。！？、 ")

def trigrams(s):
    s = normalize(s)
    if len(s) < 3:
        return set()
    return {s[i:i+3] for i in range(len(s) - 2)}

def jaccard(a, b):
    if not a or not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0

JACCARD_THRESHOLD = 0.7
COPY_RUN_LEN = 30  # 连续重叠 ≥ 30 字符判定为整段照抄

violations = []

# ─── 1. title template trigram check ─────────────────
try:
    formulas = json.load(open(kb_path))
except Exception as e:
    print(f"KB_PARSE_ERROR: {e}")
    sys.exit(1)

phrase_grams = [(p, trigrams(p)) for p in DBSKILL_TITLE_PHRASES]

for f in formulas:
    fid = f.get("id", "?")
    tpl = f.get("template", "")
    tpl_grams = trigrams(tpl)
    for phrase, pg in phrase_grams:
        sim = jaccard(tpl_grams, pg)
        if sim > JACCARD_THRESHOLD:
            violations.append(
                f"trigram-jaccard:{fid}:tpl={tpl[:30]}|phrase={phrase}|sim={sim:.2f}"
            )

# ─── 2. concept-term continuous-copy check ───────────
# 收集 KB 与 playbook 文本
files_to_scan = [kb_path]
for f in sorted(glob.glob(os.path.join(playbook_dir, "*.md"))):
    files_to_scan.append(f)

# 对每个文件，按概念词搜索周围窗口；只要连续 COPY_RUN_LEN 字符里包含
# ≥ 2 个概念词原话相邻（间距 ≤ 5 字），视为整段照抄。
# 单独出现概念词允许（plan §9.6 "允许出现概念词，但不能连续 ≥ 30 字整段照抄"）
def find_continuous_copy(text):
    text_norm = normalize(text)
    hits = []
    # 找出所有概念词位置（在 normalized 文本里）
    positions = []
    for term in DBSKILL_CONCEPT_TERMS:
        t_norm = normalize(term)
        if not t_norm:
            continue
        start = 0
        while True:
            idx = text_norm.find(t_norm, start)
            if idx < 0:
                break
            positions.append((idx, idx + len(t_norm), term))
            start = idx + 1
    # 按位置排序，找窗口内 ≥2 个 + 跨度 ≥ COPY_RUN_LEN（整段照抄）
    # 或者 ≥ 3 个 dbskill 概念词紧密相邻（间距 ≤ 5 字）即视为聚集照抄
    positions.sort()
    for i in range(len(positions)):
        cluster = [positions[i]]
        for j in range(i + 1, len(positions)):
            # 相邻间距 ≤ 5 字算同一段连续
            if positions[j][0] - cluster[-1][1] <= 5:
                cluster.append(positions[j])
            else:
                break
        if len(cluster) >= 2:
            span = cluster[-1][1] - cluster[0][0]
            terms = "+".join(c[2] for c in cluster)
            if span >= COPY_RUN_LEN:
                hits.append((cluster[0][0], span, f"{terms}|run>=30"))
            elif len(cluster) >= 3:
                # 3+ concept terms within proximity is also a copy red flag
                hits.append((cluster[0][0], span, f"{terms}|cluster>=3"))
    return hits

for fpath in files_to_scan:
    try:
        with open(fpath) as fh:
            text = fh.read()
    except Exception:
        continue
    rel = os.path.relpath(fpath, os.path.dirname(os.path.dirname(playbook_dir)))
    for pos, span, terms in find_continuous_copy(text):
        violations.append(f"continuous-copy:{rel}@{pos}:span={span}:terms={terms}")

if violations:
    print("VIOLATIONS:")
    for v in violations[:10]:
        print(v)
    sys.exit(1)

print("OK")
PYEOF
)
rc=$?

if [ "$rc" -ne 0 ] || ! echo "$result" | grep -q "^OK$"; then
    # 收集前几条具体违规消息
    detail=$(echo "$result" | head -6 | tr '\n' '|')
    emit "fail" "dbskill raw-copy check failed: ${detail:0:300}"
    exit 2
fi

emit "pass" "no dbskill raw copy detected (trigram jaccard < 0.7, no continuous concept-term run >= 30)"
exit 0
