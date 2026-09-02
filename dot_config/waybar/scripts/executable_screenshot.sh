#!/usr/bin/env bash
set -Eeuo pipefail

for command in grim slurp wl-copy; do
    command -v "$command" >/dev/null 2>&1 || {
        command -v notify-send >/dev/null 2>&1 &&
            notify-send -u critical "Screenshot" "Missing command: $command"
        exit 1
    }
done

geometry="$(slurp)" || exit 0
[[ -n "$geometry" ]] || exit 0

grim -g "$geometry" - | wl-copy --type image/png
