#!/bin/sh
set -eu

item="chezmoi age identity"
identity=${1:-"${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/age-identity.txt"}
config_dir=$(dirname -- "$identity")

umask 077
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

rbw get "$item" > "$tmp_file"
if ! grep -q '^AGE-SECRET-KEY-' "$tmp_file"; then
    printf '%s\n' "Bitwarden item does not contain an age identity" >&2
    exit 1
fi

age-keygen -y "$tmp_file" >/dev/null
install -d -m 700 "$config_dir"
install -m 600 "$tmp_file" "$identity"

printf '%s\n' "restored age identity to $identity"
