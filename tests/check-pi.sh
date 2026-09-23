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
    "private_AGENTS.md",
    "modify_private_settings.json",
    "private_models.json",
    "private_keybindings.json",
    "private_subagent.json.tmpl",
    "exact_agents/private_scout.md",
    "exact_agents/private_reviewer.md",
    "extensions/pi-codex-minimal-tools/private_config.json.tmpl",
    "extensions/pi-codex-minimal-tools/private_models.json.tmpl",
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
    ".local/state/pi/agent/sessions/",
    ".local/state/agents/tmp/",
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

instructions = (source_dir / "private_AGENTS.md").read_text()
for required in (
    "## Coding principles",
    "## Tool selection",
    "uv run python",
    "uv run --with <package> python ...",
    "--no-project",
    "pnpm dlx <package>",
    "pnpm exec <command>",
    "Honor explicit\n  project requirements and canonical scripts;",
    "Avoid `/tmp`, `/var/tmp`, and bare `mktemp`",
    '$HOME/.local/state/agents/tmp',
    'mktemp -d "$scratch_root/task-name.XXXXXXXX"',
    "umask 077",
    "Leave task directories and their contents in place after use.",
    "Do not store credentials in retained scratch files.",
):
    if required not in instructions:
        raise SystemExit(f"missing global agent rule: {required}")
scratch_example = instructions.split("```sh\n", 1)[1].split("```", 1)[0]
subprocess.run(["sh", "-n"], input=scratch_example, text=True, check=True)


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
if settings.get("defaultThinkingLevel") != "high":
    raise SystemExit("Pi default thinking level is not high")
if settings.get("defaultProvider") != "openai" or settings.get("defaultModel") != "gpt-6-astra":
    raise SystemExit("Pi default model is not openai/gpt-6-astra")
if "openai/gpt-6-astra" not in settings.get("enabledModels", []):
    raise SystemExit("GPT-6 Astra is not enabled in Pi settings")
if not {"openai/gpt-6-sol", "openai/gpt-6-luna"} <= set(
    settings.get("enabledModels", [])
):
    raise SystemExit("GPT-6 Sol/Luna are not enabled in Pi settings")
enabled_models = set(settings.get("enabledModels", []))
expected_deepseek_models = {
    "deepseek/deepseek-flash",
}
enabled_deepseek_models = {
    model for model in enabled_models if model.startswith("deepseek/")
}
if enabled_deepseek_models != expected_deepseek_models:
    raise SystemExit("unexpected enabled DeepSeek model inventory")
if any(model.startswith("openai/deepseek-") for model in enabled_models):
    raise SystemExit("DeepSeek models remain enabled under the OpenAI provider")

scout_text = (source_dir / "exact_agents/private_scout.md").read_text()
scout_frontmatter = {
    key.strip(): value.strip()
    for line in scout_text.split("---", 2)[1].splitlines()
    if ":" in line
    for key, value in [line.split(":", 1)]
}
if scout_frontmatter.get("model") != "deepseek/deepseek-flash":
    raise SystemExit("Pi scout does not use DeepSeek Flash")
if scout_frontmatter.get("thinking") != "high":
    raise SystemExit("Pi scout thinking level is not high")

package_sources = {
    package if isinstance(package, str) else package["source"]
    for package in settings["packages"]
}
expected_npm_packages = {
    "npm:@juicesharp/rpiv-ask-user-question@2.11.0",
    "npm:@oai404iao/pi-telegram-notify@0.5.0",
    "npm:@oai404iao/pi-codex-minimal-tools@4.0.0",
    "npm:@oai404iao/pi-subagent@0.6.0",
}
actual_npm_packages = {
    source for source in package_sources if source.startswith("npm:")
}
if actual_npm_packages != expected_npm_packages:
    raise SystemExit("Pi npm package versions are not pinned")

models = json.loads((source_dir / "private_models.json").read_text())
providers = models.get("providers", {})
expected_providers = {"deepseek", "openai", "xai"}
if set(providers) != expected_providers:
    raise SystemExit("unexpected Pi provider inventory")
if any("apiKey" in provider for provider in providers.values()):
    raise SystemExit("Pi provider credentials must stay in local auth.json")
openai = providers["openai"]
deepseek = providers["deepseek"]
expected_context_overrides = {
    "gpt-5.6-luna": 350000,
    "gpt-5.6-sol": 350000,
    "gpt-5.6-terra": 350000,
    "gpt-6-astra": 350000,
    "gpt-6-luna": 350000,
    "gpt-6-sol": 350000,
}
actual_context_overrides = {
    model_id: override.get("contextWindow")
    for model_id, override in openai.get("modelOverrides", {}).items()
}
if actual_context_overrides != expected_context_overrides:
    raise SystemExit("unexpected GPT-5.6/GPT-6 context overrides")
custom_openai_models = {
    model["id"]: model
    for model in openai.get("models", [])
}
if set(custom_openai_models) != {"gpt-5.6-sol-cyber"}:
    raise SystemExit("unexpected custom OpenAI model inventory")
if custom_openai_models["gpt-5.6-sol-cyber"].get("contextWindow") != 350000:
    raise SystemExit("GPT-5.6 Sol Cyber context window is not 350K")
if "models" in deepseek:
    raise SystemExit("DeepSeek provider must use Pi's built-in model catalog")

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
    )
    for relative in templates:
        result = subprocess.run(
            [*execute_template, str(source_dir / relative)],
            text=True,
            capture_output=True,
            check=True,
        )
        rendered = load_json(result.stdout)
        package = (
            "pi-subagent@0.6.0"
            if relative == "private_subagent.json.tmpl"
            else "pi-codex-minimal-tools@4.0.0"
        )
        schema = "models" if relative.endswith("private_models.json.tmpl") else "config"
        if rendered.get("$schema") != f"https://unpkg.com/@oai404iao/{package}/{schema}.schema.json":
            raise SystemExit(f"schema version does not match the pinned package: {relative}")
        if relative == "private_subagent.json.tmpl":
            retired_keys = {
                "defaultBackground",
                "enableRunInBackground",
                "reportDelivery",
                "syncBundledAgents",
            }
            if rendered.get("runtimeMode") != "foreground":
                raise SystemExit("Pi subagent runtime is not foreground-only")
            if retired_keys & rendered.keys():
                raise SystemExit("Pi subagent config retains retired settings")
        elif relative == "extensions/pi-codex-minimal-tools/private_config.json.tmpl":
            deprecated_keys = {
                "nativeProviderTools",
                "openaiTransport",
                "openaiWebSocketPrewarm",
                "compactionMode",
                "requestProfile",
                "apiKeyMode",
                "webSearchEnabled",
                "viewImage",
                "applyPatchEnabled",
                "additionalModelIds",
            }
            if deprecated_keys & rendered.keys():
                raise SystemExit("Codex tools config retains deprecated settings")
            if rendered.get("webSocketEnabled") is not False:
                raise SystemExit("Codex tools WebSocket transport is enabled")
            if rendered.get("fastMode") is not False:
                raise SystemExit("Codex tools Fast mode is enabled by default")
            if rendered.get("imageGeneration") is not False:
                raise SystemExit("Codex tools image generation is enabled")
        elif relative == "extensions/pi-codex-minimal-tools/private_models.json.tmpl":
            profiles = {
                profile["id"]: profile
                for profile in rendered["models"]
            }
            if set(profiles) != {
                "openai/gpt-5.6-sol",
                "openai/gpt-6-astra",
                "openai/gpt-6-luna",
                "openai/gpt-6-sol",
            }:
                raise SystemExit("unexpected Codex tool profile inventory")
            parent_responses = profiles.get(
                "openai/gpt-5.6-sol", {}
            ).get("responses", {})
            for model_id in (
                "openai/gpt-6-astra",
                "openai/gpt-6-luna",
                "openai/gpt-6-sol",
            ):
                profile = profiles.get(model_id, {})
                responses = profile.get("responses", {})
                if (
                    profile.get("extends") != "openai/gpt-5.6-sol"
                    or responses.get("reasoningSummary") != "auto"
                    or responses.get(
                        "transport", parent_responses.get("transport")
                    ) != "auto"
                ):
                    raise SystemExit(
                        f"{model_id} Codex tool profile is incomplete"
                    )

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
    if telegram.get("$schema") != "https://unpkg.com/@oai404iao/pi-telegram-notify@0.5.0/config.schema.json":
        raise SystemExit("Telegram schema version does not match the pinned package")
    if telegram["botToken"] != "123456:test-token" or telegram["chatId"] != "-123456789":
        raise SystemExit("Telegram template did not use the fake rbw values")
PY

printf '%s\n' "Pi configs passed"
