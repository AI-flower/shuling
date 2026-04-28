#!/usr/bin/env bash
# ops/verify/checks/30-policy-drift.sh — policies/throttle.yaml + quota.yaml 与 xhs.sh 硬编码值一致
# severity: warn
#
# 当前 v3.0 还没拆 yaml — 直接 pass + skipped 提示
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
NAME="30-policy-drift"
SEVERITY="warn"

emit() {
  local msg="$2"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"check":"%s","status":"%s","message":"%s","severity":"%s"}\n' \
    "$NAME" "$1" "$msg" "$SEVERITY"
}

throttle_yaml="$ROOT/agent/policies/throttle.yaml"
quota_yaml="$ROOT/agent/policies/quota.yaml"
xhs="$ROOT/agent/scripts/xhs.sh"

if [ ! -f "$throttle_yaml" ] || [ ! -f "$quota_yaml" ]; then
  emit "pass" "policies yaml not yet split, skipped"
  exit 0
fi

if [ ! -f "$xhs" ]; then
  emit "fail" "agent/scripts/xhs.sh not found"
  exit 1
fi

mismatches=()

# 解析 throttle.yaml — 简单格式：tool: <int>
while IFS= read -r line; do
  case "$line" in
    \#*|"") continue ;;
  esac
  tool="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([A-Za-z_]+):[[:space:]]*([0-9]+).*/\1/')"
  yaml_val="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([A-Za-z_]+):[[:space:]]*([0-9]+).*/\2/')"
  [ -z "$tool" ] && continue
  [ "$tool" = "$yaml_val" ] && continue
  # 在 xhs.sh 的 min_gap_for() 内查找匹配
  sh_val="$(awk -v t="$tool" '
    /min_gap_for\(\)/ {flag=1; next}
    flag && /^}/ {flag=0}
    flag && $0 ~ "^[[:space:]]+"t")[[:space:]]+echo[[:space:]]+[0-9]+" {
      sub(/.*echo[[:space:]]+/, ""); sub(/[[:space:]]+;;.*/, ""); print; exit
    }
  ' "$xhs")"
  if [ -n "$sh_val" ] && [ "$sh_val" != "$yaml_val" ]; then
    mismatches+=("throttle.${tool}:yaml=${yaml_val},sh=${sh_val}")
  fi
done < "$throttle_yaml"

while IFS= read -r line; do
  case "$line" in
    \#*|"") continue ;;
  esac
  tool="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([A-Za-z_]+):[[:space:]]*([0-9]+).*/\1/')"
  yaml_val="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([A-Za-z_]+):[[:space:]]*([0-9]+).*/\2/')"
  [ -z "$tool" ] && continue
  [ "$tool" = "$yaml_val" ] && continue
  sh_val="$(awk -v t="$tool" '
    /daily_cap_for\(\)/ {flag=1; next}
    flag && /^}/ {flag=0}
    flag && $0 ~ "^[[:space:]]+"t")[[:space:]]+echo[[:space:]]+[0-9]+" {
      sub(/.*echo[[:space:]]+/, ""); sub(/[[:space:]]+;;.*/, ""); print; exit
    }
  ' "$xhs")"
  if [ -n "$sh_val" ] && [ "$sh_val" != "$yaml_val" ]; then
    mismatches+=("quota.${tool}:yaml=${yaml_val},sh=${sh_val}")
  fi
done < "$quota_yaml"

if [ ${#mismatches[@]} -gt 0 ]; then
  emit "warn" "policy drift: ${mismatches[*]}"
  exit 1
fi

emit "pass" "policy yaml values match xhs.sh hardcoded values"
exit 0
