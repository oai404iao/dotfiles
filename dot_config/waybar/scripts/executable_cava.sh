#!/usr/bin/env bash
set -Eeuo pipefail

bar="▁▂▃▄▅▆▇█"
dict="s/;//g;"

# creating "dictionary" to replace char with bar
i=0
while ((i < ${#bar})); do
    dict="${dict}s/$i/${bar:$i:1}/g;"
    ((i += 1))
done

# Use a private, unique temporary file and always remove it.
umask 077
config_file="$(mktemp "${TMPDIR:-/tmp}/waybar-cava.XXXXXX")"
trap 'rm -f -- "$config_file"' EXIT

cat >"$config_file" <<'EOF'
[general]
bars = 10

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
EOF

# read stdout from cava
cava -p "$config_file" | while IFS= read -r line; do
    printf '%s\n' "$line" | sed "$dict"
done
