#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

for output_profile in auto laptop-dual-1080p; do
    home_dir="$tmp_dir/$output_profile"
    config_file="$tmp_dir/$output_profile.toml"
    mkdir -p "$home_dir"

    cat > "$config_file" <<EOF
mode = "file"
destDir = "$home_dir"

[template]
    options = ["missingkey=error"]

[data]
    role = "laptop"
    shell = "zsh"
    graphical = true
    niri = true
    niriOutputProfile = "$output_profile"
    work = false
    secretBackend = "rbw"
EOF

    chezmoi --config "$config_file" --source "$repo_dir" apply \
        --exclude scripts \
        >/dev/null 2>&1
    niri validate --config "$home_dir/.config/niri/config.kdl" \
        >/dev/null 2>&1
done

legacy_home="$tmp_dir/legacy"
legacy_config="$tmp_dir/legacy.toml"
mkdir -p "$legacy_home"
cat > "$legacy_config" <<EOF
mode = "file"
destDir = "$legacy_home"

[template]
    options = ["missingkey=error"]

[data]
    role = "laptop"
    shell = "zsh"
    graphical = true
    niri = true
    work = false
    secretBackend = "rbw"
EOF

chezmoi --config "$legacy_config" --source "$repo_dir" apply \
    --exclude scripts \
    >/dev/null 2>&1
niri validate --config "$legacy_home/.config/niri/config.kdl" \
    >/dev/null 2>&1

printf '%s\n' "Niri configs passed"
