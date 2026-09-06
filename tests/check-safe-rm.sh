#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
safe_rm="$repo_dir/dot_local/bin/executable_rm"
"$repo_dir/tests/check-safe-rm-unit.sh"
readonly GIO=/usr/bin/gio
real_home=$HOME
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

test_fail() {
    printf 'safe-rm test: %s\n' "$*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || test_fail "$2: expected file '$1'"
}

assert_directory() {
    [[ -d "$1" ]] || test_fail "$2: expected directory '$1'"
}

assert_absent() {
    if [[ -e "$1" || -L "$1" ]]; then
        test_fail "$2: expected '$1' to be absent"
    fi
}

assert_equal() {
    if [[ "$1" != "$2" ]]; then
        printf 'safe-rm test: %s: expected %q, got %q\n' \
            "$3" "$1" "$2" >&2
        exit 1
    fi
}

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
chmod 700 "$fake_runtime"
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
export GIO_USE_VFS=local

expect_refused() {
    local expected_error=$1
    shift
    local stderr_file="$sandbox/refusal.stderr"
    local status
    local stderr

    : >"$stderr_file"
    if bash "$safe_rm" "$@" >/dev/null 2>"$stderr_file"; then
        status=0
    else
        status=$?
    fi
    if [[ "$status" -eq 0 ]]; then
        printf 'safe-rm unexpectedly accepted:' >&2
        printf ' %q' "$@" >&2
        printf '\n' >&2
        return 1
    fi
    assert_equal 1 "$status" "refusal exit status"

    if ! grep -Fq -- "$expected_error" "$stderr_file"; then
        stderr=$(<"$stderr_file")
        printf 'safe-rm test: expected refusal containing %q, got: %s\n' \
            "$expected_error" "$stderr" >&2
        return 1
    fi
}

assert_gio_trashable() {
    local path=$1
    local info

    if ! info=$(LC_ALL=C "$GIO" info --nofollow-symlinks \
        --attributes=access::can-trash -- "$path" 2>&1); then
        test_fail "could not query Trash support for '$path': $info"
    fi
    if [[ "$info" != *"access::can-trash: TRUE"* ]]; then
        test_fail "expected Trash support for '$path'"
    fi
}

assert_trashed_directory() {
    local original=$1
    local expected_payload=$2
    local files_dir="$fake_data/Trash/files"
    local info_dir="$fake_data/Trash/info"
    local candidate
    local payload
    local match=
    local match_count=0
    local entry_name
    local metadata
    local entries_file="$sandbox/trash-entries"
    local metadata_path

    assert_absent "$original" "trashed operand"
    assert_directory "$files_dir" "isolated Trash payload directory"
    assert_directory "$info_dir" "isolated Trash metadata directory"

    if ! find "$files_dir" -mindepth 1 -maxdepth 1 -type d \
        -print0 >"$entries_file"; then
        test_fail "could not enumerate isolated Trash payloads"
    fi
    while IFS= read -r -d '' candidate; do
        if [[ -f "$candidate/payload" ]]; then
            payload=$(<"$candidate/payload")
            if [[ "$payload" == "$expected_payload" ]]; then
                match=$candidate
                match_count=$((match_count + 1))
            fi
        fi
    done <"$entries_file"

    assert_equal 1 "$match_count" "isolated Trash payload match count"
    entry_name=${match##*/}
    metadata="$info_dir/$entry_name.trashinfo"
    assert_file "$metadata" "isolated Trash metadata"
    grep -Fqx '[Trash Info]' "$metadata" ||
        test_fail "invalid Trash metadata header in '$metadata'"
    if ! metadata_path=$(
        python3 - "$metadata" <<'PY'
import sys
from pathlib import Path
from urllib.parse import unquote

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
paths = [line.removeprefix("Path=") for line in lines if line.startswith("Path=")]
if len(paths) != 1:
    raise SystemExit("expected exactly one Path entry")
print(unquote(paths[0]))
PY
    ); then
        test_fail "could not parse original path from '$metadata'"
    fi
    assert_equal "$original" "$metadata_path" "Trash metadata original path"
    grep -Eq '^DeletionDate=.+' "$metadata" ||
        test_fail "missing deletion date in '$metadata'"
}

# Reproduce the accident shape. Preflight must leave even the ordinary first
# operand untouched when a protected XDG root appears later.
expect_refused "protected path" -rf \
    "$ordinary" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
for directory in "$ordinary" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" \
    "$XDG_RUNTIME_DIR"; do
    assert_file "$directory/sentinel" "multi-operand protected-path preflight"
done

expect_refused "protected path" -fr "$XDG_CONFIG_HOME"
expect_refused "protected path" "$XDG_STATE_HOME" -Rfv
expect_refused "protected path" --recursive "$XDG_RUNTIME_DIR"
expect_refused "unsupported or abbreviated option" --recurs "$ordinary"
expect_refused "unsupported option: -z" -z "$ordinary"
expect_refused "--preserve-root=all cannot be represented safely" \
    --preserve-root=all -rf "$ordinary"
assert_file "$ordinary/sentinel" "option refusal"

ln -s "$fake_home" "$sandbox/home-link"
expect_refused "protected path" -rf "$sandbox/home-link/.config"
assert_file "$fake_config/sentinel" "symlinked protected path"

mkdir -p "$fake_config/child" "$fake_data/Trash"
printf 'keep\n' >"$fake_data/Trash/sentinel"
expect_refused "refusing to remove" -rf "$fake_config/child/..//"
expect_refused "protected path" -rf "$fake_home"
expect_refused "protected path" -rf "$fake_data/Trash"
assert_file "$fake_config/sentinel" "normalized protected path"
assert_file "$fake_data/Trash/sentinel" "protected Trash root"

unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR
mkdir -p "$fake_config/pi/agent" "$fake_state/pi/agent/sessions"
printf 'keep\n' >"$fake_config/pi/agent/sentinel"
printf 'keep\n' >"$fake_state/pi/agent/sessions/sentinel"
expect_refused "protected path" -rf "$fake_config/pi/agent"
expect_refused "protected path" -rf "$fake_state/pi/agent/sessions"
assert_file "$fake_config/pi/agent/sentinel" "default Pi config root"
assert_file "$fake_state/pi/agent/sessions/sentinel" "default Pi sessions root"

# A later unsupported tmpfs operand must prevent an earlier supported operand
# from moving. Skip this platform-specific check if /tmp Trash is enabled.
tmp_probe="$(mktemp -d /tmp/chezmoi-safe-rm-tmp.XXXXXX)"
: >"$tmp_probe/.safe-rm-test-root"
if ! tmp_info="$(LC_ALL=C "$GIO" info --nofollow-symlinks \
    --attributes=access::can-trash -- "$tmp_probe" 2>&1)"; then
    test_fail "could not query Trash support for '$tmp_probe': $tmp_info"
fi
if [[ "$tmp_info" != *"access::can-trash: TRUE"* ]]; then
    supported_first="$fake_home/work/supported-first"
    mkdir -p "$supported_first"
    printf 'keep\n' >"$supported_first/sentinel"
    assert_gio_trashable "$supported_first"
    expect_refused "filesystem cannot trash" -rf \
        "$supported_first" "$tmp_probe"
    assert_file "$supported_first/sentinel" \
        "unsupported later operand preflight"
    assert_file "$tmp_probe/.safe-rm-test-root" \
        "unsupported tmpfs operand preflight"
else
    printf '%s\n' "safe-rm test: skipping unsupported-/tmp preflight check" >&2
fi
if [[ "$tmp_probe" == /tmp/chezmoi-safe-rm-tmp.* &&
    -f "$tmp_probe/.safe-rm-test-root" ]]; then
    /usr/bin/rm -rf -- "$tmp_probe"
    tmp_probe=
else
    test_fail "refusing unsafe tmpfs test cleanup: '$tmp_probe'"
fi

uri_work="$fake_home/work/uri-case"
uri_operand="file://$fake_config"
uri_shadow="$uri_work/file:/${fake_config#/}"
mkdir -p "$uri_shadow"
printf 'uri-shaped\n' >"$uri_shadow/payload"
if ! (
    cd -- "$uri_work" || exit 125
    exec bash "$safe_rm" -rf -- "$uri_operand"
); then
    test_fail "could not trash a URI-shaped relative filename"
fi
assert_file "$fake_config/sentinel" "URI-shaped protected-path guard"
assert_trashed_directory "$uri_shadow" "uri-shaped"

leading_work="$fake_home/work/leading-option"
leading_operand="$leading_work/-recursive"
mkdir -p "$leading_operand"
printf 'leading-option\n' >"$leading_operand/payload"
if ! (
    cd -- "$leading_work" || exit 125
    exec bash "$safe_rm" -rf -- "-recursive"
); then
    test_fail "could not trash a relative leading-dash filename after --"
fi
assert_trashed_directory "$leading_operand" "leading-option"

victim="$fake_home/work/victim"
mkdir -p "$victim"
printf 'recoverable\n' >"$victim/payload"
if ! bash "$safe_rm" -rf -- "$victim"; then
    test_fail "could not trash the isolated victim"
fi
assert_trashed_directory "$victim" "recoverable"

plain_file="$fake_home/work/plain-file"
printf 'permanent\n' >"$plain_file"
if ! bash "$safe_rm" -f -- "$plain_file"; then
    test_fail "non-recursive delegation failed"
fi
assert_absent "$plain_file" "non-recursive delegation"

path_result="$(
    PATH="/usr/bin" \
        sh -c '. "$1"; printf "%s" "$PATH"' sh \
        "$repo_dir/dot_config/shell/profile.sh"
)"
if [[ "$path_result" != "$fake_home/.local/bin" &&
    "$path_result" != "$fake_home/.local/bin":* ]]; then
    test_fail "profile did not prepend the isolated local bin directory"
fi

printf '%s\n' "safe-rm checks passed"
