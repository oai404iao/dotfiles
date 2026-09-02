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

git config --file "$repo_dir/dot_gitconfig" --list >/dev/null
find "$repo_dir/dot_config/git" -type f -name "dot_gitconfig-*" \
    -exec git config --file {} --list >/dev/null \;

if command -v nvim >/dev/null 2>&1; then
    find "$repo_dir/dot_config/nvim" -type f -name "*.lua" \
        -exec nvim --headless -u NONE -i NONE -n \
            -c 'lua for _, path in ipairs(vim.fn.argv()) do assert(loadfile(path)) end' \
            -c 'qa!' -- {} +

    nvim --headless -u NONE -i NONE -n \
        -c 'lua for _, path in ipairs(vim.fn.argv()) do assert(vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))) end' \
        -c 'qa!' -- \
        "$repo_dir/dot_config/nvim/lazy-lock.json" \
        "$repo_dir/dot_config/nvim/lazyvim.json"
fi

if command -v chezmoi >/dev/null 2>&1 &&
    command -v niri >/dev/null 2>&1
then
    "$repo_dir/tests/check-niri.sh"
fi

"$repo_dir/tests/check-safe-rm.sh"
"$repo_dir/tests/check-pi.sh"

printf '%s\n' "source checks passed"
