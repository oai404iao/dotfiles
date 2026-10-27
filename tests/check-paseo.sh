#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_dir=$(
    umask 077
    scratch_root="$HOME/.local/state/agents/tmp"
    mkdir -p -- "$scratch_root"
    mktemp -d "$scratch_root/check-paseo.XXXXXXXX"
)

python3 - "$repo_dir" "$task_dir" <<'PY'
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tomllib

repo, task = map(Path, sys.argv[1:])
sources = {
    "dot_local/bin/executable_paseo-service": ".local/bin/paseo-service",
    "dot_config/systemd/user/paseo.service": ".config/systemd/user/paseo.service",
}
for path in repo.glob("run_*"):
    assert "paseo" not in path.name.lower()
    assert "paseo" not in path.read_text().lower(), "apply must not operate Paseo"
subprocess.run(["sh", "-n", str(repo / "dot_local/bin/executable_paseo-service")], check=True)
if not shutil.which("chezmoi"):
    print("Paseo syntax passed; rendering skipped: chezmoi unavailable")
    raise SystemExit(0)

source = task / "source"
for relative in (*sources, ".chezmoiignore", ".chezmoi.toml.tmpl"):
    target = source / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo / relative, target)

runtime = {
    "dot_local/share/paseo/config.json": ".local/share/paseo/config.json",
    "dot_local/share/paseo/client-password.txt": ".local/share/paseo/client-password.txt",
    "dot_local/share/paseo/agents/session.json": ".local/share/paseo/agents/session.json",
    "dot_paseo/config.json": ".paseo/config.json",
    "dot_paseo/client-password.txt": ".paseo/client-password.txt",
    "dot_paseo/agents/session.json": ".paseo/agents/session.json",
    "dot_paseo/daemon.pid": ".paseo/daemon.pid",
    "dot_paseo/worktrees/project/file": ".paseo/worktrees/project/file",
    "dot_local/state/deployment-backups/paseo/fixture": ".local/state/deployment-backups/paseo/fixture",
    "dot_config/systemd/user/default.target.wants/paseo.service":
        ".config/systemd/user/default.target.wants/paseo.service",
}
for relative in runtime:
    target = source / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("fixture application state\n")

def fixture(name, enabled=None, graphical=False):
    case = task / name
    home = case / "home"
    home.mkdir(parents=True)
    data = {
        "role": "desktop" if graphical else "server", "shell": "zsh",
        "graphical": graphical, "niri": graphical, "work": False,
        "niriOutputProfile": "auto", "sshAgent": False,
        "sshInboundIdentity": "none", "secretBackend": "rbw",
    }
    if enabled is not None:
        data["paseo"] = enabled
    config = case / "chezmoi.toml"
    config.write_text(
        'mode = "file"\n[template]\noptions = ["missingkey=error"]\n[data]\n'
        + "\n".join(f"{key} = {json.dumps(value)}" for key, value in data.items()) + "\n"
    )
    env = {
        **os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_CACHE_HOME": str(home / ".cache"), "TMPDIR": str(case),
    }
    command = [
        "chezmoi", "--config", str(config), "--source", str(source),
        "--destination", str(home), "--persistent-state", str(case / "state.boltdb"),
    ]
    return home, env, command

def run(command, env):
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"{command}\n{result.stderr}"
    return result.stdout

for enabled in (None, False, True):
    for graphical in (False, True):
        home, env, command = fixture(
            f"matrix-{enabled}-{graphical}", enabled, graphical,
        )
        inventory = set(run(command + [
            "managed", "--include=files", "--path-style=relative",
        ], env).splitlines())
        assert inventory == (set(sources.values()) if enabled else set()), inventory

home, env, command = fixture("apply", True)
app_config = home / ".local/share/paseo/config.json"
app_config.parent.mkdir(parents=True)
app_config.write_text('{"futureSetting":"retain","features":{"webUi":{"enabled":true}}}\n')
before = app_config.read_bytes()
for path in sources.values():
    (home / path).parent.mkdir(parents=True, exist_ok=True)
targets = [str(home / path) for path in sources.values()]
run(command + ["apply", "--exclude=scripts,encrypted", *targets], env)
assert app_config.read_bytes() == before
assert not (home / ".local/share/paseo/agents").exists()
assert not (home / ".paseo").exists()
assert not (home / runtime["dot_config/systemd/user/default.target.wants/paseo.service"]).exists()
assert (home / ".local/bin/paseo-service").stat().st_mode & 0o111
assert not run(command + ["diff", "--exclude=scripts,encrypted", *targets], env)

units = home / ".config/systemd/user"
main = (units / "paseo.service").read_text()
assert "WantedBy=default.target\n" in main

deployment_env = {}
for line in main.splitlines():
    if line.startswith("Environment="):
        for setting in shlex.split(line.removeprefix("Environment=")):
            key, value = setting.split("=", 1)
            deployment_env[key] = value.replace("%h", str(home))
assert deployment_env == {
    "PASEO_HOME": str(home / ".local/share/paseo"), "PASEO_LISTEN": "0.0.0.0:6767",
    "PASEO_WEB_UI_ENABLED": "false", "PASEO_RELAY_ENABLED": "false",
    "PASEO_SERVICE_PROXY_ENABLED": "false",
}

# A fake CLI checks the supervisor launch without invoking Paseo or any provider.
for custom in (False, True):
    roots = {
        key: str(home / (f"custom-{kind}" if custom else path))
        for key, kind, path in (
            ("XDG_CONFIG_HOME", "config", ".config"),
            ("XDG_DATA_HOME", "data", ".local/share"),
            ("XDG_STATE_HOME", "state", ".local/state"),
            ("XDG_CACHE_HOME", "cache", ".cache"),
        )
    }
    profile_dir = Path(roots["XDG_CONFIG_HOME"]) / "shell"
    profile_dir.mkdir(parents=True, exist_ok=True)
    for name in ("profile.sh", "toolchains.sh"):
        shutil.copy2(repo / "dot_config/shell" / name, profile_dir / name)
    pnpm_home = Path(roots["XDG_DATA_HOME"]) / "pnpm"
    fake = pnpm_home / "bin/paseo"
    fake.parent.mkdir(parents=True, exist_ok=True)
    fake.write_text(
        '#!/usr/bin/python3\nimport json, os, sys\n'
        'print(json.dumps({"args": sys.argv[1:], "env": dict(os.environ)}))\n'
    )
    fake.chmod(0o700)
    launch_env = {**env, **roots, **deployment_env, "PATH": "/usr/bin:/bin"}
    for key in ("PNPM_HOME", "PI_CODING_AGENT_DIR", "PI_CODING_AGENT_SESSION_DIR"):
        launch_env.pop(key, None)
    result = json.loads(run(["/bin/sh", str(home / ".local/bin/paseo-service")], launch_env))
    assert result["args"] == ["daemon", "run"]
    actual = result["env"]
    assert actual["PNPM_HOME"] == str(pnpm_home)
    assert str(pnpm_home / "bin") in actual["PATH"].split(":")
    assert actual["PI_CODING_AGENT_DIR"] == roots["XDG_CONFIG_HOME"] + "/pi/agent"
    assert actual["PI_CODING_AGENT_SESSION_DIR"] == roots["XDG_STATE_HOME"] + "/pi/agent/sessions"
    assert all(actual[key] == value for key, value in deployment_env.items())

initialized = tomllib.loads(run(command + [
    "execute-template", "--init", "--file", str(source / ".chezmoi.toml.tmpl"),
], env))
assert initialized["data"]["paseo"] is True
for enabled in (False, True):
    empty = task / "empty.toml"
    empty.write_text("")
    initialized = tomllib.loads(run([
        "chezmoi", "--config", str(empty), "--source", str(source),
        "execute-template", "--init", "--promptChoice",
        "Machine role=server,Default shell=zsh,SSH authorized_keys identity=none",
        "--promptBool", "Graphical machine=false,Work machine=false,Use rbw SSH agent=false,"
        f"Manage local Paseo service={str(enabled).lower()}",
        "--file", str(source / ".chezmoi.toml.tmpl"),
    ], env))
    assert initialized["data"]["paseo"] is enabled

if shutil.which("systemd-analyze"):
    run(["systemd-analyze", "--user", "verify", "--man=no", str(units / "paseo.service")],
        {**env, "SYSTEMD_UNIT_PATH": str(units) + ":/usr/lib/systemd/user"})
else:
    print("Paseo unit verification skipped: systemd tools unavailable")
print(f"Paseo offline checks passed ({task})")
PY
