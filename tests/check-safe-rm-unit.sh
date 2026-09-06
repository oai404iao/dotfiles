#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
safe_rm="$repo_dir/dot_local/bin/executable_rm"
fake_gio="$repo_dir/tests/fixtures/safe-rm/bin/gio"
fake_rm="$repo_dir/tests/fixtures/safe-rm/bin/rm"
fake_stat="$repo_dir/tests/fixtures/safe-rm/bin/stat"
sandbox="$(mktemp -d /tmp/chezmoi-safe-rm-unit.XXXXXX)"
marker="$sandbox/.safe-rm-test-root"
: >"$marker"

cleanup() {
    if [[ "$sandbox" == /tmp/chezmoi-safe-rm-unit.* &&
        -f "$marker" ]]; then
        /usr/bin/rm -rf -- "$sandbox"
    else
        printf 'refusing unsafe safe-rm unit cleanup: %s\n' "$sandbox" >&2
        return 1
    fi
}
trap cleanup EXIT

test_fail() {
    printf 'safe-rm unit test: %s\n' "$*" >&2
    exit 1
}

assert_equal() {
    if [[ "$1" != "$2" ]]; then
        printf 'safe-rm unit test: %s: expected %q, got %q\n' \
            "$3" "$1" "$2" >&2
        exit 1
    fi
}

assert_contains() {
    local file=$1
    local expected=$2
    local label=$3

    if ! /usr/bin/grep -Fq -- "$expected" "$file"; then
        printf 'safe-rm unit test: %s: expected diagnostic containing %q\n' \
            "$label" "$expected" >&2
        exit 1
    fi
}

assert_output() {
    local file=$1
    local expected=$2
    local label=$3
    local expected_file="$state/$label.expected"

    printf '%s' "$expected" >"$expected_file"
    /usr/bin/cmp -s -- "$expected_file" "$file" ||
        test_fail "$label did not match"
}

case_number=0
gio_planned=0
stat_planned=0
expected_rm_calls=0
state=
case_dir=
run_status=

begin_case() {
    local label=$1

    case_number=$((case_number + 1))
    case_dir=$(printf '%s/cases/%03d-%s' "$sandbox" "$case_number" "$label")
    state="$case_dir/state"
    /usr/bin/mkdir -p -- "$state/gio.plan" "$state/stat.plan"
    : >"$state/.safe-rm-test-state"
    printf '%s' "$sandbox" >"$state/sandbox"
    printf '0\n' >"$state/rm.status"
    export SAFE_RM_TEST_STATE="$state"
    gio_planned=0
    stat_planned=0
    expected_rm_calls=0
    run_status=
}

plan_stat() {
    local path=$1
    local mount_root=$2
    local result=${3:-ok}
    local plan_dir

    stat_planned=$((stat_planned + 1))
    plan_dir=$(printf '%s/stat.plan/%06d' "$state" "$stat_planned")
    /usr/bin/mkdir -p -- "$plan_dir"
    printf '%s' "$path" >"$plan_dir/path"
    printf '%s' "$mount_root" >"$plan_dir/mount-root"
    printf '%s' "$result" >"$plan_dir/result"
}

plan_info() {
    local result=$1
    local path=$2
    local plan_dir

    gio_planned=$((gio_planned + 1))
    plan_dir=$(printf '%s/gio.plan/%06d' "$state" "$gio_planned")
    /usr/bin/mkdir -p -- "$plan_dir"
    printf 'info' >"$plan_dir/kind"
    printf '%s' "$path" >"$plan_dir/path"
    printf '%s' "$result" >"$plan_dir/result"
    if [[ "$result" == retarget-true ]]; then
        (($# == 4)) || test_fail "retarget plan requires a link and target"
        printf '%s' "$3" >"$plan_dir/retarget-path"
        printf '%s' "$4" >"$plan_dir/retarget-target"
    else
        (($# == 2)) || test_fail "unexpected info plan arguments"
    fi
}

plan_trash() {
    local result=$1
    local force=$2
    local path=$3
    local plan_dir

    gio_planned=$((gio_planned + 1))
    plan_dir=$(printf '%s/gio.plan/%06d' "$state" "$gio_planned")
    /usr/bin/mkdir -p -- "$plan_dir"
    printf 'trash' >"$plan_dir/kind"
    printf '%s' "$path" >"$plan_dir/path"
    printf '%s' "$result" >"$plan_dir/result"
    printf '%s' "$force" >"$plan_dir/force"
}

plan_successful_trash() {
    local path=$1
    local force=$2

    plan_info TRUE "$path"
    plan_info TRUE "$path"
    plan_trash ok "$force" "$path"
}

configure_rm() {
    local status=$1
    local stdout=$2
    local stderr=$3

    printf '%s\n' "$status" >"$state/rm.status"
    printf '%s' "$stdout" >"$state/rm.stdout"
    printf '%s' "$stderr" >"$state/rm.stderr"
    expected_rm_calls=1
}

run_safe() {
    unset POSIXLY_CORRECT
    if safe_rm_main \
        "$fake_rm" "$fake_gio" /usr/bin/realpath /usr/bin/stat "$@" \
        >"$state/stdout" 2>"$state/stderr"; then
        run_status=0
    else
        run_status=$?
    fi
}

run_safe_posix() {
    local value=$1
    shift

    export POSIXLY_CORRECT="$value"
    if safe_rm_main \
        "$fake_rm" "$fake_gio" /usr/bin/realpath /usr/bin/stat "$@" \
        >"$state/stdout" 2>"$state/stderr"; then
        run_status=0
    else
        run_status=$?
    fi
    unset POSIXLY_CORRECT
}

run_safe_with_fake_stat() {
    unset POSIXLY_CORRECT
    if safe_rm_main \
        "$fake_rm" "$fake_gio" /usr/bin/realpath "$fake_stat" "$@" \
        >"$state/stdout" 2>"$state/stderr"; then
        run_status=0
    else
        run_status=$?
    fi
}

run_safe_nocasematch() {
    shopt -s nocasematch
    run_safe "$@"
    shopt -u nocasematch
}

assert_success() {
    local label=$1

    assert_equal 0 "$run_status" "$label status"
    assert_output "$state/stderr" "" "$label-stderr"
}

assert_failure() {
    local expected_status=$1
    local diagnostic=$2
    local label=$3

    assert_equal "$expected_status" "$run_status" "$label status"
    assert_contains "$state/stderr" "$diagnostic" "$label"
}

assert_rm_args() {
    local label=$1
    shift
    local -a actual=()
    local -a expected=("$@")
    local index

    [[ -f "$state/rm.actual/000001/argv.nul" ]] ||
        test_fail "$label did not call fake rm"
    mapfile -d '' -t actual <"$state/rm.actual/000001/argv.nul"
    assert_equal "${#expected[@]}" "${#actual[@]}" "$label argument count"
    for index in "${!actual[@]}"; do
        assert_equal "${expected[$index]}" "${actual[$index]}" \
            "$label argument $index"
    done
}

finish_case() {
    local gio_calls=0
    local rm_calls=0
    local stat_calls=0

    [[ ! -f "$state/gio.counter" ]] || gio_calls=$(<"$state/gio.counter")
    [[ ! -f "$state/rm.counter" ]] || rm_calls=$(<"$state/rm.counter")
    [[ ! -f "$state/stat.counter" ]] || stat_calls=$(<"$state/stat.counter")
    assert_equal "$gio_planned" "$gio_calls" "GIO plan consumption"
    assert_equal "$expected_rm_calls" "$rm_calls" "rm call count"
    assert_equal "$stat_planned" "$stat_calls" "stat plan consumption"
    if [[ -s "$state/gio.protocol-errors" ]]; then
        test_fail "fake GIO rejected a call: $(<"$state/gio.protocol-errors")"
    fi
    if [[ -s "$state/stat.protocol-errors" ]]; then
        test_fail "fake stat rejected a call: $(<"$state/stat.protocol-errors")"
    fi
}

fake_home="$sandbox/home"
xdg_config="$sandbox/xdg/config"
xdg_cache="$sandbox/xdg/cache"
xdg_data="$sandbox/xdg/data"
xdg_state="$sandbox/xdg/state"
xdg_runtime="$sandbox/xdg/runtime"
pi_config="$sandbox/pi/config"
pi_sessions="$sandbox/pi/sessions"
work="$sandbox/work"
/usr/bin/mkdir -p -- \
    "$fake_home" "$xdg_config" "$xdg_cache" "$xdg_data" "$xdg_state" \
    "$xdg_runtime" "$pi_config" "$pi_sessions" "$work"
/usr/bin/chmod 700 "$xdg_runtime"

export HOME="$fake_home"
export XDG_CONFIG_HOME="$xdg_config"
export XDG_CACHE_HOME="$xdg_cache"
export XDG_DATA_HOME="$xdg_data"
export XDG_STATE_HOME="$xdg_state"
export XDG_RUNTIME_DIR="$xdg_runtime"
export PI_CODING_AGENT_DIR="$pi_config"
export PI_CODING_AGENT_SESSION_DIR="$pi_sessions"
export GIO_USE_VFS=local
unset POSIXLY_CORRECT

begin_case source
source_sentinel="$case_dir/sentinel"
: >"$source_sentinel"
source_pwd=$PWD
source_flags=$-
source "$safe_rm" >"$state/source.stdout" 2>"$state/source.stderr"
declare -F safe_rm_main >/dev/null ||
    test_fail "sourcing did not define safe_rm_main"
assert_equal "$source_pwd" "$PWD" "source working directory"
assert_equal "$source_flags" "$-" "source shell flags"
assert_output "$state/source.stdout" "" "source-stdout"
assert_output "$state/source.stderr" "" "source-stderr"
[[ -f "$source_sentinel" ]] || test_fail "sourcing changed the sentinel"
if [[ "$(/usr/bin/grep -Fc \
    '/usr/bin/rm /usr/bin/gio /usr/bin/realpath /usr/bin/stat' \
    "$safe_rm")" -ne 1 ]]; then
    test_fail "production command paths are not confined to the direct entry"
fi
finish_case

begin_case nonrecursive
delegated="$case_dir/delegated"
/usr/bin/mkdir -p -- "$delegated"
: >"$delegated/sentinel"
configure_rm 37 $'delegated stdout\n' $'delegated diagnostic\n'
nonrecursive_args=(-f -- "name with space" "" -leading)
run_safe "${nonrecursive_args[@]}"
assert_failure 37 "delegated diagnostic" "nonrecursive delegation"
assert_output "$state/stdout" $'delegated stdout\n' "nonrecursive-stdout"
assert_rm_args "nonrecursive delegation" "${nonrecursive_args[@]}"
[[ -f "$delegated/sentinel" ]] ||
    test_fail "fake rm removed a nonrecursive payload"
finish_case

operand="$work/parser-operand"
/usr/bin/mkdir -p -- "$operand"
: >"$operand/sentinel"

begin_case protected-later
protected_first="$case_dir/ordinary"
/usr/bin/mkdir -p -- "$protected_first"
run_safe -r "$protected_first" "$XDG_CONFIG_HOME"
assert_failure 1 "protected path" "protected later operand"
[[ -d "$protected_first" ]] ||
    test_fail "protected-path preflight changed the first operand"
finish_case

begin_case missing-later
missing_first="$case_dir/ordinary"
missing_later="$case_dir/missing"
/usr/bin/mkdir -p -- "$missing_first"
run_safe -r "$missing_first" "$missing_later"
assert_failure 1 "No such file or directory" "missing later operand"
[[ -d "$missing_first" ]] ||
    test_fail "missing-path preflight changed the first operand"
finish_case

begin_case cluster-fi
run_safe -rfi "$operand"
assert_failure 1 "interactive recursive removal is not supported" \
    "cluster -f then -i"
finish_case

begin_case cluster-if
plan_successful_trash "$operand" true
run_safe -rif "$operand"
assert_success "cluster -i then -f"
finish_case

begin_case cluster-fI
run_safe -rfI "$operand"
assert_failure 1 "interactive recursive removal is not supported" \
    "cluster -f then -I"
finish_case

begin_case cluster-If
plan_successful_trash "$operand" true
run_safe -rIf "$operand"
assert_success "cluster -I then -f"
finish_case

begin_case split-fi
run_safe -r -f -i "$operand"
assert_failure 1 "interactive recursive removal is not supported" \
    "split -f then -i"
finish_case

begin_case split-if
plan_successful_trash "$operand" true
run_safe -r -i -f "$operand"
assert_success "split -i then -f"
finish_case

begin_case split-fI
run_safe -r -f -I "$operand"
assert_failure 1 "interactive recursive removal is not supported" \
    "split -f then -I"
finish_case

begin_case split-If
plan_successful_trash "$operand" true
run_safe -r -I -f "$operand"
assert_success "split -I then -f"
finish_case

begin_case long-force-interactive
run_safe --recursive --force --interactive=always "$operand"
assert_failure 1 "interactive recursive removal is not supported" \
    "long force then interactive"
finish_case

begin_case long-interactive-force
plan_successful_trash "$operand" true
run_safe --recursive --interactive --force "$operand"
assert_success "long interactive then force"
finish_case

begin_case interactive-never
plan_successful_trash "$operand" false
run_safe --recursive --interactive=never "$operand"
assert_success "interactive never"
finish_case

begin_case force-interactive-never
run_safe --recursive --force --interactive=never "$case_dir/missing"
assert_success "force then interactive never"
finish_case

begin_case invalid-interactive
run_safe --recursive --interactive=sometimes "$operand"
assert_failure 1 "unsupported interactive mode: sometimes" \
    "invalid interactive mode"
finish_case

begin_case nocasematch-option
run_safe_nocasematch -rF "$case_dir/missing"
assert_failure 1 "unsupported option: -F" "nocasematch option parsing"
finish_case

begin_case nocasematch-attribute
nocasematch_operand="$case_dir/operand"
/usr/bin/mkdir -p -- "$nocasematch_operand"
plan_info wrong-case-true "$nocasematch_operand"
run_safe_nocasematch -r "$nocasematch_operand"
assert_failure 1 "filesystem cannot trash" "nocasematch GIO attribute"
finish_case

begin_case zero-operands
zero_args=(-r -i --one-file-system --no-preserve-root --preserve-root=all)
configure_rm 38 "" $'zero-operand delegation\n'
run_safe "${zero_args[@]}"
assert_failure 38 "zero-operand delegation" \
    "zero operands before policy refusals"
assert_rm_args "zero operands" "${zero_args[@]}"
finish_case

begin_case permutation
plan_successful_trash "$operand" false
run_safe "$operand" -rv
assert_success "default option permutation"
assert_output "$state/stdout" "trashed '$operand'"$'\n' \
    "permutation-stdout"
finish_case

for posix_value in 1 ""; do
    begin_case "posix-${posix_value:-empty}"
    posix_args=("$operand" -rf)
    configure_rm 39 "" $'POSIX delegation\n'
    run_safe_posix "$posix_value" "${posix_args[@]}"
    assert_failure 39 "POSIX delegation" \
        "POSIXLY_CORRECT ${posix_value:-empty}"
    assert_rm_args "POSIXLY_CORRECT ${posix_value:-empty}" \
        "${posix_args[@]}"
    finish_case
done

begin_case trailing-force
trailing_force_operand="$case_dir/operand"
/usr/bin/mkdir -p -- "$trailing_force_operand"
plan_successful_trash "$trailing_force_operand" true
original_pwd=$PWD
cd -- "$case_dir"
run_safe -r "$trailing_force_operand" -f
cd -- "$original_pwd"
assert_success "default trailing force option"
finish_case

begin_case posix-trailing-force
posix_trailing_operand="$case_dir/operand"
/usr/bin/mkdir -p -- "$posix_trailing_operand"
original_pwd=$PWD
cd -- "$case_dir"
run_safe_posix "" -r "$posix_trailing_operand" -f
cd -- "$original_pwd"
assert_failure 1 "cannot remove '-f'" "POSIX trailing force operand"
[[ -d "$posix_trailing_operand" ]] ||
    test_fail "POSIX path preflight changed the first operand"
finish_case

for alias in --interact=never --force=true; do
    begin_case "alias-${alias#--}"
    run_safe --recursive "$alias" "$operand"
    assert_failure 1 "unsupported or abbreviated option: $alias" \
        "undocumented alias $alias"
    finish_case
done

begin_case initial-info-error
initial_error="$case_dir/operand"
/usr/bin/mkdir -p -- "$initial_error"
plan_info error "$initial_error"
run_safe -r "$initial_error"
assert_failure 1 "cannot verify trash support for '$initial_error'" \
    "initial GIO info error"
finish_case

begin_case initial-info-false
initial_false="$case_dir/operand"
/usr/bin/mkdir -p -- "$initial_false"
plan_info FALSE "$initial_false"
run_safe -r "$initial_false"
assert_failure 1 "filesystem cannot trash '$initial_false'" \
    "initial GIO FALSE"
finish_case

begin_case initial-info-spoofed-false
initial_spoofed_false="$case_dir/operand"
/usr/bin/mkdir -p -- "$initial_spoofed_false"
plan_info spoofed-false "$initial_spoofed_false"
run_safe -r "$initial_spoofed_false"
assert_failure 1 "filesystem cannot trash '$initial_spoofed_false'" \
    "initial GIO spoofed FALSE"
finish_case

begin_case later-info-false
supported_first="$case_dir/A"
unsupported_later="$case_dir/B"
/usr/bin/mkdir -p -- "$supported_first" "$unsupported_later"
plan_info TRUE "$supported_first"
plan_info FALSE "$unsupported_later"
run_safe -r "$supported_first" "$unsupported_later"
assert_failure 1 "filesystem cannot trash '$unsupported_later'" \
    "later GIO FALSE"
[[ -d "$supported_first" && -d "$unsupported_later" ]] ||
    test_fail "capability preflight changed an operand"
finish_case

for second_result in error FALSE; do
    begin_case "second-info-${second_result,,}"
    second_operand="$case_dir/operand"
    /usr/bin/mkdir -p -- "$second_operand"
    plan_info TRUE "$second_operand"
    plan_info "$second_result" "$second_operand"
    run_safe -r "$second_operand"
    if [[ "$second_result" == error ]]; then
        second_diagnostic="cannot recheck trash support for '$second_operand'"
    else
        second_diagnostic="filesystem can no longer trash '$second_operand'"
    fi
    assert_failure 1 "$second_diagnostic" "second GIO info $second_result"
    finish_case
done

begin_case second-info-spoofed-false
second_spoofed_operand="$case_dir/operand"
/usr/bin/mkdir -p -- "$second_spoofed_operand"
plan_info TRUE "$second_spoofed_operand"
plan_info spoofed-false "$second_spoofed_operand"
run_safe -r "$second_spoofed_operand"
assert_failure 1 "filesystem can no longer trash '$second_spoofed_operand'" \
    "second GIO spoofed FALSE"
finish_case

for stat_result in error relative; do
    begin_case "initial-stat-$stat_result"
    stat_operand="$case_dir/operand"
    /usr/bin/mkdir -p -- "$stat_operand"
    plan_stat "$stat_operand" / "$stat_result"
    run_safe_with_fake_stat -r "$stat_operand"
    assert_failure 1 "cannot determine Trash location" \
        "initial stat $stat_result"
    finish_case
done

begin_case second-stat-error
second_stat_operand="$case_dir/operand"
/usr/bin/mkdir -p -- "$second_stat_operand"
plan_stat "$second_stat_operand" /
plan_stat "$second_stat_operand" / error
plan_info TRUE "$second_stat_operand"
run_safe_with_fake_stat -r "$second_stat_operand"
assert_failure 1 "cannot determine Trash location before trashing" \
    "second stat error"
finish_case

begin_case changed-mount-root
changed_volume="$case_dir/volume"
changed_mount_operand="$changed_volume/.Trash-$(/usr/bin/id -u)/item"
/usr/bin/mkdir -p -- "$changed_mount_operand"
plan_stat "$changed_mount_operand" /
plan_stat "$changed_mount_operand" "$changed_volume"
plan_info TRUE "$changed_mount_operand"
run_safe_with_fake_stat -r "$changed_mount_operand"
assert_failure 1 "path became protected before trashing" \
    "changed mount root"
finish_case

begin_case symlink-retarget
safe_target="$case_dir/safe-target"
retarget_link="$case_dir/retarget-link"
/usr/bin/mkdir -p -- "$safe_target"
/usr/bin/ln -s -- "$safe_target" "$retarget_link"
plan_info retarget-true "$retarget_link" "$retarget_link" "$XDG_CONFIG_HOME"
run_safe -r "$retarget_link"
assert_failure 1 "path became protected before trashing" \
    "symlink retargeted between checks"
assert_equal "$XDG_CONFIG_HOME" "$(/usr/bin/readlink -- "$retarget_link")" \
    "retargeted symlink target"
finish_case

begin_case partial-completion
partial_a="$case_dir/A"
partial_b="$case_dir/B"
partial_c="$case_dir/C"
/usr/bin/mkdir -p -- "$partial_a" "$partial_b" "$partial_c"
plan_info TRUE "$partial_a"
plan_info TRUE "$partial_b"
plan_info TRUE "$partial_c"
plan_info TRUE "$partial_a"
plan_trash ok false "$partial_a"
plan_info TRUE "$partial_b"
plan_trash error false "$partial_b"
run_safe -rv "$partial_a" "$partial_b" "$partial_c"
assert_failure 1 "inspect the Trash before retrying" "partial completion"
assert_output "$state/stdout" "trashed '$partial_a'"$'\n' \
    "partial-completion-stdout"
[[ -d "$partial_a" && -d "$partial_b" && -d "$partial_c" ]] ||
    test_fail "fake GIO changed a partial-completion payload"
finish_case

xdg_trash="$XDG_DATA_HOME/Trash"
home_trash="$HOME/.local/share/Trash"
/usr/bin/mkdir -p -- \
    "$xdg_trash/descendant" "$home_trash/descendant" "$work/outside"
/usr/bin/ln -s -- "$xdg_trash" "$work/xdg-trash-alias"
/usr/bin/ln -s -- "$work/outside" "$xdg_trash/final-symlink"

protected_trash_paths=(
    "$xdg_trash"
    "$xdg_trash/descendant"
    "$home_trash"
    "$home_trash/descendant"
    "$work/xdg-trash-alias"
    "$xdg_trash/final-symlink"
    "$work/xdg-trash-alias/final-symlink"
)
for protected_trash in "${protected_trash_paths[@]}"; do
    begin_case trash-root
    run_safe -r -- "$protected_trash"
    assert_failure 1 "protected path" "configured Trash path $protected_trash"
    finish_case
done

uid=$(/usr/bin/id -u)
volume_root="$sandbox/volume"
volume_trash_paths=(
    "$volume_root"
    "$volume_root/.Trash"
    "$volume_root/.Trash/$uid"
    "$volume_root/.Trash/$uid/files/item"
    "$volume_root/.Trash-$uid"
    "$volume_root/.Trash-$uid/files/item"
)
for volume_trash in "${volume_trash_paths[@]}"; do
    /usr/bin/mkdir -p -- "$volume_trash"
    begin_case volume-trash
    plan_stat "$volume_trash" "$volume_root"
    run_safe_with_fake_stat -r -- "$volume_trash"
    assert_failure 1 "protected path" "volume Trash path $volume_trash"
    finish_case
done

nested_trash_name="$volume_root/project/.Trash/$uid/item"
/usr/bin/mkdir -p -- "$nested_trash_name"
begin_case nested-trash-name
plan_stat "$nested_trash_name" "$volume_root"
plan_stat "$nested_trash_name" "$volume_root"
plan_successful_trash "$nested_trash_name" false
run_safe_with_fake_stat -r -- "$nested_trash_name"
assert_success "nested non-volume Trash name"
finish_case

printf '%s\n' "safe-rm deterministic unit checks passed"
