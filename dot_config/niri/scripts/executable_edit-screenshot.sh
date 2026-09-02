#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
NIRI_CONFIG="${NIRI_CONFIG:-$XDG_CONFIG_HOME/niri/config.kdl}"

notify_error() {
    local message="$1"
    printf '%s\n' "$message" >&2
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u critical "Screenshot" "$message"
}

for required in niri satty wl-copy; do
    command -v "$required" >/dev/null 2>&1 || {
        notify_error "Missing command: $required"
        exit 1
    }
done

runtime_base="${XDG_RUNTIME_DIR:-}"
if [[ "$runtime_base" != /* || ! -d "$runtime_base" || ! -w "$runtime_base" ||
      "$(stat -c '%u' "$runtime_base" 2>/dev/null || printf '%s' -1)" != "$UID" ]]; then
    runtime_base="${TMPDIR:-/tmp}/niri-edit-screenshot-$UID"
    if [[ -e "$runtime_base" &&
          (! -d "$runtime_base" ||
           "$(stat -c '%u' "$runtime_base" 2>/dev/null || printf '%s' -1)" != "$UID") ]]; then
        notify_error "Unsafe runtime fallback: $runtime_base"
        exit 1
    fi
    install -d -m 700 "$runtime_base"
fi

install -d -m 700 "$runtime_base/niri-edit-screenshot"
exec 9>"$runtime_base/niri-edit-screenshot/lock"
flock -n 9 || exit 0

get_screenshot_dir() {
    local line template
    [[ -r "$NIRI_CONFIG" ]] || return 1
    line="$(
        grep -E '^[[:space:]]*screenshot-path[[:space:]]' "$NIRI_CONFIG" |
            grep -v '^[[:space:]]*//' |
            tail -n 1 || true
    )"
    [[ -n "$line" ]] || return 1
    template="$(sed -E 's/.*screenshot-path[[:space:]]+"([^"]+)".*/\1/' <<<"$line")"
    [[ -n "$template" && "$template" != "$line" ]] || return 1
    template="${template/#\~/$HOME}"
    dirname -- "$template"
}

shot_dir="$(get_screenshot_dir)" || {
    pictures_dir="$(xdg-user-dir PICTURES 2>/dev/null || true)"
    shot_dir="${pictures_dir:-$HOME/Pictures}/Screenshots"
}
[[ "$shot_dir" == /* ]] || {
    notify_error "Screenshot directory must be absolute: $shot_dir"
    exit 1
}

edited_dir="$shot_dir/Edited"
install -d -m 700 "$shot_dir" "$edited_dir"

timestamp="$(date +'%Y-%m-%d_%H-%M-%S-%N')"
source_path="$shot_dir/Screenshot_$timestamp.png"
edited_path="$edited_dir/satty-$timestamp.png"
timeout_seconds="${SHOT_REGION_TIMEOUT:-120}"
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || timeout_seconds=120

niri msg action screenshot --path "$source_path" || {
    notify_error "Niri screenshot action failed"
    exit 1
}

deadline=$((SECONDS + timeout_seconds))
last_size=-1
stable_checks=0
while ((SECONDS < deadline)); do
    size="$(stat -c '%s' -- "$source_path" 2>/dev/null || printf '0')"
    if [[ "$size" =~ ^[0-9]+$ ]] && ((size > 0)); then
        if ((size == last_size)); then
            stable_checks=$((stable_checks + 1))
            ((stable_checks >= 2)) && break
        else
            stable_checks=0
            last_size="$size"
        fi
    fi
    sleep 0.05
done

if ((stable_checks < 2)); then
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u normal "Screenshot" "Screenshot cancelled or timed out"
    exit 0
fi

satty --filename "$source_path" --output-filename "$edited_path" || exit 0
if [[ -s "$edited_path" ]]; then
    wl-copy --type image/png <"$edited_path" 9>&-
fi
