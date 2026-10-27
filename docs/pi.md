# Pi

This repository configures Pi for the personal Arch environment: pinned
extensions, routed model providers, secret-manager references, and bounded
agent collaboration. It does not install Pi or own its sessions and downloads.

## Start here

| I want to… | Read |
| --- | --- |
| Connect a provider or adopt an existing Pi configuration | [Authentication](pi-authentication.md) |
| Install extensions, switch notifications, or repair package imports | [Packages](pi-packages.md) |
| Understand Jev, child agents, codemode, or global instructions | [Agents and instructions](pi-agents.md) |
| Install or update shared task instructions | [Global skills](skills.md) |
| Change machine data or understand chezmoi ownership | [Configuration](configuration.md) |

For the Pi interface itself, use the upstream [quickstart](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/quickstart.md)
and [terminal guide](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/usage.md).
Their default `~/.pi/agent` paths differ from this environment's XDG paths.

### Before starting Pi

The pinned extensions require **Pi 1.2.0 or newer and Node.js 22.19 or newer**.
For the system-managed Arch installation, upgrade with `sudo pacman -Syu pi`;
fully exit and restart Pi afterward. `/reload` cannot upgrade the running host
SDK. Package versions and transitive dependencies are separate concerns; see
[package setup](pi-packages.md#install-or-change-packages).

The shared shell profile exports `PI_CODING_AGENT_DIR` and
`PI_CODING_AGENT_SESSION_DIR`, defaulting to:

| Purpose | Default path |
| --- | --- |
| Configuration and extension settings | `~/.config/pi/agent` |
| Mutable sessions and child-tree stores | `~/.local/state/pi/agent/sessions` |

Existing environment overrides remain effective. Start Pi from the project it
should work on. Unlock `rbw` before the process first resolves a provider key;
this is a live vault operation, not an offline setup check.

```sh
cd /path/to/project
pi
```

Use `/model` and `/thinking` for the current session. New sessions use the
managed defaults below; resumed sessions can restore their previous selections.
Tools and extensions run with the Pi process's permissions, not in a project
sandbox. Read [security](security.md) before granting access to unfamiliar code.

## Managed configuration

The source directory is
[`dot_config/private_pi/agent/`](../dot_config/private_pi/agent/).
Managed files use mode `0600`; `~/.config/pi` remains mode `0700`.

| Target under `~/.config/pi/agent/` | Ownership |
| --- | --- |
| `settings.json` | Modifier replaces declared settings; preserves unknown/runtime keys and other codemode options. |
| `models.json`, `keybindings.json` | Declarative provider/model metadata and key bindings; no API keys in models. |
| `auth.json` | Modifier merges five providers' command references; all other credentials and extra fields remain local. |
| `subagent.json`, `agents/{scout,reviewer,worker}.md` | User-scoped runtime policy and role definitions. |
| `extensions/jev.ts` | Command Code classifier registration. |
| `extensions/pi-codex-minimal-tools/{config,models}.json` | Codex capabilities and model profiles. |
| `extensions/pi-telegram-notify/config.json` | Headless-only credential template; contains plaintext after rendering. |
| `npm/pnpm-workspace.yaml` | Modifier merges exact reviewed build approvals, not installation state. |
| `AGENTS.md` | Single external file from `my_skills/main`, with a 24-hour fetch cache. |

The settings modifier deliberately owns the entire package declaration list.
A local edit to a declared key can be replaced on the next targeted apply.
It is not an import mechanism for arbitrary runtime settings.

### Defaults and model reference

| Setting | Managed value |
| --- | --- |
| Startup provider/model | `openai/gpt-6.1-sol` |
| Thinking | `high`, with transcript thinking blocks hidden |
| Theme | `dark` |
| Tools | Add `codemode` to inherited defaults; codemode mode `on` |
| npm command | `pnpm --config.node-linker=hoisted` |
| Sessions | `~/.local/state/pi/agent/sessions` |
| Submit / newline | Enter / Shift+Enter, Alt+Enter, or Ctrl+J |

The enabled-model list is `anthropic/claude-opus-5-5`,
`openai/gpt-5.6-sol`, `openai/gpt-6-astra`, `openai/gpt-6-luna`,
`openai/gpt-6.1-sol`, `openai/gpt-6.1-terra`, and `deepseek/deepseek-flash`.
It is a selection scope, not the full provider catalog.

Provider metadata routes `openai`, `deepseek`, and `xai` through
`https://api.spiredive.com/v1`, `anthropic` through
`https://api.krill-code.net`, and `typesafe` through
`https://api.commandcode.ai/provider/v1`. Anthropic retains Pi's built-in
catalog. DeepSeek disables the developer role. Providers do not override
`User-Agent`; the client supplies its default.

Model overrides retain built-in metadata while setting a 350,000-token context
for GPT-5.6 Luna/Sol/Terra, GPT-6 Astra/Luna/Sol, GPT-6.1 Sol, and DeepSeek Flash.
The additional `openai/gpt-5.6-sol-cyber` model uses Responses, text/image input,
reasoning, a 350,000-token context and 128,000-token output limit, tool-search
support, and explicit thinking-level and tiered price metadata. Exact values
live in [`private_models.json`](../dot_config/private_pi/agent/private_models.json).
These declarations do not establish live endpoint compatibility.

### What stays local

Do not add `auth.json` itself, `trust.json`, `models-store.json`, installation
IDs, npm manifests/lockfiles/packages, git checkouts, downloaded binaries,
or local extension symlinks. Sessions, `<rootSessionId>.subagents/<treeId>/`
control stores, `.pi-subagent/` manifests, recovery fragments, caches, and logs
are mutable state too. `.chezmoiignore` is authoritative.

Disabled packages and their configuration are not managed. Removing a package
declaration stops loading it; it does not make the retained files disposable.
Shared skills are [installed separately](skills.md), not copied into Pi's tree.

### Review a settings change

Privately back up the existing target first. For a sanitized settings file only:

```sh
chezmoi diff --skip-secrets --exclude=encrypted ~/.config/pi/agent/settings.json
chezmoi apply --exclude=scripts,encrypted ~/.config/pi/agent/settings.json
```

Never diff or apply the whole Pi directory. `--skip-secrets` is not a redaction
filter for existing destination credentials. Use the authentication workflow
for `auth.json`, Telegram, and a legacy `models.json` containing a literal key.

Run `./tests/check-pi.sh` for fake-secret rendering, managed inventory, merge
behavior, profiles, isolated deployment, and mocked Jev transport checks.
Run `./tests/check-skills.sh` for skill installer changes, and
`./tests/check-source.sh` plus `git diff --check` before publishing source
changes. These checks do not call paid models, access the real vault, send
notifications, rebuild dependencies, or validate live provider compatibility.

## Notifications by machine profile

`graphical` selects local Kitty notifications or Telegram at apply time.
Follow [notification setup and switching](pi-packages.md#notifications-by-machine-profile);
a missing local source link does not fall back to Telegram.

## pnpm build approvals

Only three exact dependency versions are approved for user-level Pi installs.
See [the build-policy workflow](pi-packages.md#pnpm-build-approvals) before
applying the policy or deliberately executing a rebuild.

## Pi package layout migration

Applying settings does not rebuild existing installs. Use the
[lockfile-preserving hoisted-layout migration](pi-packages.md#pi-package-layout-migration)
when imports fail or the Codex doctor reports no model profile.

## Subagent 1.0.0 migration

Foreground mode and the old descriptor/control contract are retired.
Follow [the asynchronous-runtime migration](pi-agents.md#subagent-100-migration)
before upgrading an existing install; keep historical sessions and start new children.

### `createCodemodeExtension is not a function`

This usually means the running host SDK is too old, not that codemode should
be disabled. Follow [host-version troubleshooting](pi-agents.md#createcodemodeextension-is-not-a-function).

## Jev task triage

Jev supplies one advisory workflow/review classification per new user task.
See [registration, authentication, and fallback rules](pi-agents.md#jev-task-triage).

## Agent delegation guidance

Simple tasks stay with the root. Scout, reviewer, and worker serve bounded
independent work, not a mandatory pipeline. See [roles and coordination](pi-agents.md#choose-a-role).

## Codemode

Native codemode batches JavaScript tool calls while keeping direct tools
visible. See [tool exposure and child limits](pi-agents.md#codemode).

## Global agent instructions

Edit the upstream `my_skills` prompt, publish it, then use the
[reviewed-cache deployment workflow](pi-agents.md#global-agent-instructions).
Do not create a second local source here.

## Credentials

Provider keys are command references, not literals in model metadata or shell
startup. See [credential ownership and caching](pi-authentication.md).

### Apply authentication references safely

Exit Pi, make a private backup outside the source and retained scratch, and
apply only the auth target without displaying a diff. The complete
[safe authentication workflow](pi-authentication.md#apply-authentication-references-safely)
also covers OAuth conflicts and failed command caches.
