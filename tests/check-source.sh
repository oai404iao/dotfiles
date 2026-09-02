#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

find "$repo_dir" \
    -path "$repo_dir/.git" -prune -o \
    -type f \( -name "*.zsh" -o -name "dot_zshenv" -o -name "dot_zprofile" -o -name "dot_zshrc" \) \
    -exec zsh -n {} \;

find "$repo_dir/scripts" "$repo_dir/tests" \
    -type f -name "*.sh" \
    -exec sh -n {} \;

find "$repo_dir" \
    -path "$repo_dir/.git" -prune -o \
    -type f \( -name "*.bash" -o -name "dot_bash_profile" -o -name "dot_bashrc" \) \
    -exec bash -n {} \;

if command -v chezmoi >/dev/null 2>&1 &&
    command -v niri >/dev/null 2>&1
then
    "$repo_dir/tests/check-niri.sh"
fi

printf '%s\n' "source checks passed"
