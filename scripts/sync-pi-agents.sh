#!/bin/sh
# Fetch the published global agent instructions from my_skills/main and deploy
# them to both Pi and Antigravity (agy).
# --dry-run prints the diff against each installed file without writing it.
set -eu

url=https://raw.githubusercontent.com/oai404iao/my_skills/main/prompts/pi-global-agents.md
pi_dir=${PI_CODING_AGENT_DIR:-$HOME/.config/pi/agent}
gemini_dir=${GEMINI_DIR:-$HOME/.gemini}
pi_target=$pi_dir/AGENTS.md
gemini_target=$gemini_dir/GEMINI.md

case ${1-} in
    '') dry_run=0 ;;
    --dry-run) dry_run=1 ;;
    *) printf 'usage: %s [--dry-run]\n' "$0" >&2; exit 2 ;;
esac

umask 077
mkdir -p -- "$pi_dir" "$gemini_dir"
# Download beside the Pi target so staging stays under a private directory.
tmp=$(mktemp -- "$pi_dir/.AGENTS.md.XXXXXXXX")
stage=
cleanup() {
    rm -f -- "$tmp"
    [ -z "$stage" ] || rm -f -- "$stage"
}
trap cleanup EXIT HUP INT TERM

curl --fail --silent --show-error --location --proto '=https' --output "$tmp" -- "$url"
if [ ! -s "$tmp" ]; then
    printf 'refusing to install empty instructions from %s\n' "$url" >&2
    exit 1
fi

sync_target() {
    target=$1
    target_dir=$(dirname -- "$target")
    if [ -f "$target" ] && cmp -s -- "$tmp" "$target"; then
        printf '%s is up to date\n' "$target"
        return 0
    fi
    if [ "$dry_run" = 1 ]; then
        current=/dev/null
        [ ! -f "$target" ] || current=$target
        diff -u -- "$current" "$tmp" || true
        return 0
    fi
    # Stage beside the target so the final rename is atomic within one filesystem.
    stage=$(mktemp -- "$target_dir/.$(basename -- "$target").XXXXXXXX")
    cp -- "$tmp" "$stage"
    chmod 600 -- "$stage"
    mv -f -- "$stage" "$target"
    stage=
    printf 'updated %s\n' "$target"
}

sync_target "$pi_target"
sync_target "$gemini_target"
