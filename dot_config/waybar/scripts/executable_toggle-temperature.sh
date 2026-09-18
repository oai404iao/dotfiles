#!/bin/sh
set -eu

current=$(busctl --user get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature)
if [ "$current" = "q 6500" ]; then
    target=4500
else
    target=6500
fi

exec busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q "$target"
