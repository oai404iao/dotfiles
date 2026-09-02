#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

########################
# 配置区域（直接改这里）
########################

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
NIRI_CONFIG="${NIRI_CONFIG:-$XDG_CONFIG_HOME/niri/config.kdl}"

SHOTEDITOR_DEFAULT="satty"                   # 默认截图编辑器：swappy 或 satty
COPY_CMD="wl-copy"                            # 复制到剪贴板的命令

# 菜单程序使用数组，避免 eval 重新解释提示文本。
MENU_CMD=(fuzzel --dmenu)

# 图片目录
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || true)"
PICTURES_DIR="${PICTURES_DIR:-$HOME/Pictures}"
SCREEN_DIR="$PICTURES_DIR/Screenshots"

########################
# 本地化（中/英）
########################

LOCALE="${LC_MESSAGES:-${LANG:-en}}"
if [[ "$LOCALE" == zh* ]]; then
    # 通用
    LABEL_CANCEL="取消"
    LABEL_SETTINGS="设置"
    LABEL_EDIT_YES="编辑"
    LABEL_EDIT_NO="不编辑"

    # Niri 模式
    LABEL_NIRI_FULL="全屏"
    LABEL_NIRI_WINDOW="窗口"
    LABEL_NIRI_REGION="选取区域"

    # Grim 模式
    LABEL_GRIM_FULL="全屏"
    LABEL_GRIM_REGION="选取区域"

    # 设置菜单
    LABEL_SETTINGS_EDITOR="截图工具"
    LABEL_SETTINGS_BACKEND="后端模式"
    LABEL_BACKEND_AUTO="自动（检测 Niri）"
    LABEL_BACKEND_GRIM="仅 Grim+slurp"
    LABEL_BACK="返回"

    # 编辑开关显示
    LABEL_EDIT_STATE_ON="编辑：开启"
    LABEL_EDIT_STATE_OFF="编辑：关闭"

    # 提示文字
    PROMPT_MAIN="请选择截图模式"
    PROMPT_SETTINGS="设置 / 更改选项"
    PROMPT_EDITOR="请选择截图编辑工具"
    PROMPT_BACKEND="请选择后端模式"
else
    LABEL_CANCEL="Cancel"
    LABEL_SETTINGS="Settings"
    LABEL_EDIT_YES="Edit"
    LABEL_EDIT_NO="No edit"

    LABEL_NIRI_FULL="Fullscreen"
    LABEL_NIRI_WINDOW="Window"
    LABEL_NIRI_REGION="Region"

    LABEL_GRIM_FULL="Fullscreen"
    LABEL_GRIM_REGION="Select area"

    LABEL_SETTINGS_EDITOR="Screenshot tool"
    LABEL_SETTINGS_BACKEND="Backend mode"
    LABEL_BACKEND_AUTO="Auto (detect Niri)"
    LABEL_BACKEND_GRIM="Grim+slurp only"
    LABEL_BACK="Back"

    LABEL_EDIT_STATE_ON="Edit: ON"
    LABEL_EDIT_STATE_OFF="Edit: OFF"

    PROMPT_MAIN="Choose screenshot mode"
    PROMPT_SETTINGS="Settings / Options"
    PROMPT_EDITOR="Choose screenshot editor"
    PROMPT_BACKEND="Choose backend mode"
fi

########################
# 持久化配置路径
########################

CONFIG_DIR="$XDG_CONFIG_HOME/waybar-power-screenshot-sh"

BACKEND_FILE="$CONFIG_DIR/backend"
EDITOR_FILE="$CONFIG_DIR/editor"
EDIT_MODE_FILE="$CONFIG_DIR/edit_mode"   # yes / no

# 用户偏好必须能跨缓存清理保留。
install -d -m 700 "$CONFIG_DIR"

# 本次运行创建的临时文件统一清理。
TMP_FILES=()
cleanup() {
    local file
    for file in "${TMP_FILES[@]}"; do
        rm -f -- "$file"
    done
}
trap cleanup EXIT

########################
# 通用工具函数
########################

menu() {
    printf '%s\n' "$@" | "${MENU_CMD[@]}" 2>/dev/null || true
}

menu_prompt() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" | "${MENU_CMD[@]}" --prompt "$prompt" 2>/dev/null || true
}

load_backend_mode() {
    local mode
    if [[ -n "${SHOT_BACKEND:-}" ]]; then
        mode="$SHOT_BACKEND"
    elif [[ -f "$BACKEND_FILE" ]]; then
        mode="$(<"$BACKEND_FILE")"
    else
        mode="auto"
    fi
    case "$mode" in
        auto|grim|niri) ;;
        *) mode="auto" ;;
    esac
    printf '%s\n' "$mode"
}

save_backend_mode() {
    local mode="$1"
    write_setting "$BACKEND_FILE" "$mode"
}

load_editor() {
    local ed
    if [[ -n "${SHOTEDITOR:-}" ]]; then
        ed="$SHOTEDITOR"
    elif [[ -f "$EDITOR_FILE" ]]; then
        ed="$(<"$EDITOR_FILE")"
    else
        ed="$SHOTEDITOR_DEFAULT"
    fi

    ed="${ed,,}"
    case "$ed" in
        swappy|satty) ;;
        *) ed="$SHOTEDITOR_DEFAULT" ;;
    esac
    printf '%s\n' "$ed"
}

save_editor() {
    local ed="$1"
    write_setting "$EDITOR_FILE" "$ed"
}

load_edit_mode() {
    local v="yes"
    if [[ -f "$EDIT_MODE_FILE" ]]; then
        v="$(<"$EDIT_MODE_FILE")"
    fi
    case "$v" in
        yes|no) ;;
        *) v="yes" ;;    # 默认：编辑开启
    esac
    printf '%s\n' "$v"
}

save_edit_mode() {
    local v="$1"
    write_setting "$EDIT_MODE_FILE" "$v"
}

write_setting() {
    local path="$1" value="$2" tmp
    tmp="$(mktemp "$CONFIG_DIR/.setting.XXXXXX")"
    printf '%s\n' "$value" >"$tmp"
    mv -f -- "$tmp" "$path"
}

detect_backend() {
    case "$BACKEND_MODE" in
        niri) echo "niri" ;;
        grim) echo "grim" ;;
        auto|*)
            if command -v niri >/dev/null 2>&1 && pgrep -x niri >/dev/null 2>&1; then
                echo "niri"
            else
                echo "grim"
            fi
            ;;
    esac
}

choose_editor() {
    local choice
    choice="$(menu_prompt "$PROMPT_EDITOR" "swappy" "satty" "$LABEL_BACK")"
    case "$choice" in
        swappy|Swappy)
            SHOTEDITOR="swappy"
            save_editor "$SHOTEDITOR"
            ;;
        satty|Satty)
            SHOTEDITOR="satty"
            save_editor "$SHOTEDITOR"
            ;;
        *) : ;;
    esac
}

choose_backend_mode() {
    local choice
    choice="$(menu_prompt "$PROMPT_BACKEND" "$LABEL_BACKEND_AUTO" "$LABEL_BACKEND_GRIM" "$LABEL_BACK")"
    case "$choice" in
        "$LABEL_BACKEND_AUTO")
            BACKEND_MODE="auto"
            save_backend_mode "$BACKEND_MODE"
            ;;
        "$LABEL_BACKEND_GRIM")
            BACKEND_MODE="grim"
            save_backend_mode "$BACKEND_MODE"
            ;;
        *) : ;;
    esac
}

settings_menu() {
    while :; do
        local backend_desc editor_line backend_line choice

        if [[ -n "${SHOT_BACKEND:-}" ]]; then
            backend_desc="${BACKEND_MODE} (env)"
        else
            if [[ "$BACKEND_MODE" == "grim" ]]; then
                backend_desc="$LABEL_BACKEND_GRIM"
            elif [[ "$BACKEND_MODE" == "niri" ]]; then
                backend_desc="niri"
            else
                backend_desc="$LABEL_BACKEND_AUTO"
            fi
        fi

        editor_line="$LABEL_SETTINGS_EDITOR: $SHOTEDITOR"
        backend_line="$LABEL_SETTINGS_BACKEND: $backend_desc"

        choice="$(menu_prompt "$PROMPT_SETTINGS" "$editor_line" "$backend_line" "$LABEL_BACK")"
        case "$choice" in
            "$editor_line")  choose_editor ;;
            "$backend_line")
                if [[ -n "${SHOT_BACKEND:-}" ]]; then
                    : # 环境变量强制时不改持久化
                else
                    choose_backend_mode
                fi
                ;;
            *)               return ;;  # 返回上一层
        esac
    done
}

wait_for_screenshot() {
    local shot="$1" timeout_seconds="$2"
    local size=0 last_size=-1 stable_checks=0
    local deadline=$((SECONDS + timeout_seconds))

    while ((SECONDS < deadline)); do
        size="$(stat -c '%s' -- "$shot" 2>/dev/null || printf '0')"
        if [[ "$size" =~ ^[0-9]+$ ]] && ((size > 0)); then
            if ((size == last_size)); then
                stable_checks=$((stable_checks + 1))
                ((stable_checks >= 2)) && return 0
            else
                stable_checks=0
                last_size="$size"
            fi
        fi
        sleep 0.05
    done
    return 1
}

########################
# Niri 相关
########################

get_niri_shot_dir() {
    local line tpl dir config_dir file
    local -a config_files=()

    [[ -f "$NIRI_CONFIG" ]] && config_files+=("$NIRI_CONFIG")
    config_dir="$(dirname -- "$NIRI_CONFIG")"
    if [[ -d "$config_dir/conf.d" ]]; then
        while IFS= read -r -d '' file; do
            config_files+=("$file")
        done < <(
            find "$config_dir/conf.d" -maxdepth 1 -type f -name '*.kdl' \
                -print0
        )
    fi

    if ((${#config_files[@]} == 0)); then
        printf '%s\n' "$SCREEN_DIR"
        return 0
    fi

    line="$(
        grep -hE '^[[:space:]]*screenshot-path[[:space:]]' \
            "${config_files[@]}" |
            grep -v '^[[:space:]]*//' |
            tail -n 1 || true
    )"
    if [[ -z "$line" ]]; then
        printf '%s\n' "$SCREEN_DIR"
        return 0
    fi

    tpl="$(sed -E 's/.*screenshot-path[[:space:]]+"([^"]+)".*/\1/' <<<"$line")"
    if [[ -z "$tpl" || "$tpl" == "$line" ]]; then
        printf '%s\n' "$SCREEN_DIR"
        return 0
    fi

    tpl="${tpl/#\~/$HOME}"
    dir="$(dirname -- "$tpl")"

    printf '%s\n' "$dir"
}

# Grim 用：从文件编辑
edit_file_image() {
    local src="$1"
    local backend="$2"  # "niri" 或 "grim"

    local dir ts dst

    if [[ "$backend" == "niri" ]]; then
        dir="$NIRI_EDIT_DIR"
    else
        dir="$SCREEN_DIR"
    fi

    mkdir -p "$dir"
    ts="$(date +'%Y-%m-%d_%H-%M-%S-%N')"
    dst="$dir/$SHOTEDITOR-$ts.png"

    case "$SHOTEDITOR" in
        satty)
            command -v satty >/dev/null 2>&1 || {
                echo "Missing screenshot editor: satty" >&2
                return 1
            }
            satty --filename "$src" --output-filename "$dst" || return 1
            ;;
        swappy)
            command -v swappy >/dev/null 2>&1 || {
                echo "Missing screenshot editor: swappy" >&2
                return 1
            }
            swappy -f "$src" -o "$dst" || return 1
            ;;
        *)
            echo "Unknown SHOTEDITOR: $SHOTEDITOR (use satty or swappy)" >&2
            return 1
            ;;
    esac

    if [[ -s "$dst" ]] && command -v "$COPY_CMD" >/dev/null 2>&1; then
        # wl-copy 通常会 fork 为后台剪贴板服务；不得让它继承菜单锁。
        "$COPY_CMD" --type image/png <"$dst" 9>&-
    fi
}

niri_capture_and_maybe_edit() {
    local mode="$1"       # fullscreen / window / region
    local need_edit="$2"  # yes / no

    local action
    case "$mode" in
        fullscreen) action="screenshot-screen" ;;
        window)     action="screenshot-window" ;;
        region)     action="screenshot"       ;;
        *)          return 0 ;;
    esac

    local shot timeout_seconds ts
    ts="$(date +'%Y-%m-%d_%H-%M-%S-%N')"
    shot="$NIRI_SHOT_DIR/Screenshot_$ts.png"
    timeout_seconds="${SHOT_TIMEOUT:-15}"
    [[ "$mode" == "region" ]] && timeout_seconds="${SHOT_REGION_TIMEOUT:-120}"
    [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || timeout_seconds=15

    # niri 25.11+ 可接收精确输出路径，避免把其他并发截图误认为本次结果。
    if ! niri msg action "$action" --path "$shot"; then
        echo "Niri screenshot action failed: $action" >&2
        return 1
    fi

    if ! wait_for_screenshot "$shot" "$timeout_seconds"; then
        echo "Timed out waiting for Niri screenshot" >&2
        command -v notify-send >/dev/null 2>&1 &&
            notify-send -u normal "Screenshot" "Screenshot cancelled or timed out"
        return 1
    fi

    if [[ "$need_edit" == "yes" ]]; then
        edit_file_image "$shot" "niri"
    fi
    return 0
}

run_niri_flow() {
    NIRI_SHOT_DIR="$(get_niri_shot_dir)" || return 0
    NIRI_EDIT_DIR="$NIRI_SHOT_DIR/Edited"
    mkdir -p "$NIRI_SHOT_DIR" "$NIRI_EDIT_DIR"

    while :; do
        local choice mode edit_mode edit_label

        edit_mode="$(load_edit_mode)"
        if [[ "$edit_mode" == "yes" ]]; then
            edit_label="$LABEL_EDIT_STATE_ON"
        else
            edit_label="$LABEL_EDIT_STATE_OFF"
        fi

        choice="$(menu_prompt "$PROMPT_MAIN" \
            "$LABEL_NIRI_FULL" \
            "$LABEL_NIRI_WINDOW" \
            "$LABEL_NIRI_REGION" \
            "$edit_label" \
            "$LABEL_SETTINGS" \
            "$LABEL_CANCEL"
        )"

        [[ -z "$choice" || "$choice" == "$LABEL_CANCEL" ]] && return 2

        case "$choice" in
            "$LABEL_NIRI_FULL")   mode="fullscreen" ;;
            "$LABEL_NIRI_WINDOW") mode="window"     ;;
            "$LABEL_NIRI_REGION") mode="region"     ;;
            "$edit_label")
                if [[ "$edit_mode" == "yes" ]]; then
                    save_edit_mode "no"
                else
                    save_edit_mode "yes"
                fi
                continue
                ;;
            "$LABEL_SETTINGS")
                # 进入设置菜单（可以在里面改 editor / backend / edit-mode）
                settings_menu

                # 立即重新加载持久化配置，使修改即时生效
                SHOTEDITOR="$(load_editor)"
                BACKEND_MODE="$(load_backend_mode)"

                # 检查后端是否被改动；若改动则通知上层切换后端
                NEW_BACKEND="$(detect_backend)"
                if [[ "$NEW_BACKEND" != "niri" ]]; then
                    return 1
                fi

                continue
                ;;
            *)
                return 2
                ;;
        esac

        edit_mode="$(load_edit_mode)"
        if [[ "$edit_mode" == "yes" ]]; then
            niri_capture_and_maybe_edit "$mode" "yes" || return 2
        else
            niri_capture_and_maybe_edit "$mode" "no" || return 2
        fi

        # 截图完成后退出（主循环会根据返回码决定是否结束脚本）
        return 0
    done
}

########################
# Grim + slurp 相关
########################

grim_capture_and_maybe_edit() {
    local mode="$1"       # fullscreen / region
    local need_edit="$2"  # yes / no

    mkdir -p "$SCREEN_DIR"

    local ts shot geo
    ts="$(date +'%Y-%m-%d_%H-%M-%S-%N')"

    if [[ "$need_edit" == "yes" ]]; then
        # 编辑模式：私有临时原图，用完由 EXIT trap 清理。
        shot="$(mktemp "${TMPDIR:-/tmp}/waybar-shot.XXXXXX.png")"
        TMP_FILES+=("$shot")

        case "$mode" in
            fullscreen)
                grim "$shot" || return 1
                ;;
            region)
                geo="$(slurp 2>/dev/null)" || return 0
                [[ -n "$geo" ]] || return 0
                grim -g "$geo" "$shot" || return 1
                ;;
            *)
                return 0 ;;
        esac

        edit_file_image "$shot" "grim"
        return 0
    else
        # 不编辑：原图保存到 Screenshots
        shot="$SCREEN_DIR/Screenshot_$ts.png"

        case "$mode" in
            fullscreen)
                grim "$shot" || return 1
                ;;
            region)
                geo="$(slurp 2>/dev/null)" || return 0
                [[ -n "$geo" ]] || return 0
                grim -g "$geo" "$shot" || return 1
                ;;
            *)
                return 0 ;;
        esac
        return 0
    fi
}

run_grim_flow() {
    mkdir -p "$SCREEN_DIR"

    while :; do
        local choice mode edit_mode edit_label

        edit_mode="$(load_edit_mode)"
        if [[ "$edit_mode" == "yes" ]]; then
            edit_label="$LABEL_EDIT_STATE_ON"
        else
            edit_label="$LABEL_EDIT_STATE_OFF"
        fi

        choice="$(menu_prompt "$PROMPT_MAIN" \
            "$LABEL_GRIM_FULL" \
            "$LABEL_GRIM_REGION" \
            "$edit_label" \
            "$LABEL_SETTINGS" \
            "$LABEL_CANCEL"
        )"

        [[ -z "$choice" || "$choice" == "$LABEL_CANCEL" ]] && return 2

        case "$choice" in
            "$LABEL_GRIM_FULL")   mode="fullscreen" ;;
            "$LABEL_GRIM_REGION") mode="region"     ;;
            "$edit_label")
                if [[ "$edit_mode" == "yes" ]]; then
                    save_edit_mode "no"
                else
                    save_edit_mode "yes"
                fi
                continue
                ;;
            "$LABEL_SETTINGS")
                settings_menu

                # 立即重新加载持久化配置，使修改即时生效
                SHOTEDITOR="$(load_editor)"
                BACKEND_MODE="$(load_backend_mode)"

                NEW_BACKEND="$(detect_backend)"
                if [[ "$NEW_BACKEND" != "grim" ]]; then
                    return 1
                fi

                continue
                ;;
            *)
                return 2
                ;;
        esac

        edit_mode="$(load_edit_mode)"
        if [[ "$edit_mode" == "yes" ]]; then
            grim_capture_and_maybe_edit "$mode" "yes" || return 2
        else
            grim_capture_and_maybe_edit "$mode" "no" || return 2
        fi

        return 0
    done
}

########################
# 入口（主循环）
########################

notify_error() {
    local message="$1"
    echo "$message" >&2
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u critical "Screenshot" "$message"
}

for required in fuzzel xdg-user-dir; do
    command -v "$required" >/dev/null 2>&1 || {
        notify_error "Missing command: $required"
        exit 1
    }
done

runtime_base="${XDG_RUNTIME_DIR:-}"
if [[ "$runtime_base" != /* || ! -d "$runtime_base" || ! -w "$runtime_base" ]]; then
    runtime_base="${TMPDIR:-/tmp}/waybar-shot-runtime-$UID"
    if [[ -e "$runtime_base" &&
          (! -d "$runtime_base" ||
           "$(stat -c '%u' "$runtime_base" 2>/dev/null || printf '%s' -1)" != "$UID") ]]; then
        notify_error "Unsafe runtime fallback: $runtime_base"
        exit 1
    fi
    install -d -m 700 "$runtime_base"
fi
install -d -m 700 "$runtime_base/waybar-power-screenshot"
exec 9>"$runtime_base/waybar-power-screenshot/lock"
if ! flock -n 9; then
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u low "Screenshot" "Screenshot menu is already open"
    exit 0
fi

while :; do
    BACKEND_MODE="$(load_backend_mode)"
    SHOTEDITOR="$(load_editor)"

    BACKEND="$(detect_backend)"

    case "$BACKEND" in
        niri)
            for required in niri "$SHOTEDITOR"; do
                command -v "$required" >/dev/null 2>&1 || {
                    notify_error "Missing command: $required"
                    exit 1
                }
            done
            rc=0
            run_niri_flow || rc=$?
            if [[ "$rc" -eq 0 ]]; then
                exit 0
            elif [[ "$rc" -eq 1 ]]; then
                # 后端切换：继续主循环以根据新后端重试
                continue
            else
                # 取消或其他：退出
                exit 0
            fi
            ;;
        grim)
            for required in grim slurp "$SHOTEDITOR"; do
                command -v "$required" >/dev/null 2>&1 || {
                    notify_error "Missing command: $required"
                    exit 1
                }
            done
            rc=0
            run_grim_flow || rc=$?
            if [[ "$rc" -eq 0 ]]; then
                exit 0
            elif [[ "$rc" -eq 1 ]]; then
                continue
            else
                exit 0
            fi
            ;;
        *)
            run_grim_flow
            exit 0
            ;;
    esac
done
