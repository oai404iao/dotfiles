#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

value="${1:-}"
[[ "$value" =~ ^[0-9]+$ ]] && ((value >= 0 && value <= 100)) || {
    printf 'Usage: %s <0-100>\n' "$0" >&2
    exit 2
}

command -v ddcutil >/dev/null 2>&1 || {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u critical "External display" "Missing command: ddcutil"
    exit 1
}

runtime="${XDG_RUNTIME_DIR:-}"
if [[ "$runtime" != /* || ! -d "$runtime" || ! -w "$runtime" ||
      "$(stat -c '%u' "$runtime" 2>/dev/null || printf '%s' -1)" != "$UID" ]]; then
    runtime="${XDG_STATE_HOME:-$HOME/.local/state}/waybar-ddc-brightness"
    install -d -m 700 "$runtime"
fi
lock="$runtime/waybar-ddc-brightness.lock"

args=()
[[ -n "${DDC_DISPLAY:-}" ]] && args+=(--display "$DDC_DISPLAY")
[[ -n "${DDC_BUS:-}" ]] && args+=(--bus "$DDC_BUS")

if output="$(flock "$lock" ddcutil "${args[@]}" setvcp 10 "$value" 2>&1)"; then
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u low "External display" "Brightness: $value%"
else
    printf '%s\n' "$output" >&2
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u normal "External display" \
            "DDC/CI is unavailable. Check monitor power and DDC/CI settings."
    exit 1
fi
