#!/usr/bin/env python3
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
SCRIPTS = {
    "absolute": "dot_local/share/nautilus/scripts/executable_复制绝对路径.tmpl",
    "relative": "dot_local/share/nautilus/scripts/executable_复制相对路径.tmpl",
}
COPY_COMMAND = ["wl-copy", "--type", "text/plain;charset=utf-8"]


def render(path, data=None):
    command = [
        "chezmoi", "--config", "/dev/null", "--config-format", "toml",
        "--source", str(REPO),
    ]
    if data is not None:
        command.extend(["--override-data", json.dumps(data)])
    command.extend(["execute-template", "--file", str(REPO / path)])
    return subprocess.run(command, capture_output=True, text=True, check=True).stdout


class NautilusScriptsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scripts = {
            mode: compile(render(path), path, "exec")
            for mode, path in SCRIPTS.items()
        }

    def execute(self, mode, selected=None, current=None, failure=None):
        environment = {"NAUTILUS_SCRIPT_SELECTED_FILE_PATHS": "/ignored/fallback"}
        if selected is not None:
            environment["NAUTILUS_SCRIPT_SELECTED_URIS"] = selected
        if current is not None:
            environment["NAUTILUS_SCRIPT_CURRENT_URI"] = current
        with (
            patch.dict(os.environ, environment, clear=True),
            patch.object(sys, "argv", [SCRIPTS[mode]]),
            patch("subprocess.run", side_effect=failure) as clipboard,
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            status = 0
            try:
                exec(self.scripts[mode], {"__name__": "__main__", "__file__": SCRIPTS[mode]})
            except SystemExit as error:
                status = error.code or 0
        return status, clipboard

    def assert_copy(self, mode, selected, expected, current=None):
        status, clipboard = self.execute(mode, selected, current)
        self.assertEqual(status, 0)
        clipboard.assert_called_once_with(
            COPY_COMMAND, input=expected.encode("utf-8"), check=True,
        )

    def test_empty_selection_leaves_clipboard_unchanged(self):
        for mode in SCRIPTS:
            for selected in (None, ""):
                with self.subTest(mode=mode, selected=selected):
                    status, clipboard = self.execute(mode, selected, "sftp://remote/base")
                    self.assertEqual(status, 0)
                    clipboard.assert_not_called()

    def test_absolute_multiselection_decodes_uri_paths(self):
        self.assert_copy(
            "absolute",
            "file:///home/test/%E6%96%87%E4%BB%B6%20%25%23.txt\n"
            "file://localhost/home/test/second\n",
            "/home/test/文件 %#.txt\n/home/test/second",
            "sftp://remote/ignored",
        )

    def test_absolute_does_not_require_current_uri(self):
        self.assert_copy("absolute", "file:///home/test/file", "/home/test/file")

    def test_relative_paths(self):
        for selected, expected in (
            ("file:///home/test/name", "./name"),
            ("file:///home/test/sub/name", "./sub/name"),
            ("file:///home/other", "../other"),
            ("file:///home/test", "."),
            ("file:///home/test/%E6%96%87%E4%BB%B6%20%25%23.txt", "./文件 %#.txt"),
            ("file://localhost/home/test/name", "./name"),
        ):
            with self.subTest(selected=selected):
                self.assert_copy("relative", selected, expected, "file:///home/test")
        self.assert_copy(
            "relative",
            "file:///home/test/a\nfile:///home/test/sub/b\nfile:///home/other\n",
            "./a\n./sub/b\n../other",
            "file://localhost/home/test/",
        )
        self.assert_copy(
            "relative", "file:///home/test%20dir/name", "./name",
            "file:///home/test%20dir",
        )

    def test_rejects_invalid_selection_before_copying(self):
        for mode in SCRIPTS:
            for invalid in (
                "sftp://remote/home/test/file",
                "https://example.invalid/file",
                "file://remote/home/test/file",
                "file:relative",
                "/home/test/not-a-uri",
                "file:///home/test/line%0Abreak",
                "file:///home/test/line%0Dbreak",
                "file:///home/test/null%00byte",
            ):
                with self.subTest(mode=mode, invalid=invalid):
                    status, clipboard = self.execute(
                        mode, f"file:///home/test/good\n{invalid}\n", "file:///home/test",
                    )
                    self.assertNotEqual(status, 0)
                    clipboard.assert_not_called()

    def test_relative_requires_valid_local_current_uri(self):
        for current in (
            None, "", "sftp://remote/home/test", "file://remote/home/test",
            "file:relative", "/home/test", "file:///home/line%0Abreak",
            "file:///home/line%0Dbreak", "file:///home/null%00byte",
        ):
            with self.subTest(current=current):
                status, clipboard = self.execute("relative", "file:///home/test/file", current)
                self.assertNotEqual(status, 0)
                clipboard.assert_not_called()

    def test_paths_preserve_symlink_spelling(self):
        scratch = Path.home() / ".local/state/agents/tmp"
        scratch.mkdir(parents=True, exist_ok=True)
        task = Path(tempfile.mkdtemp(prefix="check-nautilus-scripts.", dir=scratch))
        target = task / "target"
        target.mkdir()
        (target / "file").touch()
        link = task / "link"
        link.symlink_to(target, target_is_directory=True)
        self.assert_copy("absolute", (link / "file").as_uri(), str(link / "file"))
        self.assert_copy("relative", (link / "file").as_uri(), "./link/file", task.as_uri())
        self.assert_copy("relative", (link / "file").as_uri(), "./file", link.as_uri())

    def test_clipboard_failures_return_nonzero(self):
        for mode in SCRIPTS:
            for failure in (
                FileNotFoundError("wl-copy is unavailable"),
                subprocess.CalledProcessError(1, COPY_COMMAND),
            ):
                with self.subTest(mode=mode, failure=type(failure).__name__):
                    status, clipboard = self.execute(
                        mode, "file:///home/test/file", "file:///home/test", failure,
                    )
                    self.assertNotEqual(status, 0)
                    clipboard.assert_called_once()

    def test_scripts_are_graphical_only(self):
        for graphical in (False, True):
            for niri in (False, True):
                for desktop_shell in ("custom", "dms"):
                    with self.subTest(graphical=graphical, niri=niri, shell=desktop_shell):
                        ignore = render(".chezmoiignore", {
                            "graphical": graphical,
                            "niri": niri,
                            "desktopShell": desktop_shell,
                        }).splitlines()
                        self.assertEqual(
                            ".local/share/nautilus/scripts/" in ignore, not graphical,
                        )


if __name__ == "__main__":
    unittest.main()
