#!/usr/bin/env bash
# v2.3.0 upgrade hook: 补齐 IMAGE_GEN_* 字段
# - 已有且非空 → 不动
# - 存在但空 (API_KEY) → 扫其他 target 借
# - 存在但空 (非 API_KEY) → 写默认值
# - 完全缺 → 追加
# 输出单行 JSON，幂等
# 兼容 Mac bash 3.2（不使用关联数组）

set -e

TARGET_PATH="${1:-}"
if [ -z "$TARGET_PATH" ] || [ ! -d "$TARGET_PATH" ]; then
    echo '{"status":"failed","detail":"target_path required or not a directory"}'
    exit 1
fi

ENV_FILE="$TARGET_PATH/config/runtime.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "{\"status\":\"failed\",\"detail\":\"runtime.env not found at $ENV_FILE\",\"target\":\"$TARGET_PATH\"}"
    exit 1
fi

# ─── 要管理的字段 ──────────────────────────────────────────
FIELDS="IMAGE_GEN_PROVIDER IMAGE_GEN_API_KEY IMAGE_GEN_MODEL IMAGE_GEN_PROTOCOL IMAGE_GEN_BASE_URL"

# 取字段默认值（bash 3.2 兼容 —— 不用关联数组）
default_of() {
    case "$1" in
        IMAGE_GEN_PROVIDER) echo "gemini" ;;
        IMAGE_GEN_API_KEY) echo "" ;;
        IMAGE_GEN_MODEL) echo "gemini-3-pro-image-preview" ;;
        IMAGE_GEN_PROTOCOL) echo "gemini-native" ;;
        IMAGE_GEN_BASE_URL) echo "" ;;
        *) echo "" ;;
    esac
}

# ─── 读 ENV_FILE 中某字段的当前值 ──────────────────────────
# 返回 __MISSING__ 表示完全无此行；否则返回值（可能为空串）
# 只认未注释的 KEY=VALUE
get_current_value() {
    local key="$1"
    local file="$2"
    local line
    line=$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -1 || true)
    if [ -z "$line" ]; then
        echo "__MISSING__"
        return
    fi
    local val="${line#*=}"
    # 去两端可能的引号
    val="${val%\"}"
    val="${val#\"}"
    val="${val%\'}"
    val="${val#\'}"
    echo "$val"
}

# ─── 从其他 target 借一个非空 IMAGE_GEN_API_KEY ───────────
borrow_api_key() {
    local candidates=""
    local d
    # codex
    for d in "$HOME"/.codex/skills/*/config/runtime.env; do
        [ -f "$d" ] && [ "$d" != "$ENV_FILE" ] && candidates="$candidates
$d"
    done
    # hermes (用 find 递归)
    while IFS= read -r d; do
        if [ -n "$d" ] && [ -f "$d" ] && [ "$d" != "$ENV_FILE" ]; then
            candidates="$candidates
$d"
        fi
    done < <(find "$HOME/.hermes/skills" -type f -name "runtime.env" -path "*/config/runtime.env" 2>/dev/null || true)
    # claude
    for d in "$HOME"/.claude/skills/*/config/runtime.env; do
        [ -f "$d" ] && [ "$d" != "$ENV_FILE" ] && candidates="$candidates
$d"
    done

    local src val
    while IFS= read -r src; do
        [ -z "$src" ] && continue
        val=$(get_current_value "IMAGE_GEN_API_KEY" "$src")
        if [ "$val" != "__MISSING__" ] && [ -n "$val" ]; then
            echo "$val"
            return
        fi
    done <<EOF
$candidates
EOF
    echo ""
}

# ─── 追加或改写一个字段 ────────────────────────────────────
set_field() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -qE "^[[:space:]]*${key}=" "$file"; then
        local tmp="${file}.tmp.$$"
        awk -v k="$key" -v v="$value" '
            BEGIN { done = 0 }
            {
                if (!done && $0 ~ "^[[:space:]]*" k "=") {
                    print k "=" v
                    done = 1
                } else {
                    print $0
                }
            }
        ' "$file" > "$tmp"
        mv "$tmp" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# ─── 决策循环 ──────────────────────────────────────────────
actions=""
borrowed_key=""
borrowed_key_tried=0

add_action() {
    if [ -z "$actions" ]; then
        actions="$1"
    else
        actions="$actions,$1"
    fi
}

get_borrowed_key() {
    if [ "$borrowed_key_tried" -eq 0 ]; then
        borrowed_key=$(borrow_api_key)
        borrowed_key_tried=1
    fi
    echo "$borrowed_key"
}

for key in $FIELDS; do
    current=$(get_current_value "$key" "$ENV_FILE")

    if [ "$current" != "__MISSING__" ] && [ -n "$current" ]; then
        continue
    fi

    if [ "$current" != "__MISSING__" ] && [ -z "$current" ]; then
        # 存在但空
        if [ "$key" = "IMAGE_GEN_API_KEY" ]; then
            bk=$(get_borrowed_key)
            if [ -n "$bk" ]; then
                set_field "$key" "$bk" "$ENV_FILE"
                add_action "$key:filled_from_other_target"
            else
                add_action "$key:left_empty_no_source"
            fi
        else
            default_val=$(default_of "$key")
            if [ -n "$default_val" ]; then
                set_field "$key" "$default_val" "$ENV_FILE"
                add_action "$key:filled_default"
            else
                add_action "$key:left_empty_no_default"
            fi
        fi
        continue
    fi

    # 完全缺失 → 追加
    if [ "$key" = "IMAGE_GEN_API_KEY" ]; then
        bk=$(get_borrowed_key)
        if [ -n "$bk" ]; then
            set_field "$key" "$bk" "$ENV_FILE"
            add_action "$key:appended_from_other_target"
        else
            set_field "$key" "" "$ENV_FILE"
            add_action "$key:appended_empty_no_source"
        fi
    else
        default_val=$(default_of "$key")
        set_field "$key" "$default_val" "$ENV_FILE"
        if [ -n "$default_val" ]; then
            add_action "$key:appended_default"
        else
            add_action "$key:appended_empty"
        fi
    fi
done

# ─── 输出 JSON ─────────────────────────────────────────────
if [ -z "$actions" ]; then
    echo "{\"status\":\"skipped\",\"reason\":\"all IMAGE_GEN_* fields already set\",\"target\":\"$TARGET_PATH\"}"
    exit 0
fi

echo "{\"status\":\"ok\",\"detail\":\"$actions\",\"target\":\"$TARGET_PATH\"}"
