#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v chezmoi >/dev/null 2>&1; then
    printf '%s\n' "desktop profile checks skipped: chezmoi unavailable"
    exit 0
fi

python3 - "$repo_dir" <<'PY'
import json
import configparser
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

repo = pathlib.Path(sys.argv[1])
scratch = pathlib.Path.home() / ".local/state/agents/tmp"
scratch.mkdir(parents=True, exist_ok=True)
task = pathlib.Path(tempfile.mkdtemp(prefix="check-desktop-profiles.", dir=scratch))

def run(command, env, **kwargs):
    result = subprocess.run(
        command, env=env, capture_output=True, text=True, **kwargs
    )
    if result.returncode:
        raise SystemExit(f"{command}\n{result.stderr or result.stdout}")
    return result.stdout

def fixture(name, shell=None, graphical=True, niri=True, output="auto"):
    home = task / name
    home.mkdir()
    (home / ".config").mkdir()
    config = home / "chezmoi.toml"
    data = {
        "role": "laptop", "shell": "zsh", "graphical": graphical, "niri": niri,
        "niriOutputProfile": output, "work": False, "secretBackend": "rbw",
    }
    if shell is not None:
        data["desktopShell"] = shell
    config.write_text(
        'mode = "file"\n'
        f'destDir = "{home}"\n'
        '[template]\noptions = ["missingkey=error"]\n[data]\n'
        + "\n".join(f"{key} = {json.dumps(value)}" for key, value in data.items())
    )
    env = {
        **os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_CACHE_HOME": str(home / ".cache"), "XDG_DATA_HOME": str(home / ".local/share"),
        "XDG_STATE_HOME": str(home / ".local/state"), "TMPDIR": str(task),
        "PATH": str(repo / "tests/fixtures/pi/bin") + os.pathsep + os.environ["PATH"],
    }
    command = [
        "chezmoi", "--config", str(config), "--source", str(repo),
        "--persistent-state", str(home / "chezmoi-state.boltdb"),
    ]
    return home, env, command

custom_only = {
    ".config/fuzzel/fuzzel.ini", ".config/mako/config",
    ".config/waybar/config.jsonc", ".config/waypaper/config.ini",
    ".config/matugen/config.toml", ".config/swaylock/config",
    ".config/systemd/user/waybar-gammarelay.service",
    ".config/niri/conf.d/20-outputs.kdl", ".config/niri/colors.kdl",
    ".config/niri/conf.d/60-binds.kdl",
}
dms_only = {
    ".config/DankMaterialShell/settings.json", ".config/niri/dms/outputs.kdl",
    ".config/niri/dms/layout.kdl", ".config/niri/dms/colors.kdl",
    ".config/kitty/dank-theme.conf", ".config/gtk-3.0/dank-colors.css",
    ".config/kitty/dms-ansi.conf",
    ".config/gtk-4.0/dank-colors.css", ".config/qt6ct/qt6ct.conf",
}
targets = [
    ".config/niri", ".config/kitty", ".config/gtk-3.0", ".config/gtk-4.0",
    ".config/fcitx5/conf/classicui.conf",
]

def managed(command, env):
    return set(run(command + ["managed", "--include", "files"], env).splitlines())

def apply(home, env, command, shell):
    paths = targets + ([
        ".config/DankMaterialShell/settings.json", ".config/qt6ct/qt6ct.conf",
    ] if shell == "dms" else [])
    for path in paths:
        (home / path).parent.mkdir(parents=True, exist_ok=True)
    run(command + ["apply", "--force", "--exclude", "scripts,encrypted"]
        + [str(home / path) for path in paths], env)

for shell in ("custom", "dms"):
    for output in ("auto", "laptop-dual-1080p", "desktop-single-4k"):
        home, env, command = fixture(f"{shell}-{output}", shell, output=output)
        inventory = managed(command, env)
        assert (dms_only if shell == "dms" else custom_only) <= inventory
        assert not (custom_only if shell == "dms" else dms_only) & inventory
        apply(home, env, command, shell)
        niri_dir = home / ".config/niri"
        if shutil.which("niri"):
            run(["niri", "validate", "--config", str(niri_dir / "config.kdl")], env)
        session = (niri_dir / "conf.d/40-session.kdl").read_text()
        binds_file = niri_dir / ("dms/binds.kdl" if shell == "dms" else "conf.d/60-binds.kdl")
        binds = binds_file.read_text()
        assert 'Mod+V { toggle-window-floating; }' in binds
        assert 'Mod+M { maximize-window-to-edges; }' in binds
        assert 'Mod+Comma hotkey-overlay-title=' in binds
        output_file = niri_dir / ("dms/outputs.kdl" if shell == "dms" else "conf.d/20-outputs.kdl")
        if output == "desktop-single-4k":
            assert 'scale 1.5' in output_file.read_text()
        elif output == "laptop-dual-1080p":
            assert 'scale 1.25' in output_file.read_text()
        kitty = (home / ".config/kitty/kitty.conf").read_text()
        classicui = (home / ".config/fcitx5/conf/classicui.conf").read_text()
        if shell == "dms":
            assert session.count('spawn-at-startup "dms" "run"') == 1
            assert not re.search(r'waybar|mako|awww|copyq|swayidle|swaylock|gammarelay', session + binds)
            assert '"audio" "micmute"' in binds
            assert '"lock" "lockAndOutputsOff"' in binds
            assert 'include dank-theme.conf' in kitty and 'include current-theme.conf' not in kitty
            assert kitty.index("include dank-theme.conf") < kitty.index("include dms-ansi.conf")
            ansi = (home / ".config/kitty/dms-ansi.conf").read_text().splitlines()
            assert len(ansi) == 16
            for index, line in enumerate(ansi):
                assert re.fullmatch(rf"color{index}\s+#[0-9a-f]{{6}}", line)
            assert 'Theme=dms\n' in classicui
            settings_file = home / ".config/DankMaterialShell/settings.json"
            settings = json.loads(settings_file.read_text())
            assert settings["runUserMatugenTemplates"] is False
            assert settings["runDmsMatugenTemplates"] is True
            assert settings["currentThemeName"] == "dynamic"
            assert settings["matugenScheme"] == "scheme-neutral"
            assert settings["terminalsAlwaysDark"] is True
            qt6ct = configparser.ConfigParser(interpolation=None)
            qt6ct.read(home / ".config/qt6ct/qt6ct.conf")
            assert qt6ct["Appearance"]["icon_theme"] == "Adwaita"
            gtk_settings = (home / ".config/gtk-3.0/settings.ini").read_text()
            assert "gtk-theme-name" not in gtk_settings
            assert "gtk-application-prefer-dark-theme" not in gtk_settings
            for power in ("ac", "battery"):
                assert settings[f"{power}LockTimeout"] == 300
                assert settings[f"{power}MonitorTimeout"] == 0
                assert settings[f"{power}PostLockMonitorTimeout"] == 30
                assert settings[f"{power}SuspendTimeout"] == 0
            assert settings["lockBeforeSuspend"] and settings["loginctlLockIntegration"]
            assert not settings["fadeToLockEnabled"]
            assert settings["clipboardClickToPaste"] and settings["clipboardEnterToPaste"]
            # Existing GUI preferences and compositor-generated files must survive apply.
            settings["acLockTimeout"] = 600
            settings["futurePreference"] = True
            settings_file.write_text(json.dumps(settings))
            output_file.write_text('// user output preferences\n')
            color_file = niri_dir / "dms/colors.kdl"
            color_file.write_text('// generated palette\n')
            binds_file.write_text(binds.replace("Mod+D hotkey", "Mod+Space hotkey"))
            apply(home, env, command, shell)
            assert json.loads(settings_file.read_text()) == settings
            assert output_file.read_text() == '// user output preferences\n'
            assert color_file.read_text() == '// generated palette\n'
            assert "Mod+D hotkey" not in binds_file.read_text()
            assert "Mod+Space hotkey" in binds_file.read_text()
            assert 'include "conf.d/60-binds.kdl"' not in (niri_dir / "config.kdl").read_text()
        else:
            assert '"dms"' not in session + binds
            for program in ("waybar", "mako", "awww-daemon", "copyq", "swayidle"):
                assert f'spawn-at-startup "{program}"' in session
            assert 'include current-theme.conf' in kitty and 'include dank-theme.conf' not in kitty
            assert 'include dms-ansi.conf' not in kitty
            assert 'Theme=Matugen\n' in classicui
        for version in ("3.0", "4.0"):
            css = (home / f".config/gtk-{version}/gtk.css").read_text()
            expected = "dank-colors.css" if shell == "dms" else "colors.css"
            assert css.startswith(f'@import "{expected}";\n')
            assert ('@import "nautilus.css";' in css) == (version == "4.0" and shell == "custom")

home, env, command = fixture("legacy")
assert custom_only <= managed(command, env)
assert not dms_only & managed(command, env)
for shell in ("dms", "custom"):
    for graphical, niri in ((False, False), (False, True), (True, False)):
        home, env, command = fixture(f"{shell}-{graphical}-{niri}", shell, graphical, niri)
        inventory = managed(command, env)
        assert not dms_only & inventory
        assert ".config/niri/config.kdl" not in inventory
        if graphical:
            run(command + ["apply", "--exclude", "scripts,encrypted"]
                + [str(home / path) for path in (".config/kitty", ".config/gtk-3.0", ".config/gtk-4.0", ".config/fcitx5")], env)
            assert "include current-theme.conf" in (home / ".config/kitty/kitty.conf").read_text()
            assert "Theme=Matugen\n" in (home / ".config/fcitx5/conf/classicui.conf").read_text()
            for version in ("3.0", "4.0"):
                assert "dank-colors.css" not in (home / f".config/gtk-{version}/gtk.css").read_text()

home, env, command = fixture("invalid", "invalid")
result = subprocess.run(command + ["managed"], env=env, capture_output=True, text=True)
assert result.returncode and "desktopShell must be custom or dms" in result.stderr

# Exercise the real init prompt without the user's saved machine data.
home, env, command = fixture("init")
empty = home / "empty.toml"
empty.write_text("")
for shell in ("dms", "custom"):
    rendered = run(
        ["chezmoi", "--config", str(empty), "--source", str(repo),
         "execute-template", "--init", "--promptChoice",
         f"Machine role=laptop,Default shell=zsh,Desktop shell: DMS or custom components={shell},Niri output profile=auto,SSH authorized_keys identity=none",
         "--promptBool", "Graphical machine=true,Use niri=true,Work machine=false,Use rbw SSH agent=false,Use recoverable rm wrapper=false",
         "--file", str(repo / ".chezmoi.toml.tmpl")], env,
    )
    assert tomllib.loads(rendered)["data"]["desktopShell"] == shell

# Switching replaces only managed CSS imports, not unrelated custom CSS.
home, env, command = fixture("switch", "dms")
for version in ("3.0", "4.0"):
    css = home / f".config/gtk-{version}/gtk.css"
    css.parent.mkdir(parents=True, exist_ok=True)
    css.write_text('@import "colors.css";\n@import "dank-colors.css";\n'
                   + ('@import "nautilus.css";\n' if version == "4.0" else '')
                   + '/* keep */\n@import "local.css";\n')
apply(home, env, command, "dms")
config = home / "chezmoi.toml"
for shell in ("custom", "dms"):
    config.write_text(re.sub(r'desktopShell = "[^"]+"', f'desktopShell = "{shell}"', config.read_text()))
    apply(home, env, command, shell)
    if shutil.which("niri"):
        run(["niri", "validate", "--config", str(home / ".config/niri/config.kdl")], env)
    for version in ("3.0", "4.0"):
        css = (home / f".config/gtk-{version}/gtk.css").read_text()
        assert css.count("colors.css") == 1
        assert '/* keep */\n@import "local.css";\n' in css

ignored = run(command + ["execute-template", "--file", str(repo / ".chezmoiignore")], env)
for path in (
    ".local/state/DankMaterialShell/", ".cache/DankMaterialShell/",
    ".config/DankMaterialShell/clsettings.json", ".config/DankMaterialShell/plugin_settings.json",
    ".config/DankMaterialShell/notification_history.json", ".config/quickshell/",
):
    assert path in ignored.splitlines()

print(f"desktop profile checks passed (retained fixtures: {task})")
PY
