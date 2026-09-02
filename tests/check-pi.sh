#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_dir/dot_config/private_pi/agent"

python3 - "$source_dir" <<'PY'
import json
import os
import pathlib
import shutil
import subprocess
import sys

source_dir = pathlib.Path(sys.argv[1])
repo_dir = source_dir.parents[2]

expected = {
    "modify_private_settings.json",
    "private_models.json",
    "private_keybindings.json",
    "private_subagent.json.tmpl",
    "agents/private_planner.md",
    "agents/private_scout.md",
    "agents/private_reviewer.md",
    "agents/private_worker.md",
    "extensions/pi-codex-minimal-tools/private_config.json.tmpl",
    "extensions/pi-codex-minimal-tools/private_models.json.tmpl",
    "extensions/pi-subagent/private_config.json.tmpl",
    "extensions/pi-telegram-notify/private_config.json.tmpl",
}
actual = {
    str(path.relative_to(source_dir))
    for path in source_dir.rglob("*")
    if path.is_file()
}
if actual != expected:
    raise SystemExit(
        f"unexpected Pi source inventory: missing={sorted(expected - actual)}, "
        f"extra={sorted(actual - expected)}"
    )

expected_ignored = {
    ".config/pi/agent/auth.json",
    ".config/pi/agent/trust.json",
    ".config/pi/agent/models-store.json",
    ".config/pi/agent/external-thinking.json",
    ".config/pi/agent/npm/",
    ".config/pi/agent/git/",
    ".config/pi/agent/bin/",
    ".config/pi/agent/pi-codex-minimal-tools/",
    ".config/pi/agent/.pi-subagent/",
    ".config/pi/agent/sessions/",
    ".config/pi/agent/recovery-fragments/",
    ".config/pi/agent/extensions/pi-permission-system/config.json",
    ".config/pi/agent/extensions/pi-permission-system/logs/",
    ".config/pi/agent/workflows/model-tiers.json",
    ".config/pi/agent/workflows/projects/",
}
ignore_lines = set((repo_dir / ".chezmoiignore").read_text().splitlines())
if not expected_ignored <= ignore_lines:
    raise SystemExit(
        f"missing Pi ignore rules: {sorted(expected_ignored - ignore_lines)}"
    )


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(text):
    return json.loads(text, object_pairs_hook=unique_object)


for path in source_dir.rglob("*.json"):
    if not path.name.startswith("modify_"):
        load_json(path.read_text())

settings_modifier = source_dir / "modify_private_settings.json"
compile(settings_modifier.read_text(), str(settings_modifier), "exec")
settings_result = subprocess.run(
    [sys.executable, str(settings_modifier)],
    input='{"lastChangelogVersion":"preserve-me","futureState":true}',
    text=True,
    capture_output=True,
    check=True,
)
settings = load_json(settings_result.stdout)
if settings.get("lastChangelogVersion") != "preserve-me" or settings.get("futureState") is not True:
    raise SystemExit("Pi settings modifier did not preserve mutable state")
package_sources = {
    package if isinstance(package, str) else package["source"]
    for package in settings["packages"]
}
expected_npm_packages = {
    "npm:@juicesharp/rpiv-ask-user-question@1.20.0",
    "npm:@oai404iao/pi-telegram-notify@0.1.3",
    "npm:@oai404iao/pi-keep-defaults@0.1.3",
    "npm:@oai404iao/pi-codex-minimal-tools@1.4.0",
    "npm:@oai404iao/pi-subagent@0.3.0",
}
actual_npm_packages = {
    source for source in package_sources if source.startswith("npm:")
}
if actual_npm_packages != expected_npm_packages:
    raise SystemExit("Pi npm package versions are not pinned")

models = json.loads((source_dir / "private_models.json").read_text())
references = [
    provider.get("apiKey")
    for provider in models.get("providers", {}).values()
]
expected_reference = "!rbw get 'pi spiredive api key'"
if references != [expected_reference] * 4:
    raise SystemExit("Pi provider credentials are not using the expected rbw reference")

for forbidden in (
    "auth.json",
    "trust.json",
    "models-store.json",
    "installation_id",
    "agents-manifest.json",
    "external-thinking.json",
):
    if any(path.name == forbidden for path in source_dir.rglob("*")):
        raise SystemExit(f"generated Pi state is managed unexpectedly: {forbidden}")

if shutil.which("chezmoi"):
    execute_template = [
        "chezmoi",
        "--config",
        "/dev/null",
        "--config-format",
        "toml",
        "execute-template",
        "--file",
    ]
    templates = (
        "private_subagent.json.tmpl",
        "extensions/pi-codex-minimal-tools/private_config.json.tmpl",
        "extensions/pi-codex-minimal-tools/private_models.json.tmpl",
        "extensions/pi-subagent/private_config.json.tmpl",
    )
    for relative in templates:
        result = subprocess.run(
            [*execute_template, str(source_dir / relative)],
            text=True,
            capture_output=True,
            check=True,
        )
        load_json(result.stdout)

    fake_env = os.environ.copy()
    fake_bin = repo_dir / "tests/fixtures/pi/bin"
    fake_env["PATH"] = f"{fake_bin}{os.pathsep}{fake_env['PATH']}"
    result = subprocess.run(
        [
            *execute_template,
            str(source_dir / "extensions/pi-telegram-notify/private_config.json.tmpl"),
        ],
        text=True,
        capture_output=True,
        check=True,
        env=fake_env,
    )
    telegram = load_json(result.stdout)
    if telegram["botToken"] != "123456:test-token" or telegram["chatId"] != "-123456789":
        raise SystemExit("Telegram template did not use the fake rbw values")
PY

printf '%s\n' "Pi configs passed"
