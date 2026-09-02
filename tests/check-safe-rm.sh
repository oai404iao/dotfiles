#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
safe_rm="$repo_dir/dot_local/bin/executable_rm"
real_home=$HOME
real_config=${XDG_CONFIG_HOME:-$real_home/.config}
real_cache=${XDG_CACHE_HOME:-$real_home/.cache}
real_data=${XDG_DATA_HOME:-$real_home/.local/share}
real_state=${XDG_STATE_HOME:-$real_home/.local/state}
real_runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
real_pi_config=${PI_CODING_AGENT_DIR:-$real_config/pi/agent}
real_pi_sessions=${PI_CODING_AGENT_SESSION_DIR:-$real_state/pi/agent/sessions}
sandbox="$(mktemp -d "$real_home/.cache/chezmoi-safe-rm.XXXXXX")"
marker="$sandbox/.safe-rm-test-root"
: >"$marker"
tmp_probe=

cleanup() {
    if [[ -n "$tmp_probe" ]]; then
        if [[ "$tmp_probe" == /tmp/chezmoi-safe-rm-tmp.* &&
            -f "$tmp_probe/.safe-rm-test-root" ]]; then
            /usr/bin/rm -rf -- "$tmp_probe"
        else
            printf 'refusing unsafe tmpfs test cleanup: %s\n' "$tmp_probe" >&2
            return 1
        fi
    fi

    if [[ "$sandbox" == "$real_home/.cache/chezmoi-safe-rm."* &&
        -f "$marker" ]]; then
        /usr/bin/rm -rf -- "$sandbox"
    else
        printf 'refusing unsafe test cleanup: %s\n' "$sandbox" >&2
        return 1
    fi
}
trap cleanup EXIT

fake_home="$sandbox/home"
fake_config="$fake_home/.config"
fake_cache="$fake_home/.cache"
fake_data="$fake_home/.local/share"
fake_state="$fake_home/.local/state"
fake_runtime="$sandbox/runtime"
ordinary="$fake_home/work/ordinary"

mkdir -p \
    "$fake_config" "$fake_cache" "$fake_data" "$fake_state" \
    "$fake_runtime" "$ordinary"
for directory in \
    "$fake_config" "$fake_cache" "$fake_data" "$fake_state" \
    "$fake_runtime" "$ordinary"; do
    printf 'keep\n' >"$directory/sentinel"
done

export HOME="$fake_home"
export XDG_CONFIG_HOME="$fake_config"
export XDG_CACHE_HOME="$fake_cache"
export XDG_DATA_HOME="$fake_data"
export XDG_STATE_HOME="$fake_state"
export XDG_RUNTIME_DIR="$fake_runtime"
export PI_CODING_AGENT_DIR="$fake_config/pi/agent"
export PI_CODING_AGENT_SESSION_DIR="$fake_state/pi/agent/sessions"

expect_refused() {
    if bash "$safe_rm" "$@" >/dev/null 2>&1; then
        printf 'safe-rm unexpectedly accepted:' >&2
        printf ' %q' "$@" >&2
        printf '\n' >&2
        return 1
    fi
}

# Reproduce the accident shape. Preflight must leave even the ordinary first
# operand untouched when a protected XDG root appears later.
expect_refused -rf \
    "$ordinary" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
for directory in "$ordinary" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" \
    "$XDG_RUNTIME_DIR"; do
    [[ -f "$directory/sentinel" ]]
done

expect_refused -fr "$XDG_CONFIG_HOME"
expect_refused "$XDG_STATE_HOME" -Rfv
expect_refused --recursive "$XDG_RUNTIME_DIR"
expect_refused --recurs "$ordinary"
expect_refused -z "$ordinary"
expect_refused --preserve-root=all -rf "$ordinary"
[[ -f "$ordinary/sentinel" ]]

ln -s "$fake_home" "$sandbox/home-link"
expect_refused -rf "$sandbox/home-link/.config"
[[ -f "$fake_config/sentinel" ]]

mkdir -p "$fake_config/child" "$fake_data/Trash"
expect_refused -rf "$fake_config/child/..//"
expect_refused -rf "$fake_home"
expect_refused -rf "$fake_data/Trash"
[[ -f "$fake_config/sentinel" ]]

unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR
mkdir -p "$fake_config/pi/agent" "$fake_state/pi/agent/sessions"
expect_refused -rf "$fake_config/pi/agent"
expect_refused -rf "$fake_state/pi/agent/sessions"

# A later unsupported tmpfs operand must prevent an earlier supported operand
# from moving. Skip this platform-specific check if /tmp Trash is enabled.
tmp_probe="$(mktemp -d /tmp/chezmoi-safe-rm-tmp.XXXXXX)"
: >"$tmp_probe/.safe-rm-test-root"
tmp_info="$(LC_ALL=C gio info --nofollow-symlinks \
    --attributes=access::can-trash -- "$tmp_probe")"
if [[ "$tmp_info" != *"access::can-trash: TRUE"* ]]; then
    supported_first="$fake_home/work/supported-first"
    mkdir -p "$supported_first"
    printf 'keep\n' >"$supported_first/sentinel"
    expect_refused -rf "$supported_first" "$tmp_probe"
    [[ -f "$supported_first/sentinel" ]]
    [[ -f "$tmp_probe/.safe-rm-test-root" ]]
fi
/usr/bin/rm -rf -- "$tmp_probe"
tmp_probe=

victim="$fake_home/work/victim"
mkdir -p "$victim"
printf 'recoverable\n' >"$victim/payload"

# Use the real home Trash for the successful round trip. The fake XDG roots
# above exist only to exercise protected-path handling.
export HOME="$real_home"
export XDG_CONFIG_HOME="$real_config"
export XDG_CACHE_HOME="$real_cache"
export XDG_DATA_HOME="$real_data"
export XDG_STATE_HOME="$real_state"
export XDG_RUNTIME_DIR="$real_runtime"
export PI_CODING_AGENT_DIR="$real_pi_config"
export PI_CODING_AGENT_SESSION_DIR="$real_pi_sessions"
bash "$safe_rm" -rf -- "$victim"
[[ ! -e "$victim" ]]

trash_listing="$(gio trash --list)"
trash_uri="$(
    printf '%s\n' "$trash_listing" |
        awk -F '\t' -v original="$victim" '$2 == original { print $1; exit }'
)"
[[ "$trash_uri" == trash:///* ]]
gio trash --restore -- "$trash_uri"
[[ "$(cat "$victim/payload")" == recoverable ]]

plain_file="$fake_home/work/plain-file"
printf 'permanent\n' >"$plain_file"
bash "$safe_rm" -f -- "$plain_file"
[[ ! -e "$plain_file" ]]

path_result="$(
    PATH="/usr/bin:$real_home/.local/bin" \
        sh -c '. "$1"; printf "%s" "$PATH"' sh \
        "$repo_dir/dot_config/shell/profile.sh"
)"
[[ "$path_result" == "$real_home/.local/bin" ||
    "$path_result" == "$real_home/.local/bin":* ]]

printf '%s\n' "safe-rm checks passed"
