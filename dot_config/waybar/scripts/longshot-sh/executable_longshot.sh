#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

longshot_acquire_lock || exit 0
export LONGSHOT_LOCK_HELD=1

if [[ ! -e "$LONGSHOT_MODE_FILE" ]]; then
    longshot_write_setting "$LONGSHOT_MODE_FILE" "PREVIEW"
fi
if [[ ! -e "$LONGSHOT_BACKEND_FILE" ]]; then
    longshot_write_setting "$LONGSHOT_BACKEND_FILE" "WF"
fi

if [[ "$(longshot_lang)" == "zh" ]]; then
    TXT_TITLE_WF="缓慢滚动，选择停止后结束"
    TXT_TITLE_GRIM="记住截图末尾位置"
    TXT_START="📷 选择截图区域"
    TXT_SETTING="⚙️ 设置"
    TXT_EXIT="❌ 退出"
    TXT_BACK="🔙 返回主菜单"
    TXT_SW_BACKEND="📹 切换后端"
    TXT_SW_ACTION="🛠 切换动作"
    TXT_PROMPT_ACTION="请选择截图后的动作"
    TXT_ST_WF="流式录制 (wf-recorder)"
    TXT_ST_GRIM="分段截图 (grim)"
    TXT_ST_PRE="预览"
    TXT_ST_EDIT="编辑 (satty)"
    TXT_ST_SAVE="仅保存"
    TXT_SETUP="Python 环境不可用。请运行：$SCRIPT_DIR/setup.sh"
else
    TXT_TITLE_WF="Scroll slowly, then choose Stop"
    TXT_TITLE_GRIM="Remember the end position"
    TXT_START="📷 Select Area"
    TXT_SETTING="⚙️ Settings"
    TXT_EXIT="❌ Exit"
    TXT_BACK="🔙 Back"
    TXT_SW_BACKEND="📹 Switch Backend"
    TXT_SW_ACTION="🛠 Switch Action"
    TXT_PROMPT_ACTION="Select action after capture"
    TXT_ST_WF="Stream (wf-recorder)"
    TXT_ST_GRIM="Manual (grim)"
    TXT_ST_PRE="Preview"
    TXT_ST_EDIT="Edit (satty)"
    TXT_ST_SAVE="Save Only"
    TXT_SETUP="Python environment is unavailable. Run: $SCRIPT_DIR/setup.sh"
fi

mode_label() {
    case "$1" in
        PREVIEW) printf '%s\n' "$TXT_ST_PRE" ;;
        EDIT)    printf '%s\n' "$TXT_ST_EDIT" ;;
        SAVE)    printf '%s\n' "$TXT_ST_SAVE" ;;
    esac
}

backend_label() {
    case "$1" in
        WF)   printf '%s\n' "$TXT_ST_WF" ;;
        GRIM) printf '%s\n' "$TXT_ST_GRIM" ;;
    esac
}

ensure_backend_ready() {
    local backend="$1"
    if [[ "$backend" == "WF" ]]; then
        longshot_require wf-recorder slurp || return 1
        if ! longshot_python_healthy; then
            longshot_notify critical "Longshot" "$TXT_SETUP"
            return 1
        fi
    else
        longshot_require grim slurp magick || return 1
    fi
}

while :; do
    current_mode="$(longshot_read_mode)"
    current_backend="$(longshot_read_backend)"

    if [[ "$current_backend" == "WF" ]]; then
        title="$TXT_TITLE_WF"
    else
        title="$TXT_TITLE_GRIM"
    fi

    setting_label="$TXT_SETTING  [$(backend_label "$current_backend") | $(mode_label "$current_mode")]"
    choice="$(longshot_menu "$title" "$TXT_START" "$setting_label" "$TXT_EXIT")" || exit 0

    case "$choice" in
        "$TXT_START")
            ensure_backend_ready "$current_backend" || exit 1
            if [[ "$current_backend" == "WF" ]]; then
                exec "$SCRIPT_DIR/longshot-wf-recorder.sh"
            else
                exec "$SCRIPT_DIR/longshot-grim.sh"
            fi
            ;;
        "$setting_label")
            while :; do
                current_mode="$(longshot_read_mode)"
                current_backend="$(longshot_read_backend)"
                backend_item="$TXT_SW_BACKEND [$(backend_label "$current_backend")]"
                action_item="$TXT_SW_ACTION [$(mode_label "$current_mode")]"

                setting_choice="$(
                    longshot_menu "$TXT_SETTING" "$TXT_BACK" "$backend_item" "$action_item"
                )" || exit 0

                case "$setting_choice" in
                    "$TXT_BACK")
                        break
                        ;;
                    "$backend_item")
                        if [[ "$current_backend" == "WF" ]]; then
                            longshot_write_setting "$LONGSHOT_BACKEND_FILE" "GRIM"
                        else
                            longshot_write_setting "$LONGSHOT_BACKEND_FILE" "WF"
                        fi
                        ;;
                    "$action_item")
                        action_choice="$(
                            longshot_menu "$TXT_PROMPT_ACTION" \
                                "$TXT_ST_PRE" "$TXT_ST_EDIT" "$TXT_ST_SAVE"
                        )" || continue
                        case "$action_choice" in
                            "$TXT_ST_PRE")  longshot_write_setting "$LONGSHOT_MODE_FILE" "PREVIEW" ;;
                            "$TXT_ST_EDIT") longshot_write_setting "$LONGSHOT_MODE_FILE" "EDIT" ;;
                            "$TXT_ST_SAVE") longshot_write_setting "$LONGSHOT_MODE_FILE" "SAVE" ;;
                        esac
                        ;;
                    *)
                        exit 0
                        ;;
                esac
            done
            ;;
        *)
            exit 0
            ;;
    esac
done
