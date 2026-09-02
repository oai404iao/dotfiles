#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ================== Runtime state & Persistent Config ==================
SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"

# --- 运行时状态 (应在每次会话结束时消失, 遵循 XDG_RUNTIME_DIR) ---
runtime_base="${XDG_RUNTIME_DIR:-}"
if [[ "$runtime_base" != /* || ! -d "$runtime_base" || ! -w "$runtime_base" ||
      "$(stat -c '%u' "$runtime_base" 2>/dev/null || printf '%s' -1)" != "$UID" ]]; then
  runtime_base="${TMPDIR:-/tmp}/wfrec-runtime-$UID"
  if [[ -e "$runtime_base" &&
        (! -d "$runtime_base" ||
         "$(stat -c '%u' "$runtime_base" 2>/dev/null || printf '%s' -1)" != "$UID") ]]; then
    printf 'Unsafe runtime fallback: %s\n' "$runtime_base" >&2
    exit 1
  fi
  install -d -m 700 "$runtime_base"
fi

STATE_DIR="$runtime_base/wfrec"

PIDFILE="$STATE_DIR/pid"
PIDSTARTFILE="$STATE_DIR/pid.starttime"
STARTFILE="$STATE_DIR/start"
SAVEPATH_FILE="$STATE_DIR/save_path"
MODEFILE="$STATE_DIR/mode"             # full/region -> tooltip
LOCKFILE="$STATE_DIR/lock"

# --- 持久性配置 ---
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/wf-recorder-sh"
LOG_DIR="$XDG_STATE_HOME/wf-recorder-sh"
LOG_FILE="$LOG_DIR/last-run.log"

CFG_CODEC="$CONFIG_DIR/codec"
CFG_FPS="$CONFIG_DIR/framerate"
CFG_AUDIO="$CONFIG_DIR/audio"
CFG_DRM="$CONFIG_DIR/drm_device"
CFG_EXT="$CONFIG_DIR/container_ext"      # persisted file format (auto/mp4/mkv/webm)

# 创建所需的目录；用户配置与运行时状态均不应暴露给其他用户。
install -d -m 700 "$STATE_DIR" "$CONFIG_DIR" "$LOG_DIR"

# Hold chosen mode
MODE_DECIDED=""

# ================== Tunables (ENV overridable) ==================
# defaults — 默认使用 CPU 编码 (libx264)
_DEFAULT_CODEC="libx264"
_DEFAULT_FRAMERATE=""
_DEFAULT_AUDIO="on"
_DEFAULT_SAVE_EXT="auto"             # auto/mp4/mkv/webm

# load persisted settings if exist
codec_from_file=$(cat "$CFG_CODEC" 2>/dev/null || true)
fps_from_file=$(cat "$CFG_FPS" 2>/dev/null || true)
audio_from_file=$(cat "$CFG_AUDIO" 2>/dev/null || true)
drm_from_file=$(cat "$CFG_DRM" 2>/dev/null || true)
ext_from_file=$(cat "$CFG_EXT" 2>/dev/null || true)

# priority: ENV > persisted > default
CODEC="${CODEC:-${codec_from_file:-$_DEFAULT_CODEC}}"
FRAMERATE="${FRAMERATE:-${fps_from_file:-$_DEFAULT_FRAMERATE}}"
AUDIO="${AUDIO:-${audio_from_file:-$_DEFAULT_AUDIO}}"
DRM_DEVICE="${DRM_DEVICE:-${drm_from_file:-}}"
SAVE_EXT="${SAVE_EXT:-${ext_from_file:-$_DEFAULT_SAVE_EXT}}"

TITLE="${TITLE:-}"
SAVE_DIR_ENV="${SAVE_DIR:-}"
SAVE_SUBDIR_FS="${SAVE_SUBDIR_FS:-fullscreen}"

OUTPUT="${OUTPUT:-}"                     # e.g. eDP-1 / DP-2
OUTPUT_SELECT="${OUTPUT_SELECT:-auto}"   # off|auto|menu
MENU_TITLE_OUTPUT="${MENU_TITLE_OUTPUT:-}"
MENU_BACKEND="${MENU_BACKEND:-auto}"     # auto|fuzzel|wofi|rofi|bemenu|fzf|term

RECORD_MODE="${RECORD_MODE:-ask}"        # ask|full|region
MODE_MENU_TITLE="${MODE_MENU_TITLE:-Select recording mode}"
REC_AREA="${REC_AREA:-}"                 # "x,y WIDTHxHEIGHT" (optional)
GEOM_IN_NAME="${GEOM_IN_NAME:-off}"

WAYBAR_POKE="${WAYBAR_POKE:-on}"
WAYBAR_SIG="${WAYBAR_SIG:-9}"
[[ "$WAYBAR_SIG" =~ ^[0-9]+$ ]] || WAYBAR_SIG=9
ICON_REC="${ICON_REC:-⏺}"
ICON_IDLE="${ICON_IDLE:-}"

# DEBUG: 若设为 on，则在前台运行 wf-recorder，并把输出直接显示到终端（仅终端，不写文件）
DEBUG="${DEBUG:-off}"

# ================== Utils ==================
has() { command -v "$1" >/dev/null 2>&1; }

lang_code() {
  local l="${LC_MESSAGES:-${LANG:-en}}"
  l="${l,,}"; l="${l%%.*}"; l="${l%%-*}"; l="${l%%_*}"
  case "$l" in zh|zh-cn|zh-tw|zh-hk) echo zh ;; ja|jp) echo ja ;; *) echo en ;; esac
}

msg() {
  local id="$1"; shift
  case "$(lang_code)" in
    zh)
      case "$id" in
        err_wf_not_found) printf "未找到 wf-recorder" ;;
        err_need_slurp)   printf "需要 slurp 以进行区域选择" ;;
        warn_drm_ignored) printf "警告：DRM_DEVICE=%s 不存在或不可读，将忽略。" "$@" ;;
        warn_invalid_fps) printf "警告：FRAMERATE=\"%s\" 非法，已忽略。" "$@" ;;
        warn_render_unreadable) printf "警告：无效的 render 节点：%s" "$@" ;;
        cancel_no_mode)   printf "已取消：未选择录制模式。" ;;
        cancel_no_output) printf "已取消：未选择输出。" ;;
        cancel_no_region) printf "已取消：未选择区域。" ;;
        warn_multi_outputs_cancel) printf "检测到多个输出但未选择，已取消。" ;;
        notif_started_full)   printf "开始录制（全屏：%s）→ %s" "$@" ;;
        notif_started_region) printf "开始录制（区域）→ %s" "$@" ;;
        notif_device_suffix)  printf "（设备 %s）" "$@" ;;
        notif_saved)    printf "已保存：%s" "$@" ;;
        notif_stopped)  printf "已停止录制。" ;;
        already_running) printf "already running" ;;
        not_running)      printf "not running" ;;
        title_mode)       printf "选择录制模式" ;;
        title_output)     printf "选择输出" ;;
        menu_fullscreen) printf "全屏" ;;
        menu_region)      printf "选择区域" ;;
        # settings labels -> "标签：值"
        title_settings)  printf "设置" ;;
        menu_settings)   printf "设置..." ;;
        menu_set_codec)  printf "编码格式：%s" "$@" ;;
        menu_set_fps)    printf "帧率：%s" "$@" ;;
        menu_set_filefmt) printf "文件格式：%s" "$@" ;;
        menu_toggle_audio) printf "音频：%s" "$@" ;;
        menu_set_render) printf "渲染设备：%s" "$@" ;;
        menu_back)        printf "返回" ;;
        fps_unlimited)    printf "不限制" ;;
        render_auto)      printf "自动" ;;
        ext_auto)         printf "自动" ;;
        title_select_codec) printf "选择编码格式" ;;
        title_select_fps)     printf "选择帧率" ;;
        title_select_filefmt) printf "选择文件格式" ;;
        title_select_render) printf "选择渲染设备（/dev/dri/renderD*）" ;;
        mode_full)        printf "全屏" ;;
        mode_region)      printf "区域" ;;
        prompt_enter_number) printf "输入编号：" ;;
        menu_exit)        printf "退出" ;;
        *) printf "%s" "$id" ;;
      esac
      ;;
    ja)
      case "$id" in
        err_wf_not_found) printf "wf-recorder が見つかりません" ;;
        err_need_slurp)   printf "領域選択には slurp が必要です" ;;
        warn_drm_ignored) printf "警告：DRM_DEVICE=%s は無視されます。" "$@" ;;
        warn_invalid_fps) printf "警告：FRAMERATE=\"%s\" は不正です。" "$@" ;;
        warn_render_unreadable) printf "警告：無効なレンダー ノード：%s" "$@" ;;
        cancel_no_mode)   printf "キャンセル：録画モード未選択。" ;;
        cancel_no_output) printf "キャンセル：出力未選択。" ;;
        cancel_no_region) printf "キャンセル：領域未選択。" ;;
        warn_multi_outputs_cancel) printf "出力が複数ですが未選択のため中止。" ;;
        notif_started_full)   printf "録画開始（全画面：%s）→ %s" "$@" ;;
        notif_started_region) printf "録画開始（領域）→ %s" "$@" ;;
        notif_device_suffix)  printf "（デバイス %s）" "$@" ;;
        notif_saved)    printf "保存しました：%s" "$@" ;;
        notif_stopped)  printf "録画を停止しました。" ;;
        already_running) printf "already running" ;;
        not_running)      printf "not running" ;;
        title_mode)       printf "録画モードを選択" ;;
        title_output)     printf "出力を選択" ;;
        menu_fullscreen) printf "全画面" ;;
        menu_region)      printf "領域選択" ;;
        # settings labels -> "ラベル：値"（全角コロン）
        title_settings)  printf "設定" ;;
        menu_settings)   printf "設定..." ;;
        menu_set_codec)  printf "コーデック：%s" "$@" ;;
        menu_set_fps)    printf "フレームレート：%s" "$@" ;;
        menu_set_filefmt) printf "ファイル形式：%s" "$@" ;;
        menu_toggle_audio) printf "音声：%s" "$@" ;;
        menu_set_render) printf "レンダーデバイス：%s" "$@" ;;
        menu_back)        printf "戻る" ;;
        fps_unlimited)    printf "無制限" ;;
        render_auto)      printf "自動" ;;
        ext_auto)         printf "自動" ;;
        title_select_codec) printf "コーデックを選択" ;;
        title_select_fps)     printf "フレームレートを選択" ;;
        title_select_filefmt) printf "ファイル形式を選択" ;;
        title_select_render) printf "レンダーデバイスを選択（/dev/dri/renderD*）" ;;
        mode_full)        printf "全画面" ;;
        mode_region)      printf "領域" ;;
        prompt_enter_number) printf "番号を入力：" ;;
        menu_exit)        printf "終了" ;;
        *) printf "%s" "$id" ;;
      esac
      ;;
    *)
      case "$id" in
        err_wf_not_found) printf "wf-recorder not found" ;;
        err_need_slurp)   printf "slurp required for region selection" ;;
        warn_drm_ignored) printf "Warning: DRM_DEVICE=%s ignored." "$@" ;;
        warn_invalid_fps) printf "Warning: invalid FRAMERATE=\"%s\"." "$@" ;;
        warn_render_unreadable) printf "Warning: invalid render node: %s" "$@" ;;
        cancel_no_mode)   printf "Canceled: no recording mode selected." ;;
        cancel_no_output) printf "Canceled: no output selected." ;;
        cancel_no_region) printf "Canceled: no region selected." ;;
        warn_multi_outputs_cancel) printf "Multiple outputs but none selected; canceled." ;;
        notif_started_full)   printf "Recording started (fullscreen: %s) → %s" "$@" ;;
        notif_started_region) printf "Recording started (region) → %s" "$@" ;;
        notif_device_suffix)  printf " (device %s)" "$@" ;;
        notif_saved)    printf "Saved: %s" "$@" ;;
        notif_stopped)  printf "Recording stopped." ;;
        already_running) printf "already running" ;;
        not_running)      printf "not running" ;;
        title_mode)       printf "Select recording mode" ;;
        title_output)     printf "Select output" ;;
        menu_fullscreen) printf "Fullscreen" ;;
        menu_region)      printf "Region" ;;
        # settings labels -> "Label: Value"
        title_settings)  printf "Settings" ;;
        menu_settings)   printf "Settings..." ;;
        menu_set_codec)  printf "Codec: %s" "$@" ;;
        menu_set_fps)    printf "Framerate: %s" "$@" ;;
        menu_set_filefmt) printf "File Format: %s" "$@" ;;
        menu_toggle_audio) printf "Audio: %s" "$@" ;;
        menu_set_render) printf "Render Device: %s" "$@" ;;
        menu_back)        printf "Back" ;;
        fps_unlimited)    printf "unlimited" ;;
        render_auto)      printf "Auto" ;;
        ext_auto)         printf "Auto" ;;
        title_select_codec) printf "Select Codec" ;;
        title_select_fps)     printf "Select Framerate" ;;
        title_select_filefmt) printf "Select File Format" ;;
        title_select_render) printf "Select Render Device (/dev/dri/renderD*)" ;;
        mode_full)        printf "Fullscreen" ;;
        mode_region)      printf "Region" ;;
        prompt_enter_number) printf "Enter number: " ;;
        menu_exit)        printf "Exit" ;;
        *) printf "%s" "$id" ;;
      esac
      ;;
  esac
}

proc_starttime() {
  local pid="$1" stat rest
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  IFS= read -r stat 2>/dev/null <"/proc/$pid/stat" || return 1
  rest="${stat#*) }"
  set -- $rest
  (($# >= 20)) || return 1
  printf '%s' "${20}"
}

proc_state() {
  local pid="$1" stat rest
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  IFS= read -r stat 2>/dev/null <"/proc/$pid/stat" || return 1
  rest="${stat#*) }"
  set -- $rest
  (($# >= 1)) || return 1
  printf '%s' "${1}"
}

is_recorder_process() {
  local pid="$1" expected_start="$2" actual_start comm state
  [[ "$pid" =~ ^[0-9]+$ && "$expected_start" =~ ^[0-9]+$ ]] || return 1
  IFS= read -r comm 2>/dev/null <"/proc/$pid/comm" || return 1
  [[ "$comm" == "wf-recorder" ]] || return 1
  state="$(proc_state "$pid")" || return 1
  [[ "$state" != "Z" && "$state" != "X" ]] || return 1
  actual_start="$(proc_starttime "$pid")" || return 1
  [[ "$actual_start" == "$expected_start" ]]
}

wait_for_recorder_start() {
  local pid="$1" start
  for _ in {1..20}; do
    start="$(proc_starttime "$pid" || true)"
    if [[ -n "$start" ]] && is_recorder_process "$pid" "$start"; then
      printf '%s' "$start"
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  return 1
}

recorder_start_is_stable() {
  local pid="$1" start="$2"
  # 避免把初始化后立即报错退出的进程误报为已开始录制。
  for _ in {1..10}; do
    sleep 0.05
    is_recorder_process "$pid" "$start" || return 1
  done
}

read_recorder_identity() {
  REC_PID=""
  REC_STARTTIME=""
  [[ -r "$PIDFILE" && -r "$PIDSTARTFILE" ]] || return 1
  IFS= read -r REC_PID <"$PIDFILE" || return 1
  IFS= read -r REC_STARTTIME <"$PIDSTARTFILE" || return 1
  is_recorder_process "$REC_PID" "$REC_STARTTIME"
}

is_running() {
  read_recorder_identity
}

write_state() {
  local path="$1" value="$2" tmp
  tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
  printf '%s\n' "$value" >"$tmp"
  mv -f -- "$tmp" "$path"
}

clear_runtime_state() {
  rm -f -- "$PIDFILE" "$PIDSTARTFILE" "$STARTFILE" "$SAVEPATH_FILE" "$MODEFILE"
}
notify() { has notify-send && notify-send "wf-recorder" "$1" || true; }

signal_waybar() {
  local pid comm
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    IFS= read -r comm 2>/dev/null <"/proc/$pid/comm" || continue
    [[ "$comm" == "waybar" ]] || continue
    kill -RTMIN+"$WAYBAR_SIG" "$pid" 2>/dev/null || true
  done < <(pgrep -x -u "$UID" waybar 2>/dev/null || true)
}
emit_waybar_signal() { [[ "${WAYBAR_POKE,,}" == "off" ]] && return 0; signal_waybar; }

start_tick() {
  local pid="$1" starttime="$2"
  "$SCRIPT_PATH" __tick "$pid" "$starttime" >/dev/null 2>&1 9>&- &
}

tick_loop() {
  local pid="$1" starttime="$2"
  while is_recorder_process "$pid" "$starttime"; do
    signal_waybar
    sleep 1
  done
  signal_waybar
}

get_save_dir() {
  local videos
  if has xdg-user-dir; then videos="$(xdg-user-dir VIDEOS 2>/dev/null || true)"; fi
  videos="${videos:-"$HOME/Videos"}"
  echo "${SAVE_DIR_ENV:-"$videos/wf-recorder"}"
}

# --- render device helpers ---
list_render_nodes() {
  local d
  for d in /dev/dri/renderD*; do
    [[ -r "$d" ]] && printf '%s\n' "$d"
  done 2>/dev/null || true
}
render_display() {
  local cur="${1:-}"
  if [[ -z "$cur" ]]; then
    msg render_auto
  else
    printf "%s" "$cur"
  fi
}
pick_render_device() {
  local dev="${DRM_DEVICE:-}"
  if [[ -n "$dev" && ! -r "$dev" ]]; then
    printf '%s\n' "$(msg warn_render_unreadable "$dev")" >&2
    dev=""
  fi
  echo -n "$dev"
}

# --- file format helpers ---
ext_for_codec(){ case "${1,,}" in
  *h264*|*hevc*) echo mp4 ;;
  *vp9*)         echo webm ;;
  *av1*)         echo mkv ;;
  *)             echo mp4 ;;
esac; }
choose_ext(){
  local e="${SAVE_EXT,,}"
  if [[ -z "$e" || "$e" == "auto" ]]; then
    ext_for_codec "$CODEC"
  else
    case "$e" in mp4|mkv|webm) echo "$e" ;; *) echo mp4 ;; esac
  fi
}

# ================== Menus ==================
__norm() { printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

_pick_menu_backend() {
  local pref="${MENU_BACKEND,,}"
  case "$pref" in fuzzel|wofi|rofi|bemenu|fzf|term) : ;; auto|"") pref="auto" ;; *) pref="auto" ;; esac
  if [[ "$pref" != "auto" ]]; then
    if has "$pref"; then echo "$pref"; else [[ -t 0 ]] && echo "term" || echo "none"; fi
    return
  fi
  for b in fuzzel wofi rofi bemenu fzf; do has "$b" && { echo "$b"; return; }; done
  [[ -t 0 ]] && echo "term" || echo "none"
}

menu_pick() { # $1:title; items...
  local title="${1:-Select}"; shift
  local items=("$@")
  ((${#items[@]})) || return 130

  local backend; backend="$(_pick_menu_backend)"
  local sel rc=130
  case "$backend" in
    fuzzel) set +e; sel="$(printf '%s\n' "${items[@]}" | fuzzel --dmenu -p "$title")"; rc=$?; set -e ;;
    wofi)   set +e; sel="$(printf '%s\n' "${items[@]}" | wofi --dmenu --prompt "$title")"; rc=$?; set -e ;;
    rofi)   set +e; sel="$(printf '%s\n' "${items[@]}" | rofi -dmenu -p "$title")"; rc=$?; set -e ;;
    bemenu) set +e; sel="$(printf '%s\n' "${items[@]}" | bemenu -p "$title")"; rc=$?; set -e ;;
    fzf)    set +e; sel="$(printf '%s\n' "${items[@]}" | fzf --prompt "$title> ")"; rc=$?; set -e ;;
    term)
      echo "$title"
      local i=1; for it in "${items[@]}"; do printf '  %d) %s\n' "$i" "$it"; ((i++)); done
      printf "%s" "$(msg prompt_enter_number)"
      local idx; set +e; read -r idx; rc=$?; set -e
      if [[ $rc -eq 0 && -n "$idx" && "$idx" =~ ^[0-9]+$ ]]; then
        if (( idx>=1 && idx<=${#items[@]} )); then sel="${items[$((idx-1))]}"; rc=0; fi
      fi
      ;;
    none) return 130 ;;
  esac
  [[ $rc -ne 0 || -z "${sel:-}" ]] && return 130
  printf '%s' "$(__norm "$sel")"
}

# ---------- Outputs ----------
list_outputs() {
  local raw
  if raw="$(wf-recorder -L 2>/dev/null)"; then :; elif has wlr-randr; then raw="$(wlr-randr 2>/dev/null | awk '/^[^ ]/{print $1}')"; else raw=""; fi
  awk 'BEGIN{RS="[ \t\r\n,]+"} /^[A-Za-z0-9_.:-]+$/ { if ($0 ~ /^(e?DP|HDMI|DVI|VGA|LVDS|Virtual|XWAYLAND)/) seen[$0]=1 } END{for(k in seen) print k}' <<<"$raw" | sort -u
}
decide_output() {
  if [[ -n "$OUTPUT" ]]; then printf '%s' "$OUTPUT"; return 0; fi
  local -a outs; mapfile -t outs < <(list_outputs || true)
  local out_title; out_title="${MENU_TITLE_OUTPUT:-$(msg title_output)}"
  if [[ "${OUTPUT_SELECT}" == "menu" ]] || { [[ "${OUTPUT_SELECT}" == "auto" ]] && ((${#outs[@]} > 1)); }; then
    local pick; pick="$(menu_pick "$out_title" "${outs[@]}")" || return 130
    printf '%s' "$pick"; return 0
  fi
  if ((${#outs[@]} == 1)); then printf '%s' "${outs[0]}"; else printf '%s\n' "$(msg warn_multi_outputs_cancel)" >&2; return 130; fi
}

# ---------- Settings ----------
choose_render_menu() {
  local -a nodes
  mapfile -t nodes < <(list_render_nodes | sort -V || true)
  local auto_item; auto_item="$(msg render_auto)"
  local pick
  if ! pick="$(menu_pick "$(msg title_select_render)" "$auto_item" "${nodes[@]}")"; then
    return 0
  fi
  if [[ "$pick" == "$auto_item" ]]; then
    DRM_DEVICE=""
    rm -f "$CFG_DRM"
    return 0
  fi
  local sel="$pick"
  if [[ -n "$sel" && -r "$sel" ]]; then
    DRM_DEVICE="$sel"
    printf '%s' "$DRM_DEVICE" >"$CFG_DRM"
  else
    printf '%s\n' "$(msg warn_render_unreadable "$sel")" >&2
  fi
}

choose_filefmt_menu() {
  local auto_item; auto_item="$(msg ext_auto)"
  local pick
  if ! pick="$(menu_pick "$(msg title_select_filefmt)" "$auto_item" "mp4" "mkv" "webm")"; then
    return 0
  fi
  if [[ "$pick" == "$auto_item" ]]; then
    SAVE_EXT="auto"
    rm -f "$CFG_EXT"
  else
    case "$pick" in
      mp4|mkv|webm) SAVE_EXT="$pick"; printf '%s' "$SAVE_EXT" >"$CFG_EXT" ;;
      *) : ;;
    esac
  fi
}

show_settings_menu() {
  while :; do
    local fps_display="${FRAMERATE:-$(msg fps_unlimited)}"
    local audio_display="${AUDIO}"
    local render_display_now; render_display_now="$(render_display "$DRM_DEVICE")"
    local ff_display; if [[ -z "$SAVE_EXT" || "${SAVE_EXT,,}" == "auto" ]]; then ff_display="$(msg ext_auto)"; else ff_display="$SAVE_EXT"; fi

    # ORDER: Framerate → Audio → Codec → File Format → Render → Back
    local pick; pick="$(menu_pick "$(msg title_settings)" \
                      "$(msg menu_set_fps "$fps_display")" \
                      "$(msg menu_toggle_audio "$audio_display")" \
                      "$(msg menu_set_codec "$CODEC")" \
                      "$(msg menu_set_filefmt "$ff_display")" \
                      "$(msg menu_set_render "$render_display_now")" \
                      "$(msg menu_back)")" || return 0

    if [[ "$pick" == "$(msg menu_set_fps "$fps_display")" ]]; then
      local newf; newf="$(menu_pick "$(msg title_select_fps)" "60" "30" "120" "144" "165" "240" "$(msg fps_unlimited)")" || continue
      if [[ "$newf" == "$(msg fps_unlimited)" ]]; then
        FRAMERATE=""; rm -f "$CFG_FPS"
      else
        if [[ "$newf" =~ ^[0-9]+$ && "$newf" -gt 0 ]]; then FRAMERATE="$newf"; printf '%s' "$FRAMERATE" >"$CFG_FPS"; fi
      fi

    elif [[ "$pick" == "$(msg menu_toggle_audio "$audio_display")" ]]; then
      if [[ "$AUDIO" == "on" ]]; then AUDIO="off"; else AUDIO="on"; fi
      printf '%s' "$AUDIO" >"$CFG_AUDIO"

    elif [[ "$pick" == "$(msg menu_set_codec "$CODEC")" ]]; then
      # 仅保留 CPU (libx264) 与所有常见 VAAPI 编码选项，CPU 放在首位
      local newc; newc="$(menu_pick "$(msg title_select_codec)" \
                        "libx264" "h264_vaapi" "hevc_vaapi" "av1_vaapi" "vp9_vaapi")" || continue
      CODEC="$newc"; printf '%s' "$CODEC" >"$CFG_CODEC"

    elif [[ "$pick" == "$(msg menu_set_filefmt "$ff_display")" ]]; then
      choose_filefmt_menu

    elif [[ "$pick" == "$(msg menu_set_render "$render_display_now")" ]]; then
      choose_render_menu

    elif [[ "$pick" == "$(msg menu_back)" ]]; then
      return 0
    fi
    # loop to refresh values instantly
  done
}

# ---------- Mode selection ----------
decide_mode() {
  case "${RECORD_MODE,,}" in
    full|fullscreen) MODE_DECIDED="full";    return 0 ;;
    region|area)     MODE_DECIDED="region"; return 0 ;;
    *) ;;
  esac
  local L_FULL L_REGION L_SETTINGS L_EXIT
  case "$(lang_code)" in
    zh) L_FULL="$(msg menu_fullscreen)"; L_REGION="$(msg menu_region)"; L_SETTINGS="$(msg menu_settings)"; L_EXIT="$(msg menu_exit)";;
    ja) L_FULL="$(msg menu_fullscreen)"; L_REGION="$(msg menu_region)"; L_SETTINGS="$(msg menu_settings)"; L_EXIT="$(msg menu_exit)";;
    *)  L_FULL="Fullscreen"; L_REGION="Region"; L_SETTINGS="$(msg menu_settings)"; L_EXIT="$(msg menu_exit)";;
  esac
  local title; title="$(msg title_mode)"
  while :; do
    local pick; pick="$(menu_pick "$title" "$L_FULL" "$L_REGION" "$L_SETTINGS" "$L_EXIT")" || return 130
    if    [[ "$pick" == "$L_FULL"    ]]; then MODE_DECIDED="full";    return 0
    elif [[ "$pick" == "$L_REGION"  ]]; then MODE_DECIDED="region"; return 0
    elif [[ "$pick" == "$L_SETTINGS" ]]; then show_settings_menu; continue
    elif [[ "$pick" == "$L_EXIT"    ]]; then return 130
    else return 130; fi
  done
}

# ---------- Helpers ----------
geom_token() {
  local g="$1"
  awk 'NF==2{split($1,a,","); split($2,b,"x");
             if(a[1]!=""){printf "%sx%s@%s,%s",b[1],b[2],a[1],a[2]}}' <<<"$g"
}
pretty_dur() {
  local dur="${1:-0}"
  [[ "$dur" =~ ^[0-9]+$ ]] || dur=0
  if ((dur>=3600)); then printf "%d:%02d:%02d" $((dur/3600)) $(((dur%3600)/60)) $((dur%60))
  else printf "%02d:%02d" $((dur/60)) $((dur%60)); fi
}
# ================== Start / Stop ==================
start_rec() {
  if is_running; then echo "$(msg already_running)"; exit 0; fi
  clear_runtime_state
  has wf-recorder || { echo "$(msg err_wf_not_found)"; exit 1; }

  MODE_DECIDED=""
  if ! decide_mode; then
    echo "$(msg cancel_no_mode)"; emit_waybar_signal; exit 130
  fi
  local mode="$MODE_DECIDED"

  local marker="" output="" GEOM="" gtok=""
  local -a args
  args=( -c "$CODEC" )

  local ROOT_DIR TARGET_DIR
  ROOT_DIR="$(get_save_dir)"
  if [[ "$mode" == "full" ]]; then TARGET_DIR="$ROOT_DIR/${SAVE_SUBDIR_FS}"; else TARGET_DIR="$ROOT_DIR"; fi
  mkdir -p "$TARGET_DIR"

  if [[ "$mode" == "full" ]]; then
    output="$(decide_output)" || { echo "$(msg cancel_no_output)"; emit_waybar_signal; exit 130; }
    [[ -n "$output" ]] && args+=( -o "$output" )
    marker="FS${output:+-$output}"
  else
    if [[ -n "$REC_AREA" ]]; then
      GEOM="$REC_AREA"
    else
      has slurp || { echo "$(msg err_need_slurp)"; emit_waybar_signal; exit 1; }
      set +e; GEOM="$(slurp)"; local rc=$?; set -e
      if [[ $rc -ne 0 || -z "${GEOM// /}" ]]; then echo "$(msg cancel_no_region)"; emit_waybar_signal; exit 130; fi
    fi
    GEOM="$(echo -n "$GEOM" | tr -s '[:space:]' ' ')"
    args+=( -g "$GEOM" )
    if [[ "${GEOM_IN_NAME,,}" == "on" ]]; then gtok="$(geom_token "$GEOM")"; marker="REGION${gtok:+-$gtok}"; else marker="REGION"; fi
  fi

  local ts safe_title base SAVE_PATH ext
  ts="$(date +'%Y-%m-%d-%H%M%S-%N')"
  safe_title="${TITLE// /_}"
  safe_title="${safe_title//[^[:alnum:]_.-]/_}"
  safe_title="${safe_title:0:80}"
  marker="${marker//[^[:alnum:]_.@,-]/_}"
  base="$ts${safe_title:+-$safe_title}-${marker}"
  ext="$(choose_ext)"
  SAVE_PATH="$TARGET_DIR/$base.$ext"

  args=( --file "$SAVE_PATH" "${args[@]}" )

  # Render device
  local dev; dev="$(pick_render_device)"; [[ -n "$dev" ]] && args+=( -d "$dev" )

  # Audio
  case "$AUDIO" in off|OFF|0|false) ;; on|ON|1|true|"") args+=( --audio ) ;; *) args+=( --audio="$AUDIO" ) ;; esac

  # Framerate
  if [[ -n "$FRAMERATE" ]]; then
    if [[ "$FRAMERATE" =~ ^[0-9]+$ && "$FRAMERATE" -gt 0 ]]; then args+=( --framerate "$FRAMERATE" )
    else printf '%s\n' "$(msg warn_invalid_fps "$FRAMERATE")" >&2; fi
  fi

  # Pixel format
  if [[ "$CODEC" == *"_vaapi" ]]; then args+=( -F "scale_vaapi=format=nv12:out_range=full:out_color_primaries=bt709" )
  else args+=( -F "format=yuv420p" ); fi

  # === 不保存日志：仅在 DEBUG=on 时将 wf-recorder 输出到终端 ===
  if [[ "${DEBUG,,}" == "on" ]]; then
    echo "DEBUG=on: running wf-recorder with output attached"
    echo "Command: wf-recorder ${args[*]}"
    wf-recorder "${args[@]}" 2>&1 9>&- &
    local pid=$!
    local pid_start=""
    pid_start="$(wait_for_recorder_start "$pid" || true)"
    if [[ -z "$pid_start" ]] || ! recorder_start_is_stable "$pid" "$pid_start"; then
      wait "$pid" 2>/dev/null || true
      notify "wf-recorder failed to start"
      return 1
    fi
    write_state "$PIDFILE" "$pid"
    write_state "$PIDSTARTFILE" "$pid_start"
    write_state "$STARTFILE" "$(date +%s)"
    write_state "$SAVEPATH_FILE" "$SAVE_PATH"
    write_state "$MODEFILE" "$mode"
    local note; if [[ "$mode" == "full" ]]; then note="$(msg notif_started_full "$output" "$SAVE_PATH")"; else note="$(msg notif_started_region "$SAVE_PATH")"; fi
    [[ -n "$dev" ]] && note+="$(msg notif_device_suffix "$dev")"
    echo "$note";
    emit_waybar_signal
    start_tick "$pid" "$pid_start"
    return 0
  fi

  # 非 DEBUG：后台运行；每次启动覆盖诊断日志，避免无限增长。
  : >"$LOG_FILE"
  setsid nohup wf-recorder "${args[@]}" >>"$LOG_FILE" 2>&1 9>&- &
  local pid=$!
  local pid_start=""
  pid_start="$(wait_for_recorder_start "$pid" || true)"
  if [[ -z "$pid_start" ]] || ! recorder_start_is_stable "$pid" "$pid_start"; then
    wait "$pid" 2>/dev/null || true
    clear_runtime_state
    notify "wf-recorder failed to start; see $LOG_FILE"
    return 1
  fi

  write_state "$PIDFILE" "$pid"
  write_state "$PIDSTARTFILE" "$pid_start"
  write_state "$STARTFILE" "$(date +%s)"
  write_state "$SAVEPATH_FILE" "$SAVE_PATH"
  write_state "$MODEFILE" "$mode"

  local note; if [[ "$mode" == "full" ]]; then note="$(msg notif_started_full "$output" "$SAVE_PATH")"; else note="$(msg notif_started_region "$SAVE_PATH")"; fi
  [[ -n "$dev" ]] && note+="$(msg notif_device_suffix "$dev")"
  echo "$note";
  emit_waybar_signal
  start_tick "$pid" "$pid_start"
}

stop_rec() {
  if ! is_running; then
    clear_runtime_state
    echo "$(msg not_running)"
    emit_waybar_signal
    exit 0
  fi
  local pid="$REC_PID" pid_start="$REC_STARTTIME"

  kill -INT "$pid" 2>/dev/null || true
  for _ in {1..40}; do
    sleep 0.1
    is_recorder_process "$pid" "$pid_start" || break
  done
  is_recorder_process "$pid" "$pid_start" && kill -TERM "$pid" 2>/dev/null || true
  sleep 0.2
  is_recorder_process "$pid" "$pid_start" && kill -KILL "$pid" 2>/dev/null || true

  local save_path=""; [[ -r "$SAVEPATH_FILE" ]] && read -r save_path <"$SAVEPATH_FILE"
  if [[ -n "$save_path" && -f "$save_path" ]]; then
    # 生成不带后缀的 latest（例如：.../latest）
    ln -sf "$(basename "$save_path")" "$(dirname "$save_path")/latest" || true
    local s; s="$(msg notif_saved "$save_path")"; echo "$s"; notify "$s"
  else
    local s; s="$(msg notif_stopped)"; echo "$s"; notify "$s"
  fi

  clear_runtime_state
  emit_waybar_signal
}

# ================== Waybar JSON/status ==================
tooltip_idle_text() {
  case "$(lang_code)" in
    zh) cat <<'EOF'
屏幕录制（wf-recorder）
左键：打开录制菜单
右键：强制关闭
EOF
      ;;
    ja) cat <<'EOF'
画面録画（wf-recorder）
左クリック：録画メニューを開く
右クリック：強制停止
EOF
      ;;
    *)  cat <<'EOF'
Screen recording (wf-recorder)
Left click: open recording menu
Right click: force stop
EOF
      ;;
  esac
}
tooltip_recording_text() { # $1 elapsed, $2 filepath, $3 mode: full|region
  local t="$1" p="${2:-}" m="${3:-}"
  local mode_label
  case "$m" in full|fullscreen) mode_label="$(msg mode_full)";; region|area) mode_label="$(msg mode_region)";; *) mode_label="";; esac
  case "$(lang_code)" in
    zh) [[ -n "$p" ]] && { [[ -n "$mode_label" ]] && printf "录制中（%s）\n已用时：%s\n文件：%s\n" "$mode_label" "$t" "$p" || printf "录制中\n已用时：%s\n文件：%s\n" "$t" "$p"; } || { [[ -n "$mode_label" ]] && printf "录制中（%s）\n已用时：%s\n" "$mode_label" "$t" || printf "录制中\n已用时：%s\n" "$t"; } ;;
    ja) [[ -n "$p" ]] && { [[ -n "$mode_label" ]] && printf "録画中（%s）\n経過時間：%s\nファイル：%s\n" "$mode_label" "$t" "$p" || printf "録画中\n経過時間：%s\nファイル：%s\n" "$t" "$p"; } || { [[ -n "$mode_label" ]] && printf "録画中（%s）\n経過時間：%s\n" "$mode_label" "$t" || printf "録画中\n経過時間：%s\n" "$t"; } ;;
    *)  [[ -n "$p" ]] && { [[ -n "$mode_label" ]] && printf "Recording (%s)\nElapsed: %s\nFile: %s\n" "$mode_label" "$t" "$p" || printf "Recording\nElapsed: %s\nFile: %s\n" "$t" "$p"; } || { [[ -n "$mode_label" ]] && printf "Recording (%s)\nElapsed: %s\n" "$mode_label" "$t" || printf "Recording\nElapsed: %s\n" "$t"; } ;;
  esac
}
pretty_status_json() {
  local text tooltip class alt
  if is_running; then
    local start=0; [[ -r "$STARTFILE" ]] && read -r start <"$STARTFILE" || true
    [[ "$start" =~ ^[0-9]+$ ]] || start=0
    local now dur; now="$(date +%s)"; dur=$((now - start)); (( dur < 0 )) && dur=0
    local t; t="$(pretty_dur "$dur")"
    local save_path=""; [[ -r "$SAVEPATH_FILE" ]] && read -r save_path <"$SAVEPATH_FILE" || true
    local mode=""; [[ -r "$MODEFILE" ]] && read -r mode <"$MODEFILE" || true
    text="$ICON_REC$t"
    tooltip="$(tooltip_recording_text "$t" "$save_path" "$mode")"
    class="recording"; alt="rec"
  else
    text="$ICON_IDLE"; tooltip="$(tooltip_idle_text)"; class="idle"; alt="idle"
  fi
  if has jq; then
    jq -cn \
      --arg text "$text" \
      --arg tooltip "$tooltip" \
      --arg class "$class" \
      --arg alt "$alt" \
      '{text: $text, tooltip: $tooltip, class: $class, alt: $alt}'
  else
    # All dynamic strings may contain markup and paths; jq is required to
    # guarantee valid JSON rather than emitting partially escaped data.
    printf '{"text":"%s","tooltip":"JSON encoder jq is missing","class":"error","alt":"error"}\n' "$ICON_IDLE"
  fi
}
status_rec() {
  local json="${1:-}"
  if [[ "$json" == "--json" ]]; then
    pretty_status_json
  else
    if is_running; then
      local start=0; [[ -r "$STARTFILE" ]] && read -r start <"$STARTFILE" || true
      [[ "$start" =~ ^[0-9]+$ ]] || start=0
      local now dur; now="$(date +%s)"; dur=$((now - start)); (( dur < 0 )) && dur=0
      printf "%s%s\n" "$ICON_REC" "$(pretty_dur "$dur")"
    else
      echo "$ICON_IDLE"
    fi
  fi
}

# ================== Main ==================
run_exclusive() {
  (
    flock -x 9
    "$@"
  ) 9>"$LOCKFILE"
}

run_shared() {
  (
    flock -s 9
    "$@"
  ) 9>"$LOCKFILE"
}

toggle_rec() {
  if is_running; then stop_rec; else start_rec; fi
}

case "${1:-toggle}" in
  start)         run_exclusive start_rec ;;
  stop)          run_exclusive stop_rec ;;
  status)        run_shared status_rec ;;
  status-json)   run_shared status_rec --json ;;
  waybar)        run_shared status_rec --json ;;
  is-active)     run_shared is_running ;;
  toggle)        run_exclusive toggle_rec ;;
  settings)      run_exclusive show_settings_menu ;;
  __tick)
    [[ "${2:-}" =~ ^[0-9]+$ && "${3:-}" =~ ^[0-9]+$ ]] || exit 2
    tick_loop "$2" "$3"
    ;;
  *)             echo "Usage: $0 {start|stop|toggle|status|status-json|waybar|is-active|settings}"; exit 2 ;;
esac
