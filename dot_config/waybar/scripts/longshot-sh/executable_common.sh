#!/usr/bin/env bash

LONGSHOT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

LONGSHOT_CONFIG_DIR="$XDG_CONFIG_HOME/longshot-sh"
LONGSHOT_DATA_DIR="$XDG_DATA_HOME/longshot-sh"
LONGSHOT_STATE_DIR="$XDG_STATE_HOME/longshot-sh"

longshot_remove_tmp_dir() {
    local path="$1" prefix="$2"
    local tmp_root path_parent path_name

    tmp_root="$(readlink -f -- "${TMPDIR:-/tmp}")" || return 1
    path_parent="$(dirname -- "$(readlink -f -- "$path")")" || return 1
    path_name="$(basename -- "$path")"

    if [[ "$path_parent" != "$tmp_root" ||
        "$path_name" != "$prefix".* ||
        ! -f "$path/.longshot-tmp" ]]; then
        printf 'refusing unsafe temporary cleanup: %s\n' "$path" >&2
        return 1
    fi

    /usr/bin/rm -rf -- "$path"
}
LONGSHOT_VENV_DIR="${LONGSHOT_VENV_DIR:-$LONGSHOT_DATA_DIR/venv}"
LONGSHOT_VENV_PYTHON="$LONGSHOT_VENV_DIR/bin/python"

LONGSHOT_MODE_FILE="$LONGSHOT_CONFIG_DIR/mode"
LONGSHOT_BACKEND_FILE="$LONGSHOT_CONFIG_DIR/backend"

install -d -m 700 \
    "$LONGSHOT_CONFIG_DIR" \
    "$LONGSHOT_DATA_DIR" \
    "$LONGSHOT_STATE_DIR"

longshot_lang() {
    local locale="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"
    locale="${locale,,}"
    case "$locale" in
        zh*) printf 'zh\n' ;;
        *)   printf 'en\n' ;;
    esac
}

longshot_notify() {
    local urgency="$1" title="$2" message="$3"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$message"
    else
        printf '%s: %s\n' "$title" "$message" >&2
    fi
}

longshot_write_setting() {
    local path="$1" value="$2" tmp
    tmp="$(mktemp "$LONGSHOT_CONFIG_DIR/.setting.XXXXXX")"
    printf '%s\n' "$value" >"$tmp"
    mv -f -- "$tmp" "$path"
}

longshot_read_mode() {
    local value="PREVIEW"
    [[ -r "$LONGSHOT_MODE_FILE" ]] && IFS= read -r value <"$LONGSHOT_MODE_FILE"
    case "$value" in
        PREVIEW|EDIT|SAVE) printf '%s\n' "$value" ;;
        *)                printf 'PREVIEW\n' ;;
    esac
}

longshot_read_backend() {
    local value="WF"
    [[ -r "$LONGSHOT_BACKEND_FILE" ]] && IFS= read -r value <"$LONGSHOT_BACKEND_FILE"
    case "$value" in
        WF|GRIM) printf '%s\n' "$value" ;;
        *)       printf 'WF\n' ;;
    esac
}

longshot_pictures_dir() {
    local pictures=""
    if command -v xdg-user-dir >/dev/null 2>&1; then
        pictures="$(xdg-user-dir PICTURES 2>/dev/null || true)"
    fi
    printf '%s\n' "${pictures:-$HOME/Pictures}"
}

longshot_python_healthy() {
    [[ -x "$LONGSHOT_VENV_PYTHON" ]] &&
        "$LONGSHOT_VENV_PYTHON" -c 'import cv2, numpy' >/dev/null 2>&1
}

longshot_require() {
    local missing=() command
    for command in "$@"; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done
    ((${#missing[@]} == 0)) && return 0

    local message
    if [[ "$(longshot_lang)" == "zh" ]]; then
        message="缺少命令：${missing[*]}"
    else
        message="Missing commands: ${missing[*]}"
    fi
    longshot_notify critical "Longshot" "$message"
    return 1
}

longshot_select_menu_backend() {
    local command
    for command in fuzzel wofi rofi; do
        if command -v "$command" >/dev/null 2>&1; then
            printf '%s\n' "$command"
            return 0
        fi
    done
    return 1
}

longshot_menu() {
    local prompt="$1"
    shift
    local backend selection
    backend="$(longshot_select_menu_backend)" || {
        longshot_notify critical "Longshot" "Missing menu command: fuzzel, wofi or rofi"
        return 1
    }

    case "$backend" in
        fuzzel)
            selection="$(
                printf '%s\n' "$@" |
                    fuzzel --dmenu --anchor top --y-margin 20 --width 35 \
                        --lines "$#" --prompt "$prompt"
            )" || return 1
            ;;
        wofi)
            selection="$(printf '%s\n' "$@" | wofi --dmenu --prompt "$prompt")" || return 1
            ;;
        rofi)
            selection="$(printf '%s\n' "$@" | rofi -dmenu -p "$prompt")" || return 1
            ;;
    esac

    [[ -n "$selection" ]] || return 1
    printf '%s\n' "$selection"
}

longshot_runtime_base() {
    local runtime="${XDG_RUNTIME_DIR:-}"
    if [[ "$runtime" == /* && -d "$runtime" && -w "$runtime" &&
          "$(stat -c '%u' "$runtime" 2>/dev/null || printf '%s' -1)" == "$UID" ]]; then
        printf '%s\n' "$runtime"
        return 0
    fi

    runtime="${TMPDIR:-/tmp}/longshot-runtime-$UID"
    if [[ -e "$runtime" &&
          (! -d "$runtime" ||
           "$(stat -c '%u' "$runtime" 2>/dev/null || printf '%s' -1)" != "$UID") ]]; then
        printf 'Unsafe runtime fallback: %s\n' "$runtime" >&2
        return 1
    fi
    install -d -m 700 "$runtime"
    printf '%s\n' "$runtime"
}

longshot_acquire_lock() {
    local runtime
    runtime="$(longshot_runtime_base)" || return 1
    install -d -m 700 "$runtime/longshot-sh"
    exec 9>"$runtime/longshot-sh/lock"
    if ! flock -n 9; then
        if [[ "$(longshot_lang)" == "zh" ]]; then
            longshot_notify low "Longshot" "已有长截图任务正在运行"
        else
            longshot_notify low "Longshot" "Another longshot task is already running"
        fi
        return 1
    fi
}

longshot_open_image() {
    local image="$1" viewer
    for viewer in imv swayimg; do
        if command -v "$viewer" >/dev/null 2>&1; then
            "$viewer" "$image" 9>&-
            return $?
        fi
    done
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$image" >/dev/null 2>&1 9>&-
        return $?
    fi
    longshot_notify normal "Longshot" "Saved: $image"
}

longshot_copy_image() {
    local image="$1"
    command -v wl-copy >/dev/null 2>&1 || return 0
    wl-copy --type image/png <"$image" 9>&-
}

longshot_finish_image() {
    local image="$1" mode="$2" final="$1" edited

    case "$mode" in
        EDIT)
            if command -v satty >/dev/null 2>&1; then
                edited="${image%.png}_edited.png"
                if satty --filename "$image" --output-filename "$edited" 9>&- &&
                   [[ -s "$edited" ]]; then
                    final="$edited"
                fi
            else
                longshot_notify normal "Longshot" "satty is missing; opening preview instead"
                longshot_open_image "$image" || true
            fi
            ;;
        PREVIEW)
            longshot_open_image "$image" || true
            ;;
        SAVE)
            ;;
        *)
            longshot_notify normal "Longshot" "Unknown mode '$mode'; saved without opening"
            ;;
    esac

    longshot_copy_image "$final" || true
    longshot_notify low "Longshot" "Saved: $final"
    printf '%s\n' "$final"
}
