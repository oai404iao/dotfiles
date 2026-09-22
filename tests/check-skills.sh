#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_dir=$(
    umask 077
    scratch_root="$HOME/.local/state/agents/tmp"
    mkdir -p -- "$scratch_root"
    mktemp -d "$scratch_root/check-skills.XXXXXXXX"
)

python3 - "$repo_dir" "$task_dir" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(sys.argv[1])
task = Path(sys.argv[2])
installer = repo / "scripts/install-skills.py"
compile(installer.read_text(), str(installer), "exec")
home = task / "home"
home.mkdir()
log = task / "npx.jsonl"
manifest = task / "manifest.json"
fake_bin = repo / "tests/fixtures/skills/bin"
env = os.environ.copy()
env.update({
    "HOME": str(home),
    "XDG_CONFIG_HOME": str(home / ".config"),
    "XDG_STATE_HOME": str(home / ".local/state"),
    "XDG_DATA_HOME": str(home / ".local/share"),
    "XDG_CACHE_HOME": str(home / ".cache"),
    "XDG_RUNTIME_DIR": str(task / "runtime"),
    "TMPDIR": str(task),
    "PATH": f"{fake_bin}{os.pathsep}{env['PATH']}",
    "SKILLS_TEST_LOG": str(log),
    "SKILLS_TEST_EXIT": "0",
    "DISABLE_TELEMETRY": "0",
})


def run(*args, success=True, environment=env):
    result = subprocess.run(
        [sys.executable, str(installer), *args],
        env=environment, cwd=task, text=True, capture_output=True,
    )
    if (result.returncode == 0) != success:
        raise SystemExit(f"unexpected installer result: {result.stdout}\n{result.stderr}")
    return result


def write_manifest(sources, version="1.5.26"):
    manifest.write_text(json.dumps({"cliVersion": version, "sources": sources}))


source = {"source": "example/skills", "skills": ["alpha", "beta"]}
second = {"source": "https://example.invalid/team/skills", "skills": ["gamma"]}
write_manifest([])
run("--manifest", str(manifest))
assert not log.exists() and not list(home.iterdir())
run("--dry-run")
assert not log.exists() and not list(home.iterdir())

declared = json.loads((repo / "scripts/skills.json").read_text())
assert declared["sources"] == [
    {"source": "vercel-labs/agent-browser", "skills": ["agent-browser"]},
    {"source": "shadcn/ui", "skills": ["shadcn"]},
    {
        "source": "oai404iao/my_skills",
        "skills": ["agents-md", "frontend-design", "git-branch-development-workflow"],
    },
    {
        "source": "tavily-ai/skills",
        "skills": [
            "tavily-cli",
            "tavily-search",
            "tavily-extract",
            "tavily-map",
            "tavily-crawl",
            "tavily-research",
            "tavily-dynamic-search",
        ],
    },
]

write_manifest([source, second])
no_npx = {**env, "PATH": str(task / "missing-bin")}
preview = run("--manifest", str(manifest), "--dry-run", environment=no_npx)
assert "--global --agent universal --skill alpha beta --yes" in preview.stdout
assert "skills@1.5.26" in preview.stdout
assert not log.exists() and not list(home.iterdir())
run("--manifest", str(manifest), success=False, environment=no_npx)
assert not log.exists() and not list(home.iterdir())

for invalid in (
    [source, source],
    [source, {"source": "example/second", "skills": ["alpha"]}],
    [source, {"source": "example/second", "skills": []}],
    [{"source": "--all", "skills": ["alpha"]}],
    [{"source": "./local-skills", "skills": ["alpha"]}],
    [{"source": "https://user:password@example.invalid/skills", "skills": ["alpha"]}],
    [{"source": "https://example.invalid/skills\u0000", "skills": ["alpha"]}],
    [{"source": "https://example.invalid/skills?token=example", "skills": ["alpha"]}],
    [{"source": "example/skills", "skills": ["*"]}],
    [{"source": "example/skills", "skills": ["--all"]}],
    [{"source": "example/skills", "skills": ["../outside"]}],
    [{"source": "example/skills", "skills": ["alpha;echo unsafe"]}],
    [{"source": "example/skills", "skills": ["alpha"], "extra": True}],
):
    write_manifest(invalid)
    run("--manifest", str(manifest), success=False)
    assert not log.exists() and not list(home.iterdir())
write_manifest([source], version="latest")
run("--manifest", str(manifest), success=False)
for invalid_json in (
    '{"cliVersion":"1.5.26","sources":[],"sources":[]}',
    '{"cliVersion":"1.5.26","sources":{}}',
    '{"cliVersion":"1.5.26","sources":[],"extra":true}',
    '{',
):
    manifest.write_text(invalid_json)
    run("--manifest", str(manifest), success=False)
assert not log.exists() and not list(home.iterdir())

skills = home / ".agents/skills"
skills.mkdir(parents=True)
sentinel = skills / "local-only.txt"
sentinel.write_text("preserve existing content")
write_manifest([source, second])
run("--manifest", str(manifest))
calls = [json.loads(line) for line in log.read_text().splitlines()]
assert len(calls) == 2
for call, entry in zip(calls, [source, second]):
    assert call["args"] == [
        "--yes", "skills@1.5.26", "add", entry["source"],
        "--global", "--agent", "universal", "--skill", *entry["skills"], "--yes",
    ]
    assert call["home"] == str(home)
    assert call["telemetry"] == "1"
    workspace = Path(call["tmpdir"])
    assert workspace.parent == home / ".local/state/agents/tmp"
    assert workspace.is_dir()
    assert workspace.stat().st_mode & 0o777 == 0o700
assert calls[0]["tmpdir"] == calls[1]["tmpdir"]
run("--manifest", str(manifest), success=False, environment={**env, "SKILLS_TEST_EXIT": "23"})
failed_calls = [json.loads(line) for line in log.read_text().splitlines()]
assert len(failed_calls) == 3
assert failed_calls[-1]["tmpdir"] != calls[0]["tmpdir"]
assert sentinel.read_text() == "preserve existing content"
assert env["TMPDIR"] == str(task) and env["DISABLE_TELEMETRY"] == "0"

ignore_lines = set((repo / ".chezmoiignore").read_text().splitlines())
assert {
    ".agents/skills/", ".agents/.skill-lock.json",
    ".local/state/skills/.skill-lock.json", "scripts/", "tests/", "docs/",
} <= ignore_lines
git_ignores = set((repo / ".gitignore").read_text().splitlines())
assert {
    "/.agents/skills/", "/.agents/.skill-lock.json",
    "/.local/state/skills/.skill-lock.json",
    "/dot_agents/skills/", "/dot_agents/dot_skill-lock.json",
    "/dot_local/state/skills/dot_skill-lock.json",
} <= git_ignores
assert not (repo / "dot_agents/skills").exists()
assert not (repo / "dot_agents/dot_skill-lock.json").exists()
assert not (repo / "dot_local/state/skills/dot_skill-lock.json").exists()
PY

printf '%s\n' "skills checks passed (retained fixtures: $task_dir)"
