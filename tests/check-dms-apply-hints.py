import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

chezmoi = shutil.which("chezmoi")
if not chezmoi:
    print("DMS apply reminder checks skipped: chezmoi unavailable")
    raise SystemExit(0)

repo = Path(__file__).resolve().parents[1]
scratch = Path.home() / ".local/state/agents/tmp"
scratch.mkdir(parents=True, exist_ok=True)
task = Path(tempfile.mkdtemp(prefix="check-dms-apply-hints.", dir=scratch))
source = task / "source"
source.mkdir()
hook = source / "run_after_check-dms-lyrics.sh.tmpl"
shutil.copyfile(repo / hook.name, hook)
home = task / "home"
home.mkdir()
bin_dir = task / "bin"
bin_dir.mkdir()
log = task / "commands.log"
env = {
    **os.environ,
    "HOME": str(home),
    "XDG_CONFIG_HOME": str(home / ".config"),
    "XDG_CACHE_HOME": str(home / ".cache"),
    "XDG_DATA_HOME": str(task / "data"),
    "XDG_STATE_HOME": str(home / ".local/state"),
    "PATH": str(bin_dir),
    "TMPDIR": str(task),
    "FAKE_DMS_VERSION": "dms v1.6.2",
    "FAKE_DMS_STATUS": "0",
    "FAKE_COMMAND_LOG": str(log),
}
config = task / "chezmoi.toml"
command = [
    chezmoi, "--config", str(config), "--source", str(source),
    "--persistent-state", str(task / "chezmoi-state.boltdb"),
]


def configure(graphical=True, niri=True, shell="dms"):
    data = {"graphical": graphical, "niri": niri}
    if shell is not None:
        data["desktopShell"] = shell
    config.write_text(
        f'mode = "file"\ndestDir = {json.dumps(str(home))}\n'
        '[template]\noptions = ["missingkey=error"]\n[data]\n'
        + "\n".join(f"{key} = {json.dumps(value)}" for key, value in data.items())
        + "\n"
    )


def run(args, **kwargs):
    return subprocess.run(
        args, env=env, check=True, capture_output=True, text=True, **kwargs
    )


for graphical in (False, True):
    for niri in (False, True):
        for shell in ("custom", "dms", None):
            configure(graphical, niri, shell)
            rendered = run(command + ["execute-template", "--file", str(hook)]).stdout
            if graphical and niri and shell == "dms":
                assert rendered.startswith("#!/bin/sh\n")
                run(["/bin/sh", "-n"], input=rendered)
            else:
                assert not rendered.strip(), (graphical, niri, shell, rendered)
                result = run(command + ["apply", "--include=scripts"])
                assert not result.stdout and not result.stderr

configure()
for name in ("dms", "qs", "python3"):
    program = bin_dir / name
    program.write_text(
        '#!/bin/sh\n'
        'printf "%s\\n" "$0 $*" >> "$FAKE_COMMAND_LOG"\n'
        'if [ "${0##*/}" = dms ] && [ "$*" = version ]; then\n'
        '    printf "%s\\n" "$FAKE_DMS_VERSION"\n'
        '    exit "$FAKE_DMS_STATUS"\n'
        'fi\n'
        'exit 99\n'
    )
    program.chmod(0o700)


def apply():
    result = run(command + ["apply", "--include=scripts"])
    assert not result.stdout, result.stdout
    assert "dms-shell-niri" not in result.stderr, result.stderr
    assert "dms-shell-hyprland" not in result.stderr, result.stderr
    return result.stderr


assert "prepared overlay missing or incomplete" in apply()
assert "prepare-dms-media-lyrics.py" in apply()
assert not log.exists()
current = Path(env["XDG_DATA_HOME"]) / "dms-media-lyrics/current"
current.mkdir(parents=True)
(current / "shell.qml").write_text("fixture\n")
marker = current / ".dms-version"
for prepared in ("dms v1.6.2", "dms v1.6.3"):
    marker.write_text(f"{prepared}\n")
    env["FAKE_DMS_VERSION"] = prepared
    assert not apply()
    assert not apply()
    for installed in ("dms v1.6.2", "dms v1.6.3", "dms v1.6.4", "dms v1.7.0"):
        if installed == prepared:
            continue
        env["FAKE_DMS_VERSION"] = installed
        reminder = apply()
        assert "version mismatch" in reminder
        assert "stock DMS will be used" in reminder
marker.write_text("dms v1.6.2\n")
env["FAKE_DMS_VERSION"] = "dms v1.6.2"
env["FAKE_DMS_STATUS"] = "1"
assert "cannot verify" in apply()
env["FAKE_DMS_STATUS"] = "0"
env["FAKE_DMS_VERSION"] = ""
assert "cannot verify" in apply()
env["FAKE_DMS_VERSION"] = "dms v1.6.2"

for content in ("", "dms v1.6.2"):
    marker.write_text(content)
    reminder = apply()
    assert "missing or incomplete" in reminder
    assert "prepare it before launching DMS" in reminder
    assert "stock DMS will be used" not in reminder
marker.write_text("dms v1.6.2\n")
(current / "shell.qml").rename(current / "saved.qml")
assert "missing or incomplete" in apply()
(current / "saved.qml").rename(current / "shell.qml")

(bin_dir / "python3").rename(task / "python3")
assert not apply(), "Python is not needed to run a prepared overlay"
marker.rename(current / "saved-version")
assert "sudo pacman -Syu --needed python" in apply()
(current / "saved-version").rename(marker)

(bin_dir / "qs").rename(task / "qs")
assert "sudo pacman -Syu --needed quickshell" in apply()
(bin_dir / "dms").rename(task / "dms")
assert "sudo pacman -Syu --needed dms-shell quickshell" in apply()
(task / "qs").rename(bin_dir / "qs")
assert "sudo pacman -Syu --needed dms-shell" in apply()
(task / "dms").rename(bin_dir / "dms")
assert not apply()

env["XDG_DATA_HOME"] = ""
assert "missing or incomplete" in apply()
default_current = home / ".local/share/dms-media-lyrics/current"
default_current.parent.mkdir(parents=True)
default_current.symlink_to(current, target_is_directory=True)
assert not apply()
assert all(line == f"{bin_dir}/dms version" for line in log.read_text().splitlines())
assert marker.read_text() == "dms v1.6.2\n"
assert (current / "shell.qml").read_text() == "fixture\n"
print(f"DMS apply reminder checks passed (retained fixtures: {task})")
