#!/usr/bin/env bash
# pre-submit-verify.sh —— 本地模拟 cookbook-dev 社区 verifier 行为
#
# 目的:
#   在方案提交社区前, 本地复现 verifier 在干净环境下会做的关键动作:
#   1. install.sh 初装到一个全新 target
#   2. 校验 target/config/runtime.env 正确写入了自定义值 (MCP_URL / IMAGE_GEN_API_KEY)
#   3. 校验 target/data/xhs.db 被 init 且含 __migrations 表
#   4. 校验 target 上 preflight.py 不再报 SQLite not_initialized
#   5. 校验 upgrade-all 的 migrations 写入 target DB 而非源仓库 DB
#
# 使用:
#   bash agent/scripts/pre-submit-verify.sh           # 彩色人类可读
#   bash agent/scripts/pre-submit-verify.sh --json    # 机器可读(给 CI / agent 用)
#
# 退出码:
#   0 全部通过, 可提交社区
#   1 有断言失败
#   2 环境问题(如 sqlite3 缺失)

set -u
set -o pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SKILL_DIR"

JSON_MODE=0
for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=1 ;;
    esac
done

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; BOLD='\033[1m'; RESET='\033[0m'
[ "$JSON_MODE" = "1" ] && { GREEN=''; RED=''; YELLOW=''; BOLD=''; RESET=''; }

RESULTS=()
TOTAL=0
PASSED=0
FAILED=0

check() {
    local name="$1"; local ok="$2"; local detail="${3:-}"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "1" ]; then
        PASSED=$((PASSED+1))
        RESULTS+=("ok|$name|$detail")
        [ "$JSON_MODE" = "0" ] && printf "${GREEN}[PASS]${RESET} %s${detail:+ — $detail}\n" "$name"
    else
        FAILED=$((FAILED+1))
        RESULTS+=("fail|$name|$detail")
        [ "$JSON_MODE" = "0" ] && printf "${RED}[FAIL]${RESET} %s${detail:+ — $detail}\n" "$name"
    fi
}

info() { [ "$JSON_MODE" = "0" ] && printf "  %s\n" "$*"; }
step() { [ "$JSON_MODE" = "0" ] && printf "\n${BOLD}=== %s ===${RESET}\n" "$*"; }

# ─── 0. 前置检查 ────────────────────────────────────────────────────
step "前置检查"
for cmd in sqlite3 rsync jq python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
        check "dep:$cmd" 1
    else
        check "dep:$cmd" 0 "命令未安装"
        [ "$JSON_MODE" = "0" ] && printf "${RED}环境问题, 无法继续${RESET}\n"
        exit 2
    fi
done

SRC_DB_BEFORE_HASH=""
if [ -f "$SKILL_DIR/data/xhs.db" ]; then
    SRC_DB_BEFORE_HASH="$(md5sum "$SKILL_DIR/data/xhs.db" 2>/dev/null | awk '{print $1}' || shasum "$SKILL_DIR/data/xhs.db" 2>/dev/null | awk '{print $1}')"
fi
info "源 DB md5 快照: ${SRC_DB_BEFORE_HASH:-无 (源 DB 不存在)}"

# ─── 1. 建干净 target (独立 HOME, 与 verifier 同构) ───────────────
WORK="$(mktemp -d "${TMPDIR:-/tmp}/shuling-pre-submit-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME/.claude"   # 让 install.sh 识别 Claude Code target
TARGET="$FAKE_HOME/.claude/skills/shuling"
info "workdir: $WORK"
info "target : $TARGET"

# ─── 2. 真跑 install.sh (模拟 verifier Step 2) ─────────────────────
step "初装到干净 target"
TEST_KEY="pre-submit-test-key-$(date +%s)"
TEST_MCP="http://127.0.0.1:65535/mcp"   # 不常用端口避免和真服务冲突

INSTALL_LOG="$WORK/install.log"
if HOME="$FAKE_HOME" \
    SHULING_ASSUME_YES=1 \
    IMAGE_GEN_API_KEY="$TEST_KEY" \
    XHS_MCP_URL="$TEST_MCP" \
    bash "$SKILL_DIR/install.sh" >"$INSTALL_LOG" 2>&1
then
    check "install.sh 成功执行" 1
else
    check "install.sh 成功执行" 0 "退出码 $? (详见 $INSTALL_LOG)"
    [ "$JSON_MODE" = "0" ] && tail -30 "$INSTALL_LOG" | sed 's/^/    /'
fi

# ─── 3. 断言 target 结构 ────────────────────────────────────────────
step "target 结构检查"
[ -d "$TARGET" ] && check "target 目录已建" 1 "$TARGET" || check "target 目录已建" 0 ""
[ -f "$TARGET/SKILL.md" ] && check "target/SKILL.md 存在" 1 || check "target/SKILL.md 存在" 0
[ -f "$TARGET/VERSION" ] && check "target/VERSION 存在" 1 || check "target/VERSION 存在" 0
[ -f "$TARGET/config/runtime.env" ] && check "target/config/runtime.env 存在" 1 || check "target/config/runtime.env 存在" 0

# ─── 4. 断言 runtime.env 的 MCP_URL 和 IMAGE_GEN_API_KEY 被覆写 ────
step "runtime.env 覆写检查"
if [ -f "$TARGET/config/runtime.env" ]; then
    MCP_LINE="$(grep -E '^\s*MCP_URL\s*=' "$TARGET/config/runtime.env" || echo '')"
    KEY_LINE="$(grep -E '^\s*IMAGE_GEN_API_KEY\s*=' "$TARGET/config/runtime.env" || echo '')"

    if echo "$MCP_LINE" | grep -qF "MCP_URL=$TEST_MCP"; then
        check "MCP_URL 覆写成用户传入值" 1 "$TEST_MCP"
    else
        check "MCP_URL 覆写成用户传入值" 0 "实际: ${MCP_LINE:-(无该行)}"
    fi

    if echo "$KEY_LINE" | grep -qF "IMAGE_GEN_API_KEY=$TEST_KEY"; then
        check "IMAGE_GEN_API_KEY 写入用户传入值" 1 "$TEST_KEY"
    else
        check "IMAGE_GEN_API_KEY 写入用户传入值" 0 "实际: ${KEY_LINE:-(无该行)}"
    fi
else
    check "MCP_URL 覆写成用户传入值" 0 "runtime.env 不存在"
    check "IMAGE_GEN_API_KEY 写入用户传入值" 0 "runtime.env 不存在"
fi

# ─── 5. 断言 target DB 被 init + __migrations 表存在 ──────────────
step "target DB 初始化检查"
TARGET_DB="$TARGET/data/xhs.db"
if [ -f "$TARGET_DB" ]; then
    check "target xhs.db 文件存在" 1 "$TARGET_DB"
    TABLES="$(sqlite3 "$TARGET_DB" ".tables" 2>/dev/null || echo '')"
    for t in posts post_metrics user_choices topic_candidates __migrations; do
        if echo "$TABLES" | tr ' ' '\n' | grep -qxF "$t"; then
            check "target DB 含 $t 表" 1
        else
            check "target DB 含 $t 表" 0 "缺失"
        fi
    done
else
    check "target xhs.db 文件存在" 0 "文件缺失"
fi

# ─── 6. target 上 preflight 不报 SQLite not_initialized ──────────
# v2 兼容层：v2 target 把 preflight.py 放在 target/scripts/，v3 在 target/agent/scripts/。
# 优先 v3 路径，回退 v2。
step "target preflight 检查"
TARGET_PREFLIGHT=""
if [ -f "$TARGET/agent/scripts/preflight.py" ]; then
    TARGET_PREFLIGHT="agent/scripts/preflight.py"
elif [ -f "$TARGET/scripts/preflight.py" ]; then
    TARGET_PREFLIGHT="scripts/preflight.py"  # v2 兼容层
fi
if [ -n "$TARGET_PREFLIGHT" ]; then
    PREFLIGHT_OUT="$WORK/preflight.json"
    (cd "$TARGET" && python3 "$TARGET_PREFLIGHT" >"$PREFLIGHT_OUT" 2>&1 || true)

    # 提取 checks 数组里的 SQLite 数据库 status
    SQLITE_STATUS="$(python3 -c "
import json, sys, re
txt = open('$PREFLIGHT_OUT').read()
# 脚本会先打印彩色 banner, 再打印 JSON。找 { 起始的 JSON 段
m = re.search(r'(\{[\s\S]+\})\s*$', txt)
if not m:
    print('NO_JSON'); sys.exit()
try:
    d = json.loads(m.group(1))
except Exception as e:
    print('PARSE_ERROR:' + str(e)); sys.exit()
for c in d.get('checks', []):
    if c.get('name') == 'SQLite 数据库':
        print(c.get('status', 'missing'))
        sys.exit()
print('NOT_FOUND')
")"
    if [ "$SQLITE_STATUS" = "ok" ]; then
        check "target preflight: SQLite 数据库 status=ok" 1
    else
        check "target preflight: SQLite 数据库 status=ok" 0 "实际 status=$SQLITE_STATUS"
    fi
else
    check "target preflight: SQLite 数据库 status=ok" 0 "preflight.py 不存在"
fi

# ─── 7. upgrade-all 场景: migrations 应写 target DB, 不污染源 DB ──
# upgrade-all 的 discover_targets 只扫 $HOME/.claude|.hermes|.codex|.agents/skills/*
# 所以用独立 HOME 隔离法, 让它识别到 mock target (跟 Section 2 一致机制)
step "upgrade-all migrations 隔离检查"
OLD_HOME="$WORK/old-home"
OLD_TARGET="$OLD_HOME/.claude/skills/shuling"
mkdir -p "$(dirname "$OLD_TARGET")"
# 复制源码骨架过去 (排除运行时数据), 改 VERSION 成老版本
rsync -a --exclude='.git' --exclude='data' --exclude='node_modules' \
    --exclude='.venv' --exclude='.session-recorder' \
    "$SKILL_DIR/" "$OLD_TARGET/" >/dev/null 2>&1
cat > "$OLD_TARGET/VERSION" <<'OLDEOF'
version: "2.1.3"
codename: "Friendly Onboarding (mock for pre-submit test)"
released: "2026-04-10"
OLDEOF
mkdir -p "$OLD_TARGET/data" "$OLD_TARGET/config"
cp "$SKILL_DIR/config/runtime.env.example" "$OLD_TARGET/config/runtime.env"
# 先用 target 自己的 db.sh init, 让它变成一个"有老 DB 但没 __migrations 的老 target"
SHULING_DB="$OLD_TARGET/data/xhs.db" bash "$OLD_TARGET/scripts/db.sh" init >/dev/null 2>&1 || true
# 把 __migrations 表从 old target 删掉（模拟 v2.1.3 时代完全没这张表）
sqlite3 "$OLD_TARGET/data/xhs.db" "DROP TABLE IF EXISTS __migrations;" 2>/dev/null || true

# 记录源 DB 快照（如有）
SRC_DB_MIDWAY_HASH=""
if [ -f "$SKILL_DIR/data/xhs.db" ]; then
    SRC_DB_MIDWAY_HASH="$(md5sum "$SKILL_DIR/data/xhs.db" 2>/dev/null | awk '{print $1}' || shasum "$SKILL_DIR/data/xhs.db" 2>/dev/null | awk '{print $1}')"
fi

# 跑 upgrade-all —— 用 HOME 隔离让 discover_targets 找到 $OLD_TARGET
UPGRADE_LOG="$WORK/upgrade-all.log"
if HOME="$OLD_HOME" bash "$SKILL_DIR/install.sh" upgrade-all --json --yes >"$UPGRADE_LOG" 2>&1; then
    check "upgrade-all 执行完成" 1
else
    check "upgrade-all 执行完成" 0 "(详见 $UPGRADE_LOG; tail: $(tail -3 "$UPGRADE_LOG" | tr '\n' ' '))"
fi

# 断言: target DB 里 __migrations 表存在且有记录
TARGET_MIG_COUNT="$(sqlite3 "$OLD_TARGET/data/xhs.db" "SELECT COUNT(*) FROM __migrations;" 2>/dev/null || echo -1)"
if [ "$TARGET_MIG_COUNT" -ge 1 ] 2>/dev/null; then
    check "upgrade-all 写入 target __migrations" 1 "$TARGET_MIG_COUNT 条"
else
    check "upgrade-all 写入 target __migrations" 0 "count=$TARGET_MIG_COUNT"
fi

# 断言: 源 DB 未被 upgrade-all 污染 (md5 不变)
SRC_DB_AFTER_HASH=""
if [ -f "$SKILL_DIR/data/xhs.db" ]; then
    SRC_DB_AFTER_HASH="$(md5sum "$SKILL_DIR/data/xhs.db" 2>/dev/null | awk '{print $1}' || shasum "$SKILL_DIR/data/xhs.db" 2>/dev/null | awk '{print $1}')"
fi
if [ -z "$SRC_DB_MIDWAY_HASH" ] && [ -z "$SRC_DB_AFTER_HASH" ]; then
    check "upgrade-all 未污染源 DB" 1 "源 DB 本来就不存在"
elif [ "$SRC_DB_MIDWAY_HASH" = "$SRC_DB_AFTER_HASH" ]; then
    check "upgrade-all 未污染源 DB" 1 "md5 未变"
else
    check "upgrade-all 未污染源 DB" 0 "md5 变了: $SRC_DB_MIDWAY_HASH → $SRC_DB_AFTER_HASH"
fi

# ─── 汇总 ────────────────────────────────────────────────────────────
if [ "$JSON_MODE" = "1" ]; then
    printf '{\n'
    printf '  "total": %d,\n' "$TOTAL"
    printf '  "passed": %d,\n' "$PASSED"
    printf '  "failed": %d,\n' "$FAILED"
    printf '  "verdict": "%s",\n' "$([ "$FAILED" = "0" ] && echo ok || echo fail)"
    printf '  "checks": [\n'
    first=1
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r st name detail <<< "$r"
        [ $first -eq 1 ] && first=0 || printf ',\n'
        detail_esc="$(printf '%s' "$detail" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')"
        printf '    {"status": "%s", "name": "%s", "detail": %s}' "$st" "$name" "$detail_esc"
    done
    printf '\n  ]\n}\n'
else
    printf "\n${BOLD}=== 汇总 ===${RESET}\n"
    printf "total=%d  passed=%d  failed=%d\n" "$TOTAL" "$PASSED" "$FAILED"
    if [ "$FAILED" = "0" ]; then
        printf "${GREEN}${BOLD}✅ 全部通过, 可提交社区${RESET}\n"
    else
        printf "${RED}${BOLD}❌ 有 %d 项失败, 修复后再提交${RESET}\n" "$FAILED"
    fi
fi

[ "$FAILED" = "0" ]
