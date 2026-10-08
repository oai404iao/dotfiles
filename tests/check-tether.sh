#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_dir=$(
    umask 077
    scratch_root="$HOME/.local/state/agents/tmp"
    mkdir -p -- "$scratch_root"
    mktemp -d "$scratch_root/check-tether.XXXXXXXX"
)

python3 - "$repo_dir" "$task_dir" <<'PY'
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tomllib

repo, task = map(Path, sys.argv[1:])
tether_source = repo / "dot_config/private_tether"
modifier = tether_source / "modify_private_bluetooth.json"
dropin_source = repo / "dot_config/systemd/user/tetherd.service.d"
dropins = {"10-notification-network.conf", "20-no-clipboard.conf"}
assert {p.relative_to(tether_source).as_posix() for p in tether_source.rglob("*")} == {
    "modify_private_bluetooth.json",
}
assert {p.name for p in dropin_source.iterdir()} == {f"{name}.tmpl" for name in dropins}
assert not (repo / "dot_config/DankMaterialShell/modify_settings.json").exists()
dms_source = repo / "dot_config/DankMaterialShell/modify_settings.json.tmpl"
assert dms_source.is_file()
assert modifier.read_text().startswith("#!/usr/bin/env python3\n")
assert dms_source.read_text().startswith("#!/usr/bin/env python3\n")
compile(modifier.read_text(), str(modifier), "exec")

def check_dropins(contents, mode):
    network = ["[Service]", "ExecStartPre=", "ExecStart="]
    clipboard = [
        "[Service]", "RuntimeDirectory=tether", "RuntimeDirectoryMode=0700",
        "RuntimeDirectoryPreserve=yes",
    ]
    if mode in (None, "notifications"):
        network += [
            "ExecStart=/usr/bin/unshare --user --map-current-user --net /usr/bin/tetherd",
            "PrivateUsers=yes",
        ]
        clipboard += [
            "Environment=WAYLAND_DISPLAY=wayland-0", "TemporaryFileSystem=%t:rw",
            "BindPaths=%t/tether", "BindReadOnlyPaths=%t/bus",
        ]
    else:
        assert mode == "wifi-clipboard"
        network += ["ExecStart=/usr/bin/tetherd", "PrivateUsers=no"]
    network += ["UMask=0077"]
    for name, expected in (
        ("10-notification-network.conf", network), ("20-no-clipboard.conf", clipboard),
    ):
        assert [
            line for line in contents[name].splitlines() if line and not line.startswith("#")
        ] == expected, (name, mode, contents[name])
bluez = repo / "scripts/tether/bluetooth-experimental.conf"
assert bluez.is_file()
assert bluez.read_text().splitlines() == [
    "[Service]", "ExecStart=", "ExecStart=/usr/lib/bluetooth/bluetoothd --experimental",
]
for path in repo.glob("run_*"):
    assert "tether" not in path.name.lower()
    if path.is_file():
        assert not re.search(r"tether|bluetooth.*experimental", path.read_text(), re.I)

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result

def strict_json(text):
    return json.loads(
        text, object_pairs_hook=unique_object,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)),
    )

def transform(path, raw, success=True):
    result = subprocess.run(
        [sys.executable, str(path)], input=raw, capture_output=True, text=True,
    )
    if success:
        assert result.returncode == 0, result.stderr
        assert result.stdout.endswith("\n")
        strict_json(result.stdout)
    else:
        assert result.returncode != 0, f"accepted invalid JSON: {raw!r}"
        assert not result.stdout, "failed modifier emitted a partial replacement"
    return result.stdout

for raw in ("{", "[]", "null", "1", '"text"', '{"x":1,"x":2}',
            '{"future":{"x":1,"x":2}}', '{"future":NaN}',
            '{"future":Infinity}', '{"future":-Infinity}'):
    transform(modifier, raw, success=False)
for key, invalid_values in {
    "device_address": (None, False, 1, [], {}),
    "auth_strategy": (None, False, 1, [], {}),
    "adapter": (None, False, 1, [], {}),
    "enabled": (None, 0, 1, "true", [], {}),
    "config_version": (None, False, True, 2.0, "2", [], {}),
    "lock_away_seconds": (None, False, True, 30.0, "30", [], {}),
    "lock_command": (None, False, 1, [], {}),
}.items():
    for value in invalid_values:
        transform(modifier, json.dumps({key: value}), success=False)

fresh_text = transform(modifier, "")
fresh = strict_json(fresh_text)
policy = {
    "ancs_enabled": True, "ancs_content_enabled": True,
    "desktop_popups_enabled": True, "popup_previews_enabled": True,
    "retention": "none", "group_messages_enabled": False, "calls_enabled": False,
    "airpods_enabled": False, "airpods_pause": "never", "airpods_handoff": False,
    "lock_on_away": False,
}
assert fresh == {"config_version": 2, **policy}
assert transform(modifier, " \n\t") == fresh_text
assert transform(modifier, fresh_text) == fresh_text
runtime = {
    "device_address": "00:11:22:33:44:55", "auth_strategy": "fixture-strategy",
    "adapter": "fixture-adapter", "enabled": False, "config_version": 99,
    "lock_away_seconds": -1, "lock_command": "fixture-lock-command",
    "future_option": {"value": ["retain", True, "通知"]},
}
old_policy = {key: not value if isinstance(value, bool) else "old" for key, value in policy.items()}
existing_text = transform(modifier, json.dumps({**runtime, **old_policy}))
existing = strict_json(existing_text)
assert all(existing[key] == value for key, value in runtime.items())
assert all(existing[key] == value for key, value in policy.items())
assert transform(modifier, existing_text) == existing_text

if not shutil.which("chezmoi"):
    print(f"Tether source checks passed; render checks skipped: chezmoi unavailable ({task})")
    raise SystemExit(0)

source = task / "source"
source.mkdir()
for relative in (
    ".chezmoiignore", ".chezmoi.toml.tmpl",
    "dot_config/private_tether/modify_private_bluetooth.json",
    "dot_config/DankMaterialShell/modify_settings.json.tmpl",
    *(f"dot_config/systemd/user/tetherd.service.d/{name}.tmpl" for name in sorted(dropins)),
    "scripts/tether/bluetooth-experimental.conf",
):
    target = source / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo / relative, target)

# Synthetic runtime files ensure ignores work, not just that today's source omits them.
runtime_sources = {
    "dot_config/private_tether/private_cert.pem": ".config/tether/cert.pem",
    "dot_config/private_tether/private_key.pem": ".config/tether/key.pem",
    "dot_config/private_tether/private_known_hosts.json": ".config/tether/known_hosts.json",
    "dot_config/private_tether/private_future.json": ".config/tether/future.json",
    "dot_config/private_tether/nested/private_state.json": ".config/tether/nested/state.json",
    "dot_local/share/tether/private_state.json": ".local/share/tether/state.json",
    "dot_local/state/tether/private_state.json": ".local/state/tether/state.json",
    "dot_config/systemd/user/default.target.wants/tetherd.service":
        ".config/systemd/user/default.target.wants/tetherd.service",
}
for relative in runtime_sources:
    target = source / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("fake runtime state\n")

def run(command, env):
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"{command}\n{result.stderr}"
    return result.stdout

def fixture(name, shell="dms", graphical=True, niri=True, tether=True, mode=None):
    case = task / name
    home = case / "home"
    home.mkdir(parents=True)
    data = {
        "role": "desktop", "shell": "zsh", "graphical": graphical,
        "niri": niri, "niriOutputProfile": "auto", "secretBackend": "rbw",
        "work": False,
    }
    if shell is not None:
        data["desktopShell"] = shell
    if tether is not None:
        data["tether"] = tether
    if mode is not None:
        data["tetherMode"] = mode
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
        "PATH": str(repo / "tests/fixtures/pi/bin") + os.pathsep + os.environ["PATH"],
    }
    command = [
        "chezmoi", "--config", str(config), "--source", str(source),
        "--destination", str(home), "--persistent-state", str(case / "state.boltdb"),
    ]
    return home, env, command

tether_target = ".config/tether/bluetooth.json"
unit_targets = {f".config/systemd/user/tetherd.service.d/{name}" for name in dropins}
tether_targets = {tether_target} | unit_targets
dms_target = ".config/DankMaterialShell/settings.json"
rule = {
    "enabled": True, "field": "desktopEntry", "pattern": "tether-gtk",
    "matchType": "exact", "action": "no_history", "urgency": "default",
    "bypassDnd": False,
}
unrelated_rules = [
    {"field": "appName", "pattern": "tether-gtk", "matchType": "exact", "action": "ignore"},
    {"field": "desktopEntry", "pattern": "tether-gtk", "matchType": "regex", "action": "ignore"},
    {"field": "desktopEntry", "pattern": "tether-gtk-helper", "matchType": "exact"},
    {"field": "summary", "pattern": "private", "matchType": "contains", "futureRule": True},
]
old_rules = [
    unrelated_rules[0], {**rule, "pattern": "TETHER-GTK", "action": "ignore", "oldOption": 1},
    *unrelated_rules[1:], {**rule, "enabled": False},
]
dms_existing = {
    "futurePreference": {"value": "keep"}, "networkPreference": "ethernet",
    "notificationRules": old_rules,
}
for shell, graphical, niri, tether, mode in itertools.product(
    (None, "custom", "dms"), (False, True), (False, True), (None, False, True),
    (None, "notifications", "wifi-clipboard"),
):
    home, env, command = fixture(
        f"matrix-{shell}-{graphical}-{niri}-{tether}-{mode}", shell, graphical, niri, tether, mode,
    )
    inventory = set(run(command + [
        "managed", "--include=files", "--path-style=relative",
    ], env).splitlines())
    dms_active = graphical and niri and shell == "dms"
    expected = ({dms_target} if dms_active else set()) | (
        tether_targets if dms_active and tether is True else set()
    )
    assert inventory == expected, (shell, graphical, niri, tether, inventory, expected)
    ignored = set(run(command + [
        "execute-template", "--file", str(source / ".chezmoiignore"),
    ], env).splitlines())
    assert "scripts/" in ignored
    assert ".local/share/tether/" in ignored and ".local/state/tether/" in ignored
    rendered = run(command + [
        "execute-template", "--file", str(source / "dot_config/DankMaterialShell/modify_settings.json.tmpl"),
    ], env)
    rendered_modifier = home / "dms-modifier.py"
    rendered_modifier.write_text(rendered)
    after_text = transform(rendered_modifier, json.dumps(dms_existing))
    after = strict_json(after_text)
    active = dms_active and tether is True
    assert after["notificationRules"] == ([rule, *unrelated_rules] if active else old_rules)
    assert after["futurePreference"] == dms_existing["futurePreference"]
    assert after["networkPreference"] == dms_existing["networkPreference"]
    assert transform(rendered_modifier, after_text) == after_text
    default = strict_json(transform(rendered_modifier, ""))
    if active:
        check_dropins({
            name: run(command + [
                "execute-template", "--file", str(dropin_source / f"{name}.tmpl"),
            ], env) for name in dropins
        }, mode)
        assert default["notificationRules"] == [rule]
        for invalid in (None, {}, [None], ["rule"]):
            transform(rendered_modifier, json.dumps({"notificationRules": invalid}), success=False)
    else:
        assert "notificationRules" not in default

home, env, command = fixture("apply-fresh")
(home / dms_target).parent.mkdir(parents=True)
(home / ".config/systemd/user/tetherd.service.d").mkdir(parents=True)
run(command + ["apply", "--exclude=scripts,encrypted", *(
    str(home / target) for target in sorted(unit_targets | {dms_target, ".config/tether"})
)], env)
target = home / tether_target
assert stat.S_IMODE(target.stat().st_mode) == 0o600
assert stat.S_IMODE(target.parent.stat().st_mode) == 0o700
assert strict_json(target.read_text()) == fresh
assert strict_json((home / dms_target).read_text())["notificationRules"] == [rule]
assert all(not (home / relative).exists() for relative in runtime_sources.values())
check_dropins({name: (home / ".config/systemd/user/tetherd.service.d" / name).read_text()
               for name in dropins}, None)
target.write_text(json.dumps(runtime))
run(command + ["apply", "--force", "--exclude=scripts,encrypted", str(target)], env)
assert strict_json(target.read_text()) == existing
assert stat.S_IMODE(target.stat().st_mode) == 0o600
assert stat.S_IMODE(target.parent.stat().st_mode) == 0o700

config = Path(command[command.index("--config") + 1])
base_config = config.read_text()
for mode in ("wifi-clipboard", "notifications", "wifi-clipboard", None):
    config.write_text(base_config + (f'tetherMode = "{mode}"\n' if mode else ""))
    targets = [str(home / path) for path in sorted(tether_targets | {dms_target})]
    run(command + ["apply", "--force", "--exclude=scripts,encrypted", *targets], env)
    check_dropins({name: (home / ".config/systemd/user/tetherd.service.d" / name).read_text()
                   for name in dropins}, mode)
    assert {p.name for p in (home / ".config/systemd/user/tetherd.service.d").iterdir()} == dropins
    assert strict_json(target.read_text()) == existing
    assert strict_json((home / dms_target).read_text())["notificationRules"] == [rule]
    before = {path: (home / path).read_bytes() for path in tether_targets | {dms_target}}
    run(command + ["apply", "--force", "--exclude=scripts,encrypted", *targets], env)
    assert before == {path: (home / path).read_bytes() for path in before}
    assert not run(command + ["diff", "--exclude=scripts,encrypted", *targets], env)

for mode in ("unknown", "", False, 1):
    for enabled in (False, True):
        _, invalid_env, invalid_command = fixture(
            f"invalid-{mode!r}-{enabled}", tether=enabled, mode=mode,
        )
        for args in (
            ["managed", "--include=files"],
            *(["execute-template", "--file", str(dropin_source / f"{name}.tmpl")]
              for name in sorted(dropins)),
        ):
            result = subprocess.run(invalid_command + args, env=invalid_env, capture_output=True, text=True)
            assert result.returncode != 0, (mode, enabled, args, result.stdout)
            assert "tetherMode must be notifications or wifi-clipboard" in result.stderr
            assert not result.stdout

for (shell, graphical, niri, enabled), mode in itertools.product((
    ("dms", True, True, False), ("dms", True, True, True),
    ("custom", True, True, True), ("dms", True, False, True),
    ("dms", False, True, True),
), (None, "notifications", "wifi-clipboard")):
    init_home, init_env, _ = fixture(f"init-{shell}-{graphical}-{niri}-{enabled}-{mode}")
    empty = init_home / "empty.toml"
    empty.write_text("")
    rendered = run([
        "chezmoi", "--config", str(empty), "--source", str(source),
        "execute-template", "--init", "--promptChoice",
        f"Machine role=desktop,Default shell=zsh,Desktop shell: DMS or custom components={shell},"
        "Niri output profile=auto,SSH authorized_keys identity=none"
        + (f",Tether mode={mode}" if mode else ""),
        "--promptBool", f"Graphical machine={str(graphical).lower()},Use niri={str(niri).lower()},Work machine=false,"
        "Use rbw SSH agent=false,Use recoverable rm wrapper=false,"
        f"Use Tether iPhone notifications={str(enabled).lower()}",
        "--file", str(source / ".chezmoi.toml.tmpl"),
    ], init_env)
    expected = graphical and niri and shell == "dms" and enabled
    rendered_data = tomllib.loads(rendered)["data"]
    assert rendered_data["tether"] is expected
    assert rendered_data["tetherMode"] == (mode if expected and mode else "notifications")
assert re.search(
    r'promptBoolOnce\s+\.\s+"tether"\s+"Use Tether iPhone notifications"\s+false',
    (repo / ".chezmoi.toml.tmpl").read_text(),
)

print(f"Tether checks passed (retained fixtures: {task})")
PY
