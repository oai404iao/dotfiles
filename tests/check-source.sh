#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

find "$repo_dir" \
    -path "$repo_dir/.git" -prune -o \
    -type f \( -name "*.zsh" -o -name "dot_zshenv" -o -name "dot_zprofile" -o -name "dot_zshrc" \) \
    -exec sh -c '
        interpreter=$1
        shift
        for file do
            "$interpreter" -n "$file" || exit 1
        done
    ' sh zsh {} +

find "$repo_dir/scripts" "$repo_dir/tests" \
    -type f -name "*.sh" \
    -exec sh -c '
        for file do
            sh -n "$file" || exit 1
        done
    ' sh {} +

find "$repo_dir" \
    -path "$repo_dir/.git" -prune -o \
    -type f \( -name "*.bash" -o -name "dot_bash_profile" -o -name "dot_bashrc" \) \
    -exec sh -c '
        for file do
            bash -n "$file" || exit 1
        done
    ' sh {} +

"$repo_dir/tests/check-git.sh"

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
"$repo_dir/tests/check-ssh.sh"
"$repo_dir/tests/check-desktop.sh"

printf '%s\n' "source checks passed"
