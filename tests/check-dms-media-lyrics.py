import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare", repo / "scripts/prepare-dms-media-lyrics.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)

scratch_root = Path.home() / ".local/state/agents/tmp"
scratch_root.mkdir(parents=True, exist_ok=True)
task = Path(tempfile.mkdtemp(prefix="check-dms-media-lyrics.", dir=scratch_root))
source = task / "source"
data = task / "data"
chrome = source / prepare.CHROME_PATH
chrome.parent.mkdir(parents=True)
chrome.write_text("approved chrome fixture\n")
(source / "shell.qml").write_text("approved shell fixture\n")
(source / "VERSION").write_text("v1.6.2\n")
(source / "untouched.qml").write_text("keep this file\n")
originals = {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()}

assert prepare.VERSION == "v1.6.2"
assert set(prepare.BASE_HASHES) == {"shell.qml", prepare.CHROME_PATH}
assert all(len(value) == 64 for value in prepare.BASE_HASHES.values())
prepare.BASE_HASHES = {
    relative: hashlib.sha256((source / relative).read_bytes()).hexdigest()
    for relative in prepare.BASE_HASHES
}
generation = prepare.prepare(source, data, task / "builds")
current = data / "dms-media-lyrics/current"
assert current.resolve() == generation
assert (generation / prepare.CHROME_PATH).read_bytes() == (
    repo / "scripts/dms-media-lyrics/MediaPlayerDashChrome.qml"
).read_bytes()
assert (generation / "untouched.qml").read_bytes() == (source / "untouched.qml").read_bytes()
assert (generation / ".dms-version").read_text() == "dms v1.6.2\n"
assert (generation / "MEDIA-LYRICS-LICENSE").read_bytes() == (
    repo / "scripts/dms-media-lyrics/LICENSE"
).read_bytes()
assert {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()} == originals


def expect_rejected():
    old_target = current.resolve()
    try:
        prepare.prepare(source, data, task / "builds")
    except ValueError:
        pass
    else:
        raise AssertionError("Expected source validation failure")
    assert current.resolve() == old_target


(source / "VERSION").write_text("v1.7.0\n")
expect_rejected()
(source / "VERSION").write_text("v1.6.2\n")
chrome.write_text("unexpected core changes\n")
expect_rejected()
chrome.write_bytes(originals[Path(prepare.CHROME_PATH)])
link = source / "external.qml"
link.symlink_to(task / "outside")
expect_rejected()
link.unlink()
next_generation = prepare.prepare(source, data, task / "builds")
assert next_generation != generation
assert current.resolve() == next_generation
assert generation.is_dir()
assert len(list((task / "builds").glob("*/shell/shell.qml"))) == 2

blocked_data = task / "blocked"
(blocked_data / "dms-media-lyrics/current").mkdir(parents=True)
try:
    prepare.prepare(source, blocked_data, task / "blocked-builds")
except ValueError:
    pass
else:
    raise AssertionError("Must not replace an existing directory")
assert not (task / "blocked-builds").exists()

bin_dir = task / "bin"
bin_dir.mkdir()
fake_dms = bin_dir / "dms"
fake_dms.write_text(
    '#!/bin/sh\n'
    'if [ "$1" = version ]; then\n'
    '    printf "%s\\n" "$FAKE_DMS_VERSION"\n'
    'else\n'
    '    printf "%s\\n" "${DMS_SHELL_DIR-unset}" "$@"\n'
    'fi\n'
)
fake_dms.chmod(0o700)
env = {
    **os.environ, "HOME": str(task / "home"), "XDG_DATA_HOME": str(data),
    "PATH": f"{bin_dir}:/usr/bin:/bin", "FAKE_DMS_VERSION": "dms v1.6.2",
    "DMS_SHELL_DIR": "/must-not-leak",
}
launcher = repo / "dot_local/bin/executable_dms-with-lyrics"


def launch():
    return subprocess.run(
        [str(launcher), "run", "-d"], env=env, check=True, capture_output=True, text=True
    )


assert launch().stdout.splitlines() == [str(current), "run", "-d"]
env["FAKE_DMS_VERSION"] = "dms v1.7.0"
result = launch()
assert result.stdout.splitlines() == ["unset", "run", "-d"]
assert "version mismatch" in result.stderr
env["XDG_DATA_HOME"] = str(task / "missing-data")
assert launch().stdout.splitlines() == ["unset", "run", "-d"]
print(f"DMS media overlay offline checks passed (retained fixtures: {task})")
