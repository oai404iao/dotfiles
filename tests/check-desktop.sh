#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

(
    LANG="en_US.UTF-8"
    LANGUAGE="en_US:en"
    LC_ALL="en_US.UTF-8"
    LC_TIME="en_US.UTF-8"
    export LANG LANGUAGE LC_ALL LC_TIME

    . "$repo_dir/dot_config/shell/profile.sh"
    [ "$LANG" = "zh_CN.UTF-8" ]
    [ "$LANGUAGE" = "zh_CN:zh" ]
    [ "$LC_ALL" = "zh_CN.UTF-8" ]
    [ -z "${LC_TIME-}" ]

    LC_ALL="zh_CN.UTF-8"
    LC_TIME="zh_CN.UTF-8"
    export LC_ALL LC_TIME
    . "$repo_dir/dot_config/shell/interactive.sh"
    [ "$LANG" = "en_US.UTF-8" ]
    [ "$LANGUAGE" = "en_US:en" ]
    [ -z "${LC_ALL-}" ]
    [ -z "${LC_TIME-}" ]
)

environment_generator="/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator"
if [ -x "$environment_generator" ]; then
    generated_environment=$(
        LC_ALL="en_US.UTF-8" \
            XDG_CONFIG_HOME="$repo_dir/dot_config" \
            "$environment_generator"
    )
    for assignment in \
        "LANG=zh_CN.UTF-8" \
        "LANGUAGE=zh_CN:zh" \
        "LC_ALL=zh_CN.UTF-8"
    do
        printf '%s\n' "$generated_environment" | grep -qxF "$assignment"
    done
fi

gtk2_result=$(
    printf '%s\n' \
        'gtk-theme-name="Existing"' \
        'gtk-font-name="Existing 10"' \
        'gtk-font-name="Duplicate 12"' |
        "$repo_dir/modify_dot_gtkrc-2.0"
)
gtk2_expected=$(printf '%s\n' \
    'gtk-theme-name="Existing"' \
    'gtk-font-name="Adwaita Sans 11"')
[ "$gtk2_result" = "$gtk2_expected" ]

python3 - "$repo_dir" <<'PY'
import configparser
import pathlib
import sys
import tomllib
import xml.etree.ElementTree as ET

repo_dir = pathlib.Path(sys.argv[1])

locale_lines = {
    line
    for line in (repo_dir / "dot_config/environment.d/10-locale.conf")
    .read_text()
    .splitlines()
    if line
}
if locale_lines != {
    "LANG=zh_CN.UTF-8",
    "LANGUAGE=zh_CN:zh",
    "LC_ALL=zh_CN.UTF-8",
}:
    raise SystemExit("unexpected user session locale")

interactive_path = "shell/interactive.sh"
for relative in ("dot_bashrc", "dot_config/zsh/dot_zshrc"):
    if interactive_path not in (repo_dir / relative).read_text():
        raise SystemExit(f"{relative} does not load the interactive locale")

font_root = ET.parse(repo_dir / "dot_config/fontconfig/fonts.conf").getroot()
aliases = {}
for alias in font_root.findall("alias"):
    generic = alias.findtext("family")
    if alias.get("binding") != "strong":
        raise SystemExit(f"font alias is not strongly bound: {generic}")
    if generic in aliases:
        raise SystemExit(f"duplicate font alias: {generic}")
    aliases[generic] = [
        family.text for family in alias.findall("prefer/family")
    ]

expected_aliases = {
    "sans-serif": [
        "Adwaita Sans",
        "Noto Sans CJK SC",
        "Noto Color Emoji",
        "Noto Sans Symbols",
    ],
    "serif": [
        "Noto Serif",
        "Noto Serif CJK SC",
        "Noto Color Emoji",
        "Noto Sans Symbols",
    ],
    "monospace": [
        "JetBrainsMono Nerd Font Mono",
        "Noto Sans Mono CJK SC",
        "Noto Color Emoji",
        "Noto Sans Symbols",
    ],
}
if aliases != expected_aliases:
    raise SystemExit(f"unexpected font aliases: {aliases}")

for gtk_version in ("3.0", "4.0"):
    settings = configparser.ConfigParser(interpolation=None)
    settings.read(repo_dir / f"dot_config/gtk-{gtk_version}/settings.ini")
    if settings.get("Settings", "gtk-font-name") != "Adwaita Sans 11":
        raise SystemExit(f"unexpected GTK {gtk_version} font")

ignore_text = (repo_dir / ".chezmoiignore").read_text()
ignore_lines = set(ignore_text.splitlines())
expected_ignored = {
    ".gtkrc-2.0",
    ".config/environment.d/im.conf",
    ".config/fontconfig/",
    ".config/gtk-3.0/",
    ".config/gtk-4.0/",
}
if not expected_ignored <= ignore_lines:
    raise SystemExit(
        f"missing headless desktop ignores: {sorted(expected_ignored - ignore_lines)}"
    )
headless_block = ignore_text.split("{{- if not .graphical }}", 1)[1].split(
    "{{- end }}", 1
)[0]
if not expected_ignored <= set(headless_block.splitlines()):
    raise SystemExit("desktop ignores are outside the graphical condition")
if ".config/environment.d/" in ignore_lines:
    raise SystemExit("the user locale is ignored on headless profiles")

kitty = (repo_dir / "dot_config/kitty/kitty.conf.tmpl").read_text()
if "font_family JetBrainsMono Nerd Font Mono\n" not in kitty:
    raise SystemExit("Kitty does not use the managed monospace font")
kitty_theme_block = """# BEGIN_KITTY_THEME
# Matugen
include current-theme.conf
# END_KITTY_THEME"""
if kitty_theme_block not in kitty:
    raise SystemExit("Kitty does not use the themes kitten marker block")
if kitty.count("include current-theme.conf") != 1:
    raise SystemExit("Kitty includes current-theme.conf more than once")

waybar = (repo_dir / "dot_config/waybar/style.css").read_text()
if 'font-family: "JetBrainsMono Nerd Font", "Noto Sans Mono CJK SC"' not in waybar:
    raise SystemExit("Waybar does not use the full-width Nerd Font")

waybar_config = (repo_dir / "dot_config/waybar/config.jsonc").read_text()
if '"reload_style_on_change": true' not in waybar_config:
    raise SystemExit("Waybar does not hot-reload CSS changes")
if '@import "colors.css";' not in waybar:
    raise SystemExit("Waybar does not import the generated colors")
matugen = tomllib.loads(
    (repo_dir / "dot_config/matugen/config.toml").read_text()
)
matugen_waybar = matugen["templates"]["waybar"]
if matugen_waybar["output_path"] != "~/.config/waybar/colors.css":
    raise SystemExit("Matugen does not update Waybar's imported colors")
if "SIGUSR2" in matugen_waybar.get("post_hook", "").upper():
    raise SystemExit("Matugen resets Waybar instead of relying on CSS reload")
matugen_kitty = matugen["templates"]["kitty"]
if matugen_kitty["output_path"] != "~/.config/kitty/themes/matugen.conf":
    raise SystemExit("Matugen does not update Kitty's selected theme")
kitty_hook = matugen_kitty.get("post_hook", "")
if not all(part in kitty_hook for part in ("themes", "--reload-in=all", "matugen")):
    raise SystemExit("Matugen does not hot-reload Kitty's theme")
left_modules = waybar_config.split('"modules-left": [', 1)[1].split("]", 1)[0]
center_modules = waybar_config.split('"modules-center": [', 1)[1].split("]", 1)[0]
right_modules = waybar_config.split('"modules-right": [', 1)[1].split("]", 1)[0]
center_entries = [
    line.strip().rstrip(",").strip('"')
    for line in center_modules.splitlines()
    if line.strip().startswith('"')
]
if center_entries != [
    "group/center-left",
    "custom/applauncher",
    "group/center-right",
]:
    raise SystemExit("the Waybar launcher is not between its balanced wings")
if '"group/desktop"' not in left_modules or '"group/system"' not in right_modules:
    raise SystemExit("the Waybar outer modules are not grouped")
if "_div" in waybar_config:
    raise SystemExit("the Waybar layout still renders Powerline dividers")

metrics = ("memory", "network#download", "network#upload")
waybar_modules = (repo_dir / "dot_config/waybar/modules.jsonc").read_text()
center_left = waybar_modules.split('"group/center-left":', 1)[1].split(
    '"group/center-right":', 1
)[0]
center_right = waybar_modules.split('"group/center-right":', 1)[1].split(
    '"group/system":', 1
)[0]
if '"idle_inhibitor"' in center_left:
    raise SystemExit("idle inhibitor remains in the center-left wing")
if '"cpu"' in center_right:
    raise SystemExit("CPU monitoring remains in the center-right wing")
if any(f'"{module}"' not in center_right for module in metrics):
    raise SystemExit("system metrics are not in the center-right wing")
for spacer in ("center-left-spacer", "center-right-spacer"):
    spacer_config = waybar_modules.split(f'"custom/{spacer}":', 1)[1].split(
        "},", 1
    )[0]
    if '"expand": true' not in spacer_config:
        raise SystemExit(f"{spacer} does not align its wing inward")
if '"format": "M{percentage}"' not in waybar_modules:
    raise SystemExit("memory is not compact")
clock_config = waybar_modules.split('"clock":', 1)[1].split('"clock#date":', 1)[0]
if '"format": "{:%H:%M}"' not in clock_config:
    raise SystemExit("the Waybar clock is not text-only")
network_metrics = waybar_modules.split('"network#download":', 1)[1].split(
    '"bluetooth":', 1
)[0]
for expected in (
    '"format": "{bandwidthDownBytes}"',
    '"format": "|"',
    '"format": "{bandwidthUpBytes}"',
):
    if expected not in network_metrics:
        raise SystemExit("Waybar network throughput is not compact")
if "" in network_metrics or "" in network_metrics:
    raise SystemExit("Waybar network throughput still contains icons")
if network_metrics.count('"max-length": 9') != 2:
    raise SystemExit("Waybar network metrics can outgrow the balanced wing")
if "#network.download {\n    color: @secondary;" not in waybar:
    raise SystemExit("Waybar download color is missing")
if "#network.upload {\n    color: @tertiary;" not in waybar:
    raise SystemExit("Waybar upload color is missing")
if "#custom-network-separator {\n    color: @outline;\n    padding: 0px;" not in waybar:
    raise SystemExit("Waybar network separator is not compact")
if "#center-left,\n#center-right {\n    min-width: 16em;" not in waybar:
    raise SystemExit("the Waybar center wings are not equally sized")
if "#custom-left_div" in waybar or "#custom-right_div" in waybar:
    raise SystemExit("the Waybar style still contains Powerline dividers")
PY

printf '%s\n' "desktop and locale configs passed"
