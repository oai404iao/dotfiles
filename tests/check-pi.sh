#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_dir/dot_config/private_pi/agent"

python3 - "$source_dir" <<'PY'
import http.server
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import tomllib

source_dir = pathlib.Path(sys.argv[1])
repo_dir = source_dir.parents[2]

expected = {
    "modify_private_auth.json",
    "modify_private_settings.json.tmpl",
    "npm/modify_private_pnpm-workspace.yaml",
    "private_models.json",
    "private_keybindings.json",
    "private_subagent.json.tmpl",
    "exact_agents/private_scout.md",
    "exact_agents/private_reviewer.md",
    "exact_agents/private_worker.md",
    "extensions/pi-codex-minimal-tools/private_config.json.tmpl",
    "extensions/pi-codex-minimal-tools/private_models.json.tmpl",
    "extensions/pi-telegram-notify/private_config.json.tmpl",
    "extensions/private_jev.ts",
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
    ".config/pi/agent/trust.json",
    ".config/pi/agent/models-store.json",
    ".config/pi/agent/external-thinking.json",
    ".config/pi/agent/npm/*",
    "!.config/pi/agent/npm/pnpm-workspace.yaml",
    ".config/pi/agent/git/",
    ".config/pi/agent/bin/",
    ".local/share/pi/extensions/",
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
if ".config/pi/agent/npm/" in ignore_lines:
    raise SystemExit("Pi pnpm build policy is hidden by a directory-wide ignore")
if ".config/pi/agent/auth.json" in ignore_lines:
    raise SystemExit("Pi auth command-reference modifier is hidden by an ignore")

external_path = ".config/pi/agent/AGENTS.md"
external_source = (repo_dir / ".chezmoiexternal.toml").read_text()
external = tomllib.loads(external_source).get(external_path)
if external != {
    "type": "file",
    "url": "https://raw.githubusercontent.com/oai404iao/my_skills/main/prompts/pi-global-agents.md",
    "private": True,
    "refreshPeriod": "24h",
}:
    raise SystemExit("Pi global instructions external contract changed unexpectedly")


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

auth_modifier = source_dir / "modify_private_auth.json"
auth_commands = {
    "deepseek": "!rbw get 'pi spiredive api key'",
    "openai": "!rbw get 'pi spiredive api key'",
    "xai": "!rbw get 'pi spiredive api key'",
    "anthropic": "!rbw get 'pi krill api key'",
    "google": "!rbw get 'pi krill api key'",
    "typesafe": "!rbw get 'pi commandcode api key'",
}
auth_defaults = {
    provider: {"type": "api_key", "key": command}
    for provider, command in auth_commands.items()
}
existing_auth = {
    "openai": {"type": "api_key", "key": "synthetic-old-key", "env": {"EXTRA": "keep"}},
    "anthropic": {"type": "api_key", "key": "!old-command", "futureField": True},
    "typesafe": {"type": "api_key", "key": "!old-jev-command", "futureField": "keep"},
    "openai-codex": {
        "type": "oauth", "access": "synthetic-access",
        "refresh": "synthetic-refresh", "expires": 123456789,
    },
    "unrelated": {"type": "api_key", "key": "synthetic-unrelated-key"},
    "futureProvider": {"type": "future", "nested": [True, {"keep": "原样"}]},
}


def modify_auth(old, env=None):
    return subprocess.run(
        [str(auth_modifier)], input=old, text=True, capture_output=True, env=env
    )


for original in ({}, existing_auth):
    expected_auth = {**original, **auth_defaults}
    for provider in auth_commands.keys() & original.keys():
        expected_auth[provider] = {**original[provider], **auth_defaults[provider]}
    inputs = (json.dumps(original),) if original else ("", " \n", "{}")
    for old in inputs:
        result = modify_auth(old)
        if result.returncode or load_json(result.stdout) != expected_auth:
            raise SystemExit("Pi auth modifier changed command references or lost local credentials")
        repeated = modify_auth(result.stdout)
        if repeated.returncode or repeated.stdout != result.stdout:
            raise SystemExit("Pi auth modifier is not idempotent")

invalid_auth = [
    "null", "[]", "true", '"synthetic-secret"', "{synthetic-secret",
    '{"duplicate": 1, "duplicate": 2}',
    '{"unrelated": {"nested": 1, "nested": 2}}',
    '{"unrelated": NaN}', '{"unrelated": Infinity}',
    '{"unrelated": 1e400}', '{"unrelated": -1e400}',
]
for provider in auth_commands:
    for conflict in (None, [], True, "synthetic-secret", {}, {"type": "future"},
                     {"type": "oauth", "access": "synthetic-secret"}):
        invalid_auth.append(json.dumps({provider: conflict}))
for invalid in invalid_auth:
    rejected = modify_auth(invalid)
    if rejected.returncode == 0 or rejected.stdout or "synthetic-secret" in rejected.stderr:
        raise SystemExit("Pi auth modifier accepted unsafe input or exposed credentials")
print("Pi auth command-reference merge and rejection checks passed")

settings_modifier = source_dir / "modify_private_settings.json.tmpl"
telegram_package = "npm:@oai404iao/pi-telegram-notify@1.0.0"
common_packages = {
    "npm:@juicesharp/rpiv-ask-user-question@2.13.9",
    "npm:@oai404iao/pi-codex-minimal-tools@5.1.2",
    "npm:@oai404iao/pi-subagent@1.3.1",
}
expected_defaults = {
    "defaultProvider": "openai",
    "defaultModel": "gpt-6.1-sol",
    "defaultThinkingLevel": "high",
    "defaultTools": ["+codemode"],
    "codemode": {"mode": "on"},
    "hideThinkingBlock": True,
    "enabledModels": [
        "anthropic/claude-opus-5-5",
        "openai/gpt-5.6-sol",
        "openai/gpt-6-astra",
        "openai/gpt-6-luna",
        "openai/gpt-6.1-sol",
        "openai/gpt-6.1-terra",
        "deepseek/deepseek-flash",
        "google/gemini-4-argon",
    ],
    "npmCommand": ["pnpm", "--config.node-linker=hoisted"],
    "theme": "dark",
    "sessionDir": "~/.local/state/pi/agent/sessions",
}


def modify_settings(script, old):
    result = subprocess.run(
        [sys.executable, "-c", script], input=old,
        text=True, capture_output=True, check=True,
    )
    return load_json(result.stdout)


def check_settings(script, notification_package, home):
    existing = {
        "lastChangelogVersion": "preserve-me",
        "futureState": {"preserve": [True, "unknown"]},
        "defaultTools": ["read"],
        "codemode": {"mode": "only", "inlineBudget": 1234, "futureOption": True},
        "npmCommand": ["npm"],
        "packages": [str(home / "Dev/local/omp/pi-extensions/pi-tree-continue")],
    }
    for old in ("", json.dumps(existing)):
        settings = modify_settings(script, old)
        packages = settings.pop("packages")
        package_sources = {
            package if isinstance(package, str) else package["source"]
            for package in packages
        }
        expected_packages = common_packages | {notification_package}
        if package_sources != expected_packages or len(packages) != len(expected_packages):
            raise SystemExit("unexpected Pi package inventory or notification overlap")
        expected = dict(expected_defaults)
        if old:
            expected.update({
                "lastChangelogVersion": existing["lastChangelogVersion"],
                "futureState": existing["futureState"],
                "codemode": {**existing["codemode"], "mode": "on"},
            })
        if settings != expected:
            raise SystemExit("Pi settings defaults or preserved mutable state changed")
        settings["packages"] = packages
        if modify_settings(script, json.dumps(settings)) != settings:
            raise SystemExit("Pi settings modifier is not idempotent")
    return settings

scout_text = (source_dir / "exact_agents/private_scout.md").read_text()
scout_frontmatter = {
    key.strip(): value.strip()
    for line in scout_text.split("---", 2)[1].splitlines()
    if ":" in line
    for key, value in [line.split(":", 1)]
}
if scout_frontmatter.get("model") != "openai/gpt-6-luna":
    raise SystemExit("Pi scout does not use GPT-6 Luna")
if scout_frontmatter.get("thinking") != "high":
    raise SystemExit("Pi scout thinking level is not high")

for name in ("scout", "reviewer", "worker"):
    text = (source_dir / f"exact_agents/private_{name}.md").read_text()
    frontmatter = {
        key.strip(): value.strip()
        for line in text.split("---", 2)[1].splitlines()
        if ":" in line
        for key, value in [line.split(":", 1)]
    }
    if frontmatter.get("name") != name or not frontmatter.get("description"):
        raise SystemExit(f"Pi {name} definition is missing its name or description")
    if name == "worker":
        if {"tools", "model", "thinking"} & frontmatter.keys():
            raise SystemExit("Pi worker must use inherited tool policy, model, and thinking")
    else:
        if frontmatter.get("tools") != "read, grep, find, ls, bash, codemode":
            raise SystemExit(f"Pi {name} ordinary-tool ceiling changed unexpectedly")
        if "Do not edit files." not in text:
            raise SystemExit(f"Pi {name} lost its read-only instructions")

models = json.loads((source_dir / "private_models.json").read_text())
providers = models.get("providers", {})
expected_providers = {"anthropic", "deepseek", "google", "openai", "typesafe", "xai"}
if set(providers) != expected_providers:
    raise SystemExit("unexpected Pi provider inventory")
if any("apiKey" in provider for provider in providers.values()):
    raise SystemExit("Pi provider credentials must stay in local auth.json")
if any(
    key.lower() == "user-agent"
    for provider in providers.values()
    for key in provider.get("headers", {})
):
    raise SystemExit("Pi providers must not override User-Agent")
if providers["anthropic"] != {"baseUrl": "https://api.kbsfdxc.net"}:
    raise SystemExit("Anthropic must override only its endpoint and use Pi's built-in catalog")
if providers["google"] != {
    "baseUrl": "https://api.kbsfdxc.net",
    "api": "anthropic-messages",
    "models": [{"id": "gemini-4-argon"}],
}:
    raise SystemExit("Google must route Gemini through Krill's Anthropic-compatible API")
if providers["typesafe"] != {"baseUrl": "https://api.commandcode.ai/provider/v1"}:
    raise SystemExit("Jev must use Command Code's System One base URL without a duplicate suffix")
openai = providers["openai"]
deepseek = providers["deepseek"]
expected_context_overrides = {
    "gpt-5.6-luna": 350000,
    "gpt-5.6-sol": 350000,
    "gpt-5.6-terra": 350000,
    "gpt-6-astra": 350000,
    "gpt-6-luna": 350000,
    "gpt-6-sol": 350000,
    "gpt-6.1-sol": 350000,
}
actual_context_overrides = {
    model_id: override.get("contextWindow")
    for model_id, override in openai.get("modelOverrides", {}).items()
}
if actual_context_overrides != expected_context_overrides:
    raise SystemExit("unexpected GPT-5.6/GPT-6/GPT-6.1 context overrides")
if deepseek.get("modelOverrides") != {"deepseek-flash": {"contextWindow": 350000}}:
    raise SystemExit("DeepSeek Flash context window is not 350K")
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
    build_modifier = source_dir / "npm/modify_private_pnpm-workspace.yaml"
    approved_builds = {
        "@google/genai@2.21.0": True,
        "esbuild@0.28.2": True,
        "protobufjs@7.6.6": True,
    }

    def modify_build_policy(old):
        return subprocess.run(
            [str(build_modifier)], input=old, text=True, capture_output=True
        )

    def parse_yaml(text):
        result = subprocess.run(
            [*execute_template[:-1], "--with-stdin",
             "{{ .chezmoi.stdin | fromYaml | toJson }}"],
            input=text, text=True, capture_output=True, check=True,
        )
        return load_json(result.stdout)

    fresh_policy = modify_build_policy("")
    if fresh_policy.returncode or parse_yaml(fresh_policy.stdout) != {"allowBuilds": approved_builds}:
        raise SystemExit("Pi pnpm fresh policy must approve only three exact versions")
    existing_policy = """allowBuilds:
  '@google/genai': true
  'esbuild@>=0.1.0': true
  protobufjs: '?'
  esbuild: false
  unrelated: false
  other@1.0.0: true
futureSetting:
  preserve: [one, two]
strictDepBuilds: true
"""
    modified = modify_build_policy(existing_policy)
    if modified.returncode or parse_yaml(modified.stdout) != {
        "allowBuilds": {**approved_builds, "unrelated": False, "other@1.0.0": True},
        "futureSetting": {"preserve": ["one", "two"]},
        "strictDepBuilds": True,
    }:
        raise SystemExit("Pi pnpm policy must narrow owned selectors and preserve other settings")
    for valid in (fresh_policy.stdout, modified.stdout):
        repeated = modify_build_policy(valid)
        if repeated.returncode or repeated.stdout != valid:
            raise SystemExit("Pi pnpm build policy modifier is not idempotent")
    for invalid in (
        "null", "[]", "true", "scalar", "allowBuilds: null",
        "allowBuilds: []", "allowBuilds: true", "allowBuilds: scalar",
        "allowBuilds: [", "allowBuilds: {}\nallowBuilds: {}",
        "allowBuilds:\n  esbuild: true\n  esbuild: false",
        "---\nallowBuilds: {}", "allowBuilds: {}\n---\nother: true",
        "allowBuilds: {}\n...\nother: true",
    ):
        rejected = modify_build_policy(invalid)
        if rejected.returncode == 0 or rejected.stdout.strip():
            raise SystemExit("Pi pnpm policy modifier accepted invalid or ambiguous YAML")

    scratch_root = pathlib.Path.home() / ".local/state/agents/tmp"
    scratch_root.mkdir(parents=True, exist_ok=True)
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="check-pi.", dir=scratch_root))
    fixture_source = scratch / "source"
    # External declarations are exercised separately with synthetic local fixtures.
    shutil.copytree(
        repo_dir, fixture_source,
        ignore=shutil.ignore_patterns(".git", ".worktrees", ".chezmoiexternal.toml"),
    )
    home = scratch / 'home with "quotes"'
    home.mkdir()
    fake_bin = scratch / "bin"
    fake_bin.mkdir()
    rbw_log = scratch / "rbw-calls"
    fake_rbw = fake_bin / "rbw"
    fake_rbw.write_text(
        '#!/bin/sh\nset -eu\n'
        'printf "%s\\n" "$*" >> "$PI_TEST_RBW_LOG"\n'
        'exec "$PI_TEST_RBW_FIXTURE" "$@"\n'
    )
    fake_rbw.chmod(0o700)
    fixture_env = {
        **os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_CACHE_HOME": str(home / ".cache"), "PNPM_HOME": str(home / ".local/share/pnpm"),
        "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
        "PI_TEST_RBW_LOG": str(rbw_log),
        "PI_TEST_RBW_FIXTURE": str(repo_dir / "tests/fixtures/pi/bin/rbw"),
    }
    external_fixture = scratch / "external-source"
    external_fixture.mkdir()
    external_payload = scratch / "global-instructions.md"
    external_target = home / external_path
    external_target.parent.mkdir(parents=True)

    def write_external_fixture(url):
        (external_fixture / ".chezmoiexternal.toml").write_text(
            f"[{json.dumps(external_path)}]\n"
            f"type = {json.dumps(external['type'])}\n"
            f"url = {json.dumps(url)}\n"
            f"private = {str(external['private']).lower()}\n"
            f"refreshPeriod = {json.dumps(external['refreshPeriod'])}\n"
        )

    external_command = [
        "chezmoi", "--config", "/dev/null", "--config-format", "toml",
        "--source", str(external_fixture), "--destination", str(home),
        "--persistent-state", str(scratch / "external-state.boltdb"),
        "--cache", str(scratch / "external-cache"),
    ]

    def apply_external(refresh, expected_contents):
        subprocess.run(
            [*external_command, f"--refresh-externals={refresh}",
             "apply", "--force", str(external_target)],
            text=True, capture_output=True, check=True, env=fixture_env,
        )
        if external_target.read_text() != expected_contents:
            raise SystemExit("Pi external instructions deployment, cache, or refresh failed")
        if external_target.stat().st_mode & 0o777 != 0o600:
            raise SystemExit("Pi external instructions must remain mode 0600")

    # Loopback HTTP tests reviewed cached deployment.
    class ExternalHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            payload = external_payload.read_bytes()
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, format, *args):
            pass

    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), ExternalHandler) as server:
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        server_thread.start()
        try:
            write_external_fixture(f"http://127.0.0.1:{server.server_port}/instructions.md")
            reviewed = "Synthetic reviewed instructions.\n"
            external_payload.write_text(reviewed)
            reviewed_diff = subprocess.run(
                [*external_command, "--refresh-externals=always",
                 "diff", str(external_target)],
                text=True, capture_output=True, check=True, env=fixture_env,
            ).stdout
            if reviewed.strip() not in reviewed_diff:
                raise SystemExit("Pi external diff did not review the refreshed instructions")
            changed = "Synthetic instructions changed after review.\n"
            external_payload.write_text(changed)
            apply_external("never", reviewed)
            apply_external("always", changed)
        finally:
            server.shutdown()
            server_thread.join()
    external_inventory = subprocess.run(
        [*external_command, "managed", "--include=files"],
        text=True, capture_output=True, check=True, env=fixture_env,
    ).stdout.splitlines()
    if external_inventory != [external_path]:
        raise SystemExit("Pi external instructions changed their destination path")
    if rbw_log.exists():
        raise SystemExit("Pi external instructions unexpectedly accessed rbw")
    print("Pi global instructions offline external deployment and refresh checks passed")

    chezmoi = [
        "chezmoi", "--config", "/dev/null", "--config-format", "toml",
        "--source", str(fixture_source), "--destination", str(home),
        "--persistent-state", str(scratch / "chezmoi-state.boltdb"),
    ]
    agent_dir = home / ".config/pi/agent"
    auth_target = agent_dir / "auth.json"
    settings_target = agent_dir / "settings.json"
    telegram_target = agent_dir / "extensions/pi-telegram-notify/config.json"
    telegram_target.parent.mkdir(parents=True)
    telegram_target.write_text('{"preserveDesktopConfig": true}\n')
    telegram_target.chmod(0o600)
    local_package = str(home / ".local/share/pi/extensions/pi-local-notify")
    profile_settings = {}
    for graphical, niri in ((False, False), (True, True), (True, False)):
        profile = (graphical, niri)
        command = [
            *chezmoi, "--override-data",
            json.dumps({"graphical": graphical, "niri": niri}),
        ]
        rendered = subprocess.run(
            [*command, "execute-template", "--file", str(settings_modifier)],
            text=True, capture_output=True, check=True, env=fixture_env,
        ).stdout
        profile_settings[profile] = check_settings(
            rendered, local_package if graphical else telegram_package, home
        )
        inventory = subprocess.run(
            [*command, "managed", "--include=files", "--exclude=encrypted,externals", str(agent_dir)],
            text=True, capture_output=True, check=True, env=fixture_env,
        ).stdout.splitlines()
        telegram_managed = ".config/pi/agent/extensions/pi-telegram-notify/config.json" in inventory
        if telegram_managed == graphical or ".config/pi/agent/settings.json" not in inventory:
            raise SystemExit("Pi profile managed settings/Telegram inventory is incorrect")
        if ".config/pi/agent/auth.json" not in inventory:
            raise SystemExit("Pi auth command references must be managed in every profile")
        if ".config/pi/agent/extensions/jev.ts" not in inventory:
            raise SystemExit("Pi Jev classifier extension must be managed in every profile")

        rbw_log.write_text("")
        fresh_auth = None if profile == (False, False) else "{}"
        for old in (fresh_auth, json.dumps(existing_auth)):
            if old is not None:
                auth_target.write_text(old)
                auth_target.chmod(0o644)
            apply_auth = [
                *command, "apply", "--force", "--exclude=scripts,encrypted,externals",
                str(auth_target),
            ]
            subprocess.run(
                apply_auth, text=True, capture_output=True, check=True, env=fixture_env,
            )
            expected_auth = load_json(modify_auth(old or "").stdout)
            if load_json(auth_target.read_text()) != expected_auth:
                raise SystemExit("Pi auth apply lost local credentials or command references")
            if auth_target.stat().st_mode & 0o777 != 0o600:
                raise SystemExit("Pi auth target must remain mode 0600")
            applied = auth_target.read_bytes()
            subprocess.run(
                apply_auth, text=True, capture_output=True, check=True, env=fixture_env,
            )
            if auth_target.read_bytes() != applied:
                raise SystemExit("Pi auth apply is not idempotent")
        if rbw_log.read_text():
            raise SystemExit("Pi auth apply unexpectedly accessed rbw")
    for invalid in invalid_auth:
        auth_target.write_text(invalid)
        rejected = subprocess.run(
            apply_auth, text=True, capture_output=True, env=fixture_env,
        )
        if rejected.returncode == 0 or auth_target.read_text() != invalid:
            raise SystemExit("Pi auth apply overwrote invalid or conflicting credentials")
        if "synthetic-secret" in rejected.stdout + rejected.stderr:
            raise SystemExit("Pi auth apply exposed rejected credentials")
    auth_target.write_text(json.dumps(existing_auth))
    if rbw_log.read_text():
        raise SystemExit("Pi auth rejection unexpectedly accessed rbw")
    print("Pi auth isolated apply, private permissions, and conflict preservation checks passed")

    # Apply only isolated fixtures; desktop rendering must not ask even the fake vault.
    settings_target.write_text(json.dumps(profile_settings[(False, False)]))
    for graphical, niri in ((True, True), (False, False), (True, False), (False, False)):
        old_telegram = telegram_target.read_bytes()
        rbw_log.write_text("")
        command = [
            *chezmoi, "--override-data",
            json.dumps({"graphical": graphical, "niri": niri}),
        ]
        subprocess.run(
            [*command, "apply", "--force", "--exclude=scripts,encrypted,externals",
             str(settings_target), str(agent_dir / "extensions")],
            text=True, capture_output=True, check=True, env=fixture_env,
        )
        if load_json(settings_target.read_text()) != profile_settings[(graphical, niri)]:
            raise SystemExit("Pi applied settings do not match the selected profile")
        if settings_target.stat().st_mode & 0o777 != 0o600:
            raise SystemExit("Pi settings target must remain mode 0600")
        if graphical:
            if rbw_log.read_text() or telegram_target.read_bytes() != old_telegram:
                raise SystemExit("Desktop Pi apply accessed rbw or changed the ignored Telegram target")
        else:
            if not rbw_log.read_text():
                raise SystemExit("Headless Pi apply did not render Telegram credentials")
            telegram = load_json(telegram_target.read_text())
            if telegram.get("$schema") != "https://unpkg.com/@oai404iao/pi-telegram-notify@1.0.0/config.schema.json":
                raise SystemExit("Telegram schema version does not match the pinned package")
            if telegram["botToken"] != "123456:test-token" or telegram["chatId"] != "-123456789":
                raise SystemExit("Telegram template did not use the fake rbw values")
        if telegram_target.stat().st_mode & 0o777 != 0o600:
            raise SystemExit("Pi Telegram target must remain mode 0600")
    print("Pi notification profiles and isolated apply checks passed")

    policy_dir = home / ".config/pi/agent/npm"
    policy_dir.mkdir(parents=True)
    (policy_dir / "pnpm-workspace.yaml").write_text(fresh_policy.stdout)
    pnpm = shutil.which("pnpm")
    if pnpm:
        version = subprocess.run(
            [pnpm, "--version"], text=True, capture_output=True, check=True,
            env=fixture_env,
        ).stdout.strip()
        if version.startswith("12."):
            consumed = subprocess.run(
                [pnpm, "--dir", str(policy_dir), "config", "get", "--json", "allowBuilds"],
                text=True, capture_output=True, check=True, env=fixture_env,
            )
            if load_json(consumed.stdout) != approved_builds:
                raise SystemExit("pnpm 12 did not consume the Pi build policy")
        else:
            print(f"pnpm 12 policy consumption skipped: found {version}")
    else:
        print("pnpm 12 policy consumption skipped: pnpm unavailable")
    inventory = subprocess.run(
        ["chezmoi", "--config", "/dev/null", "--config-format", "toml",
         "--source", str(fixture_source), "--destination", str(home),
         "--persistent-state", str(scratch / "chezmoi-state.boltdb"),
         "--override-data", '{"graphical":false,"niri":false}',
         "managed", "--include=files", "--exclude=encrypted,externals", str(policy_dir)],
        text=True, capture_output=True, check=True, env=fixture_env,
    )
    if inventory.stdout.splitlines() != [".config/pi/agent/npm/pnpm-workspace.yaml"]:
        raise SystemExit("Only the Pi npm build policy may be managed")
    print(f"Pi pnpm policy checks passed (retained fixtures: {scratch})")

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
            "pi-subagent@1.3.1"
            if relative == "private_subagent.json.tmpl"
            else "pi-codex-runtime@3.0.1"
        )
        schema = "models" if relative.endswith("private_models.json.tmpl") else "config"
        if rendered.get("$schema") != f"https://unpkg.com/@oai404iao/{package}/{schema}.schema.json":
            raise SystemExit(f"schema version does not match the pinned package: {relative}")
        if relative == "private_subagent.json.tmpl":
            expected_subagent = {
                "$schema": "https://unpkg.com/@oai404iao/pi-subagent@1.3.1/config.schema.json",
                "agentScope": "user",
                "maxDepth": 3,
                "maxConcurrentAgents": 8,
                "inheritExtensions": True,
                "maxOutputBytes": 51200,
                "openAIIdentity": True,
            }
            if rendered != expected_subagent:
                raise SystemExit("Pi subagent asynchronous multi-agent configuration changed unexpectedly")
        elif relative == "extensions/pi-codex-minimal-tools/private_config.json.tmpl":
            deprecated_keys = {
                "directImageApiFallback",
                "nativeProviderTools",
                "openaiTransport",
                "openaiWebSocketPrewarm",
                "compactionMode",
                "requestProfile",
                "apiKeyMode",
                "webSearchEnabled",
                "viewImage",
                "viewImageWorkspaceOnly",
                "applyPatchEnabled",
                "additionalModelIds",
            }
            if deprecated_keys & rendered.keys():
                raise SystemExit("Codex tools config retains deprecated settings")
            for key in ("codexRequestExtensions", "applyPatch", "webSearch"):
                if rendered.get(key) is not True:
                    raise SystemExit(f"Codex tools global switch changed unexpectedly: {key}")
            if rendered.get("endpoint_config") != []:
                raise SystemExit("Codex tools must not invent endpoint capability declarations")
            if rendered.get("webSocketEnabled") is not True:
                raise SystemExit("Codex tools WebSocket transport is disabled")
            if rendered.get("fastMode") is not False:
                raise SystemExit("Codex tools Fast mode is enabled by default")
            if rendered.get("imageGeneration") is not False:
                raise SystemExit("Codex tools image generation is enabled")
        elif relative == "extensions/pi-codex-minimal-tools/private_models.json.tmpl":
            profiles = {
                profile["id"]: profile
                for profile in rendered["models"]
            }
            if any("viewImage" in profile.get("tools", {}) for profile in profiles.values()):
                raise SystemExit("Codex profiles retain the removed viewImage setting")
            if set(profiles) != {
                "openai/gpt-5.6-sol",
                "openai/gpt-6-astra",
                "openai/gpt-6-luna",
                "openai/gpt-6-sol",
                "openai/gpt-6.1-terra",
            }:
                raise SystemExit("unexpected Codex tool profile inventory")
            if profiles["openai/gpt-6.1-terra"] != {
                "id": "openai/gpt-6.1-terra",
                "extends": "openai/gpt-6-astra",
            }:
                raise SystemExit("GPT-6.1 Terra must inherit the GPT-6 Astra profile")
            parent_responses = profiles.get(
                "openai/gpt-5.6-sol", {}
            ).get("responses", {})
            parent = profiles["openai/gpt-5.6-sol"]
            astra = profiles["openai/gpt-6-astra"]
            # Bundled Astra fields override extends; pin them explicitly to retain Lite.
            for field in ("responses", "tools", "compaction", "fast"):
                if astra.get(field) != parent.get(field):
                    raise SystemExit(f"GPT-6 Astra does not explicitly preserve Lite {field}")
            if any("endpoint" in profile.get("responses", {}) for profile in profiles.values()):
                raise SystemExit("Codex profiles retain deprecated endpoint overrides")
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

else:
    print("Pi settings/profile and other template checks skipped: chezmoi unavailable")
PY

if command -v node >/dev/null 2>&1 && command -v pi >/dev/null 2>&1; then
    node --experimental-strip-types --experimental-import-meta-resolve --disable-warning=ExperimentalWarning \
        "$repo_dir/tests/check-pi-jev.mjs" "$(command -v pi)"
else
    printf '%s\n' "Pi Jev runtime checks skipped: node or pi unavailable"
fi

printf '%s\n' "Pi configs passed"
