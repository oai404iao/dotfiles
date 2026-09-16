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

satty = tomllib.loads((repo / "dot_config/satty/config.toml").read_text())
assert satty["general"]["actions-on-enter"] == ["save-to-file", "exit"]
assert satty["general"]["actions-on-escape"] == ["exit"]
assert "output-filename" not in satty["general"]
assert satty["font"]["fallback"] == ["Noto Sans CJK SC"]

ignore = (repo / ".chezmoiignore").read_text()
graphical = ignore.split("{{- if not .graphical }}", 1)[1].split("{{- end }}", 1)[0]
for path in (
    ".config/btop/", ".config/fcitx5/", ".config/satty/", ".config/swaylock/",
    ".config/gtk-3.0/", ".config/gtk-4.0/", ".local/share/fcitx5/themes/Matugen/",
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
    for original in ("", custom, '@import "colors.css";\n@import url(\'colors.css\');\n' + custom):
        updated = modify(modifier, original)
        assert updated.startswith('@import "colors.css";\n')
        assert updated.count("colors.css") == 1
        assert modify(modifier, updated) == updated
        if original:
            assert custom in updated

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
else:
    print("Matugen rendering skipped: not installed")
PY

printf '%s\n' "desktop application configs passed"
