#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

find "$repo_dir" \
    -path "$repo_dir/.git" -prune -o \
    -type f \( -name "*.zsh" -o -name "dot_zshenv" -o -name "dot_zprofile" -o -name "dot_zshrc" \) \
    -exec zsh -n {} \;

printf '%s\n' "source checks passed"
