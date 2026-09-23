#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_dir=$(
    umask 077
    scratch_root="$HOME/.local/state/agents/tmp"
    mkdir -p -- "$scratch_root"
    mktemp -d "$scratch_root/check-keyring.XXXXXXXX"
)

python3 - "$repo_dir" "$task_dir" <<'PY'
import configparser
import os
from pathlib import Path
import shutil
import subprocess
import sys

repo, task = map(Path, sys.argv[1:])
source_dir = Path("dot_local/share/dbus-1/services")
target_dir = Path(".local/share/dbus-1/services")
names = ("org.freedesktop.secrets", "org.gnome.keyring")
targets = {str(target_dir / f"{name}.service") for name in names}
assert {p.name for p in (repo / source_dir).iterdir()} == {
    f"{name}.service" for name in names
}
for name in names:
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    config.read(repo / source_dir / f"{name}.service")
    assert config.sections() == ["D-BUS Service"]
    assert dict(config["D-BUS Service"]) == {
        "Name": name,
        "Exec": "/usr/bin/gnome-keyring-daemon --start --foreground --components=secrets",
        "SystemdService": "gnome-keyring-daemon.service",
    }

protected = {
    ".local/share/keyrings/",
    ".local/state/keyring-backups/",
}
ignore = (repo / ".chezmoiignore").read_text()
assert protected <= set(ignore.splitlines())
for path in (
    ".local/share/keyrings/login.keyring",
    ".local/state/keyring-backups/snapshot/login.keyring",
    "dot_local/share/keyrings/login.keyring",
    "dot_local/share/private_keyrings/default",
    "dot_local/state/keyring-backups/snapshot/login.keyring",
    "dot_local/state/private_keyring-backups/snapshot/login.keyring",
):
    assert not (repo / path).exists()
    subprocess.run(
        ["git", "check-ignore", "--no-index", "-q", path], cwd=repo, check=True
    )

if shutil.which("chezmoi"):
    source = task / "source"
    (source / source_dir).mkdir(parents=True)
    shutil.copy2(repo / ".chezmoiignore", source / ".chezmoiignore")
    for name in names:
        shutil.copy2(repo / source_dir / f"{name}.service", source / source_dir)
    for relative in (
        "dot_local/share/private_keyrings/default",
        "dot_local/share/private_keyrings/login.keyring",
        "dot_local/state/private_keyring-backups/snapshot/login.keyring",
    ):
        fixture = source / relative
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text("fake machine-local state\n")
    unrelated = target_dir / "org.example.Unrelated.service"
    (source / source_dir / unrelated.name).write_text("unrelated service fixture\n")

    for graphical, niri in ((False, False), (False, True), (True, False), (True, True)):
        case = task / f"graphical-{graphical}-niri-{niri}"
        home = case / "home"
        home.mkdir(parents=True)
        env = {
            **os.environ,
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_DATA_HOME": str(home / ".local/share"),
            "XDG_STATE_HOME": str(home / ".local/state"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "TMPDIR": str(case),
        }
        config = case / "chezmoi.toml"
        config.write_text(
            f'[data]\ngraphical = {str(graphical).lower()}\n'
            f'niri = {str(niri).lower()}\n'
        )
        command = [
            "chezmoi", "--source", str(source), "--destination", str(home),
            "--config", str(config), "--persistent-state", str(case / "state.boltdb"),
        ]
        result = subprocess.run(
            [*command, "managed", "--include=files", "--path-style=relative"],
            env=env, check=True, text=True, capture_output=True,
        )
        expected = targets if graphical and niri else set()
        assert set(result.stdout.splitlines()) == expected | {str(unrelated)}
        if expected:
            (home / target_dir).mkdir(parents=True)
            subprocess.run(
                [*command, "apply", "--exclude=scripts,encrypted",
                 *(str(home / path) for path in sorted(expected))],
                env=env, check=True, capture_output=True, text=True,
            )
            for name in names:
                target = home / target_dir / f"{name}.service"
                assert target.read_bytes() == (repo / source_dir / target.name).read_bytes()
        for path in protected:
            assert not (home / path).exists()
    print("keyring Niri/headless render matrix passed")
else:
    print("keyring render checks skipped: chezmoi unavailable")
PY

printf '%s\n' "keyring configuration checks passed (retained fixtures: $task_dir)"
