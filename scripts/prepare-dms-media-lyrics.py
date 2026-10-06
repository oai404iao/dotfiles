#!/usr/bin/env python3
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import tempfile

VERSION = "v1.6.2"
BASE_HASHES = {
    "shell.qml": "e35630e0e47c7ce9530c050ddbf22b9637344081b3aa8ae0163cf3c16aa6ccef",
    "Modules/DankDash/MediaPlayerDashChrome.qml": "b9a1916886d5b946d2aeb29d0cfda20783e7874525f6d982aa22b1bc32d10369",
}
CHROME_PATH = "Modules/DankDash/MediaPlayerDashChrome.qml"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source, data_home, scratch_root):
    source = source.resolve(strict=True)
    if (source / "VERSION").read_text().strip() != VERSION:
        raise ValueError(f"Expected DMS {VERSION}; refusing to reuse this overlay on another version")
    for relative, expected in BASE_HASHES.items():
        if digest(source / relative) != expected:
            raise ValueError(f"Unrecognized DMS source: {relative}")
    if any(path.is_symlink() for path in source.rglob("*")):
        raise ValueError("DMS source must be a complete tree without symlinks")

    runtime = data_home / "dms-media-lyrics"
    current = runtime / "current"
    if current.exists() and not current.is_symlink():
        raise ValueError(f"Refusing to replace non-symlink: {current}")
    overlay = Path(__file__).parent / "dms-media-lyrics"
    scratch_root.mkdir(parents=True, exist_ok=True)
    task = Path(tempfile.mkdtemp(prefix="dms-media-lyrics.", dir=scratch_root))
    staging = task / "shell"
    shutil.copytree(source, staging)
    staging.chmod(0o700)
    chrome = staging / CHROME_PATH
    chrome.chmod(0o600)
    shutil.copyfile(overlay / "MediaPlayerDashChrome.qml", chrome)
    shutil.copyfile(overlay / "LICENSE", staging / "MEDIA-LYRICS-LICENSE")
    (staging / ".dms-version").write_text(f"dms {VERSION}\n")

    runtime.mkdir(parents=True, exist_ok=True)
    generation = runtime / task.name
    shutil.copytree(staging, generation)
    if current.exists() and not current.is_symlink():
        raise ValueError(f"Refusing to replace non-symlink: {current}")
    link = runtime / f".{task.name}.link"
    link.symlink_to(generation.name, target_is_directory=True)
    os.replace(link, current)
    print(f"Prepared DMS media lyrics: {current}")
    print(f"Retained preparation workspace: {task}")
    return generation


def main():
    parser = argparse.ArgumentParser(description="Prepare an offline, version-checked DMS media lyrics overlay.")
    parser.add_argument("source", type=Path, help="Pristine extracted DMS v1.6.2 shell directory")
    args = parser.parse_args()
    home = Path.home()
    data_home = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    prepare(args.source, data_home, home / ".local/state/agents/tmp")


if __name__ == "__main__":
    main()
