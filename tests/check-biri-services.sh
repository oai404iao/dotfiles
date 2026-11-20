#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_dir=$(
    umask 077
    scratch_root="$HOME/.local/state/agents/tmp"
    mkdir -p -- "$scratch_root"
    mktemp -d "$scratch_root/check-biri-services.XXXXXXXX"
)

python3 - "$repo" "$task_dir" <<'PY'
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

repo, task = map(Path, sys.argv[1:])
headless = "biri-headless.service"
source_unit = repo / "dot_config/systemd/user" / headless
scope = "biri-desktop-sunshine.scope"
stop = ("stop", scope)
enable = ("enable", "--now", headless)
disable = ("disable", "--now", headless)
reload = ("daemon-reload",)

# Only supply the commands needed by the helper; there is no real service CLI in PATH.
bin_dir = task / "bin"
bin_dir.mkdir()
for utility in ("cmp", "dirname", "mkdir", "mktemp", "mv"):
    path = shutil.which(utility)
    assert path is not None, utility
    (bin_dir / utility).symlink_to(Path(path).resolve())
fake = bin_dir / "fake"
fake.write_text(f"#!{sys.executable}\n" + """\
import json
import os
from pathlib import Path
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
case = Path(os.environ["TMPDIR"])
settings = json.loads((case / "settings.json").read_text())
with (case / "calls.jsonl").open("a") as log:
    print(json.dumps([command, *args]), file=log)

def run():
    if command == "chezmoi":
        assert len(args) == 3 and args[:2] == ["execute-template", "--skip-secrets"]
        if args[2] == '{{ get . "biri" }}':
            print(settings["mode"])
        else:
            assert args[2] == "{{ .chezmoi.destDir }}"
            print(settings["destination"])
        return 0
    if command == "id":
        assert args == ["-u"]
        print("1000")
        return 0
    if command == "niri":
        assert args == ["validate", "--config", settings["kdl"]]
        return settings.get("validate_status", 0)
    if command == "pgrep":
        assert len(args) == 4 and args[:3] == ["-u", "1000", "-x"]
        assert set(args[3].split("|")) == {"niri", "dms", "sunshine"}
        return settings.get("pgrep_status", 1)
    if command == "systemctl":
        assert args[0] == "--user"
        if args[1:3] == ["show", "-p"]:
            _, _, _, prop, flag, unit = args
            assert flag == "--value"
            if (case / "reloaded").exists() and prop in settings["after_reload"]:
                print(settings["after_reload"][prop])
            elif (case / "disabled").exists() and unit == "biri-headless.service" and prop == "ActiveState":
                print(settings["headless_after_disable"])
            else:
                print(settings["properties"][unit][prop])
            return 0
        assert args[1:] in settings["operations"]
        if args[1] == "daemon-reload":
            assert Path(settings["unit"]).is_file() == settings["reload_with_unit"]
            (case / "reloaded").touch()
        if args[1] == "disable":
            for path in (settings["unit"], settings["kdl"]):
                assert Path(path).is_file() == (Path(path).name not in settings["absent"])
            status = settings.get("disable_status", 0)
            if status == 0:
                (case / "disabled").touch()
            return status
        return 0
    raise AssertionError(command)

try:
    sys.exit(run())
except (AssertionError, IndexError, KeyError, ValueError):
    (case / "unexpected").touch()
    raise
""")
fake.chmod(0o700)
for command in ("chezmoi", "id", "niri", "pgrep", "systemctl"):
    (bin_dir / command).symlink_to(fake)


def files_under(root):
    return {
        path: ("link", os.readlink(path)) if path.is_symlink()
        else (stat.S_IMODE(path.stat().st_mode), path.read_bytes())
        for path in root.rglob("*") if path.is_symlink() or path.is_file()
    }


def check(name, mode, *, args=("--apply",), success=True, archived=(), operations=(),
          absent=(), symlink=None, custom_state=False, stale_scope=False,
          desktop_state="inactive", headless_state="inactive", headless_after_disable="inactive",
          fragment=None, fragment_after_reload=None, validated=False, alternate_destination=False,
          alternate_config=False, symlink_dir=None, foreign_unit=False, drop_in=False,
          drop_in_after_reload=False, stale_headless=None, **statuses):
    case = task / name
    home = case / "home with space"
    config = home / ".config"
    state = home / ("custom state" if custom_state else ".local/state")
    unit = config / "systemd/user" / headless
    kdl = config / "biri/headless.kdl"
    backup_root = state / "deployment-backups/biri"
    targets = {path.name: path for path in (unit, kdl)}
    for path in (
        *targets.values(), kdl.with_name("local.kdl"), unit.with_name("local.service"),
        config / "sunshine/sunshine.conf", config / "sunshine/sunshine_state.json",
        config / "sunshine/credentials/cakey.pem", config / "niri/config.kdl",
        config / "chezmoi/chezmoi.toml",
    ):
        if path.name not in absent:
            path.parent.mkdir(parents=True, exist_ok=True)
            if path == unit:
                shutil.copyfile(source_unit, path)
            else:
                path.write_text(f"fixture: {path.name}\n")
            path.chmod(0o644)
    if foreign_unit:
        with unit.open("a") as modified:
            modified.write("Also=local.service\n")
    drop_in_path = ""
    if drop_in or drop_in_after_reload:
        path = unit.with_name(headless + ".d") / "10-local.conf"
        path.parent.mkdir()
        path.write_text("[Service]\nEnvironment=FIXTURE=1\n")
        drop_in_path = str(path)
    if stale_headless == "enabled":
        link = unit.parent / "default.target.wants" / headless
        link.parent.mkdir()
        link.symlink_to(unit)
    if symlink is not None:
        path = targets[symlink]
        path.unlink()
        path.symlink_to(path.with_name("local.kdl" if path == kdl else "local.service"))
    if symlink_dir is not None:
        path = config / symlink_dir
        redirected = home / "redirected directory"
        path.rename(redirected)
        path.symlink_to(redirected, target_is_directory=True)
    destination = home
    if alternate_destination:
        destination = home / "alternate destination"
        destination.mkdir()
    before = files_under(home)
    if fragment is None:
        fragment = str(unit) if unit.is_file() or stale_headless == "loaded" else ""
    settings = dict(
        mode=mode, destination=str(destination), unit=str(unit), kdl=str(kdl),
        absent=absent, operations=operations,
        reload_with_unit=(mode == "headless"), headless_after_disable=headless_after_disable,
        after_reload={
            "FragmentPath": str(unit) if fragment_after_reload is None else fragment_after_reload,
            "DropInPaths": drop_in_path,
        },
        properties={
            headless: {
                "FragmentPath": fragment, "ActiveState": headless_state,
                "DropInPaths": drop_in_path if drop_in else "",
            },
            "niri.service": {"ActiveState": desktop_state},
            scope: {"LoadState": "loaded" if stale_scope else "not-found"},
        },
        **statuses,
    )
    (case / "settings.json").write_text(json.dumps(settings))
    env = {"HOME": str(home), "PATH": str(bin_dir), "TMPDIR": str(case), "LC_ALL": "C"}
    if custom_state:
        env["XDG_STATE_HOME"] = str(state)
        env["XDG_CONFIG_HOME"] = str(config)
    if alternate_config:
        env["XDG_CONFIG_HOME"] = str(home / "alternate config")
    result = subprocess.run([repo / "scripts/biri", *args], cwd=case, env=env,
                            capture_output=True, text=True, timeout=15)
    assert not (case / "unexpected").exists(), (name, result.stderr)
    assert (result.returncode == 0) == success, (name, result.stdout, result.stderr)
    calls_file = case / "calls.jsonl"
    calls = [json.loads(line) for line in calls_file.read_text().splitlines()] if calls_file.exists() else []
    actual_ops = [tuple(call[2:]) for call in calls if call[0] == "systemctl" and call[2] != "show"]
    assert actual_ops == list(operations), (name, calls)
    validation = [call for call in calls if call[0] == "niri"]
    assert validation == ([["niri", "validate", "--config", str(kdl)]] if validated else []), (name, calls)
    if args == () or mode not in ("headless", "desktop", "none"):
        assert [call[0] for call in calls] == ["chezmoi"], (name, calls)
    if alternate_destination or alternate_config or symlink_dir is not None:
        assert not any(call[0] == "systemctl" for call in calls), (name, calls)
    if not args:
        assert f'"{mode}"' in result.stdout, (name, result.stdout)

    after = files_under(home)
    if archived:
        backup_files = files_under(backup_root)
        assert sorted(path.name for path in backup_files) == sorted(archived), (name, backup_files)
        for path in backup_files:
            assert not path.is_symlink() and path.read_bytes() == before.pop(targets[path.name])[1]
            assert stat.S_IMODE(path.parent.stat().st_mode) & 0o077 == 0, path.parent
            del after[path]
    else:
        assert not backup_root.exists(), (name, backup_root)
    assert after == before, (name, sorted(map(str, before)), sorted(map(str, after)))


for mode in ("headless", "desktop", "none"):
    check(f"preview-{mode}", mode, args=(), stale_scope=True)
    check(f"unexpected-fragment-{mode}", mode, success=False,
          fragment="/usr/lib/systemd/user/biri-headless.service", stale_scope=True)
    check(f"local-unit-{mode}", mode, success=False, foreign_unit=True, stale_scope=True)
    check(f"drop-in-{mode}", mode, success=False, drop_in=True, stale_scope=True)
for mode in ("", "unknown"):
    check(f"invalid-mode-{mode}", mode, success=False)
check("alternate-destination", "none", success=False, alternate_destination=True, stale_scope=True)
check("alternate-config", "none", success=False, alternate_config=True, stale_scope=True)
for folder in (".", "biri", "systemd", "systemd/user"):
    check(f"symlink-dir-{folder.replace('/', '-')}", "none", success=False, symlink_dir=folder,
          stale_scope=True)

check("headless", "headless", stale_scope=True, validated=True, operations=(stop, reload, enable))
check("headless-new-unit", "headless", fragment="", validated=True, operations=(reload, enable))
for name in (headless, "headless.kdl"):
    check(f"missing-{name}", "headless", absent=(name,), success=False)
    check(f"symlink-{name}", "headless", symlink=name, success=False)
check("invalid-kdl", "headless", validated=True, validate_status=1, success=False, stale_scope=True)
check("regular-niri", "headless", validated=True, desktop_state="active", success=False, stale_scope=True)
check("unmanaged-process", "headless", validated=True, pgrep_status=0, success=False)
check("process-query-error", "headless", validated=True, pgrep_status=2, success=False)
check("fragment-changed-on-reload", "headless", validated=True, success=False, operations=(reload,),
      fragment_after_reload="/usr/lib/systemd/user/biri-headless.service")
check("drop-in-loaded-on-reload", "headless", validated=True, success=False, operations=(reload,),
      drop_in_after_reload=True)

check("desktop", "desktop", stale_scope=True, headless_state="active", operations=(disable, reload),
      archived=(headless, "headless.kdl"))
check("none", "none", stale_scope=True, custom_state=True, operations=(disable, stop, reload),
      archived=(headless, "headless.kdl"))
check("none-uninstalled", "none", absent=(headless, "headless.kdl"))
check("none-kdl-only", "none", absent=(headless,), archived=("headless.kdl",))
for stale in ("enabled", "loaded"):
    check(f"missing-but-{stale}", "none", success=False, stale_headless=stale, absent=(headless,),
          stale_scope=True)
for mode in ("desktop", "none"):
    check(f"disable-failed-{mode}", mode, success=False, stale_scope=True,
          operations=(disable,), disable_status=1)
check("stop-not-effective", "none", stale_scope=True, headless_state="active",
      headless_after_disable="active", success=False, operations=(disable,))

print(f"Biri offline service checks passed ({task})")
PY
