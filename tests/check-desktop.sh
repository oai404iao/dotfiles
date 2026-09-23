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
import json
import os
import pathlib
import shlex
import subprocess
import sys
import tempfile
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
    path = repo_dir / f"dot_config/gtk-{gtk_version}/settings.ini"
    if gtk_version == "3.0":
        rendered = subprocess.run(
            ["chezmoi", "--config", "/dev/null", "--config-format", "toml",
             "--source", str(repo_dir), "--override-data", '{"desktopShell":"custom"}',
             "execute-template", "--file", str(path) + ".tmpl"],
            capture_output=True, text=True, check=True,
        ).stdout
        settings.read_string(rendered)
    else:
        settings.read(path)
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
if 'font-family: "JetBrainsMono Nerd Font Propo", "Noto Sans Mono CJK SC"' not in waybar:
    raise SystemExit("Waybar does not use proportional icon advances")
launcher_style = waybar.split("#custom-applauncher {", 1)[1].split("}", 1)[0]
if "padding: 0 0.16em;" not in launcher_style:
    raise SystemExit("the Waybar launcher has asymmetric glyph compensation")
launcher_label_style = waybar.split("#custom-applauncher label {", 1)[1].split("}", 1)[0]
if not all(rule in launcher_label_style for rule in (
    "min-width: inherit;",
    "font-size: inherit;",
)):
    raise SystemExit("the Waybar launcher label does not inherit its icon cell")
workspace_style = waybar.split("#workspaces button {", 1)[1].split("}", 1)[0]
workspace_label_style = waybar.split("#workspaces button label {", 1)[1].split("}", 1)[0]
if "min-width: 1.1em;" not in workspace_label_style or "min-width:" in workspace_style:
    raise SystemExit("Waybar workspace width is not reserved on the icon label")
for expected in (
    "background-image: none;",
    "text-shadow: none;",
    "transition: background-color 0.2s ease, color 0.2s ease;",
):
    if expected not in workspace_style:
        raise SystemExit("Waybar workspace states inherit GTK theme effects")

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
temperature = json.JSONDecoder().raw_decode(
    waybar_modules.split('"custom/temperature":', 1)[1].lstrip()
)[0]
system_modules = waybar_modules.split('"group/system":', 1)[1].split("}", 1)[0]
if '"custom/temperature"' not in system_modules:
    raise SystemExit("Waybar temperature is not in the system group")
if temperature["exec-if"] != "command -v wl-gammarelay-rs && command -v busctl && command -v systemctl && command -v timeout":
    raise SystemExit("Waybar temperature lacks dependency guards")
if temperature["exec"] != "${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/temperature.sh":
    raise SystemExit("Waybar temperature does not use the finite query helper")
gamma_service = configparser.ConfigParser(interpolation=None)
gamma_service.read(repo_dir / "dot_config/systemd/user/waybar-gammarelay.service")
for section, key, value in (
    ("Unit", "PartOf", "graphical-session.target"),
    ("Unit", "After", "graphical-session.target"),
    ("Service", "Type", "dbus"),
    ("Service", "BusName", "rs.wl-gammarelay"),
    ("Service", "ExecStart", "/usr/bin/wl-gammarelay-rs run"),
    ("Service", "Restart", "on-failure"),
    ("Service", "RestartSec", "2"),
):
    if gamma_service.get(section, key) != value:
        raise SystemExit(f"unexpected gamma service {section}.{key}")
niri_ignore_block = ignore_text.split(
    "{{- if not (and .graphical .niri) }}", 1
)[1].split("{{- end }}", 1)[0]
if ".config/systemd/user/waybar-gammarelay.service" not in niri_ignore_block.splitlines():
    raise SystemExit("the gamma service is not restricted to Niri profiles")
if (
    temperature["exec-on-event"] is not False
    or temperature["interval"] != 2
    or "restart-interval" in temperature
    or "signal" in temperature
):
    raise SystemExit("Waybar temperature must poll instead of restarting a continuous watcher")
for event, delta in (("on-scroll-up", "+100"), ("on-scroll-down", "-100")):
    if shlex.split(temperature[event]) != [
        "busctl", "--user", "--", "call", "rs.wl-gammarelay", "/",
        "rs.wl.gammarelay", "UpdateTemperature", "n", delta,
    ]:
        raise SystemExit(f"unexpected temperature action: {event}")
if temperature["on-click"] != "${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/toggle-temperature.sh":
    raise SystemExit("Waybar temperature does not use the preset toggle")
scratch_root = pathlib.Path.home() / ".local/state/agents/tmp"
scratch_root.mkdir(parents=True, exist_ok=True)
toggle_fixture = pathlib.Path(tempfile.mkdtemp(prefix="check-temperature.", dir=scratch_root))
fake_busctl = toggle_fixture / "busctl"
fake_busctl.write_text("""#!/bin/sh
set -eu
case "$2" in
    get-property)
        [ "$*" = "--user get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature" ]
        [ "$CURRENT" != fail ] || exit 1
        printf 'q %s\\n' "$CURRENT"
        ;;
    set-property)
        printf '%s\\n' "$*" > "$CALL_LOG"
        exit "$SET_STATUS"
        ;;
    *) exit 2 ;;
esac
""")
fake_busctl.chmod(0o700)
toggle_script = repo_dir / "dot_config/waybar/scripts/executable_toggle-temperature.sh"
for index, (current, target, set_status) in enumerate((
    ("6500", "4500", 0),
    ("4500", "6500", 0),
    ("5000", "6500", 0),
    ("fail", None, 0),
    ("6500", "4500", 1),
)):
    call_log = toggle_fixture / f"call-{index}"
    result = subprocess.run(
        ["/bin/sh", str(toggle_script)],
        env={**os.environ, "PATH": str(toggle_fixture), "CURRENT": current,
             "CALL_LOG": str(call_log), "SET_STATUS": str(set_status)},
        capture_output=True, text=True,
    )
    expected_status = 1 if current == "fail" else set_status
    if result.returncode != expected_status:
        raise SystemExit(f"temperature toggle returned {result.returncode}: {result.stderr}")
    if target is None:
        if call_log.exists():
            raise SystemExit("temperature toggle writes after a failed read")
    elif call_log.read_text().strip() != (
        "--user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q " + target
    ):
        raise SystemExit(f"unexpected preset for {current}K")
print(f"temperature preset checks passed (retained fixtures: {toggle_fixture})")
query_fixture = toggle_fixture / "query"
query_fixture.mkdir()
for name, content in {
    "timeout": """[ "$1" = 3s ]
shift
exec "$@"
""",
    "systemctl": """[ "$*" = "--user start waybar-gammarelay.service" ]
printf 'start\\n' >> "$CALL_LOG"
exit "$START_STATUS"
""",
    "busctl": """[ "$*" = "--user --timeout=3 get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature" ]
printf 'read\\n' >> "$CALL_LOG"
[ "$CURRENT" != fail ] || exit 1
printf 'q %s\\n' "$CURRENT"
""",
}.items():
    command = query_fixture / name
    command.write_text("#!/bin/sh\nset -eu\n" + content)
    command.chmod(0o700)
query_script = repo_dir / "dot_config/waybar/scripts/executable_temperature.sh"
subprocess.run(["/bin/sh", "-n", str(query_script)], check=True)
for index, (current, start_status, expected_status, output, calls) in enumerate((
    ("4500", 0, 0, "4500\n", "start\nread\n"),
    ("6500", 0, 0, "6500\n", "start\nread\n"),
    ("fail", 0, 1, "", "start\nread\n"),
    ("4500", 1, 1, "", "start\n"),
    ("4500", 124, 124, "", "start\n"),
)):
    call_log = query_fixture / f"call-{index}"
    result = subprocess.run(
        ["/bin/sh", str(query_script)],
        env={**os.environ, "PATH": str(query_fixture), "CURRENT": current,
             "CALL_LOG": str(call_log), "START_STATUS": str(start_status)},
        capture_output=True, text=True, timeout=5,
    )
    if result.returncode != expected_status or result.stdout != output:
        raise SystemExit(f"unexpected temperature query result: {result}")
    if call_log.read_text() != calls:
        raise SystemExit("temperature query did not start its service before reading")
print("temperature query checks passed")
if temperature["format"] != " {}K" or "#custom-temperature {" not in waybar:
    raise SystemExit("Waybar temperature display or style is missing")
launcher_config = waybar_modules.split('"custom/applauncher": {', 1)[1].split("}", 1)[0]
if '"format": ""' not in launcher_config:
    raise SystemExit("the Waybar launcher does not use the upstream Arch icon")
for line in waybar_modules.splitlines():
    key, separator, value = line.strip().partition(":")
    if separator and (key == '"format"' or key.startswith('"format-')):
        value = value.strip().rstrip(",")
        if value.startswith('"') and value.endswith('"'):
            text = value[1:-1]
            if text.strip() and text != text.strip():
                raise SystemExit("Waybar format has asymmetric whitespace")
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

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk, Gtk
except (ImportError, ValueError):
    print("Waybar GTK geometry check skipped: GTK 3 Python bindings unavailable")
else:
    if not Gtk.init_check()[0]:
        print("Waybar GTK geometry check skipped: no display")
    else:
        provider = Gtk.CssProvider()
        colors = (repo_dir / "dot_config/waybar/create_colors.css").read_text()
        provider.load_from_data(waybar.replace('@import "colors.css";', colors).encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )
        Gtk.Settings.get_default().set_property("gtk-enable-animations", False)
        for wrapped in (False, True):
            for hover in (False, True):
                window = Gtk.OffscreenWindow()
                window.set_name("waybar")
                label = Gtk.Label(label="")
                module = Gtk.Box() if wrapped else label
                module.set_name("custom-applauncher")
                window.add(module)
                if wrapped:
                    image = Gtk.Image()
                    module.add(image)
                    module.add(label)
                if hover:
                    module.set_state_flags(Gtk.StateFlags.PRELIGHT, False)
                window.show_all()
                if wrapped:
                    image.hide()
                while Gtk.events_pending():
                    Gtk.main_iteration()
                ink, _ = label.get_layout().get_pixel_extents()
                x, _ = label.get_layout_offsets()
                bounds = module.get_allocation()
                offset = x + ink.x + ink.width / 2 - bounds.x - bounds.width / 2
                if abs(offset) > 1:
                    raise SystemExit(
                        f"Waybar launcher is off-center by {offset}px "
                        f"(wrapped={wrapped}, hover={hover})"
                    )
                for widget in (module, label):
                    font = widget.get_style_context().get_property("font", Gtk.StateFlags.NORMAL)
                    if widget is module:
                        module_font_size = font.get_size()
                    elif font.get_size() != module_font_size:
                        raise SystemExit("Waybar launcher label resets the module font size")
                window.destroy()
        print("Waybar launcher GTK geometry passed (label and AIconLabel, normal and hover)")
PY

printf '%s\n' "desktop and locale configs passed"
