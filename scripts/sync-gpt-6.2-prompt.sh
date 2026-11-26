#!/bin/sh
set -eu

url=https://raw.githubusercontent.com/oai404iao/my_skills/main/prompts/gpt-6.2.md
dir=$HOME/.agents/prompts
target=$dir/gpt-6.2.md

umask 077
mkdir -p -- "$dir"
# Stage beside the target so a failed download leaves it intact.
stage=$(mktemp -- "$dir/.gpt-6.2.md.XXXXXXXX")
trap 'rm -f -- "$stage"' EXIT
trap 'exit 1' HUP INT TERM

curl --fail --silent --show-error --location --proto '=https' --output "$stage" -- "$url"
if [ ! -s "$stage" ]; then
    printf 'refusing to install an empty prompt from %s\n' "$url" >&2
    exit 1
fi

mv -fT -- "$stage" "$target"
printf 'updated %s\n' "$target"
