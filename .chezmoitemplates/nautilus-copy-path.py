#!/usr/bin/python3
import os
import posixpath
import subprocess
import sys
from urllib.parse import unquote_to_bytes, urlsplit


def local_path(uri):
    parsed = urlsplit(uri)
    if (
        parsed.scheme != "file"
        or parsed.netloc not in ("", "localhost")
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("Only local file paths are supported")
    path = os.fsdecode(unquote_to_bytes(parsed.path))
    if not path.startswith("/") or any(char in path for char in ("\n", "\r", "\0")):
        raise ValueError("Invalid path or filename containing a line break")
    return path


def main():
    selection = os.environ.get("NAUTILUS_SCRIPT_SELECTED_URIS", "").rstrip("\n")
    if not selection:
        return
    paths = [local_path(uri) for uri in selection.split("\n")]
    if "{{ . }}" == "relative":
        base = local_path(os.environ.get("NAUTILUS_SCRIPT_CURRENT_URI", ""))
        paths = [posixpath.relpath(path, base) for path in paths]
        paths = [
            path if path in (".", "..") or path.startswith("../") else "./" + path
            for path in paths
        ]
    subprocess.run(
        ["wl-copy", "--type", "text/plain;charset=utf-8"],
        input=os.fsencode("\n".join(paths)),
        check=True,
    )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Copy paths: {error}", file=sys.stderr)
        sys.exit(1)
