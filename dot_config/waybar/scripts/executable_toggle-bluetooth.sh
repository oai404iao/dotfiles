#!/usr/bin/env bash
set -Eeuo pipefail

command -v rfkill >/dev/null 2>&1 || {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u critical "Bluetooth" "Missing command: rfkill"
    exit 1
}

if ! rfkill list bluetooth >/dev/null 2>&1; then
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u normal "Bluetooth" "No Bluetooth radio found"
    exit 1
fi

# rfkill provides a machine-independent toggle action; do not parse localized
# human-readable output.
rfkill toggle bluetooth
