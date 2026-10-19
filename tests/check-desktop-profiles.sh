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
source = task / "source"
# Excluding external target types does not prevent archive expansion while loading source.
shutil.copytree(
    repo, source,
    ignore=shutil.ignore_patterns(".git", ".worktrees", ".chezmoiexternal.toml"),
)

def run(command, env):
    try:
        result = subprocess.run(
            command, env=env, capture_output=True, text=True,
            stdin=subprocess.DEVNULL, timeout=30,
        )
    except subprocess.TimeoutExpired:
        raise SystemExit(f"Timed out after 30s: {command}") from None
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
        "chezmoi", "--config", str(config), "--source", str(source),
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
dms_kdl_names = ("alttab", "binds", "colors", "cursor", "layout", "outputs", "windowrules")
dms_kdl_targets = {f".config/niri/dms/{name}.kdl" for name in dms_kdl_names}
dms_only = {
    ".config/DankMaterialShell/settings.json",
    ".config/kitty/dank-theme.conf", ".config/gtk-3.0/dank-colors.css",
    ".config/kitty/dms-ansi.conf",
    ".config/gtk-4.0/dank-colors.css", ".config/qt6ct/qt6ct.conf",
    ".config/matugen/dms/configs/chezmoi-btop.toml",
    ".config/matugen/dms/configs/chezmoi-fastfetch.toml",
} | dms_kdl_targets
targets = [
    ".config/niri", ".config/kitty", ".config/gtk-3.0", ".config/gtk-4.0",
    ".config/fcitx5/conf/classicui.conf",
    ".config/nvim/lua/plugins/dms-colorscheme.lua",
]

def managed(command, env):
    return set(run(command + ["managed", "--include", "files"], env).splitlines())

def assert_gtk_imports(css, version, shell):
    palette = "dank-colors.css" if shell == "dms" else "colors.css"
    expected = f'@import "{palette}";\n'
    if version == "4.0":
        expected += '@import "nautilus.css";\n'
    assert css.startswith(expected)
    assert css.count("colors.css") == 1
    assert css.count("nautilus.css") == (1 if version == "4.0" else 0)

def apply(home, env, command, shell):
    paths = targets + ([
        ".config/DankMaterialShell/settings.json", ".config/qt6ct/qt6ct.conf",
        ".config/matugen/dms/configs/chezmoi-btop.toml",
        ".config/matugen/dms/configs/chezmoi-fastfetch.toml",
        ".config/matugen/templates/btop.theme",
        ".config/matugen/templates/fastfetch-config.jsonc",
    ] if shell == "dms" else [])
    for path in paths:
        (home / path).parent.mkdir(parents=True, exist_ok=True)
    run(command + ["apply", "--force", "--exclude=scripts,encrypted,externals"]
        + [str(home / path) for path in paths], env)

home, env, command = fixture("dms-generated-fragments", "dms")
niri_dir = home / ".config/niri"
run(command + ["apply", "--exclude=scripts,encrypted,externals", str(niri_dir)], env)
generated = [home / path for path in sorted(dms_kdl_targets)]
seeded = {path: path.read_bytes() for path in generated}
assert all(seeded.values())

def apply_fragments(paths):
    output = run(
        command + ["apply", "--exclude=scripts,encrypted,externals",
                   *(str(path) for path in paths)], env,
    )
    assert not output, output

for _ in range(2):
    apply_fragments(generated)
    assert {path: path.read_bytes() for path in generated} == seeded
if shutil.which("niri"):
    run(["niri", "validate", "--config", str(niri_dir / "config.kdl")], env)
for path in generated:
    path.write_text(f"// application-owned {path.name}\n")
nonempty = {path: path.read_bytes() for path in generated}
for _ in range(2):
    apply_fragments(generated)
    assert {path: path.read_bytes() for path in generated} == nonempty

# DMS can legitimately generate zero bytes; create_ alone would delete these includes.
for path in generated:
    path.write_bytes(b"")
    for _ in range(2):
        apply_fragments([path])
        assert path.is_file() and path.read_bytes() == b""
for _ in range(2):
    apply_fragments(generated)
    assert all(path.is_file() and path.read_bytes() == b"" for path in generated)
if shutil.which("niri"):
    run(["niri", "validate", "--config", str(niri_dir / "config.kdl")], env)

for shell in ("custom", "dms"):
    for output in ("auto", "laptop-dual-1080p", "desktop-single-4k"):
        home, env, command = fixture(f"{shell}-{output}", shell, output=output)
        inventory = managed(command, env)
        assert not any(path.startswith(".config/DankMaterialShell/plugins/") for path in inventory)
        assert ".local/bin/dms-with-lyrics" not in inventory
        assert ".config/gtk-4.0/nautilus.css" in inventory
        assert (dms_only if shell == "dms" else custom_only) <= inventory
        assert not (custom_only if shell == "dms" else dms_only) & inventory
        matugen_files = {path for path in inventory if path.startswith(".config/matugen/")}
        if shell == "dms":
            assert matugen_files == {
                ".config/matugen/dms/configs/chezmoi-btop.toml",
                ".config/matugen/dms/configs/chezmoi-fastfetch.toml",
                ".config/matugen/templates/btop.theme",
                ".config/matugen/templates/fastfetch-config.jsonc",
            }
        else:
            assert not any(path.startswith(".config/matugen/dms/") for path in matugen_files)
        apply(home, env, command, shell)
        if shutil.which("nvim"):
            run([
                "nvim", "--headless", "-u", "NONE", "-i", "NONE", "-n",
                "-l", str(repo / "tests/check-dms-nvim.lua"),
                str(home / ".config/nvim/lua/plugins/dms-colorscheme.lua"),
                "enabled" if shell == "dms" else "disabled",
            ], env)
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
            assert session.count('spawn-at-startup "dms-with-lyrics" "run"') == 1
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
            assert settings["matugenTemplateNeovim"] is True
            fastfetch_config = tomllib.loads(
                (home / ".config/matugen/dms/configs/chezmoi-fastfetch.toml").read_text()
            )
            assert set(fastfetch_config) == {"templates"}
            assert set(fastfetch_config["templates"]) == {"chezmoi-fastfetch"}
            fastfetch_template = fastfetch_config["templates"]["chezmoi-fastfetch"]
            assert fastfetch_template == {
                "input_path": str(home / ".config/matugen/templates/fastfetch-config.jsonc"),
                "output_path": str(home / ".config/fastfetch/config.jsonc"),
            }
            btop_config = tomllib.loads(
                (home / ".config/matugen/dms/configs/chezmoi-btop.toml").read_text()
            )
            assert set(btop_config) == {"templates"}
            assert set(btop_config["templates"]) == {"chezmoi-btop"}
            btop_template = btop_config["templates"]["chezmoi-btop"]
            assert btop_template["input_path"] == str(home / ".config/matugen/templates/btop.theme")
            assert btop_template["output_path"] == str(home / ".config/btop/themes/matugen.theme")
            assert settings["cornerRadius"] == 16
            assert settings["widgetColorMode"] == "default"
            assert settings["runningAppsCurrentWorkspace"] is True
            assert settings["barElevationEnabled"] is False
            bar = settings["barConfigs"]
            assert len(bar) == 1
            assert bar[0]["island"] is False
            assert bar[0]["transparency"] == 0
            assert bar[0]["widgetTransparency"] == 1
            assert bar[0]["screenPreferences"] == ["all"]
            assert bar[0]["leftWidgets"] == ["launcherButton", "workspaceSwitcher", "focusedWindow"]
            assert bar[0]["centerWidgets"] == ["music", "clock", "weather"]
            assert bar[0]["rightWidgets"] == [
                "systemTray", "clipboard", "dankTodo", "cpuUsage", "memUsage",
                "notificationButton", "battery", "controlCenterButton",
            ]
            assert bar[0]["hoverPopouts"] is True
            assert bar[0]["hoverPopoutDelay"] == 450
            assert not any(key.startswith("island") and key != "island" for key in bar[0])
            qt6ct = configparser.ConfigParser(interpolation=None)
            qt_file = home / ".config/qt6ct/qt6ct.conf"
            qt6ct.read(qt_file)
            assert qt6ct["Appearance"]["color_scheme_path"] == str(home / ".config/qt6ct/colors/matugen.conf")
            assert qt6ct["Appearance"]["custom_palette"] == "true"
            assert qt6ct["Appearance"]["icon_theme"] == "Adwaita"
            assert qt6ct["Appearance"]["style"] == "Fusion"
            assert qt6ct["Fonts"]["fixed"].startswith('"JetBrainsMono Nerd Font Mono,')
            assert qt6ct["Fonts"]["general"].startswith('"Adwaita Sans,')
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
            # Only selected GUI preferences are managed; generated files remain DMS-owned.
            settings["acLockTimeout"] = 600
            settings["futurePreference"] = True
            settings["networkPreference"] = "ethernet"
            settings["barConfigs"] = [{"id": "local"}]
            settings["cornerRadius"] = 8
            settings["widgetColorMode"] = "colorful"
            settings["runningAppsCurrentWorkspace"] = False
            settings["barElevationEnabled"] = True
            settings["matugenTemplateNeovim"] = False
            settings["matugenTemplateGhostty"] = False
            settings_file.write_text(json.dumps(settings))
            qt_file.write_text(
                "; local comment\n[Appearance]\nicon_theme=breeze\ncustom_palette=false\n"
                "custom_key=keep\n[Fonts]\nfixed=monospace\n[Interface]\nretain=1\n"
            )
            output_file.write_text('// user output preferences\n')
            color_file = niri_dir / "dms/colors.kdl"
            color_file.write_text('// generated palette\n')
            binds_file.write_text(binds.replace("Mod+D hotkey", "Mod+Space hotkey"))
            apply(home, env, command, shell)
            updated = json.loads(settings_file.read_text())
            assert updated["barConfigs"] == bar
            assert updated["cornerRadius"] == 16
            assert updated["widgetColorMode"] == "default"
            assert updated["runningAppsCurrentWorkspace"] is True
            assert updated["barElevationEnabled"] is False
            assert updated["matugenTemplateNeovim"] is True
            assert updated["matugenTemplateGhostty"] is False
            assert updated["acLockTimeout"] == 600
            assert updated["futurePreference"] is True
            assert updated["networkPreference"] == "ethernet"
            qt6ct = configparser.ConfigParser(interpolation=None)
            qt6ct.read(qt_file)
            assert qt6ct["Appearance"]["icon_theme"] == "Adwaita"
            assert qt6ct["Appearance"]["custom_palette"] == "true"
            assert qt6ct["Appearance"]["color_scheme_path"] == str(home / ".config/qt6ct/colors/matugen.conf")
            assert qt6ct["Appearance"]["style"] == "Fusion"
            assert qt6ct["Fonts"]["fixed"].startswith('"JetBrainsMono Nerd Font Mono,')
            assert qt6ct["Fonts"]["general"].startswith('"Adwaita Sans,')
            assert qt6ct["Appearance"]["custom_key"] == "keep"
            assert qt6ct["Interface"]["retain"] == "1"
            assert "; local comment\n" in qt_file.read_text()
            after = (settings_file.read_bytes(), qt_file.read_bytes())
            apply(home, env, command, shell)
            assert (settings_file.read_bytes(), qt_file.read_bytes()) == after
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
            assert_gtk_imports(css, version, shell)

home, env, command = fixture("dms-existing", "dms")
settings_file = home / ".config/DankMaterialShell/settings.json"
qt_file = home / ".config/qt6ct/qt6ct.conf"
settings_file.parent.mkdir(parents=True)
qt_file.parent.mkdir(parents=True)
settings_file.write_text('{"networkPreference": "ethernet", "futurePreference": true}\n')
qt_file.write_text("[Appearance]\nicon_theme=breeze\n[Interface]\nretain=1\n")
apply(home, env, command, "dms")
settings = json.loads(settings_file.read_text())
assert settings["networkPreference"] == "ethernet"
assert settings["futurePreference"] is True
assert "acLockTimeout" not in settings
assert settings["barConfigs"][0]["island"] is False
assert settings["barElevationEnabled"] is False
assert settings["cornerRadius"] == 16
assert settings["widgetColorMode"] == "default"
assert settings["runningAppsCurrentWorkspace"] is True
qt6ct = configparser.ConfigParser(interpolation=None)
qt6ct.read(qt_file)
assert qt6ct["Appearance"]["icon_theme"] == "Adwaita"
assert qt6ct["Interface"]["retain"] == "1"

home, env, command = fixture("legacy")
assert custom_only <= managed(command, env)
assert not dms_only & managed(command, env)
assert ".config/gtk-4.0/nautilus.css" in managed(command, env)
for shell in ("dms", "custom"):
    for graphical, niri in ((False, False), (False, True), (True, False)):
        home, env, command = fixture(f"{shell}-{graphical}-{niri}", shell, graphical, niri)
        inventory = managed(command, env)
        assert not dms_only & inventory
        assert (".config/gtk-4.0/nautilus.css" in inventory) == graphical
        plugin_file = home / ".config/nvim/lua/plugins/dms-colorscheme.lua"
        plugin_file.parent.mkdir(parents=True)
        run(command + ["apply", "--exclude=scripts,encrypted,externals", str(plugin_file)], env)
        assert plugin_file.read_text().strip() == "return {}"
        assert ".config/niri/config.kdl" not in inventory
        if graphical:
            run(command + ["apply", "--exclude=scripts,encrypted,externals"]
                + [str(home / path) for path in (".config/kitty", ".config/gtk-3.0", ".config/gtk-4.0", ".config/fcitx5")], env)
            assert "include current-theme.conf" in (home / ".config/kitty/kitty.conf").read_text()
            assert "Theme=Matugen\n" in (home / ".config/fcitx5/conf/classicui.conf").read_text()
            for version in ("3.0", "4.0"):
                assert_gtk_imports(
                    (home / f".config/gtk-{version}/gtk.css").read_text(), version, "custom"
                )

home, env, command = fixture("invalid", "invalid")
result = subprocess.run(
    command + ["managed"], env=env, capture_output=True, text=True,
    stdin=subprocess.DEVNULL, timeout=30,
)
assert result.returncode and "desktopShell must be custom or dms" in result.stderr

# Exercise the real init prompt without the user's saved machine data.
home, env, command = fixture("init")
empty = home / "empty.toml"
empty.write_text("")
for shell in ("dms", "custom"):
    rendered = run(
        ["chezmoi", "--config", str(empty), "--source", str(source),
         "execute-template", "--init", "--promptChoice",
         f"Machine role=laptop,Default shell=zsh,Desktop shell: DMS or custom components={shell},Niri output profile=auto,SSH authorized_keys identity=none",
         "--promptBool", "Graphical machine=true,Use niri=true,Use Tether iPhone notifications=false,Work machine=false,Use rbw SSH agent=false",
         "--file", str(repo / ".chezmoi.toml.tmpl")], env,
    )
    assert tomllib.loads(rendered)["data"]["desktopShell"] == shell
    assert tomllib.loads(rendered)["data"]["tether"] is False

# Switching replaces only managed CSS imports, not unrelated custom CSS.
home, env, command = fixture("switch", "dms")
palettes = {}
for version in ("3.0", "4.0"):
    css = home / f".config/gtk-{version}/gtk.css"
    css.parent.mkdir(parents=True, exist_ok=True)
    css.write_text('@import "colors.css";\n@import "dank-colors.css";\n'
                   + ('@import "nautilus.css";\n@import url(\'nautilus.css\');\n' if version == "4.0" else '')
                   + '/* keep */\n@import "local.css";\n')
    palette = css.parent / "dank-colors.css"
    palette.write_text("/* DMS-generated palette */\n")
    palettes[palette] = palette.read_bytes()
config = home / "chezmoi.toml"
for shell in ("dms", "custom", "dms"):
    config.write_text(re.sub(r'desktopShell = "[^"]+"', f'desktopShell = "{shell}"', config.read_text()))
    apply(home, env, command, shell)
    if shell == "custom":
        assert (home / ".config/nvim/lua/plugins/dms-colorscheme.lua").read_text().strip() == "return {}"
    if shutil.which("niri"):
        run(["niri", "validate", "--config", str(home / ".config/niri/config.kdl")], env)
    for version in ("3.0", "4.0"):
        css = (home / f".config/gtk-{version}/gtk.css").read_text()
        assert_gtk_imports(css, version, shell)
        assert '/* keep */\n@import "local.css";\n' in css
    css_files = [home / f".config/gtk-{version}/gtk.css" for version in ("3.0", "4.0")]
    css_files.append(home / ".config/gtk-4.0/nautilus.css")
    applied = {path: path.read_bytes() for path in css_files}
    apply(home, env, command, shell)
    assert {path: path.read_bytes() for path in css_files} == applied
    assert {path: path.read_bytes() for path in palettes} == palettes

ignored = run(command + ["execute-template", "--file", str(repo / ".chezmoiignore")], env)
for path in (
    ".local/state/DankMaterialShell/", ".cache/DankMaterialShell/",
    ".local/share/dms-media-lyrics/",
    ".config/DankMaterialShell/clsettings.json", ".config/DankMaterialShell/plugin_settings.json",
    ".config/DankMaterialShell/notification_history.json", ".config/quickshell/",
    ".config/DankMaterialShell/plugins.json", ".config/DankMaterialShell/plugins.lock.json",
    ".config/DankMaterialShell/plugins/*", ".config/dank-todo/",
    ".local/bin/dms-with-lyrics",
    ".config/nvim/colors/dms.lua", ".config/nvim/lua/lualine/themes/dms.lua",
    ".config/fastfetch/config.jsonc",
):
    assert path in ignored.splitlines()
assert "!.config/DankMaterialShell/plugins/lyrics" not in ignored.splitlines()

if shutil.which("dms") and shutil.which("matugen"):
    home, env, command = fixture("dms-btop-generation", "dms")
    apply(home, env, command, "dms")
    shell = home / "test-shell"
    inputs = shell / "matugen/templates"
    inputs.mkdir(parents=True)
    (inputs / "dank.json").write_text('{"primary":"{{colors.primary.default.hex}}"}')
    legacy_output = home / "legacy-output"
    (home / ".config/matugen/config.toml").write_text(
        "[templates.legacy]\n"
        f"input_path = '{inputs / 'dank.json'}'\n"
        f"output_path = '{legacy_output}'\n"
    )
    bin_dir = home / "bin"
    bin_dir.mkdir()
    hook_log = home / "hook.log"
    pkill = bin_dir / "pkill"
    pkill.write_text(
        '#!/bin/sh\nprintf "%s\\n" "$*" >> "$DMS_TEST_HOOK_LOG"\n'
        'exit "$DMS_TEST_PKILL_STATUS"\n'
    )
    pkill.chmod(0o755)
    env = {
        **env, "PATH": str(bin_dir) + os.pathsep + env["PATH"],
        "DMS_TEST_HOOK_LOG": str(hook_log),
    }
    skip = ",".join(item["id"] for item in json.loads(run(["dms", "matugen", "check"], env)))
    theme_file = home / ".config/btop/themes/matugen.theme"
    theme_file.parent.mkdir(parents=True)
    fastfetch_file = home / ".config/fastfetch/config.jsonc"
    fastfetch_file.parent.mkdir(parents=True)
    rendered = []
    for mode, status in (("dark", "0"), ("light", "1")):
        env["DMS_TEST_PKILL_STATUS"] = status
        run([
            "dms", "matugen", "generate", "--shell-dir", str(shell),
            "--config-dir", str(home / ".config"), "--state-dir", str(home / ".cache/dms-test"),
            "--kind", "hex", "--value", "#927d76", "--mode", mode,
            "--matugen-type", "scheme-neutral", "--run-user-templates=false",
            "--skip-templates", skip,
        ], env)
        rendered.append(theme_file.read_text())
        assert "{{" not in rendered[-1]
        assert re.search(r'theme\[main_fg\]="#[0-9a-fA-F]{6}"', rendered[-1])
        assert not legacy_output.exists()
        assert "{{" not in fastfetch_file.read_text()
        assert '"keyColor": "#' in fastfetch_file.read_text()
        if shutil.which("fastfetch"):
            run(["fastfetch", "--config", str(fastfetch_file), "--structure", "colors", "--pipe"], env)
    assert rendered[0] != rendered[1]
    expected_hook = f"-USR2 -x -u {os.getuid()} btop"
    assert hook_log.read_text().splitlines() == [expected_hook, expected_hook]
    print("DMS btop/fastfetch generation and reload hooks passed with user templates disabled")
else:
    print("DMS btop/fastfetch generation skipped: dms or matugen unavailable")

if not shutil.which("nvim"):
    print("DMS Neovim selection checks skipped: nvim unavailable")

print(f"desktop profile checks passed (retained fixtures: {task})")
PY
