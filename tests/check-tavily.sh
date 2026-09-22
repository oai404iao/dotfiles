#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

python3 - "$repo_dir" <<'PY'
import json
import os
import pathlib
import shutil
import subprocess
import sys

repo_dir = pathlib.Path(sys.argv[1])
template = repo_dir / "private_dot_tavily/private_config.json.tmpl"

ignore_lines = (repo_dir / ".chezmoiignore").read_text().splitlines()
if ".tavily/session.json" not in ignore_lines:
    raise SystemExit("missing ignore rule for the Tavily session file")
for active in (".tavily", ".tavily/config.json"):
    if active in ignore_lines:
        raise SystemExit(f"managed Tavily config would be ignored: {active}")

if "tvly-" in template.read_text():
    raise SystemExit("Tavily template must not contain a literal API key")

if shutil.which("chezmoi"):
    fake_env = os.environ.copy()
    fake_bin = repo_dir / "tests/fixtures/tavily/bin"
    fake_env["PATH"] = f"{fake_bin}{os.pathsep}{fake_env['PATH']}"
    result = subprocess.run(
        [
            "chezmoi",
            "--config",
            "/dev/null",
            "--config-format",
            "toml",
            "execute-template",
            "--file",
            str(template),
        ],
        text=True,
        capture_output=True,
        check=True,
        env=fake_env,
    )
    if json.loads(result.stdout) != {"api_key": "tvly-test-key"}:
        raise SystemExit("Tavily template did not use the fake rbw value")
PY

printf '%s\n' "Tavily config passed"
