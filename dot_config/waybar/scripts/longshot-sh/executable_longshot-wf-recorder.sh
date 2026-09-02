#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [[ "${LONGSHOT_LOCK_HELD:-0}" != "1" ]]; then
    longshot_acquire_lock || exit 0
fi

longshot_require wf-recorder slurp || exit 1
if ! longshot_python_healthy; then
    longshot_notify critical "Longshot" "Python environment is unavailable. Run: $SCRIPT_DIR/setup.sh"
    exit 1
fi

SAVE_DIR="$(longshot_pictures_dir)/Screenshots/longshots"
install -d -m 700 "$SAVE_DIR"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/longshot-wf.XXXXXX")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S_%N)"
TMP_VIDEO="$TMP_DIR/capture.mp4"
OUTPUT_IMG="$SAVE_DIR/longshot_$TIMESTAMP.png"
REC_LOG="$TMP_DIR/wf-recorder.log"
REC_PID=""

cleanup() {
    if [[ -n "$REC_PID" ]] && kill -0 "$REC_PID" 2>/dev/null; then
        kill -INT "$REC_PID" 2>/dev/null || true
        for _ in {1..30}; do
            kill -0 "$REC_PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -TERM "$REC_PID" 2>/dev/null || true
    fi
    rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [[ "$(longshot_lang)" == "zh" ]]; then
    TXT_REC="录制中"
    TXT_STOP="停止并拼接"
    TXT_STITCH="正在拼接长截图..."
    TXT_FAILED="拼接失败，原始视频已保留"
else
    TXT_REC="Recording"
    TXT_STOP="Stop and stitch"
    TXT_STITCH="Stitching long screenshot..."
    TXT_FAILED="Stitching failed; the source video was preserved"
fi

geometry="$(slurp)" || exit 0
[[ -n "$geometry" ]] || exit 0

wf-recorder \
    -g "$geometry" \
    -f "$TMP_VIDEO" \
    -c libx264 \
    -p crf=0 \
    -p preset=ultrafast \
    -p pixel_format=yuv420p \
    >"$REC_LOG" 2>&1 9>&- &
REC_PID=$!

sleep 0.5
if ! kill -0 "$REC_PID" 2>/dev/null; then
    wait "$REC_PID" 2>/dev/null || true
    REC_PID=""
    longshot_notify critical "Longshot" "wf-recorder failed to start"
    exit 1
fi

longshot_menu "$TXT_REC" "$TXT_STOP" >/dev/null || true

kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
REC_PID=""

if [[ ! -s "$TMP_VIDEO" ]]; then
    longshot_notify critical "Longshot" "wf-recorder did not create a video"
    exit 1
fi

longshot_notify low "Longshot" "$TXT_STITCH"
if ! "$LONGSHOT_VENV_PYTHON" "$SCRIPT_DIR/stitch.py" "$TMP_VIDEO" "$OUTPUT_IMG" ||
   [[ ! -s "$OUTPUT_IMG" ]]; then
    recovery="$SAVE_DIR/longshot_failed_$TIMESTAMP.mp4"
    mv -f -- "$TMP_VIDEO" "$recovery"
    longshot_notify critical "Longshot" "$TXT_FAILED: $recovery"
    exit 1
fi

rm -f -- "$TMP_VIDEO"
longshot_finish_image "$OUTPUT_IMG" "$(longshot_read_mode)" >/dev/null
