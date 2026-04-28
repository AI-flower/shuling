#!/usr/bin/env bash
# ops/verify/pre-submit-verify.sh — v3.0+ 发版前 34 项回归门
#
# 用法：
#   bash ops/verify/pre-submit-verify.sh                  # 表格输出
#   bash ops/verify/pre-submit-verify.sh --json           # 单行 JSON 摘要 + 每条 check JSON
#   bash ops/verify/pre-submit-verify.sh --strict         # warn 也阻断
#   bash ops/verify/pre-submit-verify.sh --fail-fast      # 第一个 fail 立即停

set -uo pipefail

CHECKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/checks" && pwd)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fmt="table"
strict=0
fail_fast=0
for arg in "$@"; do
    case "$arg" in
        --json) fmt="json" ;;
        --strict) strict=1 ;;
        --fail-fast) fail_fast=1 ;;
    esac
done

pass=0
warn=0
fail=0
declare -a all_results

for check in "$CHECKS_DIR"/[0-9][0-9]-*.sh; do
    [ -e "$check" ] || continue
    name="$(basename "$check" .sh)"
    out="$(bash "$check" "$REPO" 2>&1)"
    rc=$?
    case "$rc" in
        0) pass=$((pass+1)) ;;
        1) warn=$((warn+1)) ;;
        *) fail=$((fail+1)) ;;
    esac
    all_results+=("$out")
    [ "$fail_fast" = "1" ] && [ "$rc" -ge 2 ] && break
done

if [ "$fmt" = "json" ]; then
    echo -n '{"summary":{"pass":'"$pass"',"warn":'"$warn"',"fail":'"$fail"',"total":'"$((pass+warn+fail))"'},"results":['
    sep=""
    for r in "${all_results[@]}"; do
        echo -n "$sep$r"
        sep=","
    done
    echo "]}"
else
    printf "%-3s %-40s %-6s %s\n" "#" "CHECK" "STATUS" "MESSAGE"
    echo "----------------------------------------------------------------------"
    n=0
    for r in "${all_results[@]}"; do
        n=$((n+1))
        c="$(echo "$r" | sed -n 's/.*"check":"\([^"]*\)".*/\1/p')"
        s="$(echo "$r" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
        m="$(echo "$r" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')"
        printf "%-3s %-40s %-6s %s\n" "$n" "$c" "$s" "$m"
    done
    echo "----------------------------------------------------------------------"
    echo "Summary: pass=$pass warn=$warn fail=$fail total=$((pass+warn+fail))"
fi

# 退出策略
[ "$fail" -gt 0 ] && exit 2
[ "$strict" = "1" ] && [ "$warn" -gt 0 ] && exit 1
exit 0
