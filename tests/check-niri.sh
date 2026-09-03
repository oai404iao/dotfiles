#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Keep isolated rendering away from the real credential backend.
PATH="$repo_dir/tests/fixtures/pi/bin:$PATH"
export PATH
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-check-niri.XXXXXX")
tmp_marker="$tmp_dir/.chezmoi-check-niri"
: >"$tmp_marker"

cleanup() {
    if [ -f "$tmp_marker" ]; then
        /usr/bin/rm -rf -- "$tmp_dir"
    else
        printf 'refusing unsafe test cleanup: %s\n' "$tmp_dir" >&2
        return 1
    fi
}
trap cleanup EXIT HUP INT TERM

binds_file="$repo_dir/dot_config/niri/conf.d/60-binds.kdl"
while IFS='|' read -r expected_bind action; do
    if ! grep -Fqx "    $expected_bind" "$binds_file"; then
        printf 'missing beginner hotkey overlay entry: %s\n' "$expected_bind" >&2
        exit 1
    fi

    custom_title_count=$(
        grep -F 'hotkey-overlay-title=' "$binds_file" |
            grep -Fc "{ $action; }" ||
            true
    )
    if [ "$custom_title_count" -ne 1 ]; then
        printf 'expected one custom hotkey overlay entry for %s, found %s\n' \
            "$action" "$custom_title_count" >&2
        exit 1
    fi
done <<'EOF'
Mod+H hotkey-overlay-title="<b>Vim focus</b> · column left" { focus-column-left; }|focus-column-left
Mod+J hotkey-overlay-title="<b>Vim focus</b> · window below" { focus-window-down; }|focus-window-down
Mod+K hotkey-overlay-title="<b>Vim focus</b> · window above" { focus-window-up; }|focus-window-up
Mod+L hotkey-overlay-title="<b>Vim focus</b> · column right" { focus-column-right; }|focus-column-right
Mod+Ctrl+H hotkey-overlay-title="<b>Vim move</b> · column left" { move-column-left; }|move-column-left
Mod+Ctrl+J hotkey-overlay-title="<b>Vim move</b> · window down in column" { move-window-down; }|move-window-down
Mod+Ctrl+K hotkey-overlay-title="<b>Vim move</b> · window up in column" { move-window-up; }|move-window-up
Mod+Ctrl+L hotkey-overlay-title="<b>Vim move</b> · column right" { move-column-right; }|move-column-right
Mod+BracketLeft hotkey-overlay-title="<b>Column</b> · merge focused window into left column / split it out left" { consume-or-expel-window-left; }|consume-or-expel-window-left
Mod+BracketRight hotkey-overlay-title="<b>Column</b> · merge focused window into right column / split it out right" { consume-or-expel-window-right; }|consume-or-expel-window-right
Mod+Comma hotkey-overlay-title="<b>Column</b> · pull top window from right column to bottom" { consume-window-into-column; }|consume-window-into-column
Mod+Period hotkey-overlay-title="<b>Column</b> · split bottom window into a new right column" { expel-window-from-column; }|expel-window-from-column
EOF

if ! awk '
    BEGIN { status = 1 }
    /Mod\+T hotkey-overlay-title=/ {
        launchers_started = 1
        status = 0
    }
    launchers_started && /hotkey-overlay-title=.*\{ (focus-window-(down|up)|move-window-(down|up)|consume-window-into-column|expel-window-from-column); \}/ {
        status = 1
    }
    END { exit status }
' "$binds_file"; then
    printf '%s\n' 'beginner-only overlay entries must precede launcher entries' >&2
    exit 1
fi

for output_profile in auto laptop-dual-1080p; do
    home_dir="$tmp_dir/$output_profile"
    config_file="$tmp_dir/$output_profile.toml"
    mkdir -p "$home_dir/.config"

    cat > "$config_file" <<EOF
mode = "file"
destDir = "$home_dir"

[template]
    options = ["missingkey=error"]

[data]
    role = "laptop"
    shell = "zsh"
    graphical = true
    niri = true
    niriOutputProfile = "$output_profile"
    work = false
    secretBackend = "rbw"
EOF

    chezmoi --config "$config_file" --source "$repo_dir" apply \
        --exclude scripts "$home_dir/.config/niri" \
        >/dev/null 2>&1
    niri validate --config "$home_dir/.config/niri/config.kdl" \
        >/dev/null 2>&1
done

legacy_home="$tmp_dir/legacy"
legacy_config="$tmp_dir/legacy.toml"
mkdir -p "$legacy_home/.config"
cat > "$legacy_config" <<EOF
mode = "file"
destDir = "$legacy_home"

[template]
    options = ["missingkey=error"]

[data]
    role = "laptop"
    shell = "zsh"
    graphical = true
    niri = true
    work = false
    secretBackend = "rbw"
EOF

chezmoi --config "$legacy_config" --source "$repo_dir" apply \
    --exclude scripts "$legacy_home/.config/niri" \
    >/dev/null 2>&1
niri validate --config "$legacy_home/.config/niri/config.kdl" \
    >/dev/null 2>&1

printf '%s\n' "Niri configs passed"
