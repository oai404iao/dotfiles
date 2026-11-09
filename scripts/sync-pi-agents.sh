#!/bin/sh
# Fetch the published Pi global instructions from my_skills/main.
# --dry-run prints the diff against the installed file without writing it.
set -eu

url=https://raw.githubusercontent.com/oai404iao/my_skills/main/prompts/pi-global-agents.md
target_dir=${PI_CODING_AGENT_DIR:-$HOME/.config/pi/agent}
target=$target_dir/AGENTS.md

case ${1-} in
    '') dry_run=0 ;;
    --dry-run) dry_run=1 ;;
    *) printf 'usage: %s [--dry-run]\n' "$0" >&2; exit 2 ;;
esac

umask 077
mkdir -p -- "$target_dir"
# Download beside the target so the final rename is atomic.
tmp=$(mktemp -- "$target_dir/.AGENTS.md.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT HUP INT TERM

curl --fail --silent --show-error --location --proto '=https' --output "$tmp" -- "$url"
if [ ! -s "$tmp" ]; then
    printf 'refusing to install empty instructions from %s\n' "$url" >&2
    exit 1
fi

if [ -f "$target" ] && cmp -s -- "$tmp" "$target"; then
    printf '%s is up to date\n' "$target"
    exit 0
fi
if [ "$dry_run" = 1 ]; then
    current=/dev/null
    [ ! -f "$target" ] || current=$target
    diff -u -- "$current" "$tmp" || true
    exit 0
fi
chmod 600 -- "$tmp"
mv -f -- "$tmp" "$target"
printf 'updated %s\n' "$target"
