#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [[ "${LONGSHOT_LOCK_HELD:-0}" != "1" ]]; then
    longshot_acquire_lock || exit 0
fi

longshot_require grim slurp magick || exit 1

SAVE_DIR="$(longshot_pictures_dir)/Screenshots/longshots"
install -d -m 700 "$SAVE_DIR"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/longshot-grim.XXXXXX")"
: >"$TMP_DIR/.longshot-tmp"
TIMESTAMP="$(date +%Y%m%d_%H%M%S_%N)"
RESULT_PATH="$SAVE_DIR/longshot_$TIMESTAMP.png"
TMP_STITCHED="$TMP_DIR/stitched.png"
KEEP_TMP=false
RECOVERY_PATH=""

cleanup() {
    [[ "$KEEP_TMP" == true ]] ||
        longshot_remove_tmp_dir "$TMP_DIR" "longshot-grim"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [[ "$(longshot_lang)" == "zh" ]]; then
    STR_NEXT="📸 截取下一张（仅取高度）"
    STR_FINISH="💾 完成并处理"
    STR_ABORT="❌ 放弃"
else
    STR_NEXT="📸 Capture next (height only)"
    STR_FINISH="💾 Finish"
    STR_ABORT="❌ Abort"
fi

geometry="$(slurp)" || exit 0
[[ -n "$geometry" ]] || exit 0

IFS=', x' read -r fixed_x _fixed_y fixed_width _fixed_height <<<"$geometry"
[[ "$fixed_x" =~ ^-?[0-9]+$ && "$fixed_width" =~ ^[0-9]+$ ]] || {
    longshot_notify critical "Longshot" "Invalid screenshot geometry: $geometry"
    exit 1
}

grim -g "$geometry" "$TMP_DIR/001.png"
[[ -s "$TMP_DIR/001.png" ]] || {
    longshot_notify critical "Longshot" "The first screenshot failed"
    exit 1
}

index=2
do_save=false

while :; do
    action="$(longshot_menu "Longshot" "$STR_NEXT" "$STR_FINISH" "$STR_ABORT")" || exit 0
    case "$action" in
        "$STR_NEXT")
            next_geometry="$(slurp)" || continue
            [[ -n "$next_geometry" ]] || continue
            IFS=', x' read -r _next_x next_y _next_width next_height <<<"$next_geometry"
            [[ "$next_y" =~ ^-?[0-9]+$ && "$next_height" =~ ^[0-9]+$ ]] || continue

            final_geometry="${fixed_x},${next_y} ${fixed_width}x${next_height}"
            image_name="$(printf '%03d.png' "$index")"
            if grim -g "$final_geometry" "$TMP_DIR/$image_name" &&
               [[ -s "$TMP_DIR/$image_name" ]]; then
                ((index += 1))
            else
                rm -f -- "$TMP_DIR/$image_name"
                longshot_notify normal "Longshot" "Screenshot failed; please try again"
            fi
            ;;
        "$STR_FINISH")
            do_save=true
            break
            ;;
        "$STR_ABORT")
            exit 0
            ;;
    esac
done

[[ "$do_save" == true ]] || exit 0

shopt -s nullglob
images=("$TMP_DIR"/[0-9][0-9][0-9].png)
((${#images[@]} > 0)) || {
    longshot_notify critical "Longshot" "No screenshots to stitch"
    exit 1
}

preserve_frames() {
    local recovery_dir="$SAVE_DIR/longshot_failed_frames_$TIMESTAMP"

    # 先阻止 EXIT trap 删除源帧；即使复制恢复目录失败，/tmp 中仍有原图。
    KEEP_TMP=true
    if install -d -m 700 "$recovery_dir" &&
       cp -p -- "${images[@]}" "$recovery_dir/"; then
        KEEP_TMP=false
        RECOVERY_PATH="$recovery_dir"
    else
        RECOVERY_PATH="$TMP_DIR"
    fi
}

if ! magick "${images[@]}" -append "$TMP_STITCHED" || [[ ! -s "$TMP_STITCHED" ]]; then
    preserve_frames
    longshot_notify critical "Longshot" \
        "ImageMagick failed; source screenshots were kept at $RECOVERY_PATH"
    exit 1
fi

if ! mv -f -- "$TMP_STITCHED" "$RESULT_PATH"; then
    preserve_frames
    longshot_notify critical "Longshot" \
        "Could not save the result; source screenshots were kept at $RECOVERY_PATH"
    exit 1
fi
longshot_finish_image "$RESULT_PATH" "$(longshot_read_mode)" >/dev/null
