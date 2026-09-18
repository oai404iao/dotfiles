#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

sh -n "$repo_dir/dot_config/btop/modify_btop.conf"
python3 - "$repo_dir" <<'PY'
import configparser
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import xml.etree.ElementTree as ET

repo = pathlib.Path(sys.argv[1])

def modify(relative, text):
    return subprocess.run(
        [str(repo / relative)], input=text, text=True, capture_output=True, check=True
    ).stdout

btop = "dot_config/btop/modify_btop.conf"
for original in ("", '# keep\ncolor_theme = "Default"\nupdate_ms = 3000\ncolor_theme="old"\n'):
    updated = modify(btop, original)
    assert updated.count('color_theme = "matugen"') == 1
    assert modify(btop, updated) == updated
    if original:
        assert "# keep\n" in updated and "update_ms = 3000\n" in updated

classicui = "dot_config/fcitx5/conf/modify_private_classicui.conf"
fixture = (
    '# keep\nFont="Old 10"\nFont="Duplicate"\nTheme=plasma\n'
    'Vertical Candidate List=False\nTrayFont="Sans 10"\n'
    '[Future]\nFont=untouched\n'
)
for original in ("", fixture):
    updated = modify(classicui, original)
    assert modify(classicui, updated) == updated
    root = updated.split("[", 1)[0]
    for value in (
        'Font="Adwaita Sans 11"', 'MenuFont="Adwaita Sans 11"', "Theme=Matugen",
        "UseDarkTheme=False", "UseAccentColor=False",
        "ForceWaylandDPI=0", "EnableFractionalScale=True",
    ):
        assert root.splitlines().count(value) == 1, value
    if original:
        assert "# keep\n" in updated
        assert "Vertical Candidate List=False\n" in updated
        assert 'TrayFont="Sans 10"\n' in updated
        assert updated.endswith("[Future]\nFont=untouched\n")

portal = "dot_config/xdg-desktop-portal/modify_niri-portals.conf"
chooser = "org.freedesktop.impl.portal.FileChooser"
for original in (
    "",
    f"# keep\n[preferred]\ndefault=gnome;gtk;\n{chooser}=gtk\n{chooser}=old\n"
    "org.freedesktop.impl.portal.ScreenCast=gnome\n[other]\n"
    f"{chooser}=untouched\n",
    "[other]\nvalue=keep",
    "[preferred]",
):
    updated = modify(portal, original)
    assert modify(portal, updated) == updated
    ini = configparser.ConfigParser(interpolation=None)
    ini.optionxform = str
    ini.read_string(updated)
    assert ini["preferred"][chooser] == "gnome;gtk;"
    if "# keep" in original:
        assert "# keep\n" in updated
        assert ini["preferred"]["default"] == "gnome;gtk;"
        assert ini["preferred"]["org.freedesktop.impl.portal.ScreenCast"] == "gnome"
        assert ini["other"][chooser] == "untouched"
    elif "value=keep" in original:
        assert ini["other"]["value"] == "keep"
    else:
        assert list(ini["preferred"]) == [chooser]

satty = tomllib.loads((repo / "dot_config/satty/config.toml").read_text())
assert satty["general"]["actions-on-enter"] == ["save-to-file", "exit"]
assert satty["general"]["actions-on-escape"] == ["exit"]
assert "output-filename" not in satty["general"]
assert satty["font"]["fallback"] == ["Noto Sans CJK SC"]

shardx = repo / "dot_local/share/applications/shardx-launcher.desktop"
launcher = configparser.ConfigParser(interpolation=None)
launcher.optionxform = str
launcher.read(shardx)
assert launcher["Desktop Entry"]["Exec"] == "env GTK_IM_MODULE=fcitx shardx-launcher"
assert launcher["Desktop Entry"]["Type"] == "Application"
assert not launcher["Desktop Entry"].getboolean("Terminal")
if shutil.which("desktop-file-validate"):
    subprocess.run(["desktop-file-validate", str(shardx)], check=True)

ignore = (repo / ".chezmoiignore").read_text()
graphical = ignore.split("{{- if not .graphical }}", 1)[1].split("{{- end }}", 1)[0]
niri = ignore.split("{{- if not (and .graphical .niri) }}", 1)[1].split("{{- end }}", 1)[0]
assert ".config/xdg-desktop-portal/niri-portals.conf" in niri.splitlines()
for path in (
    ".config/btop/", ".config/fcitx5/", ".config/satty/", ".config/swaylock/",
    ".config/gtk-3.0/", ".config/gtk-4.0/", ".local/share/fcitx5/themes/Matugen/",
    ".local/share/applications/shardx-launcher.desktop",
):
    assert path in graphical.splitlines(), path
for path in (".config/fcitx5/profile", ".config/fcitx5/config", ".local/share/fcitx5/rime/"):
    assert path in ignore.splitlines(), path
assert not (repo / "dot_local/share/fcitx5/rime").exists()

templates = tomllib.loads((repo / "dot_config/matugen/config.toml").read_text())["templates"]
assert "fcitx5-remote --check" in templates["fcitx5"]["post_hook"]
assert "fcitx5-remote -r" in templates["fcitx5"]["post_hook"]
assert "fcitx5 -r" not in templates["fcitx5"]["post_hook"]
assert "post_hook" not in templates["gtk3"]
for version in ("3.0", "4.0"):
    modifier = f"dot_config/gtk-{version}/modify_gtk.css"
    custom = '/* keep */\n@import "local.css";\nbutton { padding: 4px; }\n'
    imports = '@import "colors.css";\n@import url(\'colors.css\');\n'
    if version == "4.0":
        imports += '@import "nautilus.css";\n@import url(\'nautilus.css\');\n'
    for original in ("", custom, imports + custom):
        updated = modify(modifier, original)
        assert updated.startswith('@import "colors.css";\n')
        assert updated.count("colors.css") == 1
        if version == "4.0":
            assert updated.startswith('@import "colors.css";\n@import "nautilus.css";\n')
            assert updated.count("nautilus.css") == 1
        else:
            assert "nautilus.css" not in updated
        assert modify(modifier, updated) == updated
        if original:
            assert custom in updated

gtk3_settings = configparser.ConfigParser()
gtk3_settings.read(repo / "dot_config/gtk-3.0/settings.ini")
assert gtk3_settings["Settings"]["gtk-theme-name"] == "adw-gtk3-dark"
assert gtk3_settings["Settings"].getboolean("gtk-application-prefer-dark-theme")

fallbacks = {
    "btop": "dot_config/btop/themes/create_matugen.theme",
    "fcitx5": "dot_local/share/fcitx5/themes/Matugen/create_theme.conf",
    "swaylock-effects": "dot_config/swaylock/create_config",
    "gtk3": "dot_config/gtk-3.0/create_colors.css",
    "gtk4": "dot_config/gtk-4.0/create_colors.css",
}

def check_theme(name, text):
    assert "{{" not in text
    if name == "fcitx5":
        ini = configparser.ConfigParser(interpolation=None)
        ini.read_string(text)
        assert ini["Metadata"].getboolean("ScaleWithDPI")
        assert ini["InputPanel"]["HighlightCandidateColor"] == ini["Menu"]["HighlightCandidateColor"]
        assert ini["InputPanel/Background"]["BorderWidth"] == "1"
        for section, asset in (("Menu/CheckBox", "radio.svg"), ("Menu/SubMenu", "arrow.svg")):
            assert ini[section]["Image"] == asset
            svg = ET.parse(repo / "dot_local/share/fcitx5/themes/Matugen" / asset).getroot()
            assert svg[0].get("fill") == "#ffffff" and svg[0].get("stroke") == "#000000"
    elif name == "swaylock-effects":
        lines = text.splitlines()
        for option in (
            "screenshots", "clock", "font=Adwaita Sans", "timestr=%H:%M",
            "indicator-radius=110", "indicator-thickness=8", "effect-blur=10x5",
        ):
            assert option in lines, option
        assert not any(line.startswith(("grace", "daemonize", "ignore-empty-password")) for line in lines)
        for line in lines:
            key, sep, value = line.partition("=")
            if sep and (key == "color" or key.endswith("-color")):
                assert re.fullmatch(r"#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", value), line
    elif name.startswith("gtk"):
        assert "@define-color accent_bg_color " in text
        assert "@define-color view_bg_color " in text
    else:
        assert 'theme[main_fg]="' in text
        assert 'theme[selected_bg]="' in text

for name, path in fallbacks.items():
    check_theme(name, (repo / path).read_text())

if shutil.which("matugen"):
    scratch = pathlib.Path.home() / ".local/state/agents/tmp"
    scratch.mkdir(parents=True, exist_ok=True)
    task = pathlib.Path(tempfile.mkdtemp(prefix="check-desktop-apps.", dir=scratch))
    config = ["[config.wallpaper]", "set = false", 'command = "false"']
    for name in fallbacks:
        relative = templates[name]["input_path"].removeprefix("~/.config/")
        assert not relative.startswith("/")
        config.extend([
            f"[templates.{name}]",
            f'input_path = "{repo / "dot_config" / relative}"',
            f'output_path = "{task / name}"',
        ])
    (task / "matugen.toml").write_text("\n".join(config))
    result = subprocess.run(
        ["matugen", "--config", str(task / "matugen.toml"), "color", "hex", "#927d76"],
        capture_output=True, text=True, env={**os.environ, "TMPDIR": str(task)},
    )
    if result.returncode:
        raise SystemExit(result.stderr or result.stdout)
    for name in fallbacks:
        check_theme(name, (task / name).read_text())
    print(f"desktop themes rendered without hooks (retained fixtures: {task})")

    try:
        import gi
        gi.require_version("Gtk", "3.0")
        gi.require_version("Gdk", "3.0")
        from gi.repository import Gdk, Gtk
    except (ImportError, ValueError):
        print("GTK 3 effective palette check skipped: Python bindings unavailable")
    else:
        if not pathlib.Path("/usr/share/themes/adw-gtk3-dark/gtk-3.0/gtk.css").exists():
            print("GTK 3 effective palette check skipped: install adw-gtk-theme")
        elif not Gtk.init_check()[0]:
            print("GTK 3 effective palette check skipped: no display")
        else:
            settings = Gtk.Settings.get_default()
            settings.set_property("gtk-theme-name", "adw-gtk3-dark")
            settings.set_property("gtk-application-prefer-dark-theme", True)
            settings.set_property("gtk-enable-animations", False)
            provider = Gtk.CssProvider()
            provider.load_from_path(str(task / "gtk3"))
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
            )
            window = Gtk.OffscreenWindow()
            view = Gtk.TreeView()
            window.add(view)
            window.show_all()
            while Gtk.events_pending():
                Gtk.main_iteration()
            palette = dict(re.findall(r"@define-color (\w+) (#[0-9a-fA-F]{6});", (task / "gtk3").read_text()))
            for widget, role in ((window, "window_bg_color"), (view, "view_bg_color")):
                actual = widget.get_style_context().get_background_color(Gtk.StateFlags.NORMAL)
                expected = Gdk.RGBA()
                assert expected.parse(palette[role])
                assert all(abs(a - b) < 0.005 for a, b in zip(
                    (actual.red, actual.green, actual.blue, actual.alpha),
                    (expected.red, expected.green, expected.blue, expected.alpha),
                )), f"GTK 3 widget is not using {role}: {actual.to_string()}"
            window.destroy()
            print("GTK 3 window and file-list widgets use the rendered palette")
else:
    print("Matugen rendering skipped: not installed")
PY

python3 "$repo_dir/tests/check-nautilus-style.py"

printf '%s\n' "desktop application configs passed"
