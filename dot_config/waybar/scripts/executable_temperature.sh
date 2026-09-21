#!/bin/sh
set -eu

# Bound each query; continuous watchers can block Waybar's module teardown.
timeout 3s systemctl --user start waybar-gammarelay.service
current=$(busctl --user --timeout=3 get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature)
printf '%s\n' "${current#q }"
