#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sh -n "$repo_dir/dot_local/bin/executable_dms-with-lyrics"
python3 "$repo_dir/tests/check-dms-media-lyrics.py"
